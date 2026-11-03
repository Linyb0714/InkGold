import Foundation
import Observation
import CryptoKit
import Security

// ============================================================
// 数据模型（与原型 CARDS/MORE/相识记录一致）
// 未来接入 SwiftData：将 CardProfile 改为 @Model 即可，字段已经对齐
// ============================================================

struct CardProfile: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let title: String          // 职位/部门
    let org: String            // 公司主名（可含英文缩写）
    let line: String           // 座右铭/语式
    let mail: String
    let seed: String
    let ctx: String            // 相识上下文
    var mobile: String? = nil  // 手机（首页本卡等真实信息用）

    var glyph: GlyphShape { GlyphShape.glyphOf(seed: seed) }
}

struct MeetRecord: Identifiable {
    let id = UUID()
    let card: CardProfile
    let date: String         // "10-24"
    let scene: String        // "街拍夜行"
}

/// 名片指纹：CardProfile.seed → GlyphShape

// MARK: - 15 张名片（原种子数据）

enum SeedDeck {
    static let lyb = CardProfile(
        id: "lyb", name: "林优斌", title: "网信安业务事业部",
        org: "中电福富信息科技有限公司（CTFF）", line: "学之广在于不倦，不倦在于固志。",
        mail: "linyb0714@foxmail.com",
        seed: "s-delta", ctx: "2026-11-02 · 数字名片交流展", mobile: "13800000000")

    static let linmo = CardProfile(
        id: "linmo", name: "林墨", title: "全栈研发 · 独立开发",
        org: "自由职业", line: "使纸上 动乎于屏", mail: "hi@linmo.dev",
        seed: "f-fox", ctx: "2026-09-18 · 西湖区咖啡馆偶遇")

    static let mercy = CardProfile(
        id: "mercy", name: "陈脉", title: "交互设计 · 产品视觉",
        org: "Mercury Studio", line: "form follows feel", mail: "chen@mercury.app",
        seed: "m-merc", ctx: "2026-10-06 · Mercury 作品分享会")

    static let more: [CardProfile] = [
        CardProfile(id: "sqw", name: "沈青梧", title: "品牌主理人 · 独立工作室", org: "青梧制物", line: "器物有灵", mail: "sqw@inkgold.app", seed: "f-qingwu", ctx: "2026-08-22 · 民艺市集"),
        CardProfile(id: "gzy", name: "顾之遥", title: "交互设计师 · 智能硬件", org: "拾光实验室", line: "光落在手上", mail: "gzy@inkgold.app", seed: "f-zhiyao", ctx: "2026-07-09 · 硬件创客夜"),
        CardProfile(id: "sy", name: "苏砚", title: "数字插画师 · 自由职业", org: "墨匣", line: "笔锋藏星", mail: "sy@inkgold.app", seed: "f-suyan", ctx: "2026-03-14 · 插画联展"),
        CardProfile(id: "zy", name: "周野", title: "独立音乐人 · 声音设计", org: "野声厂", line: "声音有形状", mail: "zy@inkgold.app", seed: "f-zhouye", ctx: "2026-05-30 · 城市声音节"),
        CardProfile(id: "lc", name: "洛辞", title: "教育产品经理 · 少儿编程", org: "乐见科技", line: "点亮好奇心", mail: "lc@inkgold.app", seed: "f-luoci", ctx: "2026-06-21 · 产品沙龙"),
        CardProfile(id: "cz", name: "池昭", title: "数据工程师 · 云平台", org: "白泽数据", line: "数里行间", mail: "cz@inkgold.app", seed: "f-chizhao", ctx: "2026-02-17 · 技术开放日"),
        CardProfile(id: "wl", name: "闻礼", title: "主编 · 独立杂志", org: "拾字馆", line: "纸上见山", mail: "wl@inkgold.app", seed: "f-wenli", ctx: "2026-04-03 · 杂志创刊展"),
        CardProfile(id: "cyw", name: "程一苇", title: "建筑设计师 · 参数化", org: "一苇建筑", line: "线即空间", mail: "cyw@inkgold.app", seed: "f-yiwei", ctx: "2026-09-12 · 设计双年展"),
        CardProfile(id: "js", name: "江声", title: "摄影师 · 城市漫游", org: "自由镜头", line: "快门里的风", mail: "js@inkgold.app", seed: "f-jiangsheng", ctx: "2026-10-24 · 街拍夜行"),
        CardProfile(id: "jys", name: "纪云舒", title: "剧本作家 · 互动叙事", org: "云舒工作室", line: "故事的裂缝", mail: "jys@inkgold.app", seed: "f-yunshu", ctx: "2026-08-05 · 叙事设计营"),
        CardProfile(id: "dxh", name: "段星河", title: "天文科普作者 · 播客", org: "星河信使", line: "仰望即抵达", mail: "dxh@inkgold.app", seed: "f-xinghe", ctx: "2026-11-01 · 天文馆之夜"),
        CardProfile(id: "txm", name: "唐小满", title: "插画运营 · 少儿内容", org: "满月画室", line: "画完就去玩", mail: "txm@inkgold.app", seed: "f-xiaoman", ctx: "2026-06-08 · 亲子工作坊"),
    ]

