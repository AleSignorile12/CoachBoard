import SwiftUI
import UIKit
import LocalAuthentication

/// Optional Face ID lock (turned on in the profile). When on, Tracker locks every time it goes to the background
/// and is hidden in the app switcher. The lock screen lives in its own window above everything, sheets included.
@MainActor
final class AppLock {
    static let shared = AppLock()
    static let storageKey = "faceIDLock"

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.storageKey) }
    private var isLocked = false
    private var isAuthenticating = false
    private var started = false
    /// At launch the whistle animation plays first; Face ID is asked once it ends (the animation covers the app meanwhile).
    private var waitingForSplash = true
    private var window: UIWindow?
    private let model = LockModel()

    /// Face ID, Touch ID or Optic ID, or nil when the phone has no passcode (the lock can't be used then).
    static var methodName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    static var symbol: String {
        switch LAContext().biometryType {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }

    /// Asks for Face ID (falling back to the passcode). Used to unlock and to turn the lock on or off.
    static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: String(localized: "Unlock Tracker to see your team.")))
            ?? false
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if !started {
                started = true
                if isEnabled { isLocked = true }
            }
            if waitingForSplash { hide(); return }
            if isLocked { show(); unlock() } else { hide() }
        case .inactive:
            // Covers the app in the app switcher (during the launch animation the animation already covers it).
            if isEnabled && !waitingForSplash { show() }
        case .background:
            if isEnabled {
                isLocked = true
                show()
            }
        @unknown default:
            break
        }
    }

    /// Called when the launch animation ends. Returns true when the lock screen takes over (it fades in above the
    /// animation, so the app is never visible before unlocking).
    func splashEnded() -> Bool {
        waitingForSplash = false
        guard isLocked else { return false }
        if UIApplication.shared.applicationState == .active {
            show(fadeIn: true)
            unlock()
        }
        return true
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        model.failed = false
        Task {
            let ok = await Self.authenticate()
            isAuthenticating = false
            if ok {
                isLocked = false
                hide()
            } else {
                model.failed = true
            }
        }
    }

    private func show(fadeIn: Bool = false) {
        model.locked = isLocked
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: LockScreen(model: model) { [weak self] in
                self?.unlock()
            })
            self.window = window
        }
        guard let window else { return }
        if fadeIn && window.isHidden {
            window.alpha = 0
            window.isHidden = false
            UIView.animate(withDuration: 0.3) { window.alpha = 1 }
        } else {
            window.alpha = 1
            window.isHidden = false
        }
    }

    private func hide() {
        window?.isHidden = true
    }
}

@MainActor @Observable
private final class LockModel {
    /// False = only hiding the app in the app switcher (not asking to unlock).
    var locked = false
    var failed = false
}

private struct LockScreen: View {
    let model: LockModel
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("OnboardingIcon")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            if model.locked {
                Label("Tracker Is Locked", systemImage: "lock.fill")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            if model.locked && model.failed {
                Button(action: onUnlock) {
                    Label("Unlock", systemImage: AppLock.symbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground() }
    }
}

/// Profile row: turn the lock on or off (both ask for Face ID first, so nobody else can turn it off).
struct AppLockRow: View {
    @AppStorage(AppLock.storageKey) private var enabled = false
    @State private var method = AppLock.methodName

    var body: some View {
        Toggle(isOn: Binding { enabled } set: { newValue in
            Task { if await AppLock.authenticate() { enabled = newValue } }
        }) {
            Label(method.map { String(localized: "Lock with \($0)") } ?? String(localized: "Lock with Face ID"),
                  systemImage: AppLock.symbol)
        }
        .disabled(method == nil)
    }
}
