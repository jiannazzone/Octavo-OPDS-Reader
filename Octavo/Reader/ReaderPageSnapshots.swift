import SwiftUI
import UIKit
import WebKit

/// Pictures of the page for page turns (decision 27): UIKit snapshot views
/// of the reader's web view, which take 2–5 ms where `WebPage.exported`
/// takes 20–110 ms (`docs/notes/page-turns.md`). They hold the web view's
/// own content only; the footer and the other overlays are SwiftUI's, drawn
/// over it.
final class ReaderPageSnapshots {
    /// Found by `ReaderWebViewFinder` behind the `WebView`.
    weak var webView: WKWebView?

    /// `rect` of the page (all of it if `nil`), in the page's coordinates.
    /// `afterScreenUpdates` first commits what the web view has drawn but
    /// the screen doesn't show yet.
    func snapshot(of rect: CGRect? = nil, afterScreenUpdates: Bool = false) -> ReaderSnapshot? {
        guard let webView, webView.window != nil else { return nil }
        let rect = rect ?? webView.bounds
        guard rect.width > 0, rect.height > 0,
              let view = webView.resizableSnapshotView(from: rect, afterScreenUpdates: afterScreenUpdates, withCapInsets: .zero)
        else { return nil }
        view.isUserInteractionEnabled = false
        return ReaderSnapshot(view: view, frame: rect)
    }
}

/// One picture of the page and where it was taken from, shown by
/// `ReaderSnapshotView`. Compared by identity.
final class ReaderSnapshot: Equatable {
    let view: UIView
    /// In the page's coordinates.
    let frame: CGRect

    init(view: UIView, frame: CGRect) {
        self.view = view
        self.frame = frame
    }

    static func == (lhs: ReaderSnapshot, rhs: ReaderSnapshot) -> Bool { lhs === rhs }
}

/// A snapshot at its own size, in a SwiftUI frame of that size.
struct ReaderSnapshotView: UIViewRepresentable {
    let snapshot: ReaderSnapshot

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if snapshot.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(snapshot.view)
        }
        snapshot.view.frame = CGRect(origin: .zero, size: snapshot.frame.size)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        snapshot.frame.size
    }
}

/// Finds the reader's `WKWebView` for `ReaderPageSnapshots`. Sits behind
/// the `WebView`, in the same hosting view: SwiftUI's `WebView` doesn't
/// hand out its UIKit view.
struct ReaderWebViewFinder: UIViewRepresentable {
    let found: (WKWebView?) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.found = found
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.found = found
    }

    final class FinderView: UIView {
        var found: ((WKWebView?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // The web view joins the window in the same update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                found?(window == nil ? nil : nearestWebView())
            }
        }

        /// The first web view under the nearest ancestor that has one.
        private func nearestWebView() -> WKWebView? {
            var ancestor = superview
            while let view = ancestor {
                if let web = Self.webView(in: view) { return web }
                ancestor = view.superview
            }
            return nil
        }

        private static func webView(in view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            for subview in view.subviews {
                if let web = webView(in: subview) { return web }
            }
            return nil
        }
    }
}
