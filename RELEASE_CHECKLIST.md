# 情绪锚点日记 · 发布准备清单

> 更新日期：2026-10-24
> 当前版本：1.0（构建号由 CI 自动递增）
> Bundle ID：com.emotionanchor.diary

## 一、TestFlight 真机体验（进行中）

### 一次性配置（在 App Store Connect 网页完成）
- [ ] 1. 登录 https://appstoreconnect.apple.com → 「APP」→ 新建 APP
  - 平台 iOS，名称「情绪锚点日记」，Bundle ID 选 `com.emotionanchor.diary`
  - （若下拉没有该 ID，先去 developer.apple.com → Certificates, IDs → Identifiers 注册）
- [ ] 2. 「用户和访问」→「集成」→「App Store Connect API」→ 生成密钥
  - 角色选「App 管理」即可；记录 **Key ID** 和 **Issuer ID**，下载 **AuthKey.p8**（只能下载一次）
- [ ] 3. 查 Team ID：https://developer.apple.com/account → Membership details → Team ID（10 位）

### 把密钥交给 CI（GitHub 网页完成）
- [ ] 4. 把 AuthKey.p8 转成 base64（Windows PowerShell 执行）：
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\路径\AuthKey_XXXX.p8"))
  ```
- [ ] 5. 仓库 → Settings → Secrets and variables → Actions → New repository secret，添加 4 个：
  - `ASC_KEY_ID`（第 2 步的 Key ID）
  - `ASC_ISSUER_ID`（第 2 步的 Issuer ID）
  - `ASC_KEY_P8_BASE64`（第 4 步的输出）
  - `DEVELOPMENT_TEAM`（第 3 步的 Team ID）

### 每次发包
- [ ] 6. 仓库 → Actions → 「iOS TestFlight Upload」→ Run workflow
- [ ] 7. 等 10-30 分钟 Apple 处理 → App Store Connect → TestFlight → 把自己加为内部测试员
- [ ] 8. iPhone 上安装 TestFlight APP → 接受邀请 → 安装体验

### 真机验证清单（装上后逐项过）
- [ ] 语音记录：授权弹窗、中文识别、暂停/结束、空结果、拒绝权限
- [ ] 应用锁：Face ID 首次认证、回前台重锁、认证失败保持锁定、关闭开关
- [ ] 导出：真实保存到文件、重新打开、中文 UTF-8、时间顺序
- [ ] 删除全部数据：确认后日记/目标/密钥全部清除
- [ ] 首次引导页只出现一次
- [ ] 旧版本升级：数据迁移正常（装旧版→写数据→装新版）

## 二、AI 云服务接入（P1-5）
- [ ] 确定双轨服务商：大陆 DeepSeek / 海外 OpenAI GPT-5-nano（已定方向）
- [ ] 搭建轻量中转服务（合同适配：{"summary"} → 共情卡片 JSON）
- [ ] 端到端实测：真实 Key、断网回退、超时提示
- [ ] 隐私政策中写明 AI 数据用途与服务商名单

## 三、App Store 上架材料
- [ ] APP 图标 1024×1024（无透明、无圆角）
- [ ] 截图：6.7" 和 6.5" iPhone 各 3-5 张（核心界面：写日记、心情趋势、目标）
- [ ] 隐私政策网页（需一个可访问的 URL）
- [ ] App Store 隐私问卷：
  - 日记正文：不收集（仅存本机）
  - 语音：不收集（本机转写）
  - AI 摘要：用户主动开启才发送，声明数据用途
- [ ] 加密合规：已声明 ITSAppUsesNonExemptEncryption=false（仅用系统加密，免审查）
- [ ] 商店文案：名称、副标题、关键词、描述（中英双语，面向大陆+海外）
- [ ] 支持联系方式（邮箱或网页）
- [ ] 年龄分级问卷（日记类通常 4+）

## 四、发布前最后检查
- [ ] 版本号与构建号确认
- [ ] CI 全绿（单元 + UI 测试）
- [ ] 真机回归全过
- [ ] Archive → 提交审核 → 等 Apple 审核（通常 24-48 小时）
