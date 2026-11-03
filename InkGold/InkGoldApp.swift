import SwiftUI

// ============================================================
// 墨金名片夹 InkGold · iOS 原生版 v0.1
// 架构：FlowMachine（状态机/参数）+ RiftCanvas（渲染）+ SwiftUI 层（UI/手势）
// 平移自 HTML 原型 prototype.html（15 张名片 · 轨迹裂变 · 银河 · 轮播详情）
// ============================================================

@main
struct InkGoldApp: App {
    @State private var machine = MainActor.assumeIsolated { FlowMachine() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(machine)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
struct RootView: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        GeometryReader { g in
            ZStack {
                // z0 渲染层（背景密铺/名片/裂变/银河/聚合/切线/交换/溅落）
                RiftCanvasView()

                // z1 首页卡手势层（在 chrome 之下：按钮等实体元素可点击，
                // 空白区域触摸自然穿透到此层，屏外划入/卡区跟手不受影响）
                HomeChrome.CardGestureLayer()
                    .ignoresSafeArea()

                // z2 首页 chrome（顶栏/数据行/最近相遇/提示/底栏/感知 tag）
                HomeChrome()
                    .ignoresSafeArea()

                // z3 二级页（上下布局：正面轮播 + 背面信息/对话）
                if m.phase == .detail {
                    DetailView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(3)
                }

                // z4 剪影确认弹窗
                ExchangeOverlay()
                    .ignoresSafeArea()
                    .zIndex(4)

                // z6 「我的」页（几何扩散展开，锚点=右上入口按钮）
                ProfileView()
                    .ignoresSafeArea()
                    .zIndex(6)

                // z7 边缘右滑返回（我的页列表/二级页、详情聚合返回、弹窗关闭）。
                // 必须位于 ProfileView 之上：我的页全屏接管触摸，
                // 层级低于它时左缘窄带收不到右滑手势
                EdgeBackGestureLayer()
                    .ignoresSafeArea()
                    .zIndex(7)
            }
            .coordinateSpace(name: "phone")
            .onAppear {
                syncInsets(g)
                runAutoDemoIfAsked()
            }
            .onChange(of: g.size) { _ in syncInsets(g) }
        }
        .ignoresSafeArea()
    }

    private func syncInsets(_ g: GeometryProxy) {
        let top = g.safeAreaInsets.top > 0 ? g.safeAreaInsets.top : 59
        let bottom = g.safeAreaInsets.bottom > 0 ? g.safeAreaInsets.bottom : 34
        m.safeTop = top
        m.safeBottom = bottom
        m.layout(size: CGSize(width: g.size.width,
                              height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom),
                 top: top, bottom: bottom)
    }

