import SwiftUI
import Observation

// ============================================================
// 流程状态机：原型 idle→trail→scatter→galaxy→deck→merge 的完整平移
// 由 RiftCanvas 每帧调用 tick(dt) 推进，视图层只读状态
// ============================================================

enum Phase: Equatable {
    case idle       // 首页
    case trail      // 轨迹裂变（跟手分割）
    case scatter    // 松手 3D 散场
    case galaxy     // 银河汇聚
    case detail     // 二级页
    case merge      // 返回聚合

    var homeInteractive: Bool { self == .idle }
    var chromeVisible: Bool { self == .idle || self == .trail || self == .scatter }
}

// MARK: - 粒子

struct GalaxyParticle {
    var r, th, spin, v, size, ph: Double
    let color: (Double, Double, Double)
    let tail: CGFloat
    var x: CGFloat = 0, y: CGFloat = 0, a: Double = 0
}

struct SwapParticle {
    var t: Double
    let sp: Double, side: CGFloat
    let x0, y0, x1, y1: CGFloat
    let jx, jy: CGFloat
    let size: CGFloat, g: Double
}

// MARK: - 密铺缓存（Path 为 SwiftUI 绘制路径，与 tiles 同序）

struct TessCache {
    let key: String
    let shape: GlyphShape
    let tiles: [TessTile]
    let paths: [Path]
    var accents: [FloatingShape]
}

// MARK: - 状态机

@MainActor
@Observable
final class FlowMachine {

    let store = DeckStore()
    var homeTess: TessCache? = nil    // 全局唯一背景密铺（首页/二级页共享，随裂变形状切换）

    // 布局（全屏坐标，含安全区信息）
    var viewSize: CGSize = .zero
    var safeTop: CGFloat = 59
    var safeBottom: CGFloat = 34
    var cardRect: CGRect = .zero          // 首页"我的名片"绘制区（canvas 与占位视图对齐用）

    // 相位
    var phase: Phase = .idle
    var shapeCycle = 0
    var shapeType: GlyphShape = .hexagon
    var blocks: [RiftBlock] = []
    var trail: [CGPoint] = []
    var dragging = false

    // 银河 / 合并
    var galaxy: [GalaxyParticle] = []
    var galaxyT: Double = 0
    var mergeT: Double = 0

    // 感知 → 剪影弹窗 → 交换
    var senseOn = false
    var senseStep = 0
    var senseTimer: Double = 0
    var distSteps = ["3.1m", "2.6m", "2.1m", "1.6m", "1.1m"]
    var silhouette: (name: String, firm: String)?
    enum PopupState { case hidden, asking, sent }
    var popup: PopupState = .hidden
    var swapParticles: [SwapParticle] = []
    var splashT: Double? = nil

    // 氛围切线
    var ambOn = true
    var ambSeg: (CGPoint, CGPoint)? = nil
    var ambAnimT: Double = -1
    var ambNext: Double = 2.6
    var animClock: Double = 0

    // 「我的」页（几何扩散）：结构在 ProfileView.swift
    var profileScreen: ProfileScreen = .closed
    var profileScreenOpen: Bool { profileScreen != .closed }
    /// 几何扩散遮罩进度（0 收起 → 1 全屏）；收起必须先动画回 0 再置 closed，
    /// 否则外层底色 + 全屏 mask 残留导致黑屏遮盖（详见 openProfile/closeProfile）
    var profileProgress: Double = 0

