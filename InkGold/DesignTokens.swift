import SwiftUI

// ============================================================
// 设计令牌：全部数值与 HTML 原型（prototype.html）1:1 平移
// 每个常量旁标注原型出处，便于日后双向同步
// ============================================================

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    /// rgba(r,g,b,a) 便捷构造
    init(rgb: UInt32, _ alpha: Double) {
        self = Color(hex: rgb).opacity(alpha)
    }
}

enum DS {

    // MARK: - 色彩（原型 :root 与各组件 CSS）
    enum C {
        static let gold        = Color(hex: 0xd9a84a)   // --gold
        static let goldDim     = Color(hex: 0x8a6a2f)   // --gold-dim
        static let goldLight   = Color(hex: 0xe9cc8c)   // 233,204,140 徽记高亮
        static let goldBright  = Color(hex: 0xfff0cd)   // 255,240,205 首尾环高亮
        static let foilHi      = Color(hex: 0xffd98a)   // 金箔亮
        static let foilMid     = gold
        static let foilLo      = goldDim

        static let line        = Color(hex: 0x2a2a30)   // --line
        static let bgTop       = Color(hex: 0x0b0b0e)
        static let bgMid       = Color(hex: 0x070709)
        static let bgBottom    = Color(hex: 0x0b0b0e)
        static let mergeBg     = Color(hex: 0x060506)   // merge 全屏纯底
        static let cardPaper   = Color(hex: 0x0b0b0c)   // 名片纸底

        static let brandSub    = Color(hex: 0x8a8a93)   // .brand span
        static let statNum     = Color(hex: 0xdec98e)   // .home-stats .st i
        static let statLabel   = Color(hex: 0x8a8072)   // .home-stats .st span
        static let hint        = Color(hex: 0x5a5a62)   // .hint
        static let recentTitle = Color(hex: 0xc9a55e)   // .hr-head b
        static let recentName  = Color(hex: 0xe5dec9)   // .hr-it .nm
        static let recentDate  = Color(hex: 0x7a7466)   // .hr-it .dt
        static let recentOrg   = Color(hex: 0x5f5a4e)   // .hr-it .sc
        static let deckName    = Color(hex: 0xeee5d0)   // .deck-info h3
        static let deckTitleSub = Color(hex: 0xc9a55e)   // .deck-info .sub
        static let rowKey      = Color(hex: 0x8d7f5e)   // .drow .k
        static let rowVal      = Color(hex: 0xdcd8ca)   // .drow span:last
        static let contextText = Color(hex: 0x9a927f)   // .deck-context
        static let chatMe      = Color(hex: 0xe8dcb8)   // .bub.me
        static let chatThem    = Color(hex: 0xcfcfc8)   // .bub.them
        static let chatOnline  = Color(hex: 0x8fbf7f)   // .on-dot
        static let sendTitle   = Color(hex: 0xe2cb92)   // .send
        static let backTitle   = Color(hex: 0xd9c89a)   // .riffBack
        static let popBody     = Color(hex: 0x7a7a82)   // .pop-body
        static let btnPlain    = Color(hex: 0xcfcfc7)   // .btn
        static let btnRed      = Color(hex: 0xff6a5a)   // .btn.red
        static let distTag     = Color(hex: 0xd0d0c8)   // .dist-tag

        // 组件背景/边框（rgba 形式）
        static let infoBorder  = Color(rgb: 0xc4a84a, 0.24)   // .deck-info border
        static let infoTop     = Color(rgb: 0x141217, 0.90)   // .deck-info 渐变顶
        static let infoBottom  = Color(rgb: 0x0b0a0d, 0.95)   // .deck-info 渐变底
        static let hrBorder    = Color(rgb: 0xc4a84a, 0.16)   // .hr-it border
        static let navStroke   = Color(rgb: 0xc9a84a, 0.42)   // .nav-shape stroke
        static let navRing     = Color(rgb: 0xe9cc8c, 0.50)   // .nav-ring
        static let chipBg      = Color(hex: 0x141417)         // .chip
        static let btnBg       = Color(hex: 0x16161a)         // .btn bg
        static let btnPrimTop  = Color(hex: 0x241f15)
        static let btnPrimBot  = Color(hex: 0x191612)
        static let btnRedBg    = Color(hex: 0x1a0f0f)
        static let btnRedBr    = Color(hex: 0x5a1a1a)
        static let backBg      = Color(rgb: 0x141416, 0.72)   // .riffBack bg
        static let popBg       = Color(rgb: 0x121215, 0.97)   // .card-pop bg
        static let tagBg       = Color(rgb: 0x121215, 0.72)   // .dist-tag bg

        // 画布动态色
        static let seam        = Color(rgb: 0xff9664, 0.20)   // 255,150,100 分割缝
        static let edgeGlow    = Color(rgb: 0xff8c5f, 0.22)   // 255,140,95 散场边光
        static let sparkCore   = Color(rgb: 0xffebbe, 0.85)   // 255,235,190 光点核
        static let trailLine   = Color(hex: 0xD9783C)          // 217,120,60 轨迹线
        static let ambRed      = Color(hex: 0xFF2A2A)          // 255,42,42 切线
        static let netBlue     = Color(hex: 0x8CA0D2)          // 140,160,210 点线
    }

