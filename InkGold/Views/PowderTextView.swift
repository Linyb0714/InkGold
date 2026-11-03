import SwiftUI

// ============================================================
// 文字几何转场：二级页滑动切换名片时，上方信息文字化作
// 白/金双色空心几何图形（三角/菱形/六边形，与全站几何语言
// 同源）飞散消逝；新文字随即上浮渐显。
//
// 原理：InfoTexts 离屏 ImageRenderer 渲染成位图 → 网格采样出
// 文字像素点位与色温 → 粒子系统 Canvas 重放：
//   A 爆开（原图形位极速外扩 + 起爆闪光；金色文字区飞出
//     金色图形、白色文字区飞出白色图形，随机互换小比例）
//   B 消逝（自转续飘 + 错峰淡出至零）
//   C 新文字上浮渐显（外部驱动，与消逝重叠交接）
// ============================================================

// MARK: - 采样

/// 一个文字像素点（视图坐标 + 归一化颜色）
struct PowderDot {
    let x, y: Float
    let r, g, b, a: Float
}

/// 某张名片信息文字的采样规格（缓存复用，切换零延迟）
struct PowderTextSpec {
    let height: CGFloat
    let dots: [PowderDot]
}

/// 采样缓存：cardID+宽度 → 位图采样；首次构建 ~几毫秒（MainActor 渲染）
@MainActor
final class TextPowderCache {
    static let shared = TextPowderCache()
    private var cache: [String: PowderTextSpec] = [:]

    private let step: CGFloat = 1.9      // 采样步长（pt）——与粒子尺寸匹配后文字接近实心
    private let scale: CGFloat = 2       // 离屏渲染倍率
    private let alphaTh: Float = 0.38    // 透明度阈值：跳过文字反锯齿边缘

    func spec(for card: CardProfile, width: CGFloat) -> PowderTextSpec {
        let key = "\(card.id)-\(Int(width))"
        if let s = cache[key] { return s }
        let s = build(card: card, width: width)
        cache[key] = s
        return s
    }

    private func build(card: CardProfile, width: CGFloat) -> PowderTextSpec {
        guard width > 20 else { return PowderTextSpec(height: 40, dots: []) }
        let r = ImageRenderer(content: InfoTexts(card: card).frame(width: width))
        r.scale = scale
        guard let img = r.uiImage, let cg = img.cgImage else {
            return PowderTextSpec(height: 40, dots: [])
        }
        let w = cg.width, h = cg.height
        guard w > 4, h > 4, let data = rgbaBytes(cg, w, h) else {
            return PowderTextSpec(height: CGFloat(h) / scale, dots: [])
        }
        var dots: [PowderDot] = []
        dots.reserveCapacity(3000)
        let pxStep = max(2, Int(step * scale))
        var row = 0
        while row < h {
            var col = 0
            while col < w {
                let i = (row * w + col) * 4
                var a = Float(data[i + 3]) / 255
                if a >= alphaTh {
                    var rr = Float(data[i]) / 255
                    var gg = Float(data[i + 1]) / 255
                    var bb = Float(data[i + 2]) / 255
                    // 位图为预乘 alpha，还原真色（供暖度判定：金区/白区）
                    rr /= a; gg /= a; bb /= a
                    a = min(1, a * 1.15)          // 补齐采样跳过带来的密度损失
                    // 位图行序自底向上：翻转到视图坐标（原点左上）
                    let y = Float(h - 1 - row) / Float(scale)
                    let x = Float(col) / Float(scale)
                    dots.append(PowderDot(x: x, y: y, r: rr, g: gg, b: bb, a: a))
                }
                col += pxStep
            }
            row += pxStep
        }
        return PowderTextSpec(height: CGFloat(h) / scale, dots: dots)
    }

    /// CGImage → RGBA8 字节（上下行序为位图原生）
    private func rgbaBytes(_ cg: CGImage, _ w: Int, _ h: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }
}

// MARK: - 粒子

/// 单粒图形：从旧文字位 (ox,oy) 空心几何图形飞散出去，自转并消逝
struct PowderParticle {
    let ox, oy: Float
    let isGold: Bool                 // 白 / 金双色
    let shape: GlyphShape            // 三角 / 菱形 / 六边形（全局几何语言）
    let rot: Float                   // 初始朝向
    let rotV: Float                  // 自转角速度
    let dx, dy: Float                // 散开位移
    let ddx, ddy: Float              // 消逝段追加漂移
    let fadeV: Float                 // 消逝速率（错峰）
    let size: Float                  // 图形半径
    let lw: Float                    // 描边宽
    let tw: Float                    // 闪烁相位
}

