import SwiftUI

// ============================================================
// 二级页底部抽屉：点底部堆叠卡展开
//   closed → half：底部升至名片轮播顶，中部轮播仍可见
//                内部布局 上-名片信息（DeckInfoCard） 下-对话/编辑
//   half ↔ full：右上 icon 切换（full 时另有关闭 icon）
//   边缘右滑（外部往里扫）：full → half → closed 逐级返回
//
// 名片对话（他人卡）：名片摘要头 / 日期徽 / 气泡流（对方左·灰，
//   我方右·金，头像=名片指纹徽记）/ 快捷短语 / 输入条（本地会话）
// 名片编辑（本人卡）：实时预览头 / 六字段表单 / 保存（首期草稿态，
//   不落库——CardProfile 为值类型种子数据，正式版接 SwiftData）
// ============================================================

enum DeckDrawerState: Equatable { case closed, half, full }

/// 键盘高度观察（UIKit 通知 → SwiftUI）：
/// 抽屉 ignoresSafeArea + 手动高度布局绕过了自动避让，键盘弹出时需手动抬升内容
@MainActor
final class KeyboardObserver: ObservableObject {
    /// 单一数据源：写入 FlowMachine.kbHeight（抽屉几何/输入条间距都读它）
    weak var machine: FlowMachine?
    private var startObs = false

    func start() {
        guard !startObs else { return }
        startObs = true
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                let d = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
                let dur = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                let h = min(d?.cgRectValue.height ?? 0, 420)
                withAnimation(.easeOut(duration: dur)) { self.machine?.kbHeight = h }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dur = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: dur)) { self.machine?.kbHeight = 0 }
            }
        }
    }
}

@MainActor
struct DeckDrawer: View {
    let card: CardProfile        // 本人=真实卡 / 他人=展示版（脱敏）
    let isMine: Bool
    let stageMinY: CGFloat       // 名片轮播顶 y（phone 坐标）— half 高度锚点
    @Environment(FlowMachine.self) private var m
    @StateObject private var kb = KeyboardObserver()

