import UIKit

// ============================================================
// 名片纹理渲染（原型 offs() 逐行平移）
// 深底白噪 + 金箔洒金 + 高光渐变 + 排版文字，按 seed 确定性生成
// ============================================================

final class TextureRenderer {
    static let shared = TextureRenderer()
    private var cache: [String: UIImage] = [:]
    private let lock = NSLock()

    func card(card: CardProfile, size: CGSize, screenScale: CGFloat = 2) -> UIImage {
        let cacheKey = "\(card.id)-\(card.contentKey)-\(Int(size.width))x\(Int(size.height))"
        lock.lock()
        if let hit = cache[cacheKey] { lock.unlock(); return hit }
        lock.unlock()

        let sc = screenScale
        let w = size.width * sc, h = size.height * sc
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt)
        let img = renderer.image { ctx in
            let g = ctx.cgContext
            let rnd = mulberry32(hashStr(card.seed))
            let W = w, H = h

            // 纸底
            g.setFillColor(UIColor(red: 0x0b / 255, green: 0x0b / 255, blue: 0x0c / 255, alpha: 1).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: W, height: H))

            // 白噪点（700 粒，alpha .06，0.4–2.4px）
            g.setAlpha(0.06)
            g.setFillColor(UIColor(white: 0.53, alpha: 1).cgColor)
            for _ in 0..<700 {
                let rw = CGFloat(rnd() * 2 + 0.4) * sc / 2
                g.fill(CGRect(x: rnd() * W, y: rnd() * H, width: rw, height: rw))
            }
            g.setAlpha(1)

            // 金箔（34–60 片，r .6–3.2，20% 概率十字光）
            let fl = 34 + Int(rnd() * 26)
            for _ in 0..<fl {
                let x = rnd() * W, y = rnd() * H
                let r = (0.6 + rnd() * 2.6) * sc / 2
                let q = rnd()
                g.setAlpha(0.25 + rnd() * 0.6)
                let color: UIColor
                if q > 0.72 { color = UIColor(hex: 0xffd98a) }
                else if q > 0.4 { color = UIColor(hex: 0xd9a84a) }
                else { color = UIColor(hex: 0x8a6a2f) }
                g.setFillColor(color.cgColor)
                g.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                if rnd() < 0.2 {
                    g.setStrokeColor(UIColor(hex: 0xffd98a, alpha: 0.5).cgColor)
                    g.setLineWidth(0.6 * sc / 2)
                    g.move(to: CGPoint(x: x - r * 3, y: y)); g.addLine(to: CGPoint(x: x + r * 3, y: y))
                    g.move(to: CGPoint(x: x, y: y - r * 3)); g.addLine(to: CGPoint(x: x, y: y + r * 3))
                    g.strokePath()
                }
            }
            g.setAlpha(1)

