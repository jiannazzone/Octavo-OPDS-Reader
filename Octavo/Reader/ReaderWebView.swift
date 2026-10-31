import SwiftUI
import WebKit

/// The foliate-js page, with the browser behaviors a reader doesn't want
/// switched off. Paging gestures are handled inside the page by foliate.
struct ReaderWebView: View {
    let model: ReaderModel

    var body: some View {
        WebView(model.page)
            .webViewBackForwardNavigationGestures(.disabled)
            .webViewMagnificationGestures(.disabled)
            .webViewLinkPreviews(.disabled)
    }
}
