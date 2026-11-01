import SwiftUI
import WebKit

/// The foliate-js page, with the browser behaviors a reader doesn't want
/// switched off. Paging gestures are handled inside the page by foliate.
///
/// Reports the hinge and where the fold runs through the page to the model,
/// which turns them into a `ReaderLayout`.
///
/// `WebView` draws the page under the trailing and bottom safe areas, so the
/// page is bigger than this view's frame (466×502 against 382×420 on the
/// folded Duo) but shares its top-left corner. Region frames from the
/// geometry below are in the page's coordinates as they are; the page's size
/// comes from the page itself (`ReaderMessage.viewport`).
///
/// On top of the page: the snapshot that covers a fold while it settles,
/// and in book mode the spine shadow (a setting, on by default).
struct ReaderWebView: View {
    let model: ReaderModel
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
            .overlay(alignment: .topLeading) {
                if showsSpineShadow, model.isBookMode, let page = model.geometry?.size,
                   let gap = model.layout.gap(inReaderWidth: Double(page.width)) {
                    ReaderSpineShadow(gap: gap, height: Double(page.height))
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