    var body: some View {
        GeometryReader { geo in
            // 几何规则（H = 全屏高，kb = 键盘高）：
            //   · 全屏：顶对齐物理顶；高度 = H - kb（有键盘时底边贴键盘上沿，无键盘占满）
            //   · 半屏：底对齐；高度 = 轮播顶以上剩余区（有键盘时整体上抬，底边贴键盘）
            let H = geo.size.height
            let kb = m.kbHeight
            let halfH = max(340, H - stageMinY)
            let h: CGFloat = m.drawer == .full
                ? max(120, H - kb)
                : (m.drawer == .half ? halfH : 0)
            let fullTop = m.drawer == .full
            let anchor: Alignment = fullTop ? .top : .bottom   // 全屏顶部对齐 / 半屏底部对齐
            let yShift: CGFloat = fullTop ? 0 : -kb           // 半屏有键盘时上抬贴键盘沿

            VStack(spacing: 0) {
                header
                    .padding(.top, fullTop ? m.safeTop : 0)
                LinearGradient(colors: [.clear, Color(rgb: 0xD9A84A, 0.28), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1).padding(.horizontal, 16)

                // 模块（对话/编辑）——单层滚动结构，无嵌套
                Group {
                    if isMine {
                        EditModule(card: card)
                    } else {
                        ChatModule(card: card)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(0, h), alignment: .top)
            .background(
                LinearGradient(colors: [DS.C.infoTop, Color(hex: 0x0A090D)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(.rect(topLeadingRadius: fullTop && m.kbHeight == 0
                             ? 0 : DS.L.radiusBig,
                             topTrailingRadius: fullTop && m.kbHeight == 0
                             ? 0 : DS.L.radiusBig))
            .overlay(
                RoundedRectangle(cornerRadius: DS.L.radiusBig, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.34), Color(rgb: 0xD9A84A, 0.10)],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .frame(maxHeight: .infinity, alignment: anchor)
            .offset(y: yShift)             // 全屏不偏移（高度已扣键盘）；半屏上抬贴键盘沿
        }
        .ignoresSafeArea()
        .allowsHitTesting(m.drawerOpen)   // 收起时整层不拦截触摸
        .onAppear { kb.machine = m; kb.start() }
    }

    // MARK: 把手行（grabber + 标题 + 右侧 icon 组；全屏态=完整标题区）

    private var header: some View {
        VStack(spacing: 9) {
            Capsule()
                .fill(Color(rgb: 0xC9A84A, 0.38))
                .frame(width: 36, height: 4)
                .padding(.top, 9)
            HStack(spacing: 10) {
                // 全屏态：标题升格（大标题+描边徽记，明确的标题区域）
                if m.drawer == .full {
                    ZStack {
                        let poly = GlyphShape.path(fromPoints: GlyphShape.points[card.glyph.rawValue],
                                                    size: 30)
                        poly.stroke(Color(rgb: 0xC9A84A, 0.75), lineWidth: 1.5)
                    }
                    .frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(isMine ? "身份" : "对话")
                        .font(m.drawer == .full
                              ? .system(size: 17, weight: .semibold)
                              : DS.F.chatHead)
                        .tracking(2.5)
                        .foregroundStyle(DS.C.recentTitle)
                    Text(isMine ? "IDENTITY" : "TALK")
                        .font(DS.F.brandSub).tracking(2)
                        .foregroundStyle(DS.C.brandSub)
                }
                Spacer()
                // 对话：半屏↔全屏切换 + 关闭；编辑（本人）无半屏形态，只保留关闭
                HStack(spacing: 8) {
                    if !isMine {
                        DrawerIconBtn(system: m.drawer == .full
                                      ? "arrow.down.right.and.arrow.up.left"     // 退出全屏→半屏
                                      : "arrow.up.left.and.arrow.down.right",    // 半屏→全屏
                                      gold: m.drawer != .full) {
                            m.toggleDrawerFull()
                        }
                    }
                    DrawerIconBtn(system: "xmark") {
                        m.closeDrawer()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }
}

/// 抽屉右上角 icon 按钮（30pt 圆 chip）
struct DrawerIconBtn: View {
    let system: String
    var gold = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(gold ? DS.C.gold : DS.C.backTitle)
                .frame(width: 36, height: 36)   // 36pt 热区：真机指尖易命中
                .background(Circle().fill(DS.C.chipBg))
                .overlay(Circle().strokeBorder(gold ? DS.C.goldDim : DS.C.line, lineWidth: 1))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScale(pressedScale: 0.9))
    }
}

// ============================================================
// 名片对话模块（他人卡）
// ============================================================

@MainActor
struct ChatModule: View {
    let card: CardProfile
    @Environment(FlowMachine.self) private var m

    /// 对话消息：统一使用可持久化的 ChatMessage（定义见 CardProfile.swift）
    @State private var msgs: [ChatMessage] = []
    @State private var draft = ""
    @State private var replyJob: Task<Void, Never>?
    /// 半屏点击输入区→升全屏的过渡中（防重复触发）
    @State private var pendingFocus = false
    @FocusState private var inputFocused: Bool

    static let quickWords = ["发我的名片", "约时间聊聊", "发见面地点", "回个电话"]
    private static let replies = ["收到！很高兴与你相识。",
                                  "好的，随时保持联系。",
                                  "这就去看看你分享的名片。"]

    var body: some View {
        VStack(spacing: 0) {
            header
            flow
            quickBar
            inputBar
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { loadHistory() }
        .onChange(of: card.id) { loadHistory() }   // 切换名片：读取该卡的历史会话
        // 离开全屏（edge swipe → half / 关闭）：收起键盘，避免键盘悬空盖住半屏
        .onChange(of: m.drawer) { _, st in
            if st != .full, inputFocused { inputFocused = false }
        }
        // 统一工具栏“下拉”走系统 resign：键盘隐藏时同步置空聚焦状态
        .onChange(of: m.kbHeight) { _, h in
            if h == 0, inputFocused { inputFocused = false }
        }
        // 退出/移除：取消挂起的模拟回复，避免关闭后仍向缓存写入消息
        .onDisappear { replyJob?.cancel() }
    }

    /// 键盘是否弹出（抽屉已整体上移贴键盘沿，底部留小间距即可）
    private var kbVisible: Bool { m.kbHeight > 0 }

    // MARK: 名片摘要头

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x6a5420), Color(hex: 0x14100a)],
                                     center: UnitPoint(x: 0.35, y: 0.28),
                                     startRadius: 1, endRadius: 38))
                .overlay(Circle().strokeBorder(DS.C.goldDim, lineWidth: 1))
                .frame(width: 40, height: 40)
                .overlay(GlyphBadge(shape: card.glyph, size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.C.recentName)
                HStack(spacing: 5) {
                    Text(card.org)
                        .font(DS.F.hrSub).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    Circle().fill(DS.C.chatOnline).frame(width: 4, height: 4)
                    Text("在线")
                        .font(DS.F.bubbleTm).tracking(0.5)
                        .foregroundStyle(Color(hex: 0x8fbf7f).opacity(0.85))
                }
            }
            Spacer(minLength: 8)
            // 相识日期 chip（ctx 前段）
            Text(card.ctx.split(separator: " · ").first.map(String.init) ?? "")
                .font(DS.F.bubbleTm).tracking(0.5)
                .foregroundStyle(Color(hex: 0x7a7466))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(DS.C.chipBg))
                .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 9)
    }

    // MARK: 消息流

    private var flow: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    Text("今天")
                        .font(DS.F.bubbleTm).tracking(1)
                        .foregroundStyle(Color(hex: 0x7a7466))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(DS.C.chipBg))
                        .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
                        .padding(.top, 4)
                    ForEach(msgs) { msg in
                        Bubble(msg: msg, glyph: card.glyph)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)     // 消息少不弹跳，滚动更自然
            .frame(maxHeight: .infinity)
            .onChange(of: msgs.count) { _ in
                scrollToBottom(proxy)   // 新消息：系统动画贴底
            }
            // 半屏/全屏切换、键盘唤起/折叠：布局高度变化后再贴底，始终展示最新消息
            .onChange(of: m.drawer) { _, _ in scrollToBottom(proxy, delay: 0.4) }
            .onChange(of: m.kbHeight) { _, _ in scrollToBottom(proxy, delay: 0.35) }
        }
    }

    /// 会话流滚到底部（展示最新消息）；可延迟以等抽屉/键盘几何变化完成
    private func scrollToBottom(_ proxy: ScrollViewProxy, delay: Double = 0) {
        guard let last = msgs.last else { return }
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: 快捷短语

    private var quickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Self.quickWords, id: \.self) { w in
                    Button {
                        // 直发：不唤起输入法（半屏态也可安心点，键盘不遮挡）
                        send(text: w)
                    } label: {
                        Text(w)
                            .font(DS.F.chipWord).tracking(0.5)
                            .foregroundStyle(DS.C.backTitle)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(
                                Capsule().strokeBorder(Color(rgb: 0xD9A84A, 0.35), lineWidth: 1))
                    }
                    .buttonStyle(PressScale(pressedScale: 0.93))
                }
            }
            .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 7)
        }
    }

    // MARK: 输入条

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("轻触输入…", text: $draft)
                .font(DS.F.chatBox).tracking(1)
                .foregroundStyle(.white.opacity(0.85))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
                // 键盘弹出会遮挡半屏内容：聚焦输入即自动升全屏
                .onChange(of: inputFocused) { _, focused in
                    if focused, m.drawer == .half {
                        m.toggleDrawerFull()
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(Color(rgb: 0x09090B, 0.85))
                .overlay(Capsule().strokeBorder(inputFocused ? Color(rgb: 0xD9A84A, 0.45) : DS.C.line,
                                                lineWidth: 1))
                .clipShape(Capsule())
            Button(action: send) {
                Text("发送")
                    .font(DS.F.send).tracking(1)
                    .foregroundStyle(DS.C.sendTitle)
                    .frame(width: 60, height: 36)
                    .background(LinearGradient(colors: [Color(hex: 0x2b2415), Color(hex: 0x1b1712)],
                                               startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(DS.C.goldDim, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(PressScale(pressedScale: 0.94))
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, kbVisible ? 6 : m.safeBottom + 12)   // 键盘贴沿：间距收紧
        // 半屏态整条输入区可点：首次点击即升全屏并在动画落定后聚焦。
        // 此前半屏→全屏的布局动画会打断首次响应，导致需点 2~3 次才弹输入法
        .overlay {
            if m.drawer == .half {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !pendingFocus else { return }
                        pendingFocus = true
                        m.toggleDrawerFull()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.5))
                            pendingFocus = false
                            if m.drawer == .full { inputFocused = true }
                        }
                    }
            }
        }
    }

    // MARK: 行为

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        send(text: text)
    }

    private func send(text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let mine = ChatMessage(cardID: card.id, mine: true, text: t,
                               time: nowTime(), sentAt: Date(), state: .sending)
        msgs.append(mine)
        ChatCache.shared.append(mine)
        // 本地回执模拟：sending → sent → delivered（接网络后由服务端回执驱动）
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.18))
            bumpState(mine.id, to: .sent)
            try? await Task.sleep(for: .seconds(0.35))
            bumpState(mine.id, to: .delivered)
        }
        replyJob?.cancel()
        replyJob = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            // 对方回复即视为已读我方此前消息
            markMineRead()
            let r = Self.replies[Int(Date().timeIntervalSince1970) % Self.replies.count]
            let reply = ChatMessage(cardID: card.id, mine: false, text: r,
                                    time: nowTime(), sentAt: Date())
            msgs.append(reply)
            ChatCache.shared.append(reply)
        }
    }

    /// 推进单条消息回执（内存 + 缓存）
    private func bumpState(_ id: String, to state: ChatDeliveryState) {
        guard let i = msgs.firstIndex(where: { $0.id == id }) else { return }
        msgs[i].state = state
        if state == .delivered, msgs[i].deliveredAt == nil { msgs[i].deliveredAt = Date() }
        ChatCache.shared.updateState(messageID: id, in: card.id, to: state)
    }

    /// 对方回复：将我方历史消息置为已读
    private func markMineRead() {
        for m in msgs where m.mine && m.state != .read {
            if let i = msgs.firstIndex(where: { $0.id == m.id }) {
                msgs[i].state = .read
                if msgs[i].deliveredAt == nil { msgs[i].deliveredAt = Date() }
                msgs[i].readAt = Date()
            }
            ChatCache.shared.updateState(messageID: m.id, in: card.id, to: .read)
        }
    }

    /// 读取该名片的历史会话；首次进入则写入示例会话（本地缓存，退出后保留）
    private func loadHistory() {
        let cached = ChatCache.shared.messages(for: card.id)
        if cached.isEmpty {
            seed()
        } else {
            msgs = cached
        }
    }

    private func seed() {
        let now = Date()
        let seeded = [
            ChatMessage(cardID: card.id, mine: false,
                        text: "你好，我是\(card.name)。交换到你的名片，很高兴认识。",
                        time: "09:24", sentAt: now.addingTimeInterval(-600)),
            ChatMessage(cardID: card.id, mine: true,
                        text: "很高兴认识！「不时不食」栏目也常读，改天约个炖汤局。",
                        time: "09:31", sentAt: now.addingTimeInterval(-540)),
            ChatMessage(cardID: card.id, mine: false, text: "一言为定。",
                        time: "09:33", sentAt: now.addingTimeInterval(-520)),
        ]
        msgs = seeded
        ChatCache.shared.replace(seeded, for: card.id)
    }

    private func nowTime() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

