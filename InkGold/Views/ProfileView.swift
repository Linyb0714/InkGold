import SwiftUI

// ============================================================
// 「我的」页：由首页右上入口按钮为锚点，以当前主体几何图形
// 向外扩散展开（GeoExpandMask）；列表 + 模块二级页。
// 模块：我的名片 / 账户信息 / 氛围与动效 / 关于 / 隐私安全 / 反馈联系
// ============================================================

// MARK: - 模块枚举

enum ProfileModule: String, CaseIterable, Identifiable {
    case myCard   = "我的名片"
    case account  = "账户信息"
    case effects  = "氛围与动效"
    case about    = "关于相识"
    case privacy  = "隐私与安全"
    case feedback = "反馈与联系"

    var id: String { rawValue }

    var icon: GlyphShape {
        switch self {
        case .myCard: return .hexagon
        case .account: return .diamond
        case .effects: return .triangle
        case .about: return .hexagon
        case .privacy: return .diamond
        case .feedback: return .triangle
        }
    }

    /// 二级页是否为长文（隐私/反馈/关于）
    var isLongText: Bool {
        switch self {
        case .privacy, .feedback, .about: return true
        default: return false
        }
    }
}

enum ProfileScreen: Equatable {
    case closed
    case list
    case detail(ProfileModule)
}

// MARK: - 锚点位置（与 TopBar「我的」按钮对齐）

extension FlowMachine {
    var profileAnchor: CGPoint {
        // 与 TopBar「我的」按钮圆心对齐：右缘 padding 16 + 按钮半宽 16
        CGPoint(x: viewSize.width - 32, y: safeTop + 26)
    }
}

// MARK: - 展开容器（几何扩散转场）

@MainActor
struct ProfileView: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        // closed 时整层移出：彻底避免底色 + 全屏 mask 残留黑屏
        if m.profileScreen != .closed {
            GeometryReader { geo in
                ZStack {
                    switch m.profileScreen {
                    case .closed:
                        EmptyView()
                    case .list:
                        ProfileList(collapse: { m.closeProfile() })
                            .background(alignment: .top) {
                                ProfileGeoDecor()
                                    .ignoresSafeArea()
                            }
                            .transition(.opacity)
                    case .detail(let mod):
                        ProfileDetail(module: mod, collapse: { m.closeProfile() })
                            .background(alignment: .top) {
                                ProfileGeoDecor()
                                    .ignoresSafeArea()
                            }
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color(hex: 0x07070A))   // 遮住待机页的不透明底
                .mask(
                    GeoExpandMask(shape: m.shapeType,
                                  anchor: m.profileAnchor,
                                  rotation: m.profileProgress,
                                  progress: m.profileProgress)
                )
            }
            .ignoresSafeArea()
            .transition(.identity)   // 插入不另加淡入：遮罩几何生长是唯一展开语言，边缘保持锐利
            .allowsHitTesting(true)
        }
    }
}

/// 几何扩散蒙版：以 anchor 为中心的形状从 R0 涨到屏对角线，同时轻微旋转
struct GeoExpandMask: Shape {
    let shape: GlyphShape
    let anchor: CGPoint
    var rotation: CGFloat
    var progress: CGFloat     // 0..1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue; rotation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        if progress >= 0.999 { return Path(rect) }   // 全开
        let R0: CGFloat = 16
        let R1 = hypot(rect.width, rect.height) * 1.2
        let r = R0 + (R1 - R0) * progress
        let rot = (rotation - 0.5) * 0.5             // 展开过程 ±14° 回摆
        let v = GlyphShape.verts(shape, cx: anchor.x, cy: anchor.y, r: r)
        let c = CGPoint(x: anchor.x, y: anchor.y)
        let transformed = v.map { p in
            let dx = p.x - c.x, dy = p.y - c.y
            let cosR = cos(rot), sinR = sin(rot)
            return CGPoint(x: c.x + dx * cosR - dy * sinR,
                           y: c.y + dx * sinR + dy * cosR)
        }
        return Path(polygon: transformed)
    }
}

