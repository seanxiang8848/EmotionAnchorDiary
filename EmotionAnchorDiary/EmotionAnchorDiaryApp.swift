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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if !requiresUnlock || isUnlocked {
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
            if requiresUnlock { await authenticate() }
            else { isUnlocked = true }
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
            if phase == .background, requiresUnlock {
                isUnlocked = false
            } else if phase == .active, requiresUnlock, !isUnlocked {
                Task { await authenticate() }
            }
        }
    }

    @MainActor
    private func authenticate() async {
        guard !isAuthenticating else { return }
        guard requiresUnlock else { isUnlocked = true; return }
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