    /// 我方名片（轮播展示用）：保持产品化文案，真实联系方式不上屏到他人视角的轮播
    static let lybShow = CardProfile(
        id: "lyb", name: "林优斌", title: "网信安业务事业部 · 安全产品",
        org: "中电福富信息科技有限公司（CTFF）", line: "学之广在于不倦，不倦在于固志。",
        mail: "linyb0714@foxmail.com", seed: "s-delta",
        ctx: "2026-11-02 · 数字名片交流展")

    /// 名片夹：15 张（deck[0] = 本人真实信息；轮播舞台首张经 displayCard 动态展示版）
    static let all: [CardProfile] = [lyb] + more + [linmo, mercy]
}

extension CardProfile {
    /// 轮播/列表展示卡（隐私：本人卡动态去除手机号，字段实时跟随编辑结果）
    var displayCard: CardProfile {
        guard id == "lyb" else { return self }
        return CardProfile(id: id, name: name, title: title, org: org, line: line,
                           mail: mail, seed: seed, ctx: ctx, mobile: nil)
    }

    /// 内容指纹：纹理缓存键的一部分——编辑保存后自动失效重建
    var contentKey: String {
        "\(name)|\(title)|\(org)|\(line)|\(mail)|\(mobile ?? "")"
    }
}

/// 近场交换池（原型 poolCards）
let poolCards = [SeedDeck.linmo, SeedDeck.mercy]
/// 感知到的陌生名片（原型 names/firms 剪影）
let silhouetteNames = ["陈默", "洛辞", "池昭", "闻礼"]
let silhouetteFirms = ["织光设计", "见微传媒", "棱镜科技", "白泽咨询"]

// MARK: - 名片夹 Store

/// 本月另有的相识基数（原型 MEET_BASE，未列在最近相遇内）
let MEET_BASE = 3

@MainActor
@Observable
final class DeckStore {
    private(set) var deck: [CardProfile] = SeedDeck.all
    var currentIdx = 0

    private(set) var recentMeets: [MeetRecord] = [
        MeetRecord(card: SeedDeck.more[10], date: "11-01", scene: "天文馆之夜"),
        MeetRecord(card: SeedDeck.more[8],  date: "10-24", scene: "街拍夜行"),
        MeetRecord(card: SeedDeck.mercy,    date: "10-06", scene: "作品分享会"),
    ]
    static let cityFootprint = 3

    var current: CardProfile { deck[min(max(currentIdx, 0), deck.count - 1)] }
    var count: Int { deck.count }

    /// 原型逻辑：'2026-11' 月份匹配 date 前两位
    func monthMeetCount() -> Int {
        let m = Calendar.current.component(.month, from: Date())
        let mm = String(format: "2026-%02d", m)
        return MEET_BASE + recentMeets.filter { mm.hasSuffix("-" + $0.date.prefix(2)) }.count
    }

