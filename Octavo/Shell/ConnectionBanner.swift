import SwiftUI

/// What's wrong with the connection to the library server.
nonisolated enum ConnectionProblem: Hashable, Sendable {
    /// The server didn't answer. The app carries on with the books on the
    /// iPhone (the Library switches to On iPhone, #13).
    case unreachable(server: String)
    /// The server ended the session. Reading still works; sync is paused.
    case signedOut(server: String)
}

/// A connection problem, shown at the top of a tab with its one action
/// (decision 22, frames 21 and 22). Not a pop-up: the screen stays usable.
struct ConnectionBanner: View {
    let problem: ConnectionProblem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .tint(tint)
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(12)
        .background(tint.opacity(0.14), in: .rect(cornerRadius: 14))
    }

    private var message: String {
        switch problem {
        case .unreachable(let server): "Can’t reach \(server). Showing books on your iPhone."
        case .signedOut(let server): "\(server) signed you out. Reading still works; sync is paused."
        }
    }

    private var actionTitle: String {
        switch problem {
        case .unreachable: "Retry"
        case .signedOut: "Sign in"
        }
    }

    private var symbol: String {
        switch problem {
        case .unreachable: "exclamationmark.triangle.fill"
        case .signedOut: "person.crop.circle"
        }
    }

    private var tint: Color {
        switch problem {
        case .unreachable: .orange
        case .signedOut: .blue
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ConnectionBanner(problem: .unreachable(server: "BookOrbit")) {}
        ConnectionBanner(problem: .signedOut(server: "BookOrbit")) {}
    }
    .padding()
}
