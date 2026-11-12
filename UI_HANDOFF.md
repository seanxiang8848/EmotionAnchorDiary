# UI 交接简报 · C「夜航 / Nocturne Soliloquy」

> **状态**：用户已拍板采用 C 方向（2026-11-11）。本文件是给 Codex 的落地规格，请连同 `项目交接与产品需求说明.md`、`RELEASE_CHECKLIST.md` 一起读。
> **一句话目标**：把界面换成「深夜一盏暖灯」的观感，但**功能、文案、交互逻辑、测试一行不改**。
> **落地策略：换皮不换骨。** Stitch 手稿是网页概念稿，不是 iOS 界面稿；照稿删控件会直接打断 19 个 UI 测试。

---

## 0. 先读这条：为什么这次改动比想象中便宜

现有 `AppTheme`（`EmotionAnchorDiaryApp.swift` 第 10–21 行）已经有一整套**深色档** token，其中：

```
static let warm = palette(0xD9815C, 0xE8A681)   // 深色值 0xE8A681
```

`0xE8A681` **正是 C 稿的「2200K 暖灯主色」**；现有深色底 `0x10171B` 与 C 的 `#0F1418` 也几乎一致。

**结论：不需要推翻双外观、不需要新建主题系统、不需要新建 Swift 文件。** 只需把 `AppTheme` 的**深色档第二参数**从「深青绿」调成「近黑 + 暖灯」，浅色档第一参数**原样保留**。深色跟随系统外观，浅色仍是 Quiet Page。

---

## 1. 输入文件（只读参照，不要提交进 Xcode 工程）

| 用途 | 路径（相对 `diary/`） |
|---|---|
| **规格源（主要输入）** | `_stitch_exports/stitch_midnight_mood_journal_interface/nocturne_soliloquy/DESIGN.md` |
| 产品叙事 | `_stitch_exports/stitch_midnight_mood_journal_interface/nocturne_soliloquy_project_prd_design_brief.md` |
| 视觉参照 | `late_night_journal/code.html` + `screen.png` |
| 视觉参照 | `7_day_luminous_band_trend/code.html` + `screen.png` |
| 视觉参照 | `app_lock_screen/code.html` + `screen.png` |
| 视觉参照 | `star_trail_history/code.html` + `screen.png` |
| 全部 5 套对比 | `stitch-handoff-gallery.html` |

**判据**：`code.html` 是 Tailwind CSS + Google Fonts + Material Symbols 的网页稿；`screen.png` 是高 1600、宽 479–706 的**网页长滚动截图**，不是 390×844 iPhone 屏。只能提取色值、字号层级、间距与组件语义，**禁止按像素复刻、禁止把 HTML/CSS 当 SwiftUI 写**。

---

## 2. Token 映射表（改 `EmotionAnchorDiaryApp.swift` 第 11–21 行的深色档）

| C 稿 token | HEX | 现有成员 | 建议深色值 | 说明 |
|---|---|---|---|---|
| canvas / background | `#0F1418` | `canvas` dark `0x10171B` | `0x0F1418` | 近黑但非纯黑，保 OLED 暗适应 |
| surface-container-low | `#171C20` | `surface` dark `0x1B2529` | `0x171C20` | 卡片底 |
| surface-container | `#1B2024` | `surfaceSoft` dark `0x223037` | `0x1B2024` | 次级块 |
| linen text / on-surface | `#E9E4DA` | `ink` dark `0xEBF1EB` | `0xE9E4DA` | 暖白正文，低眩光 |
| metadata 冷雾 | `#8A9AA5` | `inkSoft` dark `0x9DAFA8` | `0x8A9AA5` | 时间戳 / 说明文字 |
| low-contrast hairline | `rgba(233,228,218,0.07)` | `hairline` dark `0x2C3A3E` | `0x272727` | 1px 发丝线，越淡越好 |
| **暖灯 accent** | `#E8A681` | `warm` dark **`0xE8A681`** | **不改** | 已经一致 |
| 暖光浅晕 | `rgba(232,166,129,0.12)` | `warmSoft` dark `0x3A2A24` | `0x2A1F1A` | 按钮底 / 选中态 |
| 冷青绿 accent | C 稿无 | `accent` dark `0x86CDB2` | `0xB8C9D4` | 换成去饱和夜雾蓝，避免青绿抢暖灯 |
| accent 浅底 | C 稿无 | `accentSoft` dark `0x1C3730` | `0x1A2229` | 去绿味 |
| 顶部暖光 | 右上角 radial 8% | `topGlow` dark `0x16292C` | `0x1A1512` | 配合第 3 节 gradient |