    /// 「我的」页展开：遮罩从右上按钮位置涨满（0.5s easeOut，含 ±14° 回摆）
    /// 时序关键：新插入的视图没有动画前值，若与 progress 动画同帧插入，
    /// 首帧直接按终值（全屏）渲染、展开动画被吞——因此先以 progress=0
    /// 插入视图（首帧藏在按钮后不可见），挂载完成后再启动 0→1 生长动画
    func openProfile() {
        guard phase == .idle, profileScreen == .closed else { return }
        profileProgress = 0
        withAnimation(.easeOut(duration: 0.25)) { profileScreen = .list }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.05))   // 等插入首帧提交（≥2 帧）
            guard profileScreen != .closed else { return }   // 期间被关闭则不启动
            guard profileProgress < 0.99 else { return }     // 防御：已在展开
            withAnimation(.easeOut(duration: 0.5)) { profileProgress = 1 }
        }
    }

    /// 「我的」页收起：遮罩先缩回按钮位置，动画落定后再置 closed；
    /// 若等待期间被重新打开（progress 回到高值）则放弃收起
    func closeProfile() {
        guard profileScreen != .closed else { return }
        withAnimation(.easeIn(duration: 0.4)) { profileProgress = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.42))
            guard profileProgress <= 0.01 else { return }
            profileScreen = .closed
        }
    }

    // 二级页底部抽屉（点底部堆叠卡展开；结构在 DeckDrawerView.swift）
    var drawer: DeckDrawerState = .closed
    var drawerOpen: Bool { drawer != .closed }

    /// 键盘高度（抽屉/输入条联动：贴键盘沿、间距收紧；FlowMachine 单一事实源）
    var kbHeight: CGFloat = 0

    /// 抽屉展开：closed → half（底部升至名片轮播顶，上-名片信息 下-对话/编辑）
    func openDrawer() {
        guard phase == .detail, drawer == .closed else { return }
        withAnimation(DS.M.drawer) { drawer = .half }
    }

    /// 编辑抽屉：直接全屏（编辑无半屏形态），并让其自动聚焦唤起系统输入法
    func openDrawerFull() {
        guard phase == .detail, drawer == .closed else { return }
        withAnimation(DS.M.drawer) { drawer = .full }
    }

    /// 半屏 ↔ 全屏（右上 icon）
    func toggleDrawerFull() {
        guard drawer != .closed else { return }
        withAnimation(DS.M.drawer) { drawer = drawer == .full ? .half : .full }
    }

    /// 收起抽屉（bottom icon / 把手下拉 / 边缘右滑）
    func closeDrawer() {
        guard drawer != .closed else { return }
        withAnimation(.easeIn(duration: 0.32)) { drawer = .closed }
    }

    // 首页 chrome 入场进度（0 隐藏 → 1 完整）；首次启动直接 1，
    // merge 返回时从 0 随 tick 渐进，头部/底部元素错峰浮现
    var chromeReveal: Double = 1

    // 背景点线（原型 bgP）
    struct DotP { var x, y: CGFloat; let vx, vy: CGFloat; let ph: Double; var t: Double; let color: (Double, Double, Double) }
    var dots: [DotP] = []

    // 提示文案
    var hintText = "在名片上滑动 · 裂变进入"
    private var hintRevertAt: Double? = nil
    let idleHint = "在名片上滑动 · 裂变进入"

    // MARK: 布局

    func layout(size: CGSize, top: CGFloat, bottom: CGFloat) {
        let changed = size != viewSize || top != safeTop || bottom != safeBottom
        viewSize = size; safeTop = top; safeBottom = bottom
        guard changed else { return }
        initDots()
        recalcCardRect()
    }

    /// 首页"我的名片"位置（原型 layout()：垂直居中于 [safeTop+92, H-safeBottom-238]，
    /// 高度不足时按 0.72 下限收缩）
    private func recalcCardRect() {
        let W = viewSize.width, H = viewSize.height
        guard W > 10, H > 10 else { return }
        let zoneTop = safeTop + 100   // 统计区放大下沉后，卡片顶同步下移保持呼吸
        let zoneBottom = H - (safeBottom + 238)
        var cw = min(W * DS.L.homeCardFactor, DS.L.homeCardMax)
        let avail = zoneBottom - zoneTop
        if avail < DS.L.homeMinAvail {
            cw *= max(DS.L.homeShrinkFloor, avail / DS.L.homeMinAvail)
        }
        let ch = cw / DS.L.cardRatio
        cardRect = CGRect(x: (W - cw) / 2,
                          y: zoneTop + (avail - ch) / 2,
                          width: cw, height: ch)
    }

    /// 由占位视图上报的卡占位矩形（布局系统算出，canvas 直接使用）
    func reportCardPlaceholder(_ r: CGRect) {
        if r != cardRect { cardRect = r }
    }

    func initDots() {
        let W = viewSize.width, H = viewSize.height
        guard W > 0 else { return }
        let rnd = mulberry32(hashStr("bg\(Int(W))x\(Int(H))"))
        let n = max(16, Int(W / 15))
        let cols: [(Double, Double, Double)] = [(201, 168, 74), (120, 160, 200), (255, 110, 90), (200, 212, 230)]
        dots = (0..<n).map { i in
            DotP(x: rnd() * W, y: rnd() * H,
                 vx: (rnd() - 0.5) * 9, vy: (rnd() - 0.5) * 7,
                 ph: rnd() * 6.28, t: rnd() * 6.28,
                 color: cols[i % cols.count])
        }
    }

    // MARK: 首页卡拖动（轨迹裂变；从屏外划入也生效）

    /// 手指当前位置进入卡区（含边缘 26pt 吸附带）即启动裂变。
    /// 这样从屏幕外部划入、划到名片上时会自然触发；
    /// 划过但未真正相交则不启动，保持待机。
    private var pendingStart: CGPoint? = nil

    func beginTrailIfNearCard(_ location: CGPoint, start: CGPoint) {
        guard phase == .idle else { return }
        guard pendingStart == nil else { return }   // 已在跟手（每次拖动只判定一次边界穿越）
        let zone = cardRect.insetBy(dx: -26, dy: -26)
        if zone.contains(location) {
            beginTrail(location)
        }
    }

    /// 松手时若从未触发裂变（本次拖动未划到卡上），清理判定状态
    func cancelPendingTrail() {
        pendingStart = nil
    }

    func beginTrail(_ p: CGPoint) {
        pendingStart = p
        shapeType = GlyphShape(rawValue: shapeCycle % 3)!
        shapeCycle += 1
        store.currentIdx = 0                       // 主屏恒为本人名片
        blocks = buildRiftBlocks(cardRect: cardRect,
                                 seedStr: store.current.seed,
                                 shape: shapeType)
        phase = .trail; dragging = true; trail = [p]
    }

    func moveTrail(_ p: CGPoint) {
        guard dragging else { return }
        if let l = trail.last, hypot(p.x - l.x, p.y - l.y) > 5 {
            trail.append(p)
            processTrail(p)
        }
    }

    private func processTrail(_ p: CGPoint) {
        guard let a = trail.count >= 2 ? trail[trail.count - 2] : nil else { return }
        for i in blocks.indices {
            if !blocks[i].cut && !blocks[i].fly &&
                distSegment(px: blocks[i].cx, py: blocks[i].cy,
                            ax: a.x, ay: a.y, bx: p.x, by: p.y) < 40 {
                blocks[i].cut = true
            }
        }
    }

    func endTrail() {
        guard dragging else { return }
        pendingStart = nil
        toScatter()
    }

    func cancelTrail() {
        guard dragging, phase == .trail else { return }
        dragging = false; pendingStart = nil; trail = []; blocks = []
        phase = .idle
    }

    func toScatter() {
        dragging = false
        for i in blocks.indices { blocks[i].fly = true; blocks[i].flyT = 0; blocks[i].cut = true }
        phase = .scatter
        setHint("散开 · 3D 旋离")
    }

    func scatterDone() {
        // 跳过银河飞逝：碎片散场后直接进入二级页（几何密铺背景），
        // 进入耗时由 ~1.9s（散场0.6+银河1.3）缩至 ~0.6s；galaxy 代码保留不删
        toDetail()
        setHint("名片详情 · 左右滑动切换", revert: 2.2)
    }

    func mkGalaxy() -> [GalaxyParticle] {
        let now = timeSeed()
        let rnd = mulberry32(hashStr("gal\(now)"))
        let W = viewSize.width, H = viewSize.height
        let maxR = Double(hypot(W, H)) * 0.62
        return (0..<96).map { _ in
            let q = rnd()
            let color: (Double, Double, Double) =
                q < 0.55 ? (201, 168, 74) : (q < 0.85 ? (120, 160, 200) : (212, 220, 238))
            return GalaxyParticle(
                r: 60 + rnd() * maxR,
                th: rnd() * Double.pi * 2,
                spin: (rnd() - 0.5) * 0.6,
                v: 0.55 + rnd() * 0.55,
                size: 0.8 + rnd() * 1.6,
                ph: rnd() * Double.pi * 2,
                color: color,
                tail: 9 + rnd() * 8)
        }
    }

    // MARK: 二级页进出

    /// 裂变演示：模拟一次横向划过（原型 simulateTrail：24 步 / 16ms）
    func simulateTrail() {
        guard phase == .idle else { return }
        let y = cardRect.minY + cardRect.height * 0.42
        beginTrail(CGPoint(x: cardRect.minX + 6, y: y))
        Task { @MainActor in
            for i in 1...24 {
                try? await Task.sleep(for: .milliseconds(16))
                guard phase == .trail else { return }
                let x = lerp(cardRect.minX + 6, cardRect.maxX - 6, Double(i) / 24)
                trail.append(CGPoint(x: x, y: y))
                processTrail(CGPoint(x: x, y: y))
            }
            toScatter()
        }
    }

    func toDetail() {
        phase = .detail
    }

    /// 最近相遇 → 直达名片详情（背景形状 = 该名片指纹）
    func goDetail(idx: Int) {
        store.currentIdx = idx
        shapeType = store.current.glyph
        phase = .detail
        setHint("名片详情 · 左右滑动切换", revert: 2.2)
    }

    /// 边缘右滑返回（系统手势语义）：
    /// 我的→列表/关闭；detail→返回聚合；弹窗→关闭；其余忽略
    func edgeSwipeBack() {
        // 抽屉最优先（外部往里扫的返回语义）：full→half→closed
        if drawer == .full {
            if store.currentIdx == 0 {
                closeDrawer()          // 编辑无半屏形态：全屏直接收起
            } else {
                withAnimation(DS.M.drawer) { drawer = .half }
            }
            return
        }
        if drawer == .half {
            closeDrawer()
            return
        }
        if profileScreen == .list {
            closeProfile()
            return
        }
        if case .detail(let mod) = profileScreen {
            _ = mod
            withAnimation(.easeOut(duration: 0.25)) { profileScreen = .list }
            return
        }
        switch phase {
        case .detail:
            withAnimation(.easeOut(duration: 0.25)) { exitToMerge() }
        case .idle:
            if popup != .hidden { dismissPopup() }
        default:
            break
        }
    }

    func exitToMerge() {
        // 关闭残留覆盖层：若编辑/对话抽屉打开着直接点「关闭」退出，
        // 下次进入详情页会继续显示该抽屉，因此返回时一并复位
        drawer = .closed
        kbHeight = 0
        // 首页恒为本人名片：返回时不同步重置 currentIdx（那会在退出动画期间触发
        // 二级页组件重建 → 视觉"刷新流线"）；延迟到 merge 落定后复位
        phase = .merge
        mergeT = 0
        chromeReveal = 0                     // 返回后 chrome 从零错峰渐显
        // 碎片从首页背景网格动态读取（与待机密铺同源同相位，落位精确啮合）
        blocks = buildRiftBlocksFromTess(ensureHomeTess(), cardRect: cardRect)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DS.M.mergeTotal + 0.05))
            guard phase == .idle else { return }   // 期间未重进二级页才复位
            store.currentIdx = 0
        }
    }

    /// 返回聚合专用：从首页背景密铺中读取卡片区域覆盖的格子作为碎片。
    /// 与 buildRiftBlocks（裂变指纹）不同——这套碎片与背景同网格、同 seed，
    /// 聚拢落位后与背景格线呼吸同步，名片知是从背景几何中“显影”。
    func buildRiftBlocksFromTess(_ tess: TessCache?, cardRect: CGRect) -> [RiftBlock] {
        guard let tess, cardRect.width > 4 else {
            return buildRiftBlocks(cardRect: cardRect,
                                   seedStr: store.current.seed,
                                   shape: shapeType)
        }
        var arr: [RiftBlock] = []
        arr.reserveCapacity(64)
        let inset: CGFloat = -10   // 外扩 10pt：边缘格子与卡边相交也纳入，保证拼合无缝
        let zone = cardRect.insetBy(dx: inset, dy: inset)
        for (i, tile) in tess.tiles.enumerated() {
            let bbox = tile.bbox
            guard bbox.intersects(zone) else { continue }
            let pts = tile.pts.map { CGPoint(x: $0.x - tile.cx, y: $0.y - tile.cy) }
            // spin 由格位确定性派生（merge 不自转，仅保持字段完整）
            let spin = (tile.seed - 0.5) * 6
            arr.append(RiftBlock(id: i, cx: tile.cx, cy: tile.cy, pts: pts,
                                 seed: tile.seed, spin: spin))
        }
        return arr
    }

    // MARK: 感知 / 交换

    func startSense() {
        senseOn = true; senseStep = 0; senseTimer = 0
        // 即时反馈：感知启动立刻可见（此前 4.8s 后才弹窗，中间无任何提示）
        setHint("感知中 · 正在接近附近的名片…")
    }

    func confirmThrow() {
        guard popup == .asking else { return }
        popup = .sent
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard popup == .sent else { return }
            popup = .hidden
            startSwap()
        }
    }

    func dismissPopup() { popup = .hidden }

    func startSwap() {
        let W = viewSize.width, H = viewSize.height
        let rnd = mulberry32(hashStr("ex\(timeSeed())"))
        let midY = H * 0.42
        swapParticles = (0..<140).map { i in
            let s: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            return SwapParticle(
                t: rnd() * 0.2, sp: 0.006 + rnd() * 0.013, side: s,
                x0: W / 2 + s * 230, y0: midY + (rnd() * 40 - 20),
                x1: W / 2 - s * 150, y1: midY + (rnd() * 30 - 15),
                jx: (rnd() * 2 - 1) * 7, jy: (rnd() * 2 - 1) * 7,
                size: 0.9 + rnd() * 2, g: 0.4 + rnd() * 0.6)
        }
        setHint("交换中 · 金色名片流")
    }

    private func swapDone() {
        let np = poolCards[Int(Date().timeIntervalSince1970) % poolCards.count]
        store.collect(np, scene: "近场交换")
        splashT = 0
        setHint("收藏 +1 · 已收下 \(np.name) 的名片（共 \(store.count) 张）", revert: 2.2)
    }

    // MARK: 氛围切线

    /// 原型 cutPath：4 型随机切割线
    func cutPath() -> (CGPoint, CGPoint) {
        let r = mulberry32(timeSeed() % 7919 | 0)
        let cr = cardRect
        let x1 = cr.minX + cr.width * 0.08 + r() * cr.width * 0.5
        let y1 = cr.minY + cr.height * 0.15
        let k = r()
        if k < 0.4 {
            return (CGPoint(x: x1, y: y1), CGPoint(x: cr.maxX - cr.width * 0.08, y: cr.maxY - cr.height * 0.15))
        } else if k < 0.7 {
            return (CGPoint(x: cr.maxX - cr.width * 0.08, y: y1), CGPoint(x: cr.minX + cr.width * 0.08, y: cr.maxY - cr.height * 0.15))
        } else if k < 0.9 {
            let cy = cr.midY
            return (CGPoint(x: x1, y: cy), CGPoint(x: cr.minX + cr.width * 0.9, y: cy))
        } else {
            let cx = cr.midX
            return (CGPoint(x: cx, y: cr.minY + cr.height * 0.08), CGPoint(x: cx, y: cr.maxY - cr.height * 0.1))
        }
    }

    func triggerAmbOnce() {
        ambSeg = cutPath()
        ambAnimT = 0
        scheduleNextAmb()
    }

    private func scheduleNextAmb() {
        let rnd = mulberry32(timeSeed() | 1)
        ambNext = animClock + 8 + rnd() * 22
    }

    // MARK: 提示

    func setHint(_ text: String, revert: Double? = nil) {
        hintText = text
        hintRevertAt = revert.map { animClock + $0 }
    }

    // MARK: 每帧推进（Canvas 驱动）

    private var lastDate: Date? = nil

    func tick(_ date: Date) -> Double {
        let dt: Double
        if let last = lastDate { dt = min(0.05, date.timeIntervalSince(last)) }
        else { dt = 0 }
        lastDate = date
        animClock += dt

        // 提示回退
        if let at = hintRevertAt, animClock >= at, phase == .idle || phase == .detail {
            hintText = idleHint
            hintRevertAt = nil
        }

        // 散场推进
        if phase == .scatter {
            var allFly = true
            for i in blocks.indices where blocks[i].fly {
                blocks[i].flyT += dt * 1.7
                if blocks[i].flyT < 1 { allFly = false }
            }
            if allFly { scatterDone() }
        }

        // 银河推进
        if phase == .galaxy {
            galaxyT += dt / DS.M.galaxyDur
            let W = viewSize.width, H = viewSize.height
            let cx = W / 2, cy = H * 0.42
            for i in galaxy.indices {
                let p = galaxy[i]
                galaxy[i].th += galaxy[i].spin * dt / 2
                galaxy[i].r -= galaxy[i].v * (240 + 120 * easeOutCubic(clamp01(galaxyT))) * dt
                if galaxy[i].r <= 4 {
                    if galaxyT < 0.82 {
                        galaxy[i].r = Double(hypot(W, H)) * (0.3 + ((p.ph * 7919).truncatingRemainder(dividingBy: 1)) * 0.45)
                        galaxy[i].th = ((p.ph * 104729).truncatingRemainder(dividingBy: 1)) * Double.pi * 2
                        galaxy[i].v = 0.55 + ((p.ph * 1299709).truncatingRemainder(dividingBy: 1)) * 0.55
                    }
                }
                galaxy[i].x = cx + CGFloat(cos(galaxy[i].th) * galaxy[i].r)
                galaxy[i].y = cy + CGFloat(sin(galaxy[i].th) * galaxy[i].r * 0.72)
                galaxy[i].a = min(1, galaxyT * 6)
                    * clamp01((galaxy[i].r - 10) / 70)
                    * clamp01((1.12 - galaxyT) / 0.22)
            }
            if galaxyT >= 1.1 { toDetail() }
        }

        // 合并推进
        if phase == .merge {
            mergeT += dt
            if mergeT >= DS.M.mergeTotal {
                phase = .idle
                hintText = idleHint
                hintRevertAt = nil
            }
        }

        // 首页 chrome 入场推进（返回时错峰浮现，总时长 0.55s）
        if phase == .idle, chromeReveal < 1 {
            chromeReveal = min(1, chromeReveal + dt / 0.55)
        }

        // 感知推进
        if senseOn {
            senseTimer += dt / DS.M.senseStep
            if senseStep < distSteps.count - 1 {
                if senseTimer >= 1 { senseStep += 1; senseTimer = 0 }
            } else if senseTimer >= DS.M.senseLast {
                senseOn = false
                let idx = Int(Date().timeIntervalSince1970)
                silhouette = (silhouetteNames[idx % 4], silhouetteFirms[idx % 4])
                popup = .asking
                hintRevertAt = nil
            }
        }

        // 交换粒子推进
        if !swapParticles.isEmpty {
            var all = true
            for i in swapParticles.indices {
                swapParticles[i].t += dt / swapParticles[i].sp * 0.5
                if swapParticles[i].t < 1 { all = false }
            }
            if all {
                swapParticles = []
                swapDone()
            }
        }

        // 溅落环
        if splashT != nil {
            splashT! += dt / 0.5
            if splashT! >= 1 { splashT = nil }
        }

        // 氛围切线（自动）
        if ambOn, phase == .idle {
            if ambAnimT < 0, animClock >= ambNext { triggerAmbOnce() }
        }
        if ambAnimT >= 0 {
            ambAnimT += dt / DS.M.ambDur
            if ambAnimT > 1 { ambAnimT = -1; ambSeg = nil }
        }

        // 背景点线推进（原型速度 ×0.6）
        let Wd = viewSize.width, Hd = viewSize.height
        if Wd > 4 {
            for i in dots.indices {
                dots[i].t += dt
                dots[i].x += dots[i].vx * dt * 0.6
                dots[i].y += dots[i].vy * dt * 0.6
                let p = dots[i]
                if p.x < -18 { dots[i].x = Wd + 18 }
                else if p.x > Wd + 18 { dots[i].x = -18 }
                if p.y < -18 { dots[i].y = Hd + 18 }
                else if p.y > Hd + 18 { dots[i].y = -18 }
            }
        }

        // 漂浮异形推进（写回密铺缓存）
        if homeTess != nil {
            var a = homeTess!.accents
            for i in a.indices {
                a[i].y += a[i].vy * dt
                a[i].rot += a[i].vr * dt
                if a[i].y < -70 { a[i].y = Hd + 70 }
            }
            homeTess!.accents = a
        }

        return dt
    }

    /// 渲染快照（值类型，供 Canvas nonisolated 闭包绘制）
    func tickAndSnapshot(_ date: Date) -> RiftSnapshot {
        _ = tick(date)
        _ = ensureHomeTess()   // 全局唯一密铺：待机/裂变/详情/返回共享
        return snapshot()
    }

    func snapshot() -> RiftSnapshot {
        RiftSnapshot(phase: phase, viewSize: viewSize, cardRect: cardRect,
                     safeTop: safeTop, safeBottom: safeBottom,
                     blocks: blocks, trail: trail, dragging: dragging,
                     shapeType: shapeType,
                     galaxy: galaxy, galaxyT: galaxyT,
                     mergeT: mergeT, animClock: animClock,
                     dots: dots, homeTess: homeTess,
                     swap: swapParticles, splashT: splashT,
                     ambSeg: ambSeg, ambAnimT: ambAnimT,
                     cardImg: cardRect.width > 4
                        ? TextureRenderer.shared.card(card: store.current, size: cardRect.size)
                        : nil)
    }
}

/// 值类型渲染快照
struct RiftSnapshot {
    var phase: Phase = .idle
    var viewSize: CGSize = .zero
    var cardRect: CGRect = .zero
    var safeTop: CGFloat = 59
    var safeBottom: CGFloat = 34
    var blocks: [RiftBlock] = []
    var trail: [CGPoint] = []
    var dragging = false
    var shapeType: GlyphShape = .hexagon
    var galaxy: [GalaxyParticle] = []
    var galaxyT: Double = 0
    var mergeT: Double = 0
    var animClock: Double = 0
    var dots: [FlowMachine.DotP] = []
    var homeTess: TessCache?
    var swap: [SwapParticle] = []
    var splashT: Double? = nil
    var ambSeg: (CGPoint, CGPoint)? = nil
    var ambAnimT: Double = -1
    var cardImg: UIImage? = nil
}