            // 高光渐变（左上 → 中部）
            let colors = [UIColor(white: 1, alpha: 0.08).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.5]) {
                g.saveGState()
                g.clip(to: CGRect(x: 0, y: 0, width: W, height: H))
                g.drawLinearGradient(grad,
                                     start: .zero,
                                     end: CGPoint(x: W * 0.6, y: H * 0.5),
                                     options: [])
                g.restoreGState()
            }

            // ---- 排版（真实名片式·放大字号版，随卡宽 350 基准等比）----
            // 布局（自上而下三段式，字号整体上调提高可读性）：
            //   ① 公司行：左上公司全称（13pt 金），右侧 CTFF 缩写徽标
            //   ② 主区：姓名大字（30pt）+ 部门/职位（14pt），左对齐大区块
            //   ③ 底部：分割线 + 联系方式两行 MOBILE/MAIL（12.5pt 值 + 9.5 标签）
            //   座右铭放主区右侧竖排版式或右侧区块（11.5pt 金调）
            let k = (W / 350) * 0.5
            let lx = 24 * sc / 2                       // 左边距
            let rx = W - 24 * sc / 2                    // 右边距
            func draw(_ text: String, color: UIColor, size: CGFloat, weight: UIFont.Weight,
                      x: CGFloat, yMid: CGFloat, alignRight: Bool = false) {
                let font = UIFont.systemFont(ofSize: size * k, weight: weight)
                let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                let sz = str.size()
                let px = alignRight ? x - sz.width : x
                str.draw(at: CGPoint(x: px, y: yMid - sz.height / 2))
            }
            /// 测量文本宽（布局避让用）
            func width(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
                let font = UIFont.systemFont(ofSize: size * k, weight: weight)
                return NSAttributedString(string: text, attributes: [.font: font]).size().width
            }
            func drawLabeled(_ tag: String, _ value: String, color: UIColor,
                             x: CGFloat, yMid: CGFloat) {
                let tagColor = UIColor(hex: 0x6a6a6d)
                let fontTag = UIFont.systemFont(ofSize: 9.5 * k, weight: .medium)
                let tagStr = NSAttributedString(string: tag + "  ", attributes: [.font: fontTag, .foregroundColor: tagColor])
                let fontV = UIFont.systemFont(ofSize: 12.5 * k, weight: .medium)
                let vStr = NSAttributedString(string: value, attributes: [.font: fontV, .foregroundColor: color])
                let ts = tagStr.size(), vs = vStr.size()
                let px = x
                let yTag = yMid - ts.height / 2 + (vs.height - ts.height) * 0.4
                tagStr.draw(at: CGPoint(x: px, y: yTag))
                vStr.draw(at: CGPoint(x: px + ts.width, y: yMid - vs.height / 2))
            }

            let goldHi = UIColor(hex: 0xe2cb92)
            let paper = UIColor(hex: 0xc9c9c0)
            let dim = UIColor(hex: 0x8a8a85)

            // ① 公司行（左上，13pt 金）+ 右侧缩写徽标
            draw(card.org, color: UIColor(hex: 0xd9a84a), size: 13, weight: .semibold,
                 x: lx, yMid: H * 0.105)
            // CTFF 徽标（右上角细边框胶囊，缩写取自括号）
            if let abbrev = card.org.firstMatch(of: /（([A-Za-z]+)）/)?.1 {
                let abbrevStr = "  " + abbrev + "  "
                let fontA = UIFont.systemFont(ofSize: 10 * k, weight: .bold)
                let astr = NSAttributedString(string: abbrevStr, attributes: [.font: fontA, .foregroundColor: UIColor(hex: 0xd9a84a)])
                let asz = astr.size()
                let pad: CGFloat = 4 * k
                let cw = asz.width + pad * 2, ch = asz.height + pad * 1.2
                let ox = rx - cw, oy = H * 0.105 - ch / 2
                // 胶囊描边
                g.setStrokeColor(UIColor(hex: 0xd9a84a, alpha: 0.55).cgColor)
                g.setLineWidth(1 * sc / 2 * k * 2)
                let rect = CGRect(x: ox, y: oy, width: cw, height: ch)
                let r = ch / 2
                g.move(to: CGPoint(x: ox + r, y: oy))
                g.addArc(center: CGPoint(x: ox + r, y: oy + r), radius: r,
                         startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
                g.addLine(to: CGPoint(x: ox + cw - r, y: oy + ch))
                g.addArc(center: CGPoint(x: ox + cw - r, y: oy + r), radius: r,
                         startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
                g.strokePath()
                // 缩写文字（垂直居中）
                astr.draw(at: CGPoint(x: ox + pad, y: oy + (ch - asz.height) / 2))
            }

            // ②主区：姓名（30pt 大字，左侧大区块）+ 部门（14pt）
            let nameY = H * 0.335
            draw(card.name, color: goldHi, size: 30, weight: .bold,
                 x: lx, yMid: nameY)
            // NAME 标签（姓名上方小字，紧贴）
            draw("NAME", color: UIColor(hex: 0xd9a84a, alpha: 0.55), size: 9.5,
                 weight: .semibold, x: lx, yMid: nameY - 24 * k)
            // 部门/职位（姓名下，14pt）
            draw(card.title, color: paper, size: 14, weight: .medium,
                 x: lx, yMid: H * 0.545)

            // 座右铭（主区右侧，右对齐、金调、11.5pt，与部门同行错开）
            let mottoColor = UIColor(hex: 0xb59a5c, alpha: 0.95)
            let mottoSize: CGFloat = 11.5
            if width(card.line, size: mottoSize, weight: .medium) > (rx - lx) * 0.52 {
                // 过长时换到部门下方整行显示（基准卡宽的一半为界）
                draw(card.line, color: mottoColor, size: mottoSize, weight: .medium,
                     x: lx, yMid: H * 0.665)
            } else {
                draw(card.line, color: mottoColor, size: mottoSize, weight: .medium,
                     x: rx, yMid: H * 0.545, alignRight: true)
            }

            // ③ 底部：分割线 + 联系方式（左对齐标签行，距底留白）
            g.setStrokeColor(UIColor(hex: 0xc4a84a, alpha: 0.5).cgColor)
            g.setLineWidth(1 * sc / 2)
            g.move(to: CGPoint(x: lx, y: H * 0.76))
            g.addLine(to: CGPoint(x: rx, y: H * 0.76))
            g.strokePath()

            if let mob = card.mobile {
                drawLabeled("MOBILE", mob, color: paper, x: lx, yMid: H * 0.855)
            } else {
                // 无手机号（展示版）：右侧画一个"交换名片"意象小徽记占位
                _ = dim
            }
            drawLabeled("MAIL", card.mail, color: dim, x: lx, yMid: H * 0.925)
        }

        lock.lock()
        cache[cacheKey] = img
        lock.unlock()
        return img
    }

    /// 轮播槽位完整位图：卡纹理 + 圆角裁剪 + 金边描边 + 双层投影，
    /// 一次烘焙（缓存）。Slot 直接显示位图，滑动 = 纯位移合成（GPU 零实时效果，
    /// 根治滑动掉帧/闪动——此前 clipShape+shadow 每帧对三张卡离屏重算）
    func slotBitmap(card: CardProfile, size: CGSize, screenScale: CGFloat = 3) -> UIImage {
        let key = "slot-\(card.id)-\(card.contentKey)-\(Int(size.width))x\(Int(size.height))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let pad: CGFloat = 46        // 阴影外扩裕量
        let W = size.width + pad * 2, H = size.height + pad * 2
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = screenScale
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt)
        let img = renderer.image { ctx in
            let g = ctx.cgContext
            let cardRect = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 12).cgPath

            // 第一层：黑色厚度投影（CG 用户空间 y 负 = 视觉向下）
            g.saveGState()
            g.setShadow(offset: CGSize(width: 0, height: -11), blur: 21,
                        color: UIColor.black.withAlphaComponent(0.68).cgColor)
            g.addPath(path)
            g.setFillColor(UIColor(hex: 0x0b0b0c).cgColor)
            g.fillPath()
            g.restoreGState()

            // 第二层：金色柔光
            g.saveGState()
            g.setShadow(offset: .zero, blur: 23,
                        color: UIColor(hex: 0xC9A84A).withAlphaComponent(0.12).cgColor)
            g.addPath(path)
            g.setFillColor(UIColor(hex: 0x0b0b0c).cgColor)
            g.fillPath()
            g.restoreGState()

            // 卡纹理（UIGraphics 语境绘制，保证方向正确；clip 圆角）
            UIGraphicsPushContext(g)
            let tex = self.card(card: card, size: size)
            g.saveGState()
            g.addPath(path)
            g.clip()
            tex.draw(in: cardRect)
            g.restoreGState()
            UIGraphicsPopContext()

            // 金边描边
            g.addPath(path)
            g.setStrokeColor(UIColor(hex: 0xC4A84A, alpha: 0.24).cgColor)
            g.setLineWidth(1 * screenScale / 2)
            g.strokePath()
        }

        lock.lock()
        cache[key] = img
        lock.unlock()
        return img
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
