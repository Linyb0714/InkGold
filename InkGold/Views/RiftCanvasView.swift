import SwiftUI

// ============================================================
// 全屏渲染层（快照模式）：主线程 tick+组装 RiftSnapshot，
// Canvas nonisolated 闭包纯绘制（隔离安全 + 每帧零锁竞争）
// 绘制数值与原型 drawGeoBg / drawHome / drawRiftNow 逐段对应
// ============================================================

extension Path {
    init(polygon pts: [CGPoint]) {
        var p = Path()
        guard let f = pts.first else { self = p; return }
        p.move(to: f)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        self = p
    }
}

extension FlowMachine {
    /// 全局背景密铺（唯一来源）：跟随 shapeType（最近一次裂变/直达的形状），
    /// 0.6 细密档。首页待机、裂变、二级页、返回聚合共享同一份——
    /// 几何随滑动切换，全网相位/呼吸/掠面光带完全连续。
    func ensureHomeTess() -> TessCache? {
        let key = "H-\(Int(viewSize.width))x\(Int(viewSize.height))-s\(shapeType.rawValue)"
        if let t = homeTess, t.key == key { return t }
        let (tiles, acc) = buildTessellation(size: viewSize, shape: shapeType,
                                             radiusScale: GeoScale.dense,
                                             seedStr: "home-s\(shapeType.rawValue)")
        let c = TessCache(key: key, shape: shapeType, tiles: tiles,
                          paths: tiles.map { Path(polygon: $0.pts) }, accents: acc)
        homeTess = c
        return c
    }
}

struct RiftCanvasView: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        TimelineView(.animation) { tl in
            RiftFrame(m: m, date: tl.date)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// TimelineView 内容帧（在 MainActor body 内完成 tick + 快照组装）
@MainActor
struct RiftFrame: View {
    let m: FlowMachine
    let date: Date

    var body: some View {
        let snap = m.tickAndSnapshot(date)
        return Canvas { ctx, size in
            RiftPainter.draw(&ctx, size, snap, date: date)
        }
    }
}

// MARK: - 纯绘制器（nonisolated：只读快照 + inout ctx）

enum RiftPainter {

    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize,
                     _ s: RiftSnapshot, date: Date) {
        guard size.width > 4, size.height > 4 else { return }

        switch s.phase {
        case .idle, .trail, .scatter:
            drawGeoBg(&ctx, size, tes: s.homeTess, dt: 0, date: date, s: s)
            if s.phase == .idle {
                drawIdleCard(&ctx, s)
                drawAmb(&ctx, s)
            } else if s.phase == .trail {
                drawTrailPhase(&ctx, s)
            } else {
                drawScatter(&ctx, s)
            }
            drawSwap(&ctx, s)
            drawSplash(&ctx, s)
        case .galaxy:
            drawGalaxy(&ctx, size, s)
        case .detail:
            drawGeoBg(&ctx, size, tes: s.homeTess, dt: 0, date: date, s: s)
        case .merge:
            drawMerge(&ctx, s, date: date)
        }
    }

    private static var cardImg: Image? {
        nil
    }

    // MARK: 背景密铺 + 轻动画

    static func drawGeoBg(_ ctx: inout GraphicsContext, _ size: CGSize,
                          tes: TessCache?, dt: Double, date: Date, s: RiftSnapshot) {
        let W = size.width, H = size.height
        guard let tes = tes else { return }
        let t = date.timeIntervalSinceReferenceDate

        let bg = Gradient(colors: [DS.C.bgTop, DS.C.bgMid, DS.C.bgBottom])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                 with: .linearGradient(bg, startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))

        // 漂浮异形（缓慢上浮自转 + 柔光内晕；位置已在 tick 写回缓存）
        for ac in tes.accents {
            let glow = Gradient(colors: [Color(rgb: 0xC9A84A, 0.06), Color(rgb: 0xC9A84A, 0)])
            ctx.drawLayer { c in
                c.translateBy(x: ac.x, y: ac.y)
                c.rotate(by: .radians(ac.rot))
                c.fill(Path(ellipseIn: CGRect(x: -ac.s * 1.5, y: -ac.s * 1.5,
                                              width: ac.s * 3, height: ac.s * 3)),
                       with: .radialGradient(glow, center: .zero,
                                             startRadius: 0, endRadius: ac.s * 1.5))
                let vp = GlyphShape.verts(tes.shape, cx: 0, cy: 0, r: ac.s)
                let a = 0.13 + 0.09 * (0.5 + 0.5 * sin(t * 0.9 + Double(ac.ph)))
                c.stroke(Path(polygon: vp), with: .color(Color(rgb: 0xC9A84A, a)), lineWidth: 1)
            }
        }