/// 我的页顶部几何装饰（当前形状的大轮廓，静态+呼吸）
struct ProfileGeoDecor: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            Canvas { ctx, size in
                _ = size
                let t = Date().timeIntervalSinceReferenceDate
                // 两个右上角大形状 + 一行渐隐小形状
                let cx = W - 86.0, cy: CGFloat = 46
                for (i, s) in [76.0, 110.0].enumerated() {
                    let a = 0.10 - Double(i) * 0.04 + 0.03 * sin(t * 0.9 + Double(i) * 2)
                    let p = Path(polygon: GlyphShape.verts(m.shapeType, cx: cx, cy: cy, r: s))
                    ctx.stroke(p, with: .color(Color(rgb: 0xC9A84A, a)), lineWidth: 1)
                }
                for k in 0..<7 {
                    let s: CGFloat = 11
                    let x = 30 + CGFloat(k) * 26
                    let y = 150 + CGFloat(k % 2) * 6
                    let p = Path(polygon: GlyphShape.verts(m.shapeType, cx: x, cy: y, r: s))
                    ctx.stroke(p, with: .color(Color(rgb: 0xC9A84A, 0.18 - CGFloat(k) * 0.018)),
                               lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 我的页（模块列表）

@MainActor
struct ProfileList: View {
    @Environment(FlowMachine.self) private var m
    var collapse: () -> Void
    @State private var showLogout = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("我的")
                        .font(DS.F.brandName).tracking(1).foregroundStyle(DS.C.gold)
                    Text("PROFILE")
                        .font(DS.F.brandSub).tracking(2).foregroundStyle(DS.C.brandSub)
                }
                Spacer()
                Button(action: collapse) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.C.backTitle)
                        .frame(width: 30, height: 30)
                        .background(Capsule().fill(DS.C.chipBg))
                        .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
                }
                .buttonStyle(PressScale())
            }
            .padding(.horizontal, 16)
            .padding(.top, m.safeTop + 10)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // 模块列表
                    VStack(spacing: 0) {
                        ForEach(Array(ProfileModule.allCases.enumerated()), id: \.element) { idx, mod in
                            ProfileRow(module: mod) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    m.profileScreen = .detail(mod)
                                }
                            }
                            if idx < ProfileModule.allCases.count - 1 {
                                Rectangle().fill(DS.C.line.opacity(0.6))
                                    .frame(height: 0.5)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                               startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
                    .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
                        .strokeBorder(DS.C.infoBorder, lineWidth: 1))
                    .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))

                    // 注销入口（独立警示行）
                    Button {
                        showLogout = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: 0xff6a5a))
                                .frame(width: 20, height: 20)
                            Text("注销账户")
                                .font(DS.F.rowVal).tracking(1)
                                .foregroundStyle(Color(hex: 0xff6a5a))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x5a5a62))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale(pressedScale: 0.985))
                    .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                               startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
                    .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
                        .strokeBorder(Color(rgb: 0xFF6A5A, 0.28), lineWidth: 1))
                    .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))

                    // 版本脚注
                    Text("相识 InkGold · v\(Bundle.main.appVersion) (build \(Bundle.main.appBuild))")
                        .font(DS.F.bubbleTm).tracking(1)
                        .foregroundStyle(Color(hex: 0x5a5a62))
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, m.safeBottom + 24)
            }
        }
        .alert("注销账户", isPresented: $showLogout) {
            Button("取消", role: .cancel) { }
            Button("注销并清除", role: .destructive) { performLogout() }
        } message: {
            Text("将清除本机的对话记录与名片编辑，名片夹恢复到初始状态。此操作不可撤销。")
        }
    }

    /// 注销：清空本地对话缓存 + 名片夹/最近相遇恢复初始 + 收起「我的」页
    private func performLogout() {
        ChatCache.shared.clearAll()
        m.store.resetToSeed()
        collapse()
    }
}

struct ProfileRow: View {
    let module: ProfileModule
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlyphBadge(shape: module.icon, size: 20)
                Text(module.rawValue)
                    .font(DS.F.rowVal).tracking(1)
                    .foregroundStyle(DS.C.rowVal)
                Spacer()
                if module == .effects {
                    // 氛围开关直接在行内提供
                    EffectsToggleInline()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x5a5a62))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(pressedScale: 0.985))
    }
}

extension Bundle {
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - 二级页（模块详情）

struct ProfileDetail: View {
    @Environment(FlowMachine.self) private var m
    let module: ProfileModule
    var collapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏（返回列表）
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { m.profileScreen = .list }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("我的")
                            .font(DS.F.back)
                    }
                    .foregroundStyle(DS.C.backTitle)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(DS.C.backBg)
                    .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(PressScale(pressedScale: 0.95))
                Spacer()
                Text(module.rawValue)
                    .font(DS.F.brandName).tracking(2).foregroundStyle(DS.C.gold)
                Spacer()
                Color.clear.frame(width: 64, height: 32)   // 平衡对齐
            }
            .padding(.horizontal, 16)
            .padding(.top, m.safeTop + 10)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, m.safeBottom + 24)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch module {
        case .myCard:
            MyCardDetail()
        case .account:
            AccountDetail()
        case .effects:
            EffectsDetail()
        case .about:
            AboutDetail()
        case .privacy:
            PrivacyDetail()
        case .feedback:
            FeedbackDetail()
        }
    }
}

// MARK: - 各模块内容

/// 卡片容器（列表页同款语言）
private struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
        .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .strokeBorder(DS.C.infoBorder, lineWidth: 1))
        .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))
    }
}

private struct DetailTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.F.rowKey).tracking(3)
            .foregroundStyle(DS.C.rowKey)
    }
}

private struct DetailBody: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.F.ctxText).tracking(0.5)
            .foregroundStyle(DS.C.contextText)
            .lineSpacing(5)
    }
}

