import SwiftUI

/// Keep screen on in Settings: how long the screen stays on after a page turn,
/// before Auto-Lock takes over. Kept in `UserDefaults` in minutes, with the
/// other reading settings (decision 14).
nonisolated enum ReaderScreenOn: Int, CaseIterable, Identifiable, Sendable {
    /// Auto-Lock as usual.
    case off = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    static let key = "reader.keepScreenOn"
    static let standard = ReaderScreenOn.tenMinutes

    var id: Self { self }

    var name: String {
        self == .off ? "Off" : "\(rawValue) minutes"
    }

    /// How long a turn keeps the screen on, if at all.
    var time: Duration? {
        self == .off ? nil : .seconds(rawValue * 60)
    }
}

/// What starts Keep screen on's time again.
private struct ReaderAwakeCheck: Equatable {
    var moves: Int
    var isInBackground: Bool
    var screenOn: ReaderScreenOn
}

/// Reading isn't touching: the screen stays on for Keep screen on's time after
/// the place moves, then Auto-Lock takes over, for a phone left on a table.
///
/// A jump counts as a turn, as does a fold that moves the page's start. Coming
/// back from the background or changing the setting starts the time again. A
/// moment away that isn't the background (Control Center, say) doesn't: the
/// time carries on.
struct ReaderKeepAwake: ViewModifier {
    let model: ReaderModel
    @AppStorage(ReaderScreenOn.key) private var screenOn = ReaderScreenOn.standard
    @Environment(\.scenePhase) private var scenePhase
    /// When the time is up. `nil` with the setting Off.
    @State private var timeIsUp: ContinuousClock.Instant?

    /// `nil` while the screen follows Auto-Lock whatever the time.
    private var holdUntil: ContinuousClock.Instant? {
        scenePhase == .active ? timeIsUp : nil
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: ReaderAwakeCheck(moves: model.moveCount, isInBackground: scenePhase == .background, screenOn: screenOn), initial: true) {
                timeIsUp = screenOn.time.map { .now + $0 }
            }
            .task(id: holdUntil) {
                guard let holdUntil, holdUntil > .now else {
                    UIApplication.shared.isIdleTimerDisabled = false
                    return
                }
                UIApplication.shared.isIdleTimerDisabled = true
                guard (try? await Task.sleep(until: holdUntil)) != nil else { return }
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
