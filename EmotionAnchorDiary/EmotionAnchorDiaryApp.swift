import Foundation
import SwiftUI
import UIKit
import LocalAuthentication

// MARK: - 设计系统「静页 Quiet Page」

/// 浅色暖纸质感（Quiet Page），深色近黑暖灯（Nocturne Soliloquy）。
/// 所有颜色都是动态色，深浅模式分别调过对比度，
/// 不依赖系统默认灰，避免深色模式下卡片变成一块死黑。
enum AppTheme {
    static let canvas = palette(0xF6F3EC, 0x0F1418)
    static let surface = palette(0xFFFFFF, 0x171C20)
    static let surfaceSoft = palette(0xEFEDE4, 0x1B2024)
    static let ink = palette(0x27312D, 0xE9E4DA)
    static let inkSoft = palette(0x77827C, 0x8A9AA5)
    static let hairline = palette(0xE5E2D8, 0x272727)
    static let accent = palette(0x2F6B5A, 0xB8C9D4)
    static let accentSoft = palette(0xE3F0E8, 0x1A2229)
    static let warm = palette(0xD9815C, 0xE8A681)
    static let warmSoft = palette(0xFBEBE0, 0x2A1F1A)
    static let topGlow = palette(0xE8F0E7, 0x1A1512)

    /// 编辑器专用：按当前外观解析好的**静态**不透明色。
    /// 动态 UIColor 一旦进入 UITextView 的 textStorage / typingAttributes，
    /// iOS 17+ 真机有概率按错误外观解析，字形被画成透明色（输入框「看不见字」）。
    static var currentInterfaceStyle: UIUserInterfaceStyle {
        let style = UITraitCollection.current.userInterfaceStyle
        return style == .unspecified ? UIScreen.main.traitCollection.userInterfaceStyle : style
    }

    static func editorInk(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? UIColor(hex: 0xE9E4DA) : UIColor(hex: 0x27312D)
    }

    static func editorTint(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? UIColor(hex: 0xE8A681) : UIColor(hex: 0x2F6B5A)
    }

    static var dropShadow: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.clear
                : UIColor(red: 0.16, green: 0.22, blue: 0.18, alpha: 0.10)
        })
    }

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [palette(0x357A66, 0x47907A), palette(0x245447, 0x2F6B5A)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var warmGradient: LinearGradient {
        LinearGradient(
            colors: [palette(0xE79C6F, 0xE8A27C), palette(0xD97B55, 0xD98A64)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [topGlow, canvas],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func moodColor(_ tag: String) -> Color {
        switch tag {
        case "低落": return palette(0x7B8CA6, 0x8A9BB0)
        case "焦虑": return palette(0xD98F6B, 0xE8A681)
        case "开心": return palette(0xD3A044, 0xC9B07A)
        case "有能量": return palette(0x6BA268, 0xA9B392)
        default: return palette(0x5B9E97, 0x9AADB8)
        }
    }

    static func moodSymbol(_ tag: String) -> String {
        switch tag {
        case "低落": return "cloud.drizzle"
        case "焦虑": return "wind"
        case "开心": return "sun.max"
        case "有能量": return "bolt.fill"
        default: return "leaf"
        }
    }

    private static func palette(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// 全屏背景：浅色顶部一层极淡的晨光；深色为右上角暖灯光晕。渐变只铺在背景层。
    func appScreenBackground() -> some View {
        background {
            AppScreenBackgroundLayers()
        }
    }

    /// 统一的纸感卡片：大圆角、细描边、柔和投影。
    func paperCard(padding: CGFloat = 18, radius: CGFloat = 22, tint: Color? = nil) -> some View {
        self.padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint ?? AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
            .shadow(color: AppTheme.dropShadow, radius: 16, x: 0, y: 7)
    }
}

/// 浅色保持原晨光线性渐变；深色改为右上角椭圆暖光，结构仍是 ZStack + ignoresSafeArea。
private struct AppScreenBackgroundLayers: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.canvas
            if colorScheme == .dark {
                EllipticalGradient(
                    colors: [
                        Color(uiColor: UIColor(hex: 0xE8A681).withAlphaComponent(0.08)),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.85, y: 0.05),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.70
                )
            } else {
                AppTheme.backgroundGradient.frame(height: 380)
            }
        }
        .ignoresSafeArea()
    }
}

/// 分区小标题：图标 + 次级文字，统一页面节奏。
struct SectionCaption: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(AppTheme.inkSoft)
    }
}

/// 主行动按钮：浅色柔和渐变与白字；深色为低亮度暖光描边、暖灯色字。文案由调用方提供，不改动可访问性标识。
struct SoftPrimaryButtonStyle: ButtonStyle {
    var fill: LinearGradient = AppTheme.primaryGradient

    func makeBody(configuration: Configuration) -> some View {
        SoftPrimaryButtonBody(configuration: configuration, fill: fill)
    }
}

