import SwiftUI

/// An empty screen: what's missing and one way forward (decision 22,
/// frame 25), for example "Nothing in progress · Open Library".
struct EmptyInvitation: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.glassProminent)
        }
    }
}

#Preview {
    EmptyInvitation(
        symbol: "books.vertical", title: "Nothing in progress",
        message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
    ) {}
}
