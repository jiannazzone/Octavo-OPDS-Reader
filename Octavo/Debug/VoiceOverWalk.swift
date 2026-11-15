#if DEBUG
import UIKit

/// DEBUG ONLY. What VoiceOver would read on the current screen, in order,
/// for #74 (`docs/notes/accessibility.md`). XCUITest's tree lists elements
/// the app hides with `accessibilityHidden` too, so it can't show this.
///
/// Walks the window's accessibility elements as VoiceOver does: hidden
/// containers and views are skipped, an element stops the walk into its
/// children, a container's `accessibilityElements` are taken in its own
/// order, a plain view's subviews by position, and a modal view hides its
/// siblings. VoiceOver's own order can still differ, so the frames are
/// printed to check it by. The book's words live in WebKit's own process and
/// show as one element here. SwiftUI builds no elements until accessibility
/// is on: `defaults write com.apple.Accessibility
/// ApplicationAccessibilityEnabled -bool true` on the simulator, then
/// relaunch. Stopping an XCUITest run turns it off again.
enum VoiceOverWalk {
    /// `tree` also lists the containers, indented, and what was skipped.
    static func read(tree: Bool = false) -> String {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
            .sorted { $0.windowLevel.rawValue > $1.windowLevel.rawValue }
        var lines: [String] = []
        for window in windows {
            lines.append("# \(type(of: window)) level \(window.windowLevel.rawValue)\(window.isKeyWindow ? " key" : "")")
            visit(window, depth: 0, tree: tree, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// Sends the page's item (the one that turns pages) a scroll, as
    /// VoiceOver does, and says whether it took it.
    static func scrollPage(_ direction: UIAccessibilityScrollDirection) -> String {
        var found: [NSObject] = []
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            collect(window, depth: 0, where: { $0.accessibilityTraits.contains(.causesPageTurn) }, into: &found)
        }
        guard let page = found.first else { return "no page item" }
        return page.accessibilityScroll(direction) ? "taken" : "refused"
    }

    /// A double tap on the item called `name`, or on the page's item, as
    /// VoiceOver sends it (and Voice Control's "Tap …").
    static func activate(named name: String?) -> String {
        var found: [NSObject] = []
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            collect(window, depth: 0, where: {
                if let name { $0.accessibilityLabel == name } else { $0.accessibilityTraits.contains(.causesPageTurn) }
            }, into: &found)
        }
        guard let item = found.first else { return "no item \(name ?? "for the page")" }
        return item.accessibilityActivate() ? "taken" : "refused"
    }

    private static func collect(_ object: NSObject, depth: Int, where matches: (NSObject) -> Bool, into found: inout [NSObject]) {
        guard depth < 80, !object.accessibilityElementsHidden else { return }
        if object.isAccessibilityElement {
            if matches(object) { found.append(object) }
            return
        }
        for child in children(of: object) {
            collect(child, depth: depth + 1, where: matches, into: &found)
        }
    }

    private static func visit(_ object: NSObject, depth: Int, tree: Bool, into lines: inout [String]) {
        let indent = tree ? String(repeating: " ", count: depth) : ""
        guard depth < 80 else { return }
        if object.accessibilityElementsHidden {
            if tree { lines.append(indent + "(hidden) " + describe(object)) }
            return
        }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 {
            if tree { lines.append(indent + "(invisible) " + describe(object)) }
            return
        }
        if object.isAccessibilityElement {
            lines.append(indent + describe(object))
            return
        }
        let children = children(of: object)
        if tree { lines.append(indent + "[\(children.count)] " + describe(object)) }
        if children.isEmpty, String(describing: type(of: object)).contains("Remote") {
            // WebKit's page, read in its own process.
            lines.append(indent + "(web content)  " + describe(object))
            return
        }
        // VoiceOver reads only modal views, not their siblings. A sheet's
        // dimming view says it's one, but the sheet beside it is read.
        let modals = children.filter {
            $0.accessibilityViewIsModal && !String(describing: type(of: $0)).contains("DimmingView")
        }
        for child in modals.isEmpty ? children : modals {
            visit(child, depth: depth + 1, tree: tree, into: &lines)
        }
    }

    private static func children(of object: NSObject) -> [NSObject] {
        if let elements = object.accessibilityElements {
            return elements.compactMap { $0 as? NSObject }
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        }
        // VoiceOver reads a plain view's subviews top to bottom, then by the
        // leading edge, not in the order they were added.
        return ((object as? UIView)?.subviews ?? []).sorted {
            let a = $0.accessibilityFrame, b = $1.accessibilityFrame
            return a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX
        }
    }

    private static func describe(_ object: NSObject) -> String {
        var parts = ["'\(object.accessibilityLabel ?? "")'"]
        if let value = object.accessibilityValue, !value.isEmpty { parts.append("value '\(value)'") }
        let traits = traitNames(object.accessibilityTraits)
        if !traits.isEmpty { parts.append(traits.joined(separator: ",")) }
        if let hint = object.accessibilityHint, !hint.isEmpty { parts.append("hint '\(hint)'") }
        let actions = object.accessibilityCustomActions?.map(\.name) ?? []
        if !actions.isEmpty { parts.append("actions [\(actions.joined(separator: ", "))]") }
        if let inputLabels = object.accessibilityUserInputLabels, !inputLabels.isEmpty {
            parts.append("input [\(inputLabels.joined(separator: ", "))]")
        }
        let frame = object.accessibilityFrame
        if [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) {
            parts.append("@\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        } else {
            parts.append("@nowhere")
        }
        parts.append(String(describing: type(of: object)))
        return parts.joined(separator: "  ")
    }

    private static func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        let names: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.link, "link"), (.header, "header"), (.selected, "selected"),
            (.image, "image"), (.staticText, "text"), (.adjustable, "adjustable"),
            (.notEnabled, "dimmed"), (.searchField, "search"), (.tabBar, "tabBar"),
            (.updatesFrequently, "updates"), (.allowsDirectInteraction, "direct"),
            (.causesPageTurn, "pageTurn"), (.keyboardKey, "key"), (.summaryElement, "summary"),
            (.toggleButton, "toggle"), (.playsSound, "sound"), (.startsMediaSession, "media"),
        ]
        let known = names.reduce(UIAccessibilityTraits()) { $0.union($1.0) }
        let others = traits.subtracting(known).rawValue
        return names.filter { traits.contains($0.0) }.map(\.1) + (others == 0 ? [] : ["other 0x" + String(others, radix: 16)])
    }
}
#endif