/// 气泡行：对方左（灰底 + 指纹徽记头像） / 我方右（金底）
private struct Bubble: View {
    let msg: ChatMessage
    let glyph: GlyphShape

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !msg.mine {
                GlyphBadge(shape: glyph, size: 26)
                    .padding(.bottom, 14)
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: msg.mine ? .trailing : .leading, spacing: 3) {
                Text(msg.text)
                    .font(DS.F.bubble).tracking(0.3)
                    .foregroundStyle(msg.mine ? DS.C.chatMe : DS.C.chatThem)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(msg.mine ? Color(rgb: 0xD9A84A, 0.13) : Color(rgb: 0x34363C, 0.46))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(msg.mine ? Color(rgb: 0xD9A84A, 0.32)
                                               : Color(white: 1, opacity: 0.05), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 5) {
                    Text(msg.time)
                        .font(DS.F.bubbleTm).foregroundStyle(.white.opacity(0.42))
                    if msg.mine {
                        Text(stateText(msg.state))
                            .font(DS.F.bubbleTm)
                            .foregroundStyle(stateColor(msg.state))
                    }
                }
            }
            if msg.mine {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x6a5420), Color(hex: 0x14100a)],
                                         center: UnitPoint(x: 0.35, y: 0.28),
                                         startRadius: 1, endRadius: 26))
                    .overlay(GlyphBadge(shape: glyph, size: 16))
                    .frame(width: 26, height: 26)
                    .padding(.bottom, 14)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func stateText(_ s: ChatDeliveryState) -> String {
        switch s {
        case .sending: return "发送中"
        case .sent: return "已发送"
        case .delivered: return "已送达"
        case .read: return "已读"
        case .failed: return "发送失败"
        }
    }

    private func stateColor(_ s: ChatDeliveryState) -> Color {
        switch s {
        case .failed: return Color(hex: 0xff6a5a)
        case .read: return Color(hex: 0x8fbf7f).opacity(0.8)
        default: return .white.opacity(0.42)
        }
    }
}

