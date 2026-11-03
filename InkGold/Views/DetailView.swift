import SwiftUI

// ============================================================
// 二级页：上=背面详细信息 / 中=名片正面轮播（三槽/步长1/头尾循环/邻卡让位）
//      底=名片对话堆叠组件（向上轻压名片区域；完整对话模块待独立设计）
// 滑动手势接管整页；竖向手势放行给对话区滚动
// ============================================================

@MainActor
struct DetailView: View {
    @Environment(FlowMachine.self) private var m

    // 轮播状态
    @State private var dragDX: CGFloat = 0
    @State private var animating = false
    @State private var entered = false

    // 顶部搜索状态（模糊匹配名片资源，点击直达轮播）
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// 模糊匹配：姓名 / 公司 / 部门职位 / 邮箱（不区分大小写）
    private var searchResults: [CardProfile] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return store.deck.filter { c in
            c.name.lowercased().contains(q)
            || c.org.lowercased().contains(q)
            || c.title.lowercased().contains(q)
            || c.mail.lowercased().contains(q)
        }
    }

    private var slotW: CGFloat { m.viewSize.width - DS.L.detailPadH * 2 }
    private var slotH: CGFloat { slotW / DS.L.cardRatio }
    private var base: CGFloat { -slotW }

    private var store: DeckStore { m.store }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            ZStack(alignment: .top) {
                // 顶部标题区：与首页 TopBar 同构（全宽、高52、贴 safeTop、左右各16）
                backButton
                    .frame(width: W)
                    .padding(.top, m.safeTop)
                    .padding(.bottom, 8)

                // 内容列（搜索/信息卡/轮播/底部堆叠），整体吃 detailPadH
                VStack(spacing: 0) {
                    // 顶部搜索（模糊匹配名片资源，点击直达轮播）
                    // zIndex 提升：结果下拉浮层需盖住下方信息卡，且保证可点
                    searchBar
                        .zIndex(20)

                    PowderCardInfo(card: store.current.displayCard,
                               contentWidth: W - DS.L.detailPadH * 2 - DS.L.infoPadH * 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .padding(.bottom, DS.L.bottomGapTop)

                    // 中：名片正面轮播
                    VStack(spacing: 0) {
                        stage
                            .background(stageMeasure)   // 记录轮播顶 y（抽屉 half 锚点）
                        NavGlyphs(cur: store.currentIdx, count: store.deck.count)
                            .padding(.top, 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // 底：堆叠卡片——本人卡=名片修改 / 他人卡=名片对话（点击升抽屉）
                    Group {
                        if store.currentIdx == 0 {
                            CardEditStack(card: m.store.deck[0])
                                .transition(.identity)   // 防闪动
                        } else {
                            ChatStack(card: store.current.displayCard)
                                .transition(.identity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 本人卡=编辑：直接全屏并唤起键盘；他人卡=对话：先半屏（快捷短语不唤键盘）
                        if store.currentIdx == 0 { m.openDrawerFull() } else { m.openDrawer() }
                    }
                    .padding(.top, DS.L.chatStackGap - DS.L.chatStackOverlap)
                    .offset(y: -DS.L.chatStackOverlap)
                    .zIndex(3)
                }
                .padding(.horizontal, DS.L.detailPadH)
                .padding(.top, m.safeTop + 60)   // 标题高52+8底距：搜索框不再与标题区重叠
                .padding(.bottom, m.safeBottom + 18)
            }
            .frame(width: W)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            // 底部抽屉（点底部堆叠卡展开；half=收起至名片轮播顶，full=全屏；边缘右滑逐级返回）
            .overlay(alignment: .bottom) {
                DeckDrawer(card: store.currentIdx == 0 ? m.store.deck[0] : store.current.displayCard,
                           isMine: store.currentIdx == 0,
                           stageMinY: stageMinY)
            }
        }
        .opacity(entered ? 1 : 0)
        .onAppear {
            withAnimation(DS.M.cardIn) { entered = true }
            prewarmTextures()   // 进页即预热邻里，首拍 commit 零卡顿
        }
        .simultaneousGesture(pageSwipe)
        // ★ 整个二级页唯一键盘工具栏（搜索 / 编辑 / 对话共用同一套）
        // 统一「相识」口径提示语 + 右侧下拉 icon，避免多处声明叠加成多条
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                KeyboardBar { dismissKeyboard() }
            }
        }
    }

    // 轮播顶坐标测量（phone 坐标系）——抽屉 half 高度锚点
    @State private var stageMinY: CGFloat = 0
    private var stageMeasure: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { stageMinY = g.frame(in: .named("phone")).minY }
                .onChange(of: g.frame(in: .named("phone")).minY) { _, new in
                    stageMinY = new
                }
        }
    }

    // MARK: 标题区（与首页 TopBar 同构：左「人脉/CONNECTIONS」，右关闭 X）

    private var backButton: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text("人脉")
                    .font(DS.F.brandName).tracking(1).foregroundStyle(DS.C.gold)
                Text("CONNECTIONS")
                    .font(DS.F.brandSub).tracking(2).foregroundStyle(DS.C.brandSub)
            }
            Spacer(minLength: 12)
            Button {
                withAnimation(.easeOut(duration: 0.25)) { m.exitToMerge() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.C.backTitle)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.C.chipBg))
                    .overlay(Circle().strokeBorder(DS.C.line, lineWidth: 1))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale(pressedScale: 0.9))
        }
        .frame(height: 52)   // 与首页 TopBar 同高，纵向对齐
        .padding(.horizontal, 16)
    }

    // MARK: 顶部搜索（名片列表上方：模糊匹配现有名片资源，点击直达轮播）

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.C.statLabel)
            TextField("搜索名片 · 姓名/公司/职位/邮箱", text: $searchText)
                .font(DS.F.chatBox).tracking(0.5)
                .foregroundStyle(.white.opacity(0.85))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { jumpToFirst() }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(rgb: 0x0B0B0D, 0.6))
        .overlay(Capsule().strokeBorder(searchFocused ? Color(rgb: 0xD9A84A, 0.4) : DS.C.line, lineWidth: 1))
        .clipShape(Capsule())
        .contentShape(Capsule())
        // 整条搜索框（含图标/内边距）均可点聚焦，避免首次点击落空
        .onTapGesture { searchFocused = true }
        // 结果浮层：有输入就显示（含未找到提示），不占位地盖在信息卡/轮播上方
        .overlay(alignment: .top) {
            if searchFocused, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resultsPanel
                    .padding(.top, 44)
                    .transition(.opacity)
            }
        }
    }

    /// 模糊匹配结果浮层（带结果数量 / 未找到提示）
    private var resultsPanel: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                Text("未找到匹配的名片")
                    .font(DS.F.hrSub).tracking(0.5)
                    .foregroundStyle(DS.C.hint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13).padding(.vertical, 12)
            } else {
                HStack(spacing: 6) {
                    Text("找到 \(searchResults.count) 张名片")
                        .font(DS.F.hrSub).tracking(0.5)
                        .foregroundStyle(DS.C.hint)
                    Spacer()
                }
                .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 7)
                Divider().overlay(DS.C.line.opacity(0.6))
                ForEach(searchResults) { c in
                    Button { jumpToCard(c.id) } label: {
                        HStack(spacing: 9) {
                            GlyphBadge(shape: c.glyph, size: 15)
                            Text(c.name)
                                .font(DS.F.hrName).tracking(0.5)
                                .foregroundStyle(DS.C.recentName)
                            Text(c.org)
                                .font(DS.F.hrSub).tracking(0.5)
                                .foregroundStyle(DS.C.recentOrg)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(c.title)
                                .font(DS.F.hrSub).tracking(0.5)
                                .foregroundStyle(DS.C.hint)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    if c.id != searchResults.last?.id {
                        Divider().overlay(DS.C.line.opacity(0.6)).padding(.leading, 40)
                    }
                }
            }
        }
        .background(Color(rgb: 0x0E0D11, 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.C.line, lineWidth: 1))
    }

    /// 回车直达首条
    private func jumpToFirst() {
        guard let first = searchResults.first else { return }
        jumpToCard(first.id)
    }

    /// 搜索点击直达：无动画切换轮播目标卡并收起搜索
    private func jumpToCard(_ id: String) {
        guard let idx = store.deck.firstIndex(where: { $0.id == id }) else { return }
        var t = Transaction(); t.animation = nil
        withTransaction(t) {
            store.currentIdx = idx
            dragDX = 0
            animating = false
            releasing = 0
        }
        prewarmTextures()
        searchFocused = false
        searchText = ""
    }

    /// 收起键盘（统一工具栏下拉）：resign 当前 responder；搜索框同步收起结果浮层
    private func dismissKeyboard() {
        searchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: 名片轮播舞台（三槽）

    private var stage: some View {
        let cur = store.current.displayCard
        let prev = store.deck[store.wrapIdx(store.currentIdx - 1)].displayCard
        let next = store.deck[store.wrapIdx(store.currentIdx + 1)].displayCard

        return HStack(spacing: 0) {
            Slot(card: prev, width: slotW, height: slotH)
            Slot(card: cur, width: slotW, height: slotH)
            Slot(card: next, width: slotW, height: slotH)
        }
        .offset(x: base + dragDX)
        // 原型语义：track 从舞台左缘起步再 translateX(-stageW)（CSS left:0），故 leading 对齐
        .frame(width: slotW, height: slotH + 16, alignment: .leading)
        .clipped()
        .padding(.vertical, DS.L.stagePadV)
    }

    /// 松手方向已定时的让位对象（与 offset 动画同步放大/缩小）
    /// 规则（与原型 shiftDeck 一致）：跟手阶段 C 全尺寸、L/R 压制；
    /// release 中：进位卡放开到全尺寸，C 收缩让位、离位卡保持压制
    @State private var releasing: Int = 0    // -1 右滑(L 进位) 0 无 1 左滑(R 进位)
    private var applyShrink: Bool { releasing == 0 }   // 跟手阶段才持续压制侧卡

    private func targetSide(left: Bool?) -> Bool {
        if left == nil { return releasing != 0 }              // C：release 时让位
        if releasing == 0 { return true }                      // 跟手：L/R 压制
        return !(releasing == 1 ? left == false : left == true) // 进位卡放开
    }

    // MARK: 整页横滑手势（原型：threshold + flick + 竖向放行）

    @State private var verticalPassed = false
    @State private var lastX: CGFloat = 0
    @State private var lastT: Date = .now
    @State private var velocity: CGFloat = 0

    /// 横滑方向判定锁定：false=未定 true=已按横滑接管；竖向显著时退出（放行给 ScrollView）
    @State private var horizontalLock = false

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("phone"))
            .onChanged { v in
                guard !animating, m.phase == .detail, m.drawer == .closed,
                      !searchFocused else { return }
                let dx = v.translation.width, dy = v.translation.height
                if !horizontalLock {
                    // 方向判定（前 ~10pt）：横向显著占优才接管，否则放行（滚动抽屉/消息流）
                    if abs(dy) >= abs(dx) { return }
                    if abs(dx) < 10 { return }
                    horizontalLock = true
                }
                // 速度采样（px/ms）
                let now = Date()
                let dtms = max(1, now.timeIntervalSince(lastT) * 1000)
                velocity = (v.location.x - lastX) / dtms
                lastX = v.location.x; lastT = now
                dragDX = dx
            }
            .onEnded { v in
                defer { horizontalLock = false }
                guard !animating, m.phase == .detail, !verticalPassed,
                      !searchFocused else {
                    verticalPassed = false
                    if m.drawer == .closed, abs(v.translation.width) < 4 { dragDX = 0 }
                    return
                }
                guard m.drawer == .closed else { return }   // 抽屉打开时锁轮播（避免与抽屉滚动打架）
                guard horizontalLock || abs(v.translation.width) > abs(v.translation.height) else {
                    withAnimation(DS.M.snap) { dragDX = 0 }
                    return
                }
                let dx = v.translation.width
                let th = min(DS.M.swipeThMax, slotW * DS.M.swipeThFactor)
                if dx < -th || (dx < -DS.M.flickDist && velocity < -DS.M.flickVel) {
                    shift(1)
                } else if dx > th || (dx > DS.M.flickDist && velocity > DS.M.flickVel) {
                    shift(-1)
                } else {
                    withAnimation(DS.M.snap) { dragDX = 0 }
                }
            }
    }

    private func shift(_ dir: Int) {
        guard !animating else { return }
        animating = true
        releasing = dir
        withAnimation(DS.M.snap) {
            dragDX = CGFloat(-dir) * slotW
        }
        // commit 务必等到滑动动画完全落定后再归零：若提前（竞态）会把尚未结束的
        // drag 一瞬置 0 → 切换成功时又左右滑一下。对齐 snap 时长并留 0.05s 余量
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.37) {
            // 切卡/复位/归零同一无动画事务提交：组件按新卡同步换内容，无转场帧
            var t = Transaction()
            t.animation = nil
            withTransaction(t) {
                store.currentIdx = store.wrapIdx(store.currentIdx + dir)
                releasing = 0
                animating = false
                dragDX = 0
            }
            prewarmTextures()   // 提前烘焙新邻里位图，下次滑动 commit 零卡顿
        }
    }

    /// 预热轮播邻里槽位位图（烘焙含卡纹理+阴影；分帧渲染不阻塞主流程）：
    /// commit 时新 prev/next 首渲染会造成主线程卡顿 → 名片卡"闪动"
    func prewarmTextures() {
        let s = m.store
        let idx = s.currentIdx
        let sz = CGSize(width: slotW - 4, height: slotH - 4)
        Task { @MainActor in
            for off in [-2, -1, 1, 2] {
                let c = s.deck[s.wrapIdx(idx + off)].displayCard
                _ = TextureRenderer.shared.slotBitmap(card: c, size: sz)
                try? await Task.sleep(for: .seconds(0.02))   // 让出一帧
            }
        }
    }

    // MARK: 槽位（侧卡让位缩放）

    private struct Slot: View {
        let card: CardProfile
        let width: CGFloat, height: CGFloat

        var body: some View {
            // 烘焙位图（卡+圆角+描边+双层阴影）：滑动纯位图位移；
            // 已去除侧卡让位的缩放/透明度/亮度动画（切换不再“从侧边重新进入”）
            Image(uiImage: TextureRenderer.shared.slotBitmap(
                card: card,
                size: CGSize(width: width - 4, height: height - 4)))
                .frame(width: width, height: height)   // 槽位占位；位图含阴影 padding 居中溢出
        }
    }
}

