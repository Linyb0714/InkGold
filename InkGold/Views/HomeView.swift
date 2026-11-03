import SwiftUI

// ============================================================
// 首页：顶栏 / 轻数据行 / 最近相遇 / 提示语 / 底栏 / 感知 tag / 卡手势层
// 布局锚点与原型 CSS 绝对定位一致
// ============================================================

struct TopBar: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text("相识")
                    .font(DS.F.brandName).tracking(1).foregroundStyle(DS.C.gold)
                Text("INKGOLD")
                    .font(DS.F.brandSub).tracking(2).foregroundStyle(DS.C.brandSub)
            }
            Spacer(minLength: 12)
            // 「我的」入口：当前主体几何徽记（与展开形状同源）
            Button {
                m.openProfile()
            } label: {
                Circle()
                    .fill(DS.C.chipBg)
                    .overlay(Circle().strokeBorder(DS.C.goldDim, lineWidth: 1))
                    .frame(width: 32, height: 32)
                    .overlay(GlyphBadge(shape: m.shapeType, size: 15).offset(y: -0.5))
            }
            .buttonStyle(PressScale(pressedScale: 0.9))
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x0b0b0d).opacity(0.92), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 92).offset(y: -40)
                .allowsHitTesting(false)   // 渐变仅为视觉，不拦截滑动（空白处需穿透至手势层）
        }
    }
}

struct StatsRow: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        HStack(spacing: 16) {
            StatCell(value: "\(m.store.count)", label: "名片夹")
            VSeparator()
            StatCell(value: "\(m.store.monthMeetCount())", label: "本月相识")
            VSeparator()
            StatCell(value: "\(DeckStore.cityFootprint)", label: "城市足迹")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.L.statsToTopbar)
    }

    struct StatCell: View {
        let value: String, label: String
        var body: some View {
            VStack(spacing: 3) {
                Text(value)
                    .font(DS.F.statNum).tracking(1).foregroundStyle(DS.C.statNum)
                    .shadow(color: Color(rgb: 0xD9A84A, 0.25), radius: 14)
                Text(label)
                    .font(DS.F.statLabel).tracking(2.5).foregroundStyle(DS.C.statLabel)
            }
        }
    }

    struct VSeparator: View {
        var body: some View {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color(rgb: 0xD9A84A, 0.3), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 1, height: 28)
        }
    }
}

// MARK: - 最近相遇

struct RecentMeets: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("最近相遇")
                    .font(DS.F.hrTitle).tracking(3).foregroundStyle(DS.C.recentTitle)
                LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.4), Color(rgb: 0xD9A84A, 0.03)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Text("全部 ›")
                    .font(DS.F.hrMore).tracking(1).foregroundStyle(DS.C.statLabel)
            }
            HStack(spacing: DS.L.recentGap) {
                ForEach(m.store.recentMeets) { meet in
                    RecentItem(meet: meet)
                }
            }
        }
        .frame(width: DS.L.recentW)
    }

    struct RecentItem: View {
        @Environment(FlowMachine.self) private var m
        let meet: MeetRecord
        var body: some View {
            let card = meet.card
            Button {
                if m.phase == .idle {
                    m.goDetail(idx: m.store.deck.firstIndex(where: { $0.id == card.id }) ?? 0)
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        GlyphBadge(shape: card.glyph, size: 13)
                        Text(card.name)
                            .font(DS.F.hrName).tracking(0.5).foregroundStyle(DS.C.recentName)
                    }
                    Text("\(meet.date) · \(meet.scene)")
                        .font(DS.F.hrSub).tracking(1).foregroundStyle(DS.C.recentDate)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    Text("来自 \(card.org)")
                        .font(DS.F.hrSub).tracking(0.5).foregroundStyle(DS.C.recentOrg)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 1)
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(rgb: 0x141217, 0.82),
                                                    Color(rgb: 0x0b0a0d, 0.90)],
                                           startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.C.hrBorder, lineWidth: 1))
            }
            .buttonStyle(PressScale(pressedScale: 0.96, pressedBorder: true))
        }
    }
}

// MARK: - 底栏

struct Dock: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        HStack(spacing: 8) {
            // 仅保留交换入口：裂变由卡片滑动触发、切线氛围自动播放，无需按钮
            // 走感知流程期间按钮即刻转为"感知中"态：点击必有即时反馈（曾因
            // 反馈弱+弹窗延迟 4.8s 被误认为"点了没响应"），同时防重复启动
            DockButton(title: m.senseOn ? "感知中 · \(m.distSteps[min(m.senseStep, m.distSteps.count - 1)])"
                                        : "交换",
                       style: .primary) {
                if m.phase == .idle && !m.senseOn { m.startSense() }
            }
            .frame(maxWidth: 200)
            .allowsHitTesting(!m.senseOn)
            .animation(.easeOut(duration: 0.25), value: m.senseOn)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, DS.L.dockPad)
        .padding(.bottom, DS.L.dockBottom)
    }

    enum Style { case primary, red, plain }

    struct DockButton: View {
        @Environment(FlowMachine.self) private var m
        let title: String
        let style: Style
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(DS.F.btn).tracking(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(bg)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(fg)
            }
            .buttonStyle(PressScale(pressedScale: 0.95))
        }

        private var bg: some ShapeStyle {
            switch style {
            case .primary:
                return AnyShapeStyle(LinearGradient(colors: [DS.C.btnPrimTop, DS.C.btnPrimBot],
                                                    startPoint: .top, endPoint: .bottom))
            case .red: return AnyShapeStyle(DS.C.btnRedBg)
            case .plain: return AnyShapeStyle(DS.C.btnBg)
            }
        }
        private var border: Color {
            style == .primary ? DS.C.goldDim : (style == .red ? DS.C.btnRedBr : DS.C.line)
        }
        private var fg: Color {
            style == .primary ? DS.C.gold : (style == .red ? DS.C.btnRed : DS.C.btnPlain)
        }
    }
}