**同一文件里另外三处必须同步**（都是静态色，安全）：

| 位置 | 改法 |
|---|---|
| `editorInk(for:)` 第 31–33 行 | 深色返回 `UIColor(hex: 0xE9E4DA)`，**浅色分支不动**；必须继续返回静态不透明 `UIColor` |
| `editorTint(for:)` 第 35–37 行 | 深色返回 `UIColor(hex: 0xE8A681)`；**浅色分支不动** |
| `moodColor(_:)` 第 71–79 行 | 深色档整体降饱和，让五档心情都往暖灯 / 夜雾靠；**`switch` 的五个中文 case 一个字不改** |

> ⚠️ `editorInk` / `editorTint` 是 11-10 刚修好的 TextKit 1 真机中文输入 bug 的关键：动态 `UIColor` 进 `textStorage` 会让字形不绘制。只改 hex 常量，**不要改函数结构、不要改返回值类型**。

---

## 3. 版式与组件（同样集中在 `EmotionAnchorDiaryApp.swift`）

| 项 | C 稿规格 | 落地做法 |
|---|---|---|
| 字体 | Newsreader Light 300 / Geist 宽字距 | **不打包字体**（打包要改 pbxproj，风险高）。标题用 `.font(.system(size: 28, weight: .light, design: .serif))`，正文沿用 `.system(.body, design: .serif)` 或现有 rounded；微标签用 `.system(.caption)` + `.tracking(1.2)`。中文不要 uppercase |
| 投影 | **零 drop shadow** | `AppTheme.dropShadow` 深色分支返回 `.clear`（一行改动、见效最大），浅色保留 |
| 背景暖光 | 右上角 `radial-gradient(ellipse at 85% 5%, rgba(232,166,129,0.08), transparent 70%)` | 在 `appScreenBackground()`（111–119 行）里把 `backgroundGradient` 换成 `RadialGradient`，**保留 ZStack + ignoresSafeArea 结构**；渐变只放背景层，绝不叠在文字视图上 |
| 卡片 | 无边框、色调淹没 | **第一阶段保留 `paperCard()` 的调用点与结构**，只把深色档的 `fill` 换成近黑、`stroke` 换成极淡发丝线、去掉 shadow。不要删 `.paperCard()` —— 删了要动 5 个视图文件，风险不值 |
| 主按钮 | 低亮度暖光描边：`rgba(232,166,129,0.12)` 底 + 1px `rgba(232,166,129,0.3)` 边 + `#E8A681` 字 | 改 `SoftPrimaryButtonStyle` 的深色表现：去掉亮渐变与白字，按压态底色淡入到 0.22。浅色档保持原样 |
| 次按钮 | 幽灵按钮、`#8A9AA5` 字、350ms ease-out | 改 `SoftSecondaryButtonStyle` 深色表现，保留 `tint` 参数与所有调用点 |
| 圆角 | 8 / 16 / 24 / full | 第一阶段保留 18–22；第二阶段如要去框化，优先通过 `AppTheme` 新增一个动态 `cardRadius` 常量，不要逐视图硬改 |
| 情绪胶囊 | 透明底 + 1px 低对比描边，选中态暖光描边 | 只改胶囊的深色样式；`moodSymbol` 的 SF Symbol 名可保留 |
| 录音节点 | 圆形 + 3s 呼吸光环 | `RecordingIndicatorView` 已用 `AppTheme.warm`，天然就是暖灯色；可加光环，但见第 5 节动效约束 |
| 图标 | Material Symbols | 用 SF Symbols（iOS 16 可用）：`lightbulb_circle→lightbulb`、`fingerprint→faceid`、`mic→mic`、`bedtime→moon.stars`、`spa→sparkles`、`water_drop→cloud.rain`、`format_quote→text.quote`、`play_arrow→play.circle`、`graphic_eq→waveform`、`flashlight_on→flashlight.on.fill`、`lock→lock`。**不要引入图标字体** |