        // 密铺轮廓：逐块呼吸 + 斜向掠面光带
        let sweep = (t * 42).truncatingRemainder(dividingBy: Double(W + H + 320)) - 160
        for (i, tile) in tes.tiles.enumerated() {
            let br = 0.5 + 0.5 * sin(t * 1.1 + Double(tile.seed) * Double.pi * 2)
            var a = 0.065 + 0.085 * br
            let dp = Double(tile.cx + tile.cy) - sweep
            if dp > -150 && dp < 150 { a += (1 - abs(dp) / 150) * 0.16 }
            ctx.stroke(tes.paths[i], with: .color(Color(rgb: 0xC9A84A, a)), lineWidth: 0.9)
            if tile.seed < 0.07 {   // 印信节点
                let g = 4.5 + br * 3
                let rg = Gradient(colors: [Color(rgb: 0xE9CC8C, 0.10 + 0.16 * br),
                                           Color(rgb: 0xC9A84A, 0)])
                ctx.fill(Path(ellipseIn: CGRect(x: tile.cx - g, y: tile.cy - g,
                                                width: g * 2, height: g * 2)),
                         with: .radialGradient(rg, center: CGPoint(x: tile.cx, y: tile.cy),
                                               startRadius: 0, endRadius: g))
            }
        }

