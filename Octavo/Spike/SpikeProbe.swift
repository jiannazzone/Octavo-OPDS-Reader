import SwiftUI
import UIKit
import WebKit

/// SPIKE ONLY (deleted after the spike). Records what the hinge and
/// reserved-region APIs report, scene changes, and screen appearances, one
/// JSON object per line in `Documents/spike-events.jsonl`, so a script on the
/// host can see what happened during a fold.
enum SpikeEvents {
    static let url = URL.documentsDirectory.appending(path: "spike-events.jsonl")
    /// Changes when the process starts, so a log shows relaunches.
    static let processID = UUID().uuidString.prefix(8)

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["event"] = event
        object["t"] = Date.now.formatted(.iso8601.time(includingFractionalSeconds: true))
        object["process"] = String(processID)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
        } else {
            try? (data + Data("\n".utf8)).write(to: url)
        }
    }

    static func hinge(_ context: DeviceHingeContext) -> [String: Any] {
        guard let hinge = context.hinge else { return ["hinge": NSNull()] }
        let status = switch hinge.status {
        case .closed: "closed"
        case .partiallyOpen: "partiallyOpen"
        case .fullyOpen: "fullyOpen"
        default: "other"
        }
        return ["status": status, "degrees": (hinge.angle.degrees * 10).rounded() / 10]
    }

    static func rect(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { (Double($0) * 10).rounded() / 10 }
    }

    /// Frames of the app's web views in window coordinates, to compare with
    /// what SwiftUI reports for the reader.
    static func webViews() -> [[Double]] {
        func find(_ view: UIView) -> [UIView] {
            view is WKWebView ? [view] : view.subviews.flatMap(find)
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .flatMap { window in find(window).map { rect($0.convert($0.bounds, to: window)) } }
    }

    /// The app's scenes: whether a fold makes a new one or moves the old one.
    static func scenes() -> [[String: Any]] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
            [
                "session": String(scene.session.persistentIdentifier.suffix(12)),
                "object": String(UInt(bitPattern: ObjectIdentifier(scene).hashValue), radix: 16),
                "screen": rect(scene.screen.bounds),
                "screenObject": String(UInt(bitPattern: ObjectIdentifier(scene.screen).hashValue), radix: 16),
                "state": scene.activationState.rawValue,
                "windows": scene.windows.count,
                "orientation": scene.effectiveGeometry.interfaceOrientation.rawValue,
            ]
        }
    }
}

private struct SpikeProbe: ViewModifier {
    let name: String
    /// Distinguishes two copies of the same screen, e.g. after SwiftUI rebuilt it.
    @State private var instance = UUID().uuidString.prefix(6)
    @Environment(\.scenePhase) private var scenePhase

    nonisolated struct Regions: Equatable {
        var size: CGSize
        var global: CGRect
        var regions: [ReservedRegion]
    }

    func body(content: Content) -> some View {
        content
            .onAppear { SpikeEvents.log("appear", ["view": name, "instance": String(instance), "scenes": SpikeEvents.scenes()]) }
            .onDisappear { SpikeEvents.log("disappear", ["view": name, "instance": String(instance)]) }
            .onChange(of: scenePhase, initial: true) { old, new in
                SpikeEvents.log("scenePhase", ["view": name, "old": "\(old)", "new": "\(new)", "scenes": SpikeEvents.scenes()])
            }
            .onHingeChange { old, new in
                SpikeEvents.log("hinge", ["view": name, "instance": String(instance), "old": SpikeEvents.hinge(old), "new": SpikeEvents.hinge(new)])
            }
            .onGeometryChange(for: Regions.self) { proxy in
                Regions(
                    size: proxy.size,
                    global: proxy.frame(in: .global),
                    regions: proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
                        + proxy.reservedRegions(kind: .occlusion, options: .includeInactive, layoutDirectionBehavior: .fixed)
                )
            } action: { value in
                SpikeEvents.log("geometry", [
                    "view": name,
                    "instance": String(instance),
                    "size": [value.size.width, value.size.height],
                    "global": SpikeEvents.rect(value.global),
                    "regions": value.regions.map { region in
                        [
                            "kind": region.kind == .division ? "division" : region.kind == .occlusion ? "occlusion" : "other",
                            "frame": SpikeEvents.rect(region.frame),
                            "margins": [region.margins.top, region.margins.leading, region.margins.bottom, region.margins.trailing],
                            "active": region.isActive,
                        ] as [String: Any]
                    },
                    "scenes": SpikeEvents.scenes(),
                    "webViews": SpikeEvents.webViews(),
                ])
            }
    }
}

extension View {
    /// SPIKE ONLY. Logs hinge, reserved-region and scene changes for `name`.
    func spikeProbe(_ name: String) -> some View {
        modifier(SpikeProbe(name: name))
    }
}