// MARK: - 几何导航条（7 项可视 / mask 渐隐 / 当前实心 / 首尾环）

struct NavGlyphs: View {
    let cur: Int
    let count: Int
    @State private var offsetX: CGFloat = 0

    var body: some View {
        let base = DS.Nav.calcBase()
        ZStack {
            HStack(spacing: DS.L.navGap) {
                ForEach(-4...4, id: \.self) { k in
                    let idx = ((cur + k) % count + count) % count
                    let card = SeedDeck.all[idx]
                    NavItem(shape: card.glyph, current: k == 0, isEnd: idx == 0 || idx == count - 1)
                }
            }
            .offset(x: offsetX)
        }
        // 原型 .nav-track left:0 起步：leading 对齐后 offset base 才是正确的中心锁定
        .frame(width: DS.Nav.window, height: 20, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: DS.L.navMask / DS.Nav.window),
            .init(color: .black, location: 1 - DS.L.navMask / DS.Nav.window),
            .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing))
        .onAppear {
            var t = Transaction(); t.animation = nil
            withTransaction(t) { offsetX = base }
        }
        .onChange(of: cur) { old, new in
            // 数字方向位移一次到位后瞬移回基线；无动画事务防转场帧
            let delta = ((new - old) % count + count) % count
            let dir = delta == 1 ? 1 : (delta == count - 1 ? -1 : 1)
            var t = Transaction(); t.animation = nil
            withTransaction(t) {
                offsetX = base - CGFloat(dir) * DS.Nav.step
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
                var t2 = Transaction(); t2.animation = nil
                withTransaction(t2) { offsetX = base }
            }
        }
    }
}

