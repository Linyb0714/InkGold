import SwiftUI

// ============================================================
// 名片背面：信息卡（金边/角标/结构化行/相识上下文）
//      + 名片对话堆叠组件（本版轻量展示；完整对话模块待独立设计）
//      ChatPanel（完整对话面板）暂保留不挂载，供后续独立设计演进
// ============================================================

// MARK: - 名片对话·堆叠组件（轻量占位版）

/// 层叠“名片对话”卡组：最新一张完整展示，历史消息在其上方露出边缘，
/// 呼应名片堆叠意象；整组向上轻压名片正面区域（z 轴叠压）。
/// 注意：完整对话功能（输入/发送/消息流）待独立设计后实现。
struct ChatStack: View {
    let card: CardProfile

    /// 历史层露出高度（pt/层）
    private let edge: CGFloat = 13

    var body: some View {
        ZStack(alignment: .bottom) {   // 以前卡底边对齐，后层向上露头
            // 后层（历史消息，越往后越浅）
            plate(offsetY: -edge * 2, opacity: 0.5, scale: 0.965)
            plate(offsetY: -edge, opacity: 0.75, scale: 0.985)
            // 前卡：最新消息
            frontPlate
        }
        .frame(height: 96 + edge * 2, alignment: .bottom)
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
    }

    /// 后层历史卡（仅露上边缘）
    private func plate(offsetY: CGFloat, opacity: Double, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .fill(DS.C.infoBottom)
            .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
                .strokeBorder(Color(rgb: 0xC4A84A, 0.20), lineWidth: 1))
            .frame(height: 96)
            .scaleEffect(x: scale, y: 1, anchor: .bottom)
            .offset(y: offsetY - edge)   // 底部对齐基准再上移
            .opacity(opacity)
    }

    /// 前卡：名片对话最新态（头部 + 最新一条 + 展开暗示）
    private var frontPlate: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("对话")
                    .font(DS.F.chatHead).tracking(2.5).foregroundStyle(DS.C.recentTitle)
                LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.35), Color(rgb: 0xD9A84A, 0.02)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Text("● 在线")
                    .font(DS.F.chatDot).tracking(1).foregroundStyle(DS.C.chatOnline)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 7)

            // 最新一条消息（我方），随名片个性化
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(rgb: 0xD9A84A, 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(rgb: 0xD9A84A, 0.32), lineWidth: 1))
                    .frame(width: 34, height: 34)
                    .overlay(
                        GlyphBadge(shape: card.glyph, size: 20)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("一言为定。")
                        .font(DS.F.bubble).foregroundStyle(DS.C.chatMe)
                        .lineLimit(1)
                    Text("10-12 09:33 · 与 \(card.name) 的对话")
                        .font(DS.F.bubbleTm).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.bottom, 9)
        }
        .frame(height: 96, alignment: .top)
        .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
        .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .strokeBorder(Color(rgb: 0xC4A84A, 0.20), lineWidth: 1))
        .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))
    }
}

struct DeckInfoCard: View {
    let card: CardProfile
    /// 文字层透明度（文字粉末转场期间为 0，壳体保持）
    var textOpacity: Double = 1
    /// 文字上浮量（新文字入场轻动画；0=已落位）
    var riseOffset: CGFloat = 0

    var body: some View {
        InfoTexts(card: card)
            .opacity(textOpacity)
            .offset(y: riseOffset)
            .padding(.horizontal, DS.L.infoPadH).padding(.top, 15).padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
            .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo).strokeBorder(DS.C.infoBorder, lineWidth: 1))
            .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))   // 内顶部 1px 亮线
            .overlay(alignment: .topLeading) { CornerMark().padding(-1) }
            .overlay(alignment: .bottomTrailing) {
                CornerMark(rotated: true).padding(-1)
            }
    }

    /// 金色角标（左上 / 右下，15×15，2px）
    struct CornerMark: View {
        var rotated = false
        var body: some View {
            CornerShape()
                .stroke(Color(rgb: 0xD9A84A, 0.8), lineWidth: 2)
                .frame(width: 15, height: 15)
                .rotationEffect(.degrees(rotated ? 180 : 0))
        }
        struct CornerShape: Shape {
            func path(in rect: CGRect) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: rect.minX, y: rect.minY + 22))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + 22, y: rect.minY))
                return p
            }
        }
    }
}