    func wrapIdx(_ i: Int) -> Int { ((i % deck.count) + deck.count) % deck.count }

    /// 本人名片编辑保存（草稿值 → deck[0]；首期在内存生效，正式版落 SwiftData）
    func saveOwnCard(name: String, org: String, title: String,
                     line: String, mobile: String, mail: String) {
        var c = deck[0]
        c = CardProfile(id: c.id, name: name.isEmpty ? c.name : name,
                        title: title.isEmpty ? c.title : title,
                        org: org.isEmpty ? c.org : org,
                        line: line.isEmpty ? c.line : line,
                        mail: mail.isEmpty ? c.mail : mail,
                        seed: c.seed, ctx: c.ctx,
                        mobile: mobile.isEmpty ? c.mobile : mobile)
        deck[0] = c
    }

    /// 交换成功：新名片插入最近相遇顶部（原型 exchangeDone unshift）
    func collect(_ card: CardProfile, scene: String) {
        let df = DateFormatter(); df.dateFormat = "MM-dd"
        recentMeets.insert(MeetRecord(card: card, date: df.string(from: Date()), scene: scene), at: 0)
        if recentMeets.count > 3 { recentMeets = Array(recentMeets.prefix(3)) }
    }

    /// 注销/重置：名片夹恢复种子、最近相遇恢复初始、当前回到本人卡
    func resetToSeed() {
        deck = SeedDeck.all
        currentIdx = 0
        recentMeets = [
            MeetRecord(card: SeedDeck.more[10], date: "11-01", scene: "天文馆之夜"),
            MeetRecord(card: SeedDeck.more[8],  date: "10-24", scene: "街拍夜行"),
            MeetRecord(card: SeedDeck.mercy,    date: "10-06", scene: "作品分享会"),
        ]
    }
}

// MARK: - 对话消息与本地缓存（定稿 v2）
// 约束：
//   · 会话维度：一人一会话（会话键 = cardID），不做群聊/同人多会话
//   · 消息类型：当前仅文本；kind + payload 预留名片/位置/图片/语音
//   · 状态与回执：sending → sent → delivered → read（失败 failed）
//   · 多端同步：预留 serverSeq；初期仅本地，接账号后再补增量同步
//   · 缓存策略：不设上限清理；AES-GCM 加密落盘（密钥存 Keychain）

/// 消息类型（当前仅文本）
enum ChatMessageKind: String, Codable {
    case text
    // 预留：card / location / image / voice
}

/// 非文本消息载荷（预留；文本消息为 nil）
struct ChatMessagePayload: Codable, Equatable {
    var cardID: String?         // 名片分享
    var latitude: Double?       // 位置
    var longitude: Double?
    var mediaRef: String?       // 图片/语音本地引用
}

/// 消息状态与回执
enum ChatDeliveryState: String, Codable {
    case sending, sent, delivered, read, failed
}

/// 对话消息（一人一会话）
struct ChatMessage: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    let cardID: String                  // 会话键 = 对话对象名片 ID
    let mine: Bool                      // true=我方，false=对方
    var kind: ChatMessageKind = .text
    let text: String
    let time: String                    // 展示用 HH:mm
    let sentAt: Date                    // 完整时间戳（排序/跨天）
    var state: ChatDeliveryState = .sent
    var deliveredAt: Date? = nil
    var readAt: Date? = nil
    /// 云同步预留：服务端序号（nil = 尚未上云）
    var serverSeq: Int? = nil
    /// 预留载荷（文本时为 nil）
    var payload: ChatMessagePayload? = nil

    enum CodingKeys: String, CodingKey {
        case id, cardID, mine, kind, text, time, sentAt, state
        case deliveredAt, readAt, serverSeq, payload
    }

    init(id: String = UUID().uuidString,
         cardID: String, mine: Bool, kind: ChatMessageKind = .text,
         text: String, time: String, sentAt: Date,
         state: ChatDeliveryState = .sent,
         deliveredAt: Date? = nil, readAt: Date? = nil,
         serverSeq: Int? = nil, payload: ChatMessagePayload? = nil) {
        self.id = id
        self.cardID = cardID
        self.mine = mine
        self.kind = kind
        self.text = text
        self.time = time
        self.sentAt = sentAt
        self.state = state
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.serverSeq = serverSeq
        self.payload = payload
    }

    /// 容错解码：兼容旧版缓存（缺失字段取默认值）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        cardID = try c.decode(String.self, forKey: .cardID)
        mine = try c.decode(Bool.self, forKey: .mine)
        kind = try c.decodeIfPresent(ChatMessageKind.self, forKey: .kind) ?? .text
        text = try c.decode(String.self, forKey: .text)
        time = try c.decode(String.self, forKey: .time)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt) ?? Date()
        state = try c.decodeIfPresent(ChatDeliveryState.self, forKey: .state) ?? .sent
        deliveredAt = try c.decodeIfPresent(Date.self, forKey: .deliveredAt)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        serverSeq = try c.decodeIfPresent(Int.self, forKey: .serverSeq)
        payload = try c.decodeIfPresent(ChatMessagePayload.self, forKey: .payload)
    }
}