        // 点线星网（跳过暖红）
        for i in s.dots.indices {
            for j in (i + 1)..<s.dots.count {
                let a = s.dots[i], b = s.dots[j]
                let d = hypot(a.x - b.x, a.y - b.y)
                if d < 110 {
                    var p = Path()
                    p.move(to: CGPoint(x: a.x, y: a.y)); p.addLine(to: CGPoint(x: b.x, y: b.y))
                    ctx.stroke(p, with: .color(Color(rgb: 0x8CA0D2, 0.05 * (1 - d / 110))),
                               lineWidth: 0.6)
                }
            }
        }
        for p in s.dots where p.color.0 != 255 {
            let tw = 0.5 + 0.5 * sin(p.ph + p.t)
            let r = 0.8 + CGFloat(p.t.truncatingRemainder(dividingBy: 1)) * 0.9
            let col = Color(red: p.color.0 / 255, green: p.color.1 / 255, blue: p.color.2 / 255)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(col.opacity(0.10 + 0.16 * tw)))
        }

        // 暗角收束
        let vg = Gradient(colors: [.clear, Color.black.opacity(0.46)])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                 with: .radialGradient(vg, center: CGPoint(x: W / 2, y: H * 0.44),
                                       startRadius: min(W, H) * 0.32,
                                       endRadius: max(W, H) * 0.75))
    }

    // MARK: 首页名片

    /// 首页名片（含泛光/投影/阴影/左缘/金边全套装饰）
    /// alpha < 1 时整体淡入——供 merge 尾段复用，保证结束帧与 idle 首帧一致零跳变
    static func drawIdleCard(_ ctx: inout GraphicsContext, _ s: RiftSnapshot, alpha: Double = 1) {
        guard let img = s.cardImg, alpha > 0.01 else { return }
        let saved = ctx.opacity
        ctx.opacity = alpha
        defer { ctx.opacity = saved }
        let image = Image(uiImage: img)
        let r = s.cardRect
        let cx = r.midX, cy = r.midY

        let gb = Gradient(colors: [Color(rgb: 0xC4A84A, 0.12),
                                   Color(rgb: 0xC4A84A, 0.04), .clear])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: s.viewSize.width, height: s.viewSize.height)),
                 with: .radialGradient(gb, center: CGPoint(x: cx, y: cy),
                                       startRadius: r.width * 0.08,
                                       endRadius: r.width * 0.95))

        ctx.drawLayer { c in
            c.addFilter(.shadow(color: .black.opacity(0.72), radius: 26, x: 0, y: 13))
            c.draw(image, in: r)
        }
        ctx.fill(Path(CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 3)),
                 with: .color(.black.opacity(0.42)))
        ctx.fill(Path(CGRect(x: r.minX, y: r.maxY + 1, width: r.width, height: 5)),
                 with: .color(.black.opacity(0.24)))
        ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: 2, height: r.height)),
                 with: .color(Color(rgb: 0xFFEBB4, 0.10)))
        ctx.stroke(Path(r), with: .color(Color(rgb: 0xC4A84A, 0.16)), lineWidth: 1)
    }

    // MARK: 轨迹裂变

    static func drawTrailPhase(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        guard let img = s.cardImg else { return }
        ctx.draw(Image(uiImage: img), in: s.cardRect)
        for b in s.blocks where b.cut { drawSeam(&ctx, b, s) }
        if s.dragging, s.trail.count > 1 { drawTrailPath(&ctx, s) }
    }

    static func blockPath(_ b: RiftBlock) -> Path {
        Path(polygon: b.pts.map { CGPoint(x: b.cx + $0.x, y: b.cy + $0.y) })
    }

    static func drawSeam(_ ctx: inout GraphicsContext, _ b: RiftBlock, _ s: RiftSnapshot) {
        let absPts = b.pts.map { CGPoint(x: b.cx + $0.x, y: b.cy + $0.y) }
        ctx.stroke(Path(polygon: absPts), with: .color(DS.C.seam), lineWidth: 0.8)
        drawEdgeSpark(&ctx, pts: absPts, seed: b.seed, alpha: 1, coreAlpha: 0.85, s: s)
    }

    /// 沿多边形周长流动的光点（原型 edgeGlow）
    static func drawEdgeSpark(_ ctx: inout GraphicsContext, pts: [CGPoint],
                              seed: CGFloat, alpha: Double, coreAlpha: Double,
                              s: RiftSnapshot) {
        var edges: [(CGPoint, CGPoint, CGFloat)] = []
        var total: CGFloat = 0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let L = hypot(b.x - a.x, b.y - a.y)
            edges.append((a, b, L)); total += L
        }
        guard total > 0 else { return }
        var dist = (CGFloat(s.animClock) * 55 * (0.7 + CGFloat((seed * 100).truncatingRemainder(dividingBy: 1)) * 0.6)
                    + seed * 40).truncatingRemainder(dividingBy: total)
        for e in edges {
            if dist <= e.2 {
                let k = dist / e.2
                let x = e.0.x + (e.1.x - e.0.x) * k
                let y = e.0.y + (e.1.y - e.0.y) * k
                let g = 3.2 + sin(s.animClock * 4 + Double(seed) * 6) * 0.8
                let grad = Gradient(colors: [DS.C.sparkCore.opacity(coreAlpha * alpha),
                                             Color(rgb: 0xFF783C, 0)])
                ctx.fill(Path(ellipseIn: CGRect(x: x - g, y: y - g, width: g * 2, height: g * 2)),
                         with: .radialGradient(grad, center: CGPoint(x: x, y: y),
                                               startRadius: 0, endRadius: g))
                break
            }
            dist -= e.2
        }
    }

    static func drawTrailPath(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        let n = s.trail.count
        for i in 1..<n {
            let a = s.trail[i - 1], b = s.trail[i]
            let k = Double(i) / Double(n)
            var p = Path()
            p.move(to: a); p.addLine(to: b)
            // 由浅至深：起点（旧）浅、终点（最新指尖）深，符合手指轨迹的实时感
            ctx.stroke(p, with: .color(DS.C.trailLine.opacity(0.22 + 0.63 * k)), lineWidth: 2)
        }
    }

    // MARK: 3D 散场

    static func drawScatter(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        guard let img = s.cardImg else { return }
        let image = Image(uiImage: img)
        let card = s.cardRect
        let CY = card.midY
        for b in s.blocks where b.fly && b.flyT < 1 {
            let t = Double(b.flyT)
            let dir = atan2(b.cy - CY, b.cx - card.midX)
            let d = easeOutCubic(t) * (30 + Double(b.seed) * 110)
            let px = b.cx + cos(dir) * CGFloat(d)
            let py = b.cy + sin(dir) * CGFloat(d) + t * 30
            let rot = Double(b.spin) * t * .pi
            let rel = Path(polygon: b.pts)

            ctx.drawLayer { c in
                c.translateBy(x: px, y: py)
                c.concatenate(CGAffineTransform(a: CGFloat(cos(rot)), b: 0, c: 0, d: 1, tx: 0, ty: 0))
                c.drawLayer { inner in
                    inner.clip(to: rel)
                    inner.opacity = 1 - t
                    inner.draw(image, in: CGRect(x: card.minX - b.cx, y: card.minY - b.cy,
                                                 width: card.width, height: card.height))
                }
                c.opacity = 1 - t
                c.stroke(rel, with: .color(DS.C.edgeGlow.opacity(1 - t)), lineWidth: 0.8)
            }
        }
    }

    // MARK: 银河

    static func drawGalaxy(_ ctx: inout GraphicsContext, _ size: CGSize, _ s: RiftSnapshot) {
        let W = size.width, H = size.height
        let bgGrad = Gradient(colors: [Color(hex: 0x0b0b0e), Color(hex: 0x060608), Color(hex: 0x0b0b0e)])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                 with: .linearGradient(bgGrad, startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))

        let cx = W / 2, cy = H * 0.42
        let cr = 34 + sin(s.galaxyT * 6) * 6
        let cg = Gradient(colors: [Color(rgb: 0xC9A84A, 0.14), Color(rgb: 0xC9A84A, 0)])
        ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                 with: .radialGradient(cg, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))

        let alive = s.galaxy.filter { $0.a > 0.001 }

        for i in alive.indices {
            for j in (i + 1)..<alive.count {
                let a = alive[i], b = alive[j]
                let d = hypot(a.x - b.x, a.y - b.y)
                if d < 64 {
                    var p = Path()
                    p.move(to: CGPoint(x: a.x, y: a.y)); p.addLine(to: CGPoint(x: b.x, y: b.y))
                    let la = 0.05 * (1 - d / 64) * min(a.a, b.a)
                    ctx.stroke(p, with: .color(Color(red: 150 / 255, green: 170 / 255,
                                                     blue: 210 / 255, opacity: la)), lineWidth: 0.6)
                }
            }
        }

        for p in alive {
            let ux = CGFloat(cos(p.th)), uy = CGFloat(sin(p.th)) * 0.72
            var tail = Path()
            tail.move(to: CGPoint(x: p.x + ux * p.tail, y: p.y + uy * p.tail))
            tail.addLine(to: CGPoint(x: p.x, y: p.y))
            let col = Color(red: p.color.0 / 255, green: p.color.1 / 255, blue: p.color.2 / 255)
            ctx.stroke(tail, with: .color(col.opacity(0.35 * p.a)), lineWidth: 0.7)
            let tw = 0.6 + 0.4 * sin(p.ph + s.galaxyT * 8)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - p.size, y: p.y - p.size,
                                            width: p.size * 2, height: p.size * 2)),
                     with: .color(col.opacity(0.55 * p.a * tw + 0.25 * p.a)))
            let gr = p.size * 3.2
            let gl = Gradient(colors: [col.opacity(0.20 * p.a), col.opacity(0)])
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr, width: gr * 2, height: gr * 2)),
                     with: .radialGradient(gl, center: CGPoint(x: p.x, y: p.y),
                                           startRadius: 0, endRadius: gr))
        }
    }

    // MARK: 返回聚合（几何背景先行 → 碎片聚合 → 名片带装饰渐显 → 碎片让位）

    static func drawMerge(_ ctx: inout GraphicsContext, _ s: RiftSnapshot, date: Date) {
        // 背景：与首页一致的细密几何密铺（返回即“组成几何图形背景”，不再纯黑）
        drawGeoBg(&ctx, s.viewSize, tes: s.homeTess, dt: 0, date: date, s: s)
        guard s.cardRect.width > 4 else { return }

        let t1 = clamp01(s.mergeT / DS.M.mergeT1)
        let t2 = clamp01((s.mergeT - DS.M.mergeT2Start) / DS.M.mergeT2Dur)
        // 碎片让位：尾段 0.3s 淡出，让真实名片从下方透出（避免结束瞬跳）
        let fade = 1 - clamp01((s.mergeT - 1.1) / 0.3)

        // 名片（含全套装饰）随 t2 渐显——结束帧 = idle 首帧
        if t2 > 0 {
            drawIdleCard(&ctx, s, alpha: t2)
        }

        let CX = s.cardRect.midX, CY = s.cardRect.midY
        guard let img = s.cardImg else { return }
        let t = date.timeIntervalSinceReferenceDate
        let image = Image(uiImage: img)
        // 卡片矩形（碎片局部坐标）：碎片显示区域 = 格子 ∩ 卡片，落位拼合出精确卡形
        let localCard = CGRect(x: s.cardRect.minX, y: s.cardRect.minY,
                               width: s.cardRect.width, height: s.cardRect.height)
        for b in s.blocks where fade > 0.01 {
            let dir = atan2(b.cy - CY, b.cx - CX)
            let rDist = (150 + Double(b.seed) * 160) * (1 - easeOutCubic(t1))
            let px = b.cx + cos(dir) * CGFloat(rDist)
            let py = b.cy + sin(dir) * CGFloat(rDist)
            let rel = Path(polygon: b.pts)
            let pieceAlpha = t1 * 0.95 * fade
            ctx.drawLayer { c in
                c.translateBy(x: px, y: py)
                c.drawLayer { inner in
                    inner.clip(to: rel)                    // 格子形状
                    inner.clip(to: Path(localCard.offsetBy(dx: -b.cx, dy: -b.cy)))  // ∩ 卡片矩形
                    inner.opacity = pieceAlpha
                    inner.draw(image,
                               in: CGRect(x: s.cardRect.minX - b.cx, y: s.cardRect.minY - b.cy,
                                          width: s.cardRect.width, height: s.cardRect.height))
                }
                // 描边：金色系与背景同源，呼吸相位与背景格线同步（同 seed 同频率）
                let br = 0.5 + 0.5 * sin(t * 1.1 + Double(b.seed) * Double.pi * 2)
                let strokeA = (0.28 + 0.22 * br) * fade
                c.opacity = fade
                c.stroke(rel, with: .color(Color(rgb: 0xE9CC8C, strokeA)), lineWidth: 1)
            }
        }
    }

    // MARK: 交换金流

    static func drawSwap(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        guard !s.swap.isEmpty else { return }
        _ = ctx
        ctx.drawLayer { c in
            c.addFilter(.shadow(color: Color(hex: 0xd9a84a).opacity(0.9), radius: 7))
            for e in s.swap {
                let tt = clamp01(e.t)
                let x = lerp(e.x0, e.x1, tt) + sin(tt * .pi * 5) * e.jx
                let y = lerp(e.y0, e.y1, tt) + cos(tt * .pi * 4) * e.jy
                let a = (1 - tt) * 0.9 * e.g
                guard a > 0.01 else { continue }
                c.opacity = a
                let r = e.size
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(hex: 0xd9a84a)))
            }
            c.opacity = 1
        }
    }

    // MARK: 溅落确认环

    static func drawSplash(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        guard let t = s.splashT else { return }
        let a = 1 - t
        let r = 14 + t * 90
        let c = CGPoint(x: s.cardRect.midX, y: s.cardRect.midY)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(Color(hex: 0xd9a84a).opacity(0.7 * a)), lineWidth: 2)
    }

    // MARK: 氛围切线

    static func drawAmb(_ ctx: inout GraphicsContext, _ s: RiftSnapshot) {
        guard s.ambAnimT >= 0, let seg = s.ambSeg else { return }
        let t = s.ambAnimT
        let x = lerp(seg.0.x, seg.1.x, t)
        let y = lerp(seg.0.y, seg.1.y, t)
        let dx = (seg.1.x - seg.0.x) * 0.06
        let dy = (seg.1.y - seg.0.y) * 0.06
        let red = DS.C.ambRed.opacity(0.88)
        ctx.drawLayer { c in
            c.addFilter(.shadow(color: DS.C.ambRed.opacity(0.9), radius: 10))
            var head = Path()
            head.move(to: CGPoint(x: x, y: y)); head.addLine(to: CGPoint(x: x + dx, y: y + dy))
            c.stroke(head, with: .color(red), lineWidth: 1.5)
        }
        var cross = Path()
        let sc: CGFloat = 6
        cross.move(to: CGPoint(x: x - sc, y: y)); cross.addLine(to: CGPoint(x: x + sc, y: y))
        cross.move(to: CGPoint(x: x, y: y - sc)); cross.addLine(to: CGPoint(x: x, y: y + sc))
        ctx.stroke(cross, with: .color(DS.C.ambRed.opacity(0.7)), lineWidth: 1)
    }
}