extension DS {
    enum Nav {
        static var step: CGFloat { DS.L.navItem + DS.L.navGap }                      // 26
        static var window: CGFloat {
            CGFloat(DS.L.navVis * Int(DS.L.navItem) + (DS.L.navVis - 1) * Int(DS.L.navGap))   // 174
        }
        /// 第 5 项（中心）对齐窗口中心
        static func calcBase() -> CGFloat {
            window / 2 - (4 * step + DS.L.navItem / 2)     // 87 - 113 = -26
        }
    }
}

/// 单个几何导航项（含首尾环）
struct NavItem: View {
    let shape: GlyphShape
    let current: Bool
    let isEnd: Bool

    var body: some View {
        let poly = GlyphShape.path(fromPoints: GlyphShape.points[shape.rawValue], size: DS.L.navItem)
        ZStack {
            if isEnd {
                Circle()
                    .stroke(current ? DS.C.goldBright.opacity(0.95) : DS.C.navRing,
                            lineWidth: 1)
                    .frame(width: DS.L.navItem * 0.9, height: DS.L.navItem * 0.9)
            }
            poly.fill(current ? Color(rgb: 0xD9A84A, 0.92) : .clear)
            poly.stroke(current ? Color(hex: 0xe9cc8c).opacity(0.95)
                                : (isEnd ? Color(hex: 0xe9cc8c).opacity(0.8) : DS.C.navStroke),
                        lineWidth: 1.3)
        }
        .frame(width: DS.L.navItem, height: DS.L.navItem)
        .animation(.easeOut(duration: 0.25), value: current)
    }
}

// MARK: - 二级页统一键盘工具栏（搜索 / 编辑 / 对话共用同一套）

/// 与「相识」品牌一致的统一键盘工具栏：
/// 左侧固定提示语「相识 · 正在输入」+ 右侧下拉 icon 收起键盘。
/// 全二级页只声明一处，避免多个输入框各自挂 toolbar 叠加成多条。
struct KeyboardBar: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x9a927f))
            Text("相识 · 正在输入")
                .font(.system(size: 11)).tracking(0.5)
                .foregroundStyle(Color(hex: 0x9a927f))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xd9c89a))
                    .frame(width: 64, height: 26)
                    .background(Capsule().fill(Color(hex: 0x17161c)))
                    .overlay(Capsule().strokeBorder(Color(rgb: 0xD9A84A, 0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
    }
}