struct MyCardDetail: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        DetailCard {
            let me = m.store.deck[0]
            Image(uiImage: TextureRenderer.shared.card(card: me, size: CGSize(width: 330, height: 330 / DS.L.cardRatio)))
                .resizable()
                .frame(height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(rgb: 0xC4A84A, 0.30), lineWidth: 1))
            DetailTitle(text: "几何指纹")
                .padding(.top, 14)
            DetailBody(text: "你的名片裂变碎片形貌由名片 ID 唯一决定（\(me.glyph == .triangle ? "三角形" : me.glyph == .diamond ? "菱形" : "六边形")族），永不与他人重样。在首页划过名片，指纹形状随每次裂变轮换。")
                .padding(.top, 6)
        }
    }
}

struct AccountDetail: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        DetailCard {
            let me = m.store.deck[0]
            ForEach([("姓名", me.name), ("公司", me.org), ("部门", me.title),
                     ("手机", me.mobile ?? "—"), ("邮箱", me.mail)], id: \.0) { k, v in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(k).font(DS.F.rowKey).tracking(3.5).foregroundStyle(DS.C.rowKey)
                        .frame(width: 52, alignment: .leading)
                    Text(v).font(DS.F.rowVal).foregroundStyle(DS.C.rowVal)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
            DetailBody(text: "名片信息可在名片列表的本人卡点击底部「名片修改」直接编辑，保存后同步更新首页大卡与列表展示。")
                .padding(.top, 8)
        }
    }
}

struct EffectsToggleInline: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        Toggle("", isOn: Binding(
            get: { m.ambOn },
            set: { m.ambOn = $0 }))
            .labelsHidden()
            .tint(Color(hex: 0xd9a84a))
            .scaleEffect(0.8)
    }
}

struct EffectsDetail: View {
    @Environment(FlowMachine.self) private var m
    var body: some View {
        DetailCard {
            HStack {
                DetailTitle(text: "待机氛围切线")
                Spacer()
                EffectsToggleInline()
            }
            DetailBody(text: "开启后，待机页的名片每隔一段时间会掠过一道科技切线，呼应安全巡检的产品意象。关闭仅在本次会话内生效。")
                .padding(.top, 8)
        }
    }
}

struct AboutDetail: View {
    var body: some View {
        DetailCard {
            DetailTitle(text: "相识 · INKGOLD")
            VStack(alignment: .leading, spacing: 8) {
                ForEach([("版本", "v\(Bundle.main.appVersion) (build \(Bundle.main.appBuild))"),
                        ("开发者", "林优斌"),
                        ("团队", "中电福富 · 网信安业务事业部"),
                        ("设计出品", "InkGold Studio")], id: \.0) { k, v in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(k).font(DS.F.rowKey).tracking(3.5).foregroundStyle(DS.C.rowKey)
                            .frame(width: 64, alignment: .leading)
                        Text(v).font(DS.F.rowVal).foregroundStyle(DS.C.rowVal)
                    }
                }
            }
            .padding(.top, 12)
            DetailBody(text: "一款黑金美学的数字名片夹。靠近即相识：近场发现、双向确认交换、几何裂变进入名片宇宙；碎片形貌由名片 ID 唯一决定，永不重样。")
                .padding(.top, 10)
        }
    }
}

struct PrivacyDetail: View {
    var body: some View {
        DetailCard {
            DetailTitle(text: "隐私与安全")
            DetailBody(text: """
            · 本原型阶段的全部数据仅保存在你的设备本地，不上传任何服务器。
            · 交换演示中的「附近名片」为模拟数据，不涉及真实的蓝牙扫描与定位。
            · 你的手机号等隐私字段仅在「首页大卡」本人视角展示；面向他人的轮播、对话与分享视图已自动替换为脱敏的展示版。
            · 银河、裂变等动效渲染完全在本地 GPU 完成，无任何网络行为。
            · 正式版将接入系统级近场框架（BLE / UWB），届时将以系统弹窗向你在授权请求中说明用途，可随时在系统设置中收回。
            """)
                .padding(.top, 8)
        }
    }
}

struct FeedbackDetail: View {
    var body: some View {
        DetailCard {
            DetailTitle(text: "反馈与联系")
            VStack(alignment: .leading, spacing: 8) {
                ForEach([("邮箱", "linyb0714@foxmail.com"),
                        ("事业线", "网信安业务事业部 · 安全产品"),
                        ("迭代计划", "名片对话 / 名片修改模块即将独立设计开放")], id: \.0) { k, v in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(k).font(DS.F.rowKey).tracking(3.5).foregroundStyle(DS.C.rowKey)
                            .frame(width: 64, alignment: .leading)
                        Text(v).font(DS.F.rowVal).foregroundStyle(DS.C.rowVal)
                    }
                }
            }
            .padding(.top, 12)
            DetailBody(text: "使用中遇到任何观感或手感问题（动效节奏、字号、亮度），描述场景即可，我们按参数化收敛。")
                .padding(.top, 8)
        }
    }
}
