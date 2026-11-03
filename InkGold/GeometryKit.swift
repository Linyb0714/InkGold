import CoreGraphics
import Foundation
import SwiftUI

// ============================================================
// 几何与随机引擎：mulberry32 / FNV-1a / 密铺生成，均从原型逐行平移
// （确定性：相同 seed 产出完全相同的碎片形貌 = 名片指纹）
// ============================================================

let TAU = CGFloat.pi * 2

/// 原型 mulberry32：可复现伪随机（严格按 JS 语义逐行平移，mod 2³²）
func mulberry32(_ seed: UInt32) -> () -> Double {
    var a = seed
    return {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (a | 1)              // imul(a^a>>>15, 1|a)
        let s = t &+ ((t ^ (t >> 7)) &* (t | 61))      // (t + imul(t^t>>>7, 61|t))
        t = s ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

/// 原型 hashStr（FNV-1a 32bit）
func hashStr(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in s.utf8 {
        h ^= UInt32(b)
        h = h &* 16777619
    }
    return h
}

func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

/// 毫秒时间戳截断为 UInt32 种子（低位熵足够；避免溢出 trap）
func timeSeed() -> UInt32 {
    UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    a + (b - a) * CGFloat(t)
}

enum GlyphShape: Int, CaseIterable {
    case triangle = 0   // 正三角
    case diamond  = 1   // 菱形
    case hexagon  = 2   // 正六边形

    /// 三形状点阵（原型 GLYPTS，viewBox -12..12）
    static let points: [String] = [
        "0,-9 7.8,4.5 -7.8,4.5",                       // 三角
        "0,-9 9,0 0,9 -9,0",                           // 菱形
        "7.8,4.5 0,9 -7.8,4.5 -7.8,-4.5 0,-9 7.8,-4.5" // 六边形
    ]
    static let sizes: [Int: Int] = [0: 3, 1: 4, 2: 6]  // 顶点数

    static func glyphOf(seed: String) -> GlyphShape {
        GlyphShape(rawValue: Int(hashStr(seed) % 3))!
    }

    /// 解析点阵字符串为 (x, y) 归一点（-12..12 → -1..1）
    static func vertexUnit(_ shape: GlyphShape) -> [CGPoint] {
        let parts = points[shape.rawValue]
            .split(separator: " ")
            .map { $0.split(separator: ",").compactMap { Double($0) } }
        return parts.map { CGPoint(x: $0[0] / 12, y: $0[1] / 12) }
    }

    /// 单位形状顶点（半径 r，中心 cx,cy）——原型 shapeVerts
    static func verts(_ shape: GlyphShape, cx: CGFloat, cy: CGFloat, r: CGFloat) -> [CGPoint] {
        let u = vertexUnit(shape)
        return u.map { CGPoint(x: cx + $0.x * r, y: cy + $0.y * r) }
    }

    /// 任意形状的 Path
    static func path(_ shape: GlyphShape, center: CGPoint, r: CGFloat) -> Path {
        let v = verts(shape, cx: center.x, cy: center.y, r: r)
        var p = Path()
        guard let f = v.first else { return p }
        p.move(to: f)
        for pt in v.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    /// SVG points 字符串 → Path（用于导航条徽记）
    static func path(fromPoints str: String, size: CGFloat) -> Path {
        var p = Path()
        let half = size / 2
        let pairs = str.split(separator: " ")
            .map { $0.split(separator: ",").compactMap { Double($0) } }
        guard let first = pairs.first else { return p }
        p.move(to: CGPoint(x: half + CGFloat(first[0]) / 12 * half,
                           y: half + CGFloat(first[1]) / 12 * half))
        for pair in pairs.dropFirst() {
            p.addLine(to: CGPoint(x: half + CGFloat(pair[0]) / 12 * half,
                                  y: half + CGFloat(pair[1]) / 12 * half))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 全局几何密度尺（唯一常数源：背景/裂变/碎片同一网格）
// 与原型 0.6 缩放档一致：三角/菱形基准边 62×0.6=37.2，六边形半径 42×0.6=25.2
enum GeoScale {
    static let dense: CGFloat = 0.6
    static let triEdge: CGFloat = 62 * dense
    static let hexRadius: CGFloat = 42 * dense
}

// MARK: - 裂变块（主屏卡片区域；与背景密铺同尺寸同网格）

struct RiftBlock: Identifiable {
    let id: Int
    let cx: CGFloat, cy: CGFloat       // 块中心
    let pts: [CGPoint]                 // 相对块中心的顶点
    let seed: CGFloat                  // 0..1
    var cut = false                    // 被轨迹划过
    var fly = false
    var flyT: Double = 0
    let spin: CGFloat                  // ±3π
}

/// 原型 buildBlocks：在 CARD 矩形内按形状密铺
func buildRiftBlocks(cardRect: CGRect, seedStr: String, shape: GlyphShape) -> [RiftBlock] {
    let rnd = mulberry32(hashStr(seedStr + "g\(shape.rawValue)"))
    var arr: [RiftBlock] = []
    var id = 0
    func mk(_ cx: CGFloat, _ cy: CGFloat, _ ptsAbs: [CGPoint]) {
        arr.append(RiftBlock(id: id, cx: cx, cy: cy,
                             pts: ptsAbs.map { CGPoint(x: $0.x - cx, y: $0.y - cy) },
                             seed: CGFloat(rnd()), spin: CGFloat((rnd() - 0.5) * 6)))
        id += 1
    }
    func tri(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) {
        mk((p.x + q.x + r.x) / 3, (p.y + q.y + r.y) / 3, [p, q, r])
    }
    let x0 = cardRect.minX, y0 = cardRect.minY
    switch shape {
    case .triangle, .diamond:
        let a: CGFloat = GeoScale.triEdge, h = a * sqrt(3) / 2
        let cols = Int(ceil(cardRect.width / a)) + 3
        let rows = Int(ceil(cardRect.height / h)) + 3
        for j in 0..<rows {
            for i in 0..<cols {
                let Gx = x0 - a + CGFloat(i) * a + CGFloat(j) * (a / 2)
                let Gy = y0 - h + CGFloat(j) * h
                let A = CGPoint(x: Gx, y: Gy)
                let B = CGPoint(x: Gx + a, y: Gy)
                let C = CGPoint(x: Gx + a * 1.5, y: Gy + h)
                let D = CGPoint(x: Gx + a * 0.5, y: Gy + h)
                if shape == .triangle {
                    tri(A, B, D); tri(B, C, D)
                } else {
                    mk((A.x + C.x) / 2, (A.y + C.y) / 2, [A, B, C, D])
                }
            }
        }
    case .hexagon:
        let R: CGFloat = GeoScale.hexRadius, hw = R * sqrt(3), vh = R * 1.5
        let cols = Int(ceil(cardRect.width / hw)) + 3
        let rows = Int(ceil(cardRect.height / vh)) + 3
        for j in 0..<rows {
            for i in 0..<cols {
                let cx = x0 - hw + CGFloat(i) * hw + CGFloat(j % 2) * (hw / 2)
                let cy = y0 - vh + CGFloat(j) * vh
                let p = (0..<6).map { k -> CGPoint in
                    let ang = CGFloat.pi / 6 + CGFloat(k) * CGFloat.pi / 3
                    return CGPoint(x: cx + cos(ang) * R, y: cy + sin(ang) * R)
                }
                mk(cx, cy, p)
            }
        }
    }
    return arr
}

// MARK: - 背景密铺（全屏，供主屏/二级页共用）

struct TessTile: Identifiable {
    let id: Int
    let pts: [CGPoint]                 // 绝对坐标
    let cx: CGFloat, cy: CGFloat
    let seed: CGFloat

    /// 包围盒（相交过滤用；绝对坐标）
    var bbox: CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct FloatingShape {
    let x: CGFloat
    var y: CGFloat
    let s: CGFloat
    var rot: CGFloat
    let vr: CGFloat, vy: CGFloat, ph: CGFloat
}

func buildTessellation(size: CGSize, shape: GlyphShape, radiusScale: CGFloat,
                       seedStr: String) -> (tiles: [TessTile], accents: [FloatingShape]) {
    let rnd = mulberry32(hashStr(seedStr))
    var tiles: [TessTile] = []
    var id = 0
    func tp(_ ptsAbs: [CGPoint]) {
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in ptsAbs { cx += p.x; cy += p.y }
        cx /= CGFloat(ptsAbs.count); cy /= CGFloat(ptsAbs.count)
        tiles.append(TessTile(id: id, pts: ptsAbs, cx: cx, cy: cy, seed: CGFloat(rnd())))
        id += 1
    }
    let W = size.width, H = size.height
    switch shape {
    case .triangle, .diamond:
        let a: CGFloat = 62 * radiusScale, h = a * sqrt(3) / 2
        let cols = Int(ceil(W / a)) + 3, rows = Int(ceil(H / h)) + 3
        for j in 0..<rows {
            for i in 0..<cols {
                let Gx = -a + CGFloat(i) * a + CGFloat(j) * (a / 2)
                let Gy = -h + CGFloat(j) * h
                let A = CGPoint(x: Gx, y: Gy)
                let B = CGPoint(x: Gx + a, y: Gy)
                let C = CGPoint(x: Gx + a * 1.5, y: Gy + h)
                let D = CGPoint(x: Gx + a * 0.5, y: Gy + h)
                if shape == .triangle {
                    tp([A, B, CGPoint(x: Gx + a * 0.5, y: Gy + h)])
                    tp([B, C, D])
                } else {
                    tp([A, B, C, D])
                }
            }
        }
    case .hexagon:
        let R: CGFloat = 42 * radiusScale, hw = R * sqrt(3), vh = R * 1.5
        let cols = Int(ceil(W / hw)) + 3, rows = Int(ceil(H / vh)) + 3
        for j in 0..<rows {
            for i in 0..<cols {
                let cx = -hw + CGFloat(i) * hw + CGFloat(j % 2) * (hw / 2)
                let cy = -vh + CGFloat(j) * vh
                let p = (0..<6).map { k -> CGPoint in
                    let ang = CGFloat.pi / 6 + CGFloat(k) * CGFloat.pi / 3
                    return CGPoint(x: cx + cos(ang) * R, y: cy + sin(ang) * R)
                }
                tp(p)
            }
        }
    }
    // 漂浮异形（原型 ACC：5 个）
    var accents: [FloatingShape] = []
    let rnd2 = mulberry32(hashStr("acc\(Int(W))x\(Int(H))"))
    let accK: CGFloat = 0.62 + 0.38 * radiusScale
    for _ in 0..<5 {
        accents.append(FloatingShape(
            x: rnd2() * W, y: rnd2() * H,
            s: (24 + rnd2() * 40) * accK,
            rot: rnd2() * TAU,
            vr: (rnd2() - 0.5) * 0.3,
            vy: -(5 + rnd2() * 9),
            ph: rnd2() * TAU))
    }
    return (tiles, accents)
}

// MARK: - 距离工具（原型 distSeg）

func distSegment(px: CGFloat, py: CGFloat,
                 ax: CGFloat, ay: CGFloat,
                 bx: CGFloat, by: CGFloat) -> CGFloat {
    let dx = bx - ax, dy = by - ay
    let L = dx * dx + dy * dy
    if L == 0 { return hypot(px - ax, py - ay) }
    var t = ((px - ax) * dx + (py - ay) * dy) / L
    t = max(0, min(1, t))
    return hypot(px - (ax + dx * t), py - (ay + dy * t))
}