---

## 4. 四屏 → 现有视图映射

| C 稿屏 | 现有代码 | 做法 |
|---|---|---|
| **The Threshold**（锁屏） | `AppLockGate` / `OnboardingView`（`EmotionAnchorDiaryApp.swift`） | 只换背景与中央圆盘视觉（暗房 → 解锁后暖光扩散）。**Face ID 逻辑、`app-lock-toggle`、`使用 Face ID 或设备密码解锁` 等文案全部保留**。「拉绳开关 / Night Torch / Emergency Offload」不做交互，第二期再说 |
| **Sanctuary Canvas**（深夜书写） | `DiaryEntryView.swift`（1057 行） | ⚠️ **最关键**：稿子只有「一句提问 + 一条输入线」，但现有首页有日期、三快捷入口、编辑器、五档情绪、AI 开关、目标卡、录音、保存按钮。**全部保留，一个控件都不删**，只把它们换成低对比的无框语言（卡片去边、按钮转幽灵、间距拉大、暖光点缀）。照稿精简 = UI 测试必挂 |
| **Star Trail History** | `EntryListView.swift` / `EntryDetailView` | 第一期只在列表背景加一层**静态**星点 / 细线装饰；`List`/`ForEach`、`暂无记录`、`写下一条心情…`、删除弹窗、详情页结构全保留。星点图谱交互留第二期 |
| **Nocturnal Arc**（7 日发光带） | `MoodTrendView.swift` | 可把 `AreaMark` 换成发光带（`Path` + 渐变描边 / 柔和面积），数据仍走 `MoodTrendCalculator`，`心情趋势` / `心情曲线` / 空态文案保留 |

---

## 5. 绝对禁止改动（CI 红线）

1. **Swift 5 / iOS 16**，不用 iOS 17+ API。
2. **不新建 Swift 文件**、不改 `project.pbxproj`（历史上多次因此 CI 编译失败）。所有设计系统改动集中在 `EmotionAnchorDiaryApp.swift`。
3. **19 个 UI 测试用例**与依赖文案一字不改，包括但不限于：`今天的心情在哪儿？`、`写下此刻`、`保存并生成共情`、`设置`、`查看历史条目`、`目标追踪`、`心情趋势`、`语音记录`、`停止录音`、`暂无记录`、`欢迎使用情绪锚点日记`、`开始写日记`、`情绪锚点日记已锁定`、`使用 Face ID 或设备密码解锁`、`使用 Face ID 或设备密码解锁`、锁屏开关文案、导出 / 删除 / 空态 / 校验提示等全部中文字符串。
4. accessibility id 不改：`diary-entry-editor`、`onboardingContinueButton`、`app-lock-toggle`；各 `accessibilityLabel`（`添加目标`、`删除这篇日记` 等）不改。
5. **五档中文心情固定**「低落 / 焦虑 / 平静 / 开心 / 有能量」；不采纳 C 稿的 `Untethered / Heavy / Quiet / Yearning`，也不采纳 E 稿的四级强度与百分制。
6. `JournalTextView` 整段（TextKit 1 构造、`Coordinator`、`applyEditorStyleIfNeeded`、`replaceText`、`forceGlyphRedraw`、`textViewDidChange`）**一行不动**；文字层只用静态不透明色，不叠 blur / 动态色 / 渐变。
7. 动效必须尊重减弱动态效果：用 `UIAccessibility.isReduceMotionEnabled`（UIKit 老 API，iOS 16 稳）+ `UIAccessibility.reduceMotionStatusDidChangeNotification` 监听；开启时暖光呼吸、录音脉冲、星轨全部停成静态。
8. **本轮不发 TestFlight / 不触发 `iOS TestFlight Upload`**（用户 11-10 明确暂不发新包）。CI 只跑 `ios-build`。