struct PowderAnim {
    let start = Date()
    let particles: [PowderParticle]
    let height: CGFloat               // 画布高

    static let aEnd: Double = 0.24    // A 爆开结束（原位→外扩）
    static let total: Double = 0.60   // 消逝全部结束
    static let baseAlpha: Float = 0.55 // 线条基础透明度：保持半透的柔质感，
                                        // 峰值（起爆闪光）不超过主背景描边亮度太多
}

enum PowderFactory {
    static func make(old: PowderTextSpec, seed: UInt32) -> PowderAnim {
        let od = old.dots
        guard !od.isEmpty else {
            return PowderAnim(particles: [], height: old.height)
        }
        let rnd = mulberry32(seed)

        // 旧文字包围盒中心：散开方向基准（外圈飞更远）
        var mnX = Float.greatestFiniteMagnitude, mnY = Float.greatestFiniteMagnitude
        var mxX: Float = -1, mxY: Float = -1
        for d in od {
            mnX = min(mnX, d.x); mxX = max(mxX, d.x)
            mnY = min(mnY, d.y); mxY = max(mxY, d.y)
        }
        let cx = (mnX + mxX) / 2, cy = (mnY + mxY) / 2

        var ps: [PowderParticle] = []
        ps.reserveCapacity(od.count)
        for o in od {
            let ang = atan2(o.y - cy, o.x - cx) + Float(rnd() - 0.5) * 1.2
            let dist: Float = 46 + Float(rnd()) * 124
            let dx = cos(ang) * dist
            let dy = sin(ang) * dist - 18 * Float(rnd())   // 轻微上飘

            // 颜色：金色文字区（暖色像素）飞金色、白色文字区飞白色；
            // ± 随机互换确保自然混合，金白五五开偏向白
            let warm = (o.r - o.b) > 0.12 && o.r > 0.3
            let isGold = warm ? rnd() > 0.15 : rnd() < 0.32

            ps.append(PowderParticle(
                ox: o.x, oy: o.y,
                isGold: isGold,
                shape: GlyphShape(rawValue: Int(rnd() * 3)) ?? .hexagon,
                rot: Float(rnd()) * .pi * 2,
                rotV: (rnd() < 0.5 ? -1 : 1) * (1.4 + Float(rnd()) * 3.2),  // rad/s 自转
                dx: dx, dy: dy,
                ddx: dx * 0.24 + Float(rnd() - 0.5) * 10,
                ddy: dy * 0.24 - 5 * Float(rnd()),
                fadeV: 0.62 + Float(rnd()) * 0.38,
                size: 2.7 + Float(rnd()) * 2.0,
                lw: 1.0 + Float(rnd()) * 0.5,
                tw: Float(rnd()) * .pi * 2))
        }
        return PowderAnim(particles: ps, height: old.height)
    }
}

// MARK: - 粉末画布

struct PowderCanvas: View {
    let anim: PowderAnim
    let width: CGFloat

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, _ in
                let t = tl.date.timeIntervalSince(anim.start)
                guard t >= 0, t < PowderAnim.total else { return }

                let aEnd = PowderAnim.aEnd
                // 双色常量（与全站金白一致）：金 0xE9CC8C / 白 0xE7E4DA
                let gC = Color(red: 233/255, green: 204/255, blue: 140/255)
                let wC = Color(red: 231/255, green: 228/255, blue: 218/255)