// ============================================================
// 名片编辑模块（本人卡）
// ============================================================

@MainActor
struct EditModule: View {
    let card: CardProfile
    @Environment(FlowMachine.self) private var m

    /// 可编辑字段（与 CardEditStack 字段清单一致，定版供后续持久化）
    private static let fields: [(label: String, key: String)] = [
        ("姓名", "name"), ("公司", "org"), ("部门/职位", "title"),
        ("座右铭", "line"), ("手机", "mobile"), ("邮箱", "mail"),
    ]

    @State private var draft: [String: String] = [:]
    @State private var saved = false
    /// 按字段 key 区分焦点（单一工具栏 + 可自动聚焦首个字段）
    @FocusState private var kbFocused: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                // 实时预览头（跟随草稿即时变化）
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft["name"] ?? "")
                        .font(DS.F.deckName).tracking(2)
                        .foregroundStyle(DS.C.deckName)
                    Text(draft["org"] ?? "")
                        .font(DS.F.deckSub).tracking(1.5)
                        .foregroundStyle(DS.C.deckTitleSub)
                }
                .padding(.top, 8)

                // 表单
                VStack(spacing: 11) {
                    ForEach(Self.fields, id: \.key) { f in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(f.label)
                                .font(DS.F.rowKey).tracking(3)
                                .foregroundStyle(DS.C.rowKey)
                            TextField("—", text: bind(f.key))
                                .font(DS.F.rowVal).tracking(0.5)
                                .foregroundStyle(DS.C.rowVal)
                                .focused($kbFocused, equals: f.key)
                                .submitLabel(.done)
                                .onSubmit { hideKb() }
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(Color(rgb: 0x09090B, 0.8))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(DS.C.line, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Text("修改即刻保存并应用到名片 · 云同步与指纹重铸将在正式版提供")
                    .font(DS.F.ctxText).tracking(0.5)
                    .foregroundStyle(DS.C.hint)
                    .padding(.top, 2)

                // 保存（写回 store.deck[0]，即刻生效：首页/轮播/信息卡同步更新）
                Button {
                    save()
                } label: {
                    Text(saved ? "已保存 ✓" : "保存修改")
                        .font(DS.F.btn).tracking(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(LinearGradient(colors: [DS.C.btnPrimTop, DS.C.btnPrimBot],
                                                   startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(DS.C.goldDim, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(DS.C.gold)
                        .opacity(saved ? 0.75 : 1)
                }
                .buttonStyle(PressScale(pressedScale: 0.97))
            }
            .padding(.horizontal, DS.L.detailPadH)
            .padding(.top, 10)
            .padding(.bottom, m.safeBottom + 20)
        }
        .scrollDismissesKeyboard(.interactively)   // 下拉表单即收键盘
        .scrollBounceBehavior(.basedOnSize)        // 内容量不足时不弹跳
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { reload() }
        .onChange(of: card.id) { reload() }
        // 编辑抽屉为全屏：进入即自动聚焦首字段→唤起系统输入法；离开则收键盘
        .onChange(of: m.drawer) { _, st in
            if st == .full {
                focusFirstField()
            } else {
                hideKb()
            }
        }
        // 统一工具栏“下拉”走系统 resign：键盘隐藏时同步置空聚焦状态
        .onChange(of: m.kbHeight) { _, h in
            if h == 0, kbFocused != nil { kbFocused = nil }
        }
    }

    private func hideKb() { kbFocused = nil }

    /// 进入全屏编辑后自动聚焦首个字段（等抽屉升起动画基本落定）
    private func focusFirstField() {
        guard kbFocused == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            guard m.drawer == .full, kbFocused == nil else { return }
            kbFocused = Self.fields.first?.key
        }
    }

    private func save() {
        m.store.saveOwnCard(
            name: draft["name"] ?? "", org: draft["org"] ?? "",
            title: draft["title"] ?? "", line: draft["line"] ?? "",
            mobile: draft["mobile"] ?? "", mail: draft["mail"] ?? "")
        hideKb()
        saved = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            saved = false
        }
    }

    private func reload() {
        draft = [
            "name": card.name, "org": card.org, "title": card.title,
            "line": card.line, "mobile": card.mobile ?? "", "mail": card.mail,
        ]
    }

    private func bind(_ key: String) -> Binding<String> {
        Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 })
    }
}