// MARK: - 感知距离 tag（原型 distTag）

struct SenseTag: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        Group {
            if m.senseOn {
                let step = min(m.senseStep, m.distSteps.count - 1)
                Text("附近 · \(m.distSteps[step])")
                    .font(DS.F.distTag).tracking(1).foregroundStyle(DS.C.distTag)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(DS.C.tagBg)
                    .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: m.senseOn)
    }
}

// MARK: - 首页组装（chrome + 手势层）

@MainActor
struct HomeChrome: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            ZStack(alignment: .topLeading) {
                // 顶栏
                // 顶栏标题常驻：返回首页第一帧就显示标题，不参与 chromeReveal 渐显
                TopBar()
                    .padding(.top, m.safeTop)
                    .frame(width: W)

                // 轻数据行
                StatsRow()
                    .padding(.top, m.safeTop + 58)
                    .frame(width: W)
                    .modifier(Reveal(progress: m.chromeReveal, delay: 0.08))

                // 最近相遇（底部锚定 距屏底 110+safe）
                RecentMeets()
                    .padding(.bottom, m.safeBottom + DS.L.recentBottom)
                    .frame(width: W, height: H, alignment: .bottom)
                    .modifier(Reveal(progress: m.chromeReveal, delay: 0.18))

                // 提示语
                Text(m.hintText)
                    .font(DS.F.hint).tracking(1).foregroundStyle(DS.C.hint)
                    .padding(.bottom, m.safeBottom + DS.L.hintBottom)
                    .frame(width: W, height: H, alignment: .bottom)
                    .modifier(Reveal(progress: m.chromeReveal, delay: 0.26))

                // 感知 tag（卡顶上方 24）
                SenseTag()
                    .padding(.top, m.cardRect.minY - 24)
                    .frame(width: W, height: H, alignment: .top)

                // 底栏
                Dock()
                    .padding(.bottom, m.safeBottom)
                    .frame(width: W, height: H, alignment: .bottom)
                    .modifier(Reveal(progress: m.chromeReveal, delay: 0.34))
            }
        }
        .allowsHitTesting(m.phase.chromeVisible)
        // 返回聚合阶段即显示 chrome 容器：顶栏（标题 + 「我的」）常驻立现；
        // 其余元素仍受 chromeReveal=0 控制不可见，进入 idle 后按原顺序错峰浮现
        .opacity(m.phase.chromeVisible || m.phase == .merge ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: m.phase)   // 返回时极轻淡入
    }

    /// 首页名片手势：从屏幕任意位置（含屏外划入）开始拖动均可尝试，
    /// 轨迹与卡片相交时启动裂变——与 HTML 原型 stage 全屏监听语义一致；
    /// 裂变启动后继续跟手切缝。
    @MainActor
    struct CardGestureLayer: View {
        @Environment(FlowMachine.self) private var m

        var body: some View {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(
                        // 4→12pt：手指按压天然微动 2~8pt，阈值过低会抢走按钮 tap
                        // （真机"点了没响应"根因之一）；裂变靠大幅划动，12pt 起判依旧灵敏
                        DragGesture(minimumDistance: 12, coordinateSpace: .named("phone"))
                            .onChanged { v in
                                if m.phase == .idle {
                                    m.beginTrailIfNearCard(v.location, start: v.startLocation)
                                }
                                if m.phase == .trail {
                                    m.moveTrail(v.location)
                                }
                            }
                            .onEnded { _ in
                                if m.phase == .trail { m.endTrail() }
                                else if m.phase == .idle { m.cancelPendingTrail() }
                            }
                    )
            }
            .allowsHitTesting(m.phase == .idle || m.phase == .trail)
            .opacity(m.phase == .idle || m.phase == .trail ? 1 : 0)
        }
    }
}

// MARK: - 通用小组件

/// chrome 入场修饰：按全局进度 progress（0..1）与错峰 delay 计算
/// 透明度 + 轻微上浮位（0.5 进度窗口内完成，easeOut）
struct Reveal: ViewModifier {
    let progress: Double
    let delay: Double
    private var p: Double {
        let t = max(0, min(1, (progress - delay) / 0.5))
        return 1 - pow(1 - t, 2)   // easeOutQuad
    }
    func body(content: Content) -> some View {
        content
            .opacity(p)
            .offset(y: (1 - p) * 14)
    }
}

struct PressScale: ButtonStyle {
    var pressedScale: CGFloat = 0.94
    var pressedBorder = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .overlay {
                if pressedBorder && configuration.isPressed {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(rgb: 0xD9A84A, 0.4), lineWidth: 1)
                }
            }
    }
}

/// 几何徽记（指纹形状：内填充 + 描边）
struct GlyphBadge: View {
    let shape: GlyphShape
    let size: CGFloat
    var filled: Bool = false

    var body: some View {
        let poly = GlyphShape.path(fromPoints: GlyphShape.points[shape.rawValue], size: size)
        ZStack {
            poly.fill(Color(rgb: 0xD9A84A, 0.18))
            poly.stroke(filled ? Color(hex: 0xe9cc8c).opacity(0.95)
                               : Color(rgb: 0xC9A84A, 0.42),
                        lineWidth: 1.3)
        }
        .frame(width: size, height: size)
    }
}