private struct SoftPrimaryButtonBody: View {
    let configuration: SoftPrimaryButtonStyle.Configuration
    let fill: LinearGradient
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            configuration.label
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(Color(uiColor: UIColor(hex: 0xE8A681)))
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: UIColor(hex: 0xE8A681).withAlphaComponent(configuration.isPressed ? 0.22 : 0.12)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: UIColor(hex: 0xE8A681).withAlphaComponent(0.30)), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        } else {
            configuration.label
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(.white)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
                .shadow(color: AppTheme.dropShadow, radius: 14, x: 0, y: 7)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.92 : 1)
        }
    }
}

/// 次级按钮：浅色底 + 细描边；深色为幽灵按钮、夜雾灰字、350ms ease-out。用于「语音记录」这类并列操作。
struct SoftSecondaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.warm

    func makeBody(configuration: Configuration) -> some View {
        SoftSecondaryButtonBody(configuration: configuration, tint: tint)
    }
}

private struct SoftSecondaryButtonBody: View {
    let configuration: SoftSecondaryButtonStyle.Configuration
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            configuration.label
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(Color(uiColor: UIColor(hex: 0x8A9AA5)))
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: UIColor(hex: 0x8A9AA5).withAlphaComponent(0.22)), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: 0.35), value: configuration.isPressed)
        } else {
            configuration.label
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(tint)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.warmSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
        }
    }
}

@main
struct EmotionAnchorDiaryApp: App {
    private let persistenceController = PersistenceController.shared

    @StateObject private var diaryViewModel: DiaryEntryViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-app-lock") {
            UserDefaults.standard.set(false, forKey: "requireAppUnlock")
        }
        #endif

        let context = PersistenceController.shared.container.viewContext

        #if DEBUG
        let useUITestAIResponse = ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-success")
        let useUITestAIFailure = ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-failure")
        let useUITestAIMissingKey = ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-missing-key")
        let useUITestAIRequestMock = useUITestAIResponse || useUITestAIFailure || useUITestAIMissingKey
        #else
        let useUITestAIResponse = false
        let useUITestAIFailure = false
        let useUITestAIMissingKey = false
        let useUITestAIRequestMock = false
        #endif

        // Endpoint settings are public configuration; the user-provided key stays in Keychain.
        let aiService = DiaryAIService(
            configProvider: {
                // 没配置过时用 DeepSeek 默认地址，用户只要填 Key 就能用。
                APIConfig.load() ?? APIConfig.fallback
            },
            apiKeyProvider: {
                #if DEBUG
                if useUITestAIMissingKey { return nil }
                if useUITestAIResponse || useUITestAIFailure { return "ui-test-key" }
                #endif
                return AIKeyStore.load()
            },
            sendRequest: { request in
                #if DEBUG
                if useUITestAIRequestMock, let url = request.url {
                    if useUITestAIFailure,
                       let response = HTTPURLResponse(
                        url: url,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                       ) {
                        return (Data("{}".utf8), response)
                    }
                    if let mock = EmotionAnchorDiaryApp.uiTestAIResponse(for: url) {
                        return mock
                    }
                }
                #endif

                return try await URLSession.shared.data(for: request)
            }
        )
        _diaryViewModel = StateObject(
            wrappedValue: DiaryEntryViewModel(context: context, aiService: aiService)
        )
    }

    /// UI 测试用的假 AI 响应：结构必须与真实 `/chat/completions` 一致，
    /// 否则测的就不是真实解析链路了。
    private static func uiTestAIResponse(for url: URL) -> (Data, HTTPURLResponse)? {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else { return nil }

        let emotion: [String: Any] = [
            "label": "平静",
            "score": 3.4,
            "intensity": 0.5,
            "reason": "写下之后情绪慢慢平复"
        ]
        let analysis: [String: Any] = [
            "emotion": emotion,
            "empathy": "谢谢你写下这些感受。",
            "suggestions": ["做三次深呼吸", "记录此刻的身体感受"],
            "goal_matches": [Any](),
            "goal_updates": [Any](),
            "new_goals": [Any]()
        ]
        let content = (try? JSONSerialization.data(withJSONObject: analysis))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let choice: [String: Any] = [
            "message": ["role": "assistant", "content": content],
            "finish_reason": "stop"
        ]
        let envelope: [String: Any] = ["choices": [choice]]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        return (data, response)
    }

    /// 首次启动时显示引导页（P2-12）。
    /// 所有以 -ui-testing 开头的启动参数（既有 UI 测试）默认跳过引导，
    /// 只有显式传 -ui-testing-show-onboarding 才会在测试中显示。
    private var shouldPresentOnboarding: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-show-onboarding") {
            return !hasCompletedOnboarding
        }
        if arguments.contains(where: { $0.hasPrefix("-ui-testing") }) {
            return false
        }
        #endif
        return !hasCompletedOnboarding
    }

    var body: some Scene {
        WindowGroup {
            AppLockGate {
                DiaryEntryView(viewModel: diaryViewModel)
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .sheet(isPresented: Binding(
                    get: { shouldPresentOnboarding },
                    set: { newValue in
                        if !newValue { hasCompletedOnboarding = true }
                    }
                )) {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .interactiveDismissDisabled()
                }
        }
    }
}

