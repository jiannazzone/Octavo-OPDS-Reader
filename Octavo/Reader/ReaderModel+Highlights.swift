import WebKit

/// SPIKE (#125): highlighting the selection.
extension ReaderModel {
    func highlightSelection(color: String) async {
        guard phase == .open else { return }
        let result = try? await page.callJavaScript("return await window.octavo.highlightSelection(color)", arguments: ["color": color])
        if let made = result as? [String: Any], let cfi = made["cfi"] as? String { highlightBar = cfi }
    }
}