    // MARK: - 字体（原型 px → pt，PingFang SC 由系统字体自动承载）
    enum F {
        static func sys(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
        static let brandName   = sys(16, .semibold)
        static let brandSub    = sys(9.5)
        static let chip        = sys(11)
        static let btn         = sys(12.5)
        static let statNum     = sys(19.5, .semibold)
        static let statLabel   = sys(10)
        static let hint        = sys(11)
        static let hrTitle     = sys(11, .semibold)
        static let hrMore      = sys(9.5)
        static let hrName      = sys(11.5, .medium)
        static let hrSub       = sys(8.5)
        static let deckName    = sys(21, .semibold)
        static let deckSub     = sys(11.5)
        static let rowKey      = sys(10)
        static let rowVal      = sys(12.5)
        static let ctxText     = sys(10.5)
        static let ctxBold     = sys(10.5, .semibold)
        static let chatHead    = sys(12, .semibold)
        static let chatDot     = sys(9.5)
        static let bubble      = sys(11.5)
        static let bubbleTm    = sys(8.5)
        static let chipWord    = sys(10.5)
        static let chatBox     = sys(11)
        static let send        = sys(11)
        static let back        = sys(12)
        static let popTitle    = sys(12, .medium)
        static let popSub      = sys(10.5)
        static let popBody     = sys(11)
        static let popAct      = sys(13)
        static let distTag     = sys(11)
    }

    // MARK: - 布局常量（原型 layout()/CSS）
    enum L {
        static let cardRatio: CGFloat   = 1.9        // 名片宽:高
        static let homeCardMax: CGFloat = 430        // cw=Math.min(dw*0.9,430)
        static let homeCardFactor: CGFloat = 0.9
        static let homeMinAvail: CGFloat = 175       // avail<175 时收缩
        static let homeShrinkFloor: CGFloat = 0.72   // max(.72, avail/175)
        static let statsToTopbar: CGFloat = 8        // stats 顶距 topbar 底
        static let cardToStats: CGFloat = 38         // 卡顶距 stats 底（原型 topGap 126-88）
        static let recentBottom: CGFloat = 110       // 原型 .home-recent bottom
        static let hintBottom: CGFloat = 76          // 原型 .hint bottom
        static let dockBottom: CGFloat = 12          // 原型 .dock padding 底
        static let dockPad: CGFloat = 16             // dock 上下内边距
        static let recentW: CGFloat = 326
        static let recentGap: CGFloat = 8

        // 二级页
        static let detailPadH: CGFloat = 24          // .deck-page 左右 padding
        static let detailTopUnderSafe: CGFloat = 52  // 内容顶（状态栏下 52）
        static let backTopUnderSafe: CGFloat = 10    // 返回按钮顶
        static let stagePadV: CGFloat = 6            // .deck-stage 上 padding（下10）
        static let bottomGapTop: CGFloat = 10        // 各区块主间隔
        static let infoChatGap: CGFloat = 10         // .deck-bottom gap
        static let chatStackGap: CGFloat = 12        // 堆叠组件与上方区逻辑间隔
        static let chatStackOverlap: CGFloat = 16    // 堆叠组件向上轻压名片区域的量
        static let navItem: CGFloat = 18
        static let navGap: CGFloat = 8
        static let navVis: Int = 7                   // 几何导航可视数
        static let navMask: CGFloat = 24             // 两端渐隐宽度
        static let sideScale: CGFloat = 0.86         // 邻卡让位
        static let sideOpacity: CGFloat = 0.42
        static let sideBrightness: CGFloat = 0.66
        static let radiusInfo: CGFloat = 16
        static let radiusBig: CGFloat = 22
        static let infoPadH: CGFloat = 18          // 信息卡文字区左右内边距（实显与粉末渲染共用）
    }

    // MARK: - 动效（原型 cubic-bezier / 时长 / 阈值）
    enum M {
        static let snap = Animation.timingCurve(0.22, 0.8, 0.3, 1, duration: 0.32)   // .deck-track
        static let drawer = Animation.spring(response: 0.45, dampingFraction: 0.88)  // 底部抽屉 升/降/半↔全
        static let cardIn = Animation.timingCurve(0.2, 0.9, 0.3, 1.15, duration: 0.55) // deckCardIn
        static let fadeUp = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.55)
        static let floatDur: Double = 5.6            // deckFloat
        static let floatAmp: CGFloat = 5

        static let galaxyDur: Double = 1.2           // g.t += dt/1.2，t>=1.1 结束
        static let mergeT1: Double = 0.9
        static let mergeT2Start: Double = 0.9        // t2=(mergeT-0.9)/0.5
        static let mergeT2Dur: Double = 0.5
        static let mergeTotal: Double = 1.4
        static let scatterSpeed: Double = 1.7        // b.flyT += dt*1.7
        static let senseStep: Double = 0.9           // 距离步进
        static let senseLast: Double = 1.2           // 末步停留后弹窗
        static let tradeWait: Double = 0.8           // 确认后启动交换

        // 滑动判定
        static let swipeThMax: CGFloat = 64
        static let swipeThFactor: CGFloat = 0.18
        static let flickDist: CGFloat = 16
        static let flickVel: CGFloat = 0.55          // px/ms
        static let verticalPass: CGFloat = 18        // 竖向手势放行阈值

        // 切线氛围
        static let ambPeriod: ClosedRange<Double> = 9...31     // 8s + rand*22
        static let ambDur: Double = 0.5
    }
}
