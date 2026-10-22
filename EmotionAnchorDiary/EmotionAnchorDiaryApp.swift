import SwiftUI
import LocalAuthentication

@main
struct EmotionAnchorDiaryApp: App {
    private let persistenceController = PersistenceController.shared

    @StateObject private var diaryViewModel: DiaryEntryViewModel

    init() {
        let context = PersistenceController.shared.container.viewContext
        // Endpoint settings are public configuration; the user-provided key stays in Keychain.
        let emotionService = EmotionCoachService(endpointProvider: { APIConfig.load()?.endpoint }) {
            AIKeyStore.load()
        }
        _diaryViewModel = StateObject(
            wrappedValue: DiaryEntryViewModel(context: context, emotionService: emotionService)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppLockGate {
                DiaryEntryView(viewModel: diaryViewModel)
            }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
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

    private var lockIsEnabled: Bool { requiresUnlock || isLockUITest }

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
            if enabled {
                isUnlocked = false
                Task { await authenticate() }
            } else {
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