/// 首次使用引导（P2-12）：说明本地加密、云端分析默认关闭、
/// AI 密钥配置方式、语音权限用途以及导出/删除的影响。
private struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let items: [(symbol: String, text: String, tint: Color)] = [
        ("lock.shield", "日记只保存在这台设备上，正文加密存储", AppTheme.accent),
        ("icloud.slash", "云端 AI 分析默认关闭；开启后也只发送摘要，不发送全文", AppTheme.accent),
        ("key", "内置 DeepSeek / OpenAI 直连，密钥在“设置”里填，保存在系统钥匙串", AppTheme.warm),
        ("mic", "语音转文字在本机完成，需要麦克风与语音识别权限", AppTheme.warm),
        ("square.and.arrow.up", "可随时导出日记；“删除全部数据”会同时清除密钥，不可恢复", AppTheme.accent)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 42))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(colorScheme == .dark ? AppTheme.warm : AppTheme.accent)
                            .padding(18)
                            .background(colorScheme == .dark ? AppTheme.warmSoft : AppTheme.accentSoft)
                            .clipShape(Circle())

                        Text("欢迎使用情绪锚点日记")
                            .font(.system(size: 28, weight: .light, design: .serif))
                            .foregroundStyle(AppTheme.ink)
                        Text("开始之前，了解你的数据如何被保护")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                    VStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { index in
                            if index > 0 {
                                Divider().padding(.leading, 56)
                            }
                            OnboardingRow(
                                symbol: items[index].symbol,
                                text: items[index].text,
                                tint: items[index].tint
                            )
                        }
                    }
                    .paperCard(padding: 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .appScreenBackground()
            .safeAreaInset(edge: .bottom) {
                Button("开始写日记") { onContinue() }
                    .buttonStyle(SoftPrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("onboardingContinueButton")
            }
        }
    }
}

private struct OnboardingRow: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}


/// 锁屏中央圆盘：浅色保持原青绿徽章；深色改为暖灯圆盘，默认 10 秒呼吸光环，减弱动态效果时静止。
private struct LockLanternDisc: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var haloScale: CGFloat = 1
    @State private var reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Circle()
                    .fill(AppTheme.warm.opacity(0.12))
                    .frame(width: 128, height: 128)
                    .scaleEffect(haloScale)
                    .opacity(reduceMotionEnabled ? 0.5 : (2.05 - Double(haloScale)))
            }
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 46))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(colorScheme == .dark ? AppTheme.warm : AppTheme.accent)
                .padding(22)
                .background(colorScheme == .dark ? AppTheme.warmSoft : AppTheme.accentSoft)
                .clipShape(Circle())
        }
        .frame(width: 136, height: 136)
        .onAppear { syncHalo() }
        .onChange(of: colorScheme) { _ in syncHalo() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            reduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
            syncHalo()
        }
    }

    private func syncHalo() {
        if colorScheme != .dark || reduceMotionEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                haloScale = 1
            }
            return
        }
        haloScale = 1
        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
            haloScale = 1.18
        }
    }
}

private struct AppLockGate<Content: View>: View {
    @AppStorage("requireAppUnlock") private var requiresUnlock = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var message: String?

    private let content: Content

    /// UI tests hold the gate closed until the test taps the unlock action.
    /// The simulated success path is compiled out of Release builds.
    private var isLockUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-app-lock")
        #else
        false
        #endif
    }

    private var lockIsEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-enable-app-lock") { return true }
        #endif
        return requiresUnlock
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if !lockIsEnabled || isUnlocked {
                content
            } else {
                VStack(spacing: 22) {
                    LockLanternDisc()

                    Text("情绪锚点日记已锁定")
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                    Text("解锁后，今天的心情只属于你")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkSoft)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.warm)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.warmSoft)
                            .clipShape(Capsule())
                    }

                    Button(isAuthenticating ? "正在验证…" : "使用 Face ID 或设备密码解锁") {
                        Task { await authenticate() }
                    }
                    .buttonStyle(SoftPrimaryButtonStyle())
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appScreenBackground()
            }
        }
        .task {
            guard lockIsEnabled else { isUnlocked = true; return }
            guard !isLockUITest else { return }
            await authenticate()
        }
        .onChange(of: requiresUnlock) { enabled in
            // Enabling the setting should take effect on the next app launch or
            // after the app returns from the background, not interrupt the
            // Settings screen while the user is changing the toggle.
            if !enabled {
                isUnlocked = true
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background, lockIsEnabled {
                isUnlocked = false
            } else if phase == .active, lockIsEnabled, !isUnlocked {
                if !isLockUITest { Task { await authenticate() } }
            }
        }
    }

    @MainActor
    private func authenticate() async {
        guard !isAuthenticating else { return }
        guard lockIsEnabled else { isUnlocked = true; return }
        if isLockUITest {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-app-lock-failure") {
                message = "验证未完成，请重试。"
                return
            }
            isUnlocked = true
            message = nil
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            message = "此设备暂不可用，请在系统设置中启用设备密码后重试。"
            return
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁你的私密日记")
            isUnlocked = true
            message = nil
        } catch {
            message = "验证未完成，请重试。"
        }
    }
}