/// 信息文字组（壳内文字版式）——DeckInfoCard 实显与文字粉末离屏渲染
/// （ImageRenderer）共用同一视图，保证粒子位图与真实布局逐像素一致。
struct InfoTexts: View {
    let card: CardProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.name)
                .font(DS.F.deckName).tracking(2.5).foregroundStyle(DS.C.deckName)
            Text(card.title)
                .font(DS.F.deckSub).tracking(1.5).foregroundStyle(DS.C.deckTitleSub)
                .padding(.top, 5)
            LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.55), Color(rgb: 0xD9A84A, 0.06)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.top, 10).padding(.bottom, 8)
            InfoRow(key: "公司", value: card.org)
            InfoRow(key: "邮箱", value: card.mail)
            InfoRow(key: "语式", value: card.line)
            // 相识上下文
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(Color(rgb: 0xD9A84A, 0.5)).frame(width: 2)
                VStack(alignment: .leading, spacing: 0) {
                    (Text("相识").font(DS.F.ctxBold).foregroundStyle(DS.C.recentTitle)
                     + Text(" · " + card.ctx).font(DS.F.ctxText).foregroundStyle(DS.C.contextText))
                    Text("碎片形貌由名片ID唯一决定，永不重样。")
                        .font(DS.F.ctxText).foregroundStyle(DS.C.contextText)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .background(Color(rgb: 0xD9A84A, 0.05))
            .clipShape(.rect(bottomTrailingRadius: 8, topTrailingRadius: 8))
            .padding(.top, 10)
        }
    }
}

struct InfoRow: View {
    let key: String, value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).font(DS.F.rowKey).tracking(3.5).foregroundStyle(DS.C.rowKey)
                .frame(width: 38, alignment: .leading)
            Text(value).font(DS.F.rowVal).tracking(0.5).foregroundStyle(DS.C.rowVal)
        }
        .padding(.vertical, 4.5)
    }
}

struct GoldInnerStroke: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                             startPoint: .top, endPoint: .center), lineWidth: 1)
        )
    }
}

// MARK: - 名片修改·堆叠组件（本人卡专用，轻量版）

/// 展示当前本人名片全部可编辑字段（后续独立设计：表单交互/保存机制）。
/// 外观与 ChatStack 同族：层叠卡组、上两层露边、向上轻压名片区域。
struct CardEditStack: View {
    let card: CardProfile

    /// 历史层露出高度（pt/层）——与 ChatStack 一致的层叠语言
    private let edge: CGFloat = 13

    /// 可编辑字段清单（label, key, value）——定版字段供后续表单/持久化使用
    private var fields: [(String, String, String?)] {
        [
            ("姓名", "name", card.name),
            ("公司", "org", card.org),
            ("部门/职位", "title", card.title),
            ("座右铭", "line", card.line),
            ("手机", "mobile", card.mobile),
            ("邮箱", "mail", card.mail),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            plate(offsetY: -edge * 2, opacity: 0.5, scale: 0.965)
            plate(offsetY: -edge, opacity: 0.75, scale: 0.985)
            frontPlate
        }
        .frame(height: 96 + edge * 2, alignment: .bottom)
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
    }

