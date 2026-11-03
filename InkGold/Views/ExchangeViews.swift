import SwiftUI

// ============================================================
// 交换流程 UI：剪影确认弹窗（原型 .popup）
// 感知距离 tag 首页已有；金流粒子/溅落环在 RiftCanvas
// ============================================================

struct ExchangeOverlay: View {
    @Environment(FlowMachine.self) private var m

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if m.popup != .hidden, let s = m.silhouette {
                SilhouettePopup(name: s.name, firm: s.firm)
                    .padding(.bottom, m.safeBottom + 96)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: m.popup)
        .allowsHitTesting(m.popup != .hidden)
    }
}

@MainActor
struct SilhouettePopup: View {
    @Environment(FlowMachine.self) private var m
    let name: String
    let firm: String

    private var sent: Bool { m.popup == .sent }

    var body: some View {
        VStack(spacing: 0) {
            // 头部：剪影头像 + 标题
            HStack(spacing: 10) {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x6a5420), Color(hex: 0x14100a)],
                                         center: UnitPoint(x: 0.35, y: 0.28),
                                         startRadius: 1, endRadius: 34))
                    .overlay(Circle().strokeBorder(DS.C.goldDim, lineWidth: 1))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("附近的墨金名片")
                        .font(DS.F.popTitle).tracking(1).foregroundStyle(DS.C.gold)
                    Text("\(name) · \(firm) · 1.1m")
                        .font(DS.F.popSub).foregroundStyle(DS.C.brandSub)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)

            // 正文
            Group {
                if sent {
                    Text("已掷出名片，等待对方确认…")
                        .font(DS.F.popBody).foregroundStyle(DS.C.popBody)
                } else {
                    (Text("在 ").font(DS.F.popBody).foregroundStyle(DS.C.popBody)
                     + Text("1.1m").font(DS.F.popBody.weight(.semibold)).foregroundStyle(DS.C.popBody)
                     + Text(" 处相遇。交换前仅显示剪影，确认后才收到完整名片。")
                         .font(DS.F.popBody).foregroundStyle(DS.C.popBody))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .frame(minHeight: 48, alignment: .topLeading)

            // 操作
            HStack(spacing: 0) {
                Button {
                    m.dismissPopup()
                } label: {
                    Text("忽略")
                        .font(DS.F.popAct).foregroundStyle(Color(hex: 0x8a8a93))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(PressScale())
                .disabled(sent)

                Rectangle().fill(DS.C.line).frame(width: 1, height: 26).padding(.vertical, 6)

                Button {
                    m.confirmThrow()
                } label: {
                    Text("掷出名片")
                        .font(DS.F.popAct.weight(.semibold)).foregroundStyle(DS.C.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .opacity(sent ? 0.5 : 1)
                }
                .buttonStyle(PressScale())
                .disabled(sent)
            }
            .overlay(alignment: .top) { Rectangle().fill(DS.C.line).frame(height: 1) }
        }
        .frame(width: 310)
        .background(DS.C.popBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DS.C.goldDim, lineWidth: 1))
        .shadow(color: .black.opacity(0.75), radius: 44, y: 14)
        .shadow(color: Color(rgb: 0xC4A84A, 0.16), radius: 26)
    }
}