    /// 冒烟自检（仅当启动环境变量设置时触发；正常使用不受影响）
    /// INKGOLD_AUTODEMO=rift   → 1.5s 后自动模拟滑动，走完 裂变→散场→二级页
    /// INKGOLD_AUTODEMO=merge  → rift 链路 + 进入二级页 1.5s 后自动返回（验证聚合+chrome 入场）
    /// INKGOLD_AUTODEMO=sense  → 交换链路：感知步进→剪影弹窗→掷出→粒子流→收藏+1
    /// INKGOLD_AUTODEMO=drawer → 二级页抽屉回归：半屏(编辑)→全屏→半屏→收起→切他人卡→半屏(对话)
    private func runAutoDemoIfAsked() {
        let mode = ProcessInfo.processInfo.environment["INKGOLD_AUTODEMO"]
        guard ["rift", "merge", "profile", "sense", "carousel", "drawer"].contains(mode) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard m.phase == .idle else { return }
            switch mode {
            case "sense":
                m.startSense()
                // 感知 5 步（4×0.9 + 1.2 末停 ≈ 4.8s）→ 剪影弹窗
                for _ in 0..<120 where m.popup == .hidden {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard m.popup == .asking else { return }
                try? await Task.sleep(for: .seconds(0.6))
                m.confirmThrow()   // 粒子交换 → swapDone 收藏+1
            case "profile":
                m.openProfile()
                // 3s 后进入"关于"二级页，再 3s 后返回列表，最后用与真实交互一致的 closeProfile 收起
                try? await Task.sleep(for: .seconds(3))
                guard m.profileScreen == .list else { return }
                withAnimation(.easeOut(duration: 0.25)) { m.profileScreen = .detail(.about) }
                try? await Task.sleep(for: .seconds(3))
                guard case .detail = m.profileScreen else { return }
                withAnimation(.easeOut(duration: 0.25)) { m.profileScreen = .list }
                try? await Task.sleep(for: .seconds(2))
                guard m.profileScreen == .list else { return }
                m.closeProfile()
            case "carousel":
                // 进二级页 → 模拟轮播切到他人卡 → 返回（验证首页恒显本人卡）
                m.simulateTrail()
                for _ in 0..<80 where m.phase != .detail {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard m.phase == .detail else { return }
                try? await Task.sleep(for: .seconds(1.0))
                m.store.currentIdx = m.store.wrapIdx(m.store.currentIdx + 3)
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.easeOut(duration: 0.25)) { m.exitToMerge() }
            case "drawer":
                // 抽屉回归：编辑抽屉 半屏→全屏→半屏→收起；再切他人卡验对话抽屉
                m.simulateTrail()
                for _ in 0..<80 where m.phase != .detail {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard m.phase == .detail else { return }
                try? await Task.sleep(for: .seconds(1.0))
                m.openDrawer()                                   // 本人卡 → 编辑（half）
                try? await Task.sleep(for: .seconds(1.6))
                m.toggleDrawerFull()                             // full
                try? await Task.sleep(for: .seconds(1.4))
                m.toggleDrawerFull()                             // back half
                try? await Task.sleep(for: .seconds(1.2))
                m.closeDrawer()                                  // closed
                try? await Task.sleep(for: .seconds(1.2))
                m.store.currentIdx = m.store.wrapIdx(m.store.currentIdx + 1)   // 他人卡
                try? await Task.sleep(for: .seconds(1.0))
                m.openDrawer()                                   // → 对话（half）
                try? await Task.sleep(for: .seconds(1.2))
                m.toggleDrawerFull()                             // → 对话全屏
                try? await Task.sleep(for: .seconds(1.0))
                withAnimation(.easeOut(duration: 0.25)) { m.kbHeight = 336 }   // 模拟键盘弹出
            default:
                m.simulateTrail()
                guard mode == "merge" else { return }
                for _ in 0..<60 where m.phase != .detail {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard m.phase == .detail else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard m.phase == .detail else { return }
                withAnimation(.easeOut(duration: 0.25)) { m.exitToMerge() }
            }
        }
    }
}

/// 边缘右滑返回手势层（左缘窄带，iOS 系统返回语义）
/// 仅响应从左边缘起的向右拖动；detail 返回首页、弹窗打开时关闭弹窗
@MainActor
struct EdgeBackGestureLayer: View {
    @Environment(FlowMachine.self) private var m
    private let bandWidth: CGFloat = 24     // 左缘热区宽
    private let triggerDX: CGFloat = 70     // 右滑超过即触发

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            Color.clear
                .contentShape(Rectangle())
                .frame(width: bandWidth, height: H)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .named("phone"))
                        .onEnded { v in
                            guard v.startLocation.x <= bandWidth,
                                  v.translation.width > triggerDX,
                                  abs(v.translation.height) < 80 else { return }
                            m.edgeSwipeBack()
                        }
                )
                // 仅在可返回/可关闭的状态下接管左缘热区
                .allowsHitTesting(m.phase == .detail || m.popup != .hidden || m.profileScreenOpen || m.drawerOpen)
        }
    }
}
