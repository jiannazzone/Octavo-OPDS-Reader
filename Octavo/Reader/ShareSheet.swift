import UIKit

/// The system share sheet from code, for an action with no button to hang a
/// `ShareLink` on: VoiceOver's Share on a highlight's row (#125).
@MainActor
enum ShareSheet {
    static func present(_ text: String) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(sheet, animated: true)
    }
}