                for p in anim.particles {
                    var x: Float, y: Float, s: Float, alpha: Float

                    if t < aEnd {
                        // A 爆开：极速外扩（easeOutQuint 起步似炸）+ 起爆闪光 + 尺寸鼓包
                        let u = powEaseQuint(t / aEnd)
                        x = p.ox + p.dx * u
                        y = p.oy + p.dy * u
                        let pop = sin(.pi * min(1, Float(t) / Float(aEnd * 0.7)))
                        s = p.size * (1 + 0.4 * pop) * (1 - 0.10 * u)
                        alpha = PowderAnim.baseAlpha * (1 - 0.10 * u)
                        alpha *= 1 + 0.40 * Float(exp(-t / 0.07))   // 起爆闪光
                    } else {
                        // B 消逝：续飘自转 + 错峰淡出至零
                        let v = (t - aEnd) / (PowderAnim.total - aEnd)
                        let e = powEaseOut(min(1, max(0, v)))
                        x = p.ox + p.dx + p.ddx * e
                        y = p.oy + p.dy + p.ddy * e
                        s = p.size * (1 - 0.35 * e)
                        let f = min(1, max(0, (v / Double(p.fadeV) - 0.15) / 0.85))
                        alpha = PowderAnim.baseAlpha * (1 - powEaseOut(f))
                    }
                    // 轻微闪烁
                    alpha = min(1, alpha) * (1 + 0.14 * sin(p.tw + Float(t) * 9))
                    guard alpha > 0.02, s > 0.5 else { continue }

                    // 空心几何图形（自转）：中心建成 → 旋转 → 平移到位
                    let rot = p.rot + p.rotV * Float(t)
                    let r = CGFloat(s)
                    let px = CGFloat(x), py = CGFloat(y)
                    let cs = CGFloat(cos(rot)), sn = CGFloat(sin(rot))
                    let vs = GlyphShape.verts(p.shape, cx: 0, cy: 0, r: r)
                    var pts: [CGPoint] = []
                    pts.reserveCapacity(vs.count)
                    for v in vs {
                        let rx = v.x * cs - v.y * sn
                        let ry = v.x * sn + v.y * cs
                        pts.append(CGPoint(x: px + rx, y: py + ry))
                    }
                    let col = p.isGold ? gC.opacity(Double(alpha)) : wC.opacity(Double(alpha))
                    ctx.stroke(Path(polygon: pts), with: .color(col), lineWidth: CGFloat(p.lw))
                }
            }
        }
        .frame(width: width, height: anim.height)
        .allowsHitTesting(false)
    }

    private func powEaseOut(_ u: Double) -> Float { Float(1 - pow(1 - u, 3)) }
    /// 极速起步（爆开感）：前 20% 时间完成约 67% 位移
    private func powEaseQuint(_ u: Double) -> Float { Float(1 - pow(1 - u, 5)) }
    private func powClamp01(_ x: Double) -> Float { Float(min(1, max(0, x))) }
}

// MARK: - 组件（DetailView 挂载点）

/// 信息卡的文字粉末包装：名片切换时旧文字化作金粉散开-消逝，
/// 新文字随即上浮渐显。壳体（背景/边框/角标）保持稳定。
@MainActor
struct PowderCardInfo: View {
    let card: CardProfile
    /// InfoTexts 渲染宽度（卡片宽 - 壳内左右 padding）
    let contentWidth: CGFloat
    @Environment(FlowMachine.self) private var m
    @State private var anim: PowderAnim?
    @State private var textHidden = false
    @State private var risen = true          // 新文字上浮动画：false=底部待起
    @State private var job: Task<Void, Never>?

    var body: some View {
        DeckInfoCard(card: card,
                     textOpacity: textHidden ? 0 : 1,
                     riseOffset: risen || textHidden ? 0 : 10)
            .overlay(alignment: .topLeading) {
                if let a = anim {
                    PowderCanvas(anim: a, width: contentWidth)
                        .padding(.leading, DS.L.infoPadH).padding(.top, 15)
                }
            }
            .onChange(of: card) { old, new in
                startPowder(old: old, new: new)
            }
            .onAppear { prefetch(around: card) }
    }

    private func startPowder(old: CardProfile, new: CardProfile) {
        guard old.id != new.id else { return }
        job?.cancel()
        let cache = TextPowderCache.shared
        let oldSpec = cache.spec(for: old, width: contentWidth)
        guard oldSpec.dots.count > 0 else { return }

        // ① 旧文字瞬隐，粒子在原位接管散开-消逝
        textHidden = true
        risen = false
        anim = PowderFactory.make(old: oldSpec,
                                  seed: hashStr("pw\(old.id)>\(new.id)\(timeSeed())"))
        prefetch(around: new)

        job = Task { @MainActor in
            // ② 散开尾声：新文字上浮渐显（opacity+上浮 0.38s，与消逝重叠交接）
            try? await Task.sleep(for: .seconds(0.16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.38)) {
                textHidden = false
                risen = true
            }
            // ③ 消逝完毕回收画布
            try? await Task.sleep(for: .seconds(0.42))
            guard !Task.isCancelled else { return }
            anim = nil
        }
    }

    /// 预取相邻名片的采样规格（分帧渲染，滑动切换时零延迟）
    private func prefetch(around center: CardProfile) {
        let s = m.store
        let around = [-2, -1, 1, 2].map { s.deck[s.wrapIdx(s.currentIdx + $0)].displayCard }
        Task { @MainActor in
            for c in around where c.id != center.id {
                _ = TextPowderCache.shared.spec(for: c, width: contentWidth)
                try? await Task.sleep(for: .seconds(0.03))
            }
        }
    }
}