    private func plate(offsetY: CGFloat, opacity: Double, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .fill(DS.C.infoBottom)
            .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
                .strokeBorder(Color(rgb: 0xC4A84A, 0.20), lineWidth: 1))
            .frame(height: 96)
            .scaleEffect(x: scale, y: 1, anchor: .bottom)
            .offset(y: offsetY - edge)
            .opacity(opacity)
    }

    private var frontPlate: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("身份")
                    .font(DS.F.chatHead).tracking(2.5).foregroundStyle(DS.C.recentTitle)
                LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.35), Color(rgb: 0xD9A84A, 0.02)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Text("✎ 可编辑")
                    .font(DS.F.chatDot).tracking(1).foregroundStyle(DS.C.chatOnline)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 7)

            // 字段速览（两列排布，前四项；完整编辑待独立设计）
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    fieldRow("姓名", card.name)
                    fieldRow("部门", card.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    fieldRow("手机", card.mobile ?? "—")
                    fieldRow("邮箱", card.mail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.bottom, 9)
        }
        .frame(height: 96, alignment: .top)
        .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
        .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .strokeBorder(Color(rgb: 0xC4A84A, 0.20), lineWidth: 1))
        .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))
    }

    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(DS.F.bubbleTm).tracking(1.5).foregroundStyle(DS.C.rowKey)
            Text(value)
                .font(DS.F.bubble).foregroundStyle(DS.C.rowVal)
                .lineLimit(1)
        }
    }
}

// MARK: - 名片对话（完整面板 · 暂不挂载）
// 待办：名片对话模块独立设计——输入/发送/真实消息流/滚动交互，
// 本版由 ChatStack 堆叠组件轻量占位；后续讨论定稿后基于此演进。

struct ChatPanel: View {
    let card: CardProfile

    static let quickWords = ["发我的名片", "约时间聊聊", "发见面地点"]

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(spacing: 8) {
                Text("对话").font(DS.F.chatHead).tracking(2.5).foregroundStyle(DS.C.recentTitle)
                LinearGradient(colors: [Color(rgb: 0xD9A84A, 0.35), Color(rgb: 0xD9A84A, 0.02)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Text("● 在线").font(DS.F.chatDot).tracking(1).foregroundStyle(DS.C.chatOnline)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)

            // 气泡（随名片个性化）
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Bubble(text: "你好，我是\(card.name)。交换到你的名片，很高兴认识。",
                           time: "10-12 09:24", mine: false)
                    Bubble(text: "很高兴认识！「不时不食」栏目也常读，改天约个炖汤局。",
                           time: "10-12 09:31", mine: true)
                    Bubble(text: "一言为定。", time: "10-12 09:33", mine: false)
                }
                .padding(.horizontal, 14).padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)

            // 快捷短语
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Self.quickWords, id: \.self) { w in
                        Text(w)
                            .font(DS.F.chipWord).tracking(0.5).foregroundStyle(DS.C.backTitle)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().strokeBorder(Color(rgb: 0xD9A84A, 0.35), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            }

            // 输入条
            HStack(spacing: 8) {
                Text("轻触输入…")
                    .font(DS.F.chatBox).tracking(1).foregroundStyle(Color(hex: 0x6a6a72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .background(Color(rgb: 0x09090B, 0.8))
                    .overlay(Capsule().strokeBorder(DS.C.line, lineWidth: 1))
                    .clipShape(Capsule())
                Text("发送")
                    .font(DS.F.send).foregroundStyle(DS.C.sendTitle)
                    .frame(width: 58, height: 32)
                    .background(LinearGradient(colors: [Color(hex: 0x2b2415), Color(hex: 0x1b1712)],
                                               startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(DS.C.goldDim, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [DS.C.infoTop, DS.C.infoBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: DS.L.radiusInfo))
        .overlay(RoundedRectangle(cornerRadius: DS.L.radiusInfo)
            .strokeBorder(Color(rgb: 0xC4A84A, 0.20), lineWidth: 1))
        .modifier(GoldInnerStroke(radius: DS.L.radiusInfo))
    }

    struct Bubble: View {
        let text: String, time: String
        let mine: Bool
        var body: some View {
            VStack(alignment: .trailing, spacing: 3) {
                Text(text)
                    .font(DS.F.bubble).foregroundStyle(mine ? DS.C.chatMe : DS.C.chatThem)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(mine ? Color(rgb: 0xD9A84A, 0.13) : Color(rgb: 0x34363C, 0.46))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(mine ? Color(rgb: 0xD9A84A, 0.32)
                                           : Color(white: 1, opacity: 0.05), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(time).font(DS.F.bubbleTm).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }
}
