import Foundation
import SwiftUI
import LocalAuthentication

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
        let emotionService = EmotionCoachService(
            endpointProvider: {
                #if DEBUG
                if useUITestAIRequestMock {
                    return URL(string: "https://ai.example.test/empathy")
                }
                #endif
                return APIConfig.load()?.endpoint
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
                if useUITestAIRequestMock,
                   let url = request.url,
                   let response = HTTPURLResponse(
                    url: url,
                    statusCode: useUITestAIFailure ? 503 : 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                   ) {
                    if useUITestAIFailure {
                        return (Data("{}".utf8), response)
                    }
                    let data = Data("""
                    {"mood":"被倾听","empathy":"谢谢你写下这些感受。","suggestions":["做三次深呼吸"]}
                    """.utf8)
                    return (data, response)
                }
                #endif

                return try await URLSession.shared.data(for: request)
            }
        )
        _diaryViewModel = StateObject(
            wrappedValue: DiaryEntryViewModel(context: context, emotionService: emotionService)
        )
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("日记只保存在这台设备上，正文加密存储", systemImage: "lock.shield")
                    Label("云端 AI 分析默认关闭；开启后也只发送摘要，不发送全文", systemImage: "icloud.slash")
                    Label("AI 服务地址与密钥在“设置”里配置，密钥保存在系统钥匙串", systemImage: "key")
                    Label("语音转文字在本机完成，需要麦克风与语音识别权限", systemImage: "mic")
                    Label("可随时导出日记；“删除全部数据”会同时清除密钥，不可恢复", systemImage: "square.and.arrow.up")
                } header: {
                    VStack(spacing: 8) {
                        Text("欢迎使用情绪锚点日记")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("开始之前，了解你的数据如何被保护")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("开始写日记") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .accessibilityIdentifier("onboardingContinueButton")
            }
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
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("情绪锚点日记已锁定")
                        .font(.headline)
                    if let message {
                        Text(message).font(.footnote).foregroundColor(.secondary)
                    }
                    Button(isAuthenticating ? "正在验证…" : "使用 Face ID 或设备密码解锁") {
                        Task { await authenticate() }
                    }
                    .disabled(isAuthenticating)
                }
                .padding()
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
