import SwiftUI
import MessageUI

/// Wraps the system Messages composer. Unlike the `sms:` URL scheme, this reports
/// back whether the message was actually **sent** (via its delegate), which is what
/// lets Trove auto-track the outreach. `MFMessageComposeViewController.canSendText()`
/// is false on the Simulator — gate on it before presenting.
struct MessageComposer: UIViewControllerRepresentable {
    var body: String = ""
    var recipients: [String] = []
    var onResult: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        vc.recipients = recipients
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void
        init(onResult: @escaping (MessageComposeResult) -> Void) { self.onResult = onResult }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onResult(result)
        }
    }
}
