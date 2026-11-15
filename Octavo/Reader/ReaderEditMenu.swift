import UIKit
import WebKit

/// SPIKE (#125): Highlight first in the system's selection menu.
@MainActor
enum ReaderEditMenu {
    static weak var reader: ReaderModel?

    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .context, let reader, reader.swipes.pageHasSelection else { return }
        let highlight = UIAction(title: "Highlight") { _ in reader.highlightSelection(color: "#FACC15") }
        let note = UIAction(title: "Note") { _ in reader.highlightSelection(color: "#FACC15") }
        builder.insertChild(UIMenu(options: .displayInline, children: [highlight, note]), atStartOfMenu: .root)
    }
}

extension ReaderModel {
    func highlightSelection(color: String) {
        guard phase == .open else { return }
        call("return await window.octavo.highlightSelection(color)", arguments: ["color": color])
    }
}

/// SPIKE (#125): SwiftUI's `WebView` has no edit-menu hook on iOS, and its
/// own `UIApplication` and app delegate keep ours out of the responder
/// chain, but WebKit asks the web view itself. So the web view gets a
/// runtime subclass that adds `buildMenu(with:)`, as KVO does.
@MainActor
enum ReaderMenuProbe {
    static func install(on web: WKWebView) {
        let base: AnyClass = type(of: web)
        if NSStringFromClass(base).hasPrefix("Octavo_") { return }
        let name = "Octavo_" + NSStringFromClass(base)
        var probe: AnyClass? = NSClassFromString(name)
        if probe == nil, let made = objc_allocateClassPair(base, name, 0) {
            let selector = #selector(UIResponder.buildMenu(with:))
            let original = class_getMethodImplementation(base, selector)
            typealias Build = @convention(c) (AnyObject, Selector, UIMenuBuilder) -> Void
            let block: @convention(block) (AnyObject, UIMenuBuilder) -> Void = { object, builder in
                if let original { unsafeBitCast(original, to: Build.self)(object, selector, builder) }
                MainActor.assumeIsolated { ReaderEditMenu.build(builder) }
            }
            let types = method_getTypeEncoding(class_getInstanceMethod(base, selector)!)
            class_addMethod(made, selector, imp_implementationWithBlock(block), types)
            objc_registerClassPair(made)
            probe = made
        }
        if let probe { object_setClass(web, probe) }
    }
}