/// 对话缓存：按名片 ID 分组（一人一会话），AES-GCM 加密落盘，密钥存 Keychain
@MainActor
final class ChatCache {
    static let shared = ChatCache()

    private var byCard: [String: [ChatMessage]] = [:]
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyKey = "inkgold.chat.v1"          // 旧版明文（迁移后删除）
    private let keychainService = "app.inkgold.InkGold"
    private let keychainAccount = "chat.cache.key.aes256"

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("chat.v1.enc", isDirectory: false)
        load()
    }

    // MARK: 读取 / 写入

    func messages(for cardID: String) -> [ChatMessage] {
        (byCard[cardID] ?? []).sorted { $0.sentAt < $1.sentAt }
    }

    func hasHistory(for cardID: String) -> Bool {
        !(byCard[cardID] ?? []).isEmpty
    }

    func append(_ msg: ChatMessage) {
        byCard[msg.cardID, default: []].append(msg)
        save()
    }

    func replace(_ msgs: [ChatMessage], for cardID: String) {
        byCard[cardID] = msgs
        save()
    }

    /// 回执推进：delivered / read 同时补时间戳
    func updateState(messageID: String, in cardID: String, to state: ChatDeliveryState) {
        guard var arr = byCard[cardID],
              let i = arr.firstIndex(where: { $0.id == messageID }) else { return }
        let now = Date()
        arr[i].state = state
        if state == .delivered, arr[i].deliveredAt == nil { arr[i].deliveredAt = now }
        if state == .read {
            if arr[i].deliveredAt == nil { arr[i].deliveredAt = now }
            arr[i].readAt = now
        }
        byCard[cardID] = arr
        save()
    }

    func clearAll() {
        byCard = [:]
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    // MARK: 加密落盘（AES-GCM + Keychain 密钥 + 文件保护）

    private lazy var key: SymmetricKey = loadOrCreateKey()

    private func load() {
        // 1) 加密文件
        if let cipher = try? Data(contentsOf: fileURL),
           let plain = try? decrypt(cipher),
           let decoded = try? decoder.decode([String: [ChatMessage]].self, from: plain) {
            byCard = decoded
            return
        }
        // 2) 迁移旧版 UserDefaults 明文缓存（迁移后删除明文）
        if let legacy = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? decoder.decode([String: [ChatMessage]].self, from: legacy) {
            byCard = decoded
            UserDefaults.standard.removeObject(forKey: legacyKey)
            save()
        }
    }

    private func save() {
        guard let plain = try? encoder.encode(byCard),
              let cipher = try? encrypt(plain) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? cipher.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func encrypt(_ plain: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { return Data() }
        return combined
    }

    private func decrypt(_ cipher: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: cipher)
        return try AES.GCM.open(box, using: key)
    }

    /// Keychain 读取/生成 256-bit 密钥（首次生成；仅本机可用）
    private func loadOrCreateKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(add as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
        return SymmetricKey(data: bytes)
    }
}