---

## 6. 分两步落地与验收

### Step 1：只动 token 层（建议先单独一个 commit）
范围：`EmotionAnchorDiaryApp.swift` 第 11–21、31–37、39–68、71–79、109–133、约 150–190 行的两个 `ButtonStyle`。约 40–60 行改动。
验收：
- `ios-build` 编译 + 单元 + 19 个 UI 测试**全绿**（UI 测试约 25–30 分钟）。
- 真机分别切浅色 / 深色看一遍；**深色下打开首页，中文输入法键入，确认字形可见**（TextKit 1 回归重点）。
- 确认浅色档外观与改动前一致（第一行参数没动）。

### Step 2：逐屏精修（每屏一次编译）
`DiaryEntryView` → `MoodTrendView` → `EntryListView` → `AppLockGate`。每改一屏先编译，最后全量 CI。
终验清单：
- [ ] 深 / 浅两套外观都可读，深色下无纯黑死块、无刺眼亮块
- [ ] 输入框中文键入、保存后清空再键入、语音转写回写都正常
- [ ] 19 个 UI 测试全绿，24 组断言文案未被改动
- [ ] 锁屏 / 引导页 / 设置页 / 目标页 / 历史 / 趋势全屏无遗留青绿色块
- [ ] 系统「减弱动态效果」开启后，暖光呼吸与录音脉冲为静态
- [ ] OLED 真机全黑环境下文字不刺眼、暖光不过曝

---

## 7. 明确不做（C 稿里与现有产品冲突的部分）

| 稿子里的东西 | 不做的理由 |
|---|---|
| `23:47 • RAIN OUTSIDE • WAXING CRESCENT` 头部元数据 | 要接天气 / 月相数据源，超出范围；用现有 `M月d日 · EEEE` 日期格式替代 |
| 「仅限 23:00–03:00 睡前使用」的场景限定 | App 是全天日记，深色跟随系统外观，**不按时间强制切换** |
| 无卡片 / 无占位提示 / 只写一句 | 会删掉现有功能并打断 UI 测试；用「低对比视觉」实现安静感，不是删控件 |
| 星轨图谱替代列表、拉绳开关、Night Torch、Emergency Offload | 第二期候选，本轮不动交互与数据链路 |
| AES-256 SQLite / Secure Enclave / CoreHaptics 自定义音轨 / 端侧 whisper | 现有 `CryptoManager` / `SpeechService` / `LocalAuthentication` 已覆盖，不重写 |
| Newsreader、Geist、Material Symbols 字体打包 | 必须改 pbxproj，风险高；走系统字体 + SF Symbols |

---

## 8. 待用户确认的三个小决策（默认按「建议」执行即可）

| 决策 | 建议 |
|---|---|
| C 深色是「跟随系统」还是「App 内强制深色」 | **跟随系统**，浅色档保留，风险最低 |
| 第一期是否做星轨交互 | **不做**，只做静态装饰层 |
| 暖光呼吸节奏 | 背景 8–12s、录音节点 3s；默认开，减弱动态效果时静态 |

---

### 给 Codex 的一句话启动指令（可直接复制）

> 按 `UI_HANDOFF.md` 实施 Step 1：只修改 `EmotionAnchorDiary/EmotionAnchorDiary/EmotionAnchorDiaryApp.swift` 中 `AppTheme` 的深色档 token、`dropShadow`、`appScreenBackground`、`paperCard` 深色表现与两个 ButtonStyle，把深色外观从「深青绿」改为「近黑 + 暖灯 Nocturne Soliloquy」。浅色档、所有中文文案、accessibility id、`JournalTextView` 一行不动。不新建 Swift 文件、不改 pbxproj、不用 iOS 17 API。改完跑 `git diff --check` 与编译，报告改动行数和涉及函数，等我确认后再开始 Step 2。
