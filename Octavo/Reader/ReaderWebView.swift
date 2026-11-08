import SwiftUI
import WebKit

/// The foliate-js page, with the browser behaviors a reader doesn't want
/// switched off. Paging gestures are handled inside the page by foliate.
///
/// Reports the hinge and where the fold runs through the page to the model,
/// which turns them into a `ReaderLayout`.
///
/// `ReaderView` lays it out edge to edge (decision 8), so this view's frame
/// is the page: region frames from the geometry below are in the page's
/// coordinates as they are. The page's size comes from the page itself
/// (`ReaderMessage.viewport`), which stays right after a cold launch.
///
/// On top of the page: each page's footer, in book mode the spine shadow (a
/// setting, on by default), and the snapshot that covers a fold while it
/// settles. While a page turns (decision 27), its pictures: what lies still
/// under the spine shadow, what moves over it.
struct ReaderWebView: View {
    let model: ReaderModel
    /// The theme on the page, for the spine shadow's colour.
    let theme: ReaderTheme
    /// The progress bar covers the footer's place while it shows.
    var showsFooter = true
    /// The way back has the chapter's place in the footer (decision 33).
    var hidesFooterChapter = false
    @AppStorage(ReaderSettings.bookModeShadowKey) private var showsSpineShadow = ReaderSettings.bookModeShadowDefault

    var body: some View {
        WebView(model.page)
            .webViewBackForwardNavigationGestures(.disabled)
            .webViewMagnificationGestures(.disabled)
            .webViewLinkPreviews(.disabled)
            .onHingeChange { old, new in
                // Repeats while the hinge settles; the model compares too.
                guard new != old else { return }
                model.hingeChanged(ReaderPosture(new), angle: new.hinge?.angle.degrees)
            }
            .onGeometryChange(for: ReaderGeometry.self) { proxy in
                ReaderGeometry(proxy)
            } action: { geometry in
                model.geometryChanged(geometry)
            }
            // The web view itself, for the page turns' pictures and swipes.
            .background { [snapshots = model.snapshots, swipes = model.swipes] in
                ReaderWebViewFinder { web in
                    snapshots.webView = web
                    if let host = web?.superview { swipes.install(on: host) }
                }
            }
            .overlay(alignment: .topLeading) {
                if let turn = model.turn {
                    ReaderTurnBase(turn: turn)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsFooter, model.turn == nil {
                    ReaderFooter(model: model, hidesChapter: hidesFooterChapter)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsSpineShadow {
                    ReaderSpineShadow(model: model, theme: theme)
                }
            }
            .overlay(alignment: .topLeading) {
                if let turn = model.turn {
                    ReaderTurnLeaf(turn: turn, progress: turn.progress)
                }
            }
            .overlay(alignment: .topLeading) {
                if let cover = model.foldCover {
                    ReaderFoldCoverView(cover: cover, pageSize: model.geometry?.size)
                }
            }
    }
}

extension ReaderPosture {
    init(_ context: DeviceHingeContext) {
        switch context.hinge?.status {
        case .closed?: self = .closed
        case .partiallyOpen?: self = .halfOpen
        case .fullyOpen?: self = .open
        default: self = .noHinge
        }
    }
}

extension ReaderGeometry {
    /// The page lays out in physical coordinates, so regions aren't mirrored
    /// for right-to-left.
    nonisolated init(_ proxy: GeometryProxy) {
        self.init(
            size: proxy.size,
            divisions: proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
                .map { Region(frame: $0.frame, isActive: $0.isActive) }
        )
    }
}
