# 相识 · InkGold

黑金几何风格的数字名片夹 iOS 应用。以「名片」为核心载体，通过裂变动效进入名片列表，在本人名片与他人名片之间完成浏览、编辑与对话。

- 平台：iOS 17.0+（仅 iPhone 竖屏）
- 版本：0.1.0（build 1）
- 技术栈：SwiftUI + Observation + Canvas / GraphicsContext + CryptoKit + Keychain
- 工程生成：XcodeGen（`project.yml`）
- Bundle ID：`app.inkgold.InkGold`

---

## 一、当前已实现

### 1. 首页（待机）
- 黑金几何密铺背景、动态点线与氛围切线
- 本人名片卡展示（真实联系方式仅首页可见）
- 在名片上划动触发「裂变」动效并进入名片列表
- 顶栏标题与「我的」入口常驻；返回时标题与「我的」即时显示（极轻淡入），其余 chrome 元素按顺序错峰浮现
- 顶部统计区（名片夹 / 本月相识 / 城市足迹）

### 2. 名片列表（人脉 / CONNECTIONS）
- 三槽循环轮播，滑动为纯位图位移（已去除侧卡缩放/淡入让位动画）
- 名片背卡信息、几何导航条
- 顶部搜索：姓名 / 公司 / 部门职位 / 邮箱模糊匹配，下拉结果浮层，点击直达对应名片
- 底部堆叠卡：他人卡进入「对话」，本人卡进入「身份」
- 隐私：本人卡在轮播/列表中自动生成脱敏展示版（去除手机号）

### 3. 身份（名片编辑）
- 点击底部堆叠卡直接进入全屏编辑（无半屏形态）
- 进入即自动聚焦首个字段并唤起系统输入法
- 六字段编辑：姓名 / 公司 / 部门职位 / 座右铭 / 手机 / 邮箱
- 保存后同步更新：首页大卡纹理、列表本人卡、背卡信息（纹理缓存键含内容指纹，自动失效重建）
- 注销入口可恢复名片夹初始状态

### 4. 对话
- 他人卡半屏展开，快捷短语直发（不唤起键盘）
- 点击输入框自动升全屏并唤起系统输入法
- 半屏/全屏切换、键盘唤起/折叠后，会话列表自动贴底显示最新消息
- 本地模拟回复；消息回执：发送中 → 已发送 → 已送达 → 已读
- 按名片分组的会话缓存（一人一会话），退出重进保留

### 5. 数据与隐私
- 对话缓存：AES-GCM 加密后写入 `Application Support/chat.v1.enc`
- 密钥：256-bit 随机生成，存入 Keychain（`AfterFirstUnlockThisDeviceOnly`，仅本机）
- 文件保护：`.completeFileProtection`
- 旧版 UserDefaults 明文缓存自动迁移并删除
- 不设条数/天数上限清理

### 6. 我的
- 模块：我的名片 / 账户信息 / 氛围与动效 / 关于相识 / 隐私与安全 / 反馈与联系
- 注销账户：清除本机对话缓存与名片编辑，名片夹恢复初始

---

## 二、尚未实现（待办清单）

> 以下为当前版本明确未完成的能力，按优先级与依赖关系排列。

### 账号与同步
- [ ] 账号体系（注册 / 登录 / 鉴权）
- [ ] 云端同步（多端会话、名片、最近相遇）
- [ ] 增量同步：`lastSyncedAt`、cursor、`isDirty` 待同步标记、失败重试队列
- [ ] 缓存 schema 版本号与迁移机制
- [ ] 服务端注销（当前注销仅清本机数据）

### 真实交换
- [ ] 近场发现与交换（BLE / UWB / GATT）；当前为本地计时模拟
- [ ] 扫码交换 / 手动输入交换
- [ ] 分享名片的网络传输（当前无任何网络请求）
- [ ] 交换确认、去重与防骚扰策略

### 数据持久化
- [ ] 名片编辑落库（SwiftData / 文件），当前仅内存，重启恢复种子数据
- [ ] 最近相遇、感知记录的持久化
- [ ] 名片导入/导出（vCard）

### 对话
- [ ] 真实消息收发（当前为本地模拟回复）
- [ ] 服务端回执驱动的 delivered / read（当前为本地模拟推进）
- [ ] 消息类型扩展：名片 / 位置 / 图片 / 语音（`kind + payload` 已预留）
- [ ] 统一会话列表与未读汇总
- [ ] 群聊 / 同人多会话（当前一人一会话）
- [ ] 撤回、失败重发、离线队列
- [ ] 推送通知

### 产品与体验
- [ ] 名片自定义主题 / 头像图片
- [ ] 多语言（当前仅中文）
- [ ] 无障碍适配（VoiceOver、动态字体）
- [ ] iPad / 横屏适配（当前仅 iPhone 竖屏）
- [ ] 大量名片的列表分页 / 虚拟化
- [ ] 单元测试与 UI 测试

---

## 三、工程结构

```
InkGold/
├── project.yml                  # XcodeGen 工程描述
├── InkGold.xcodeproj
└── InkGold/
    ├── InkGoldApp.swift         # App 入口、层级装配、AUTODEMO 冒烟驱动
    ├── FlowMachine.swift        # 流程状态机（idle/trail/scatter/galaxy/detail/merge）
    ├── CardProfile.swift        # 名片模型、种子数据、DeckStore、对话模型与加密缓存
    ├── DesignTokens.swift       # 颜色/字体/布局/动效令牌
    ├── GeometryKit.swift        # 几何形状与密铺
    ├── TextureRenderer.swift    # 名片纹理 / 轮播位图烘焙（带缓存）
    ├── Assets.xcassets
    └── Views/
        ├── HomeView.swift       # 首页 chrome 与手势层
        ├── DetailView.swift     # 名片列表：标题/搜索/轮播/导航/统一键盘栏
        ├── DeckDrawerView.swift # 底部抽屉：对话 / 身份
        ├── ChatPanel.swift      # 底部堆叠卡与对话展示组件
        ├── ProfileView.swift    # 「我的」页
        ├── PowderTextView.swift # 粉末文字与信息卡
        ├── RiftCanvasView.swift # 裂变/散场/聚合/轨迹绘制
        └── ExchangeViews.swift  # 交换弹窗
```

### 构建

```bash
# 需要 XcodeGen
xcodegen generate
xcodebuild -scheme InkGold -destination 'generic/platform=iOS Simulator' build
```

> 仓库不包含开发团队标识：首次真机构建请在 Xcode 的 Signing & Capabilities 中选择你自己的 Team。

---

## 四、授权说明（重要）

本项目以「基础开源」方式公开源码：**允许阅读、学习、参考与交流**。

但**在使用（包括但不限于复制、修改、二次开发、分发、商用、集成到其他产品或服务）之前，必须与作者协商并取得书面授权**。未经授权，不得用于任何商业或生产用途。

- 作者：林优斌
- 联系：linyb0714@foxmail.com
- 版权：© 2026 林优斌，保留所有权利

如需授权，请通过上述邮箱说明使用场景、范围与期限，协商一致后另行签署授权说明。

---

## 五、备注

- `project.yml` 中 `ITSAppUsesNonExemptEncryption` 目前为 `false`；项目仅使用系统 CryptoKit 的 AES-GCM 做本地数据存储，未实现自定义加密算法。若后续加入网络传输加密，需重新评估出口合规声明。
- `Info.plist` 已声明蓝牙用途文案，为后续近场交换预留；当前版本未实际使用蓝牙。