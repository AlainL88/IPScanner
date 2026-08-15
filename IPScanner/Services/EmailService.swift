//
//  EmailService.swift
//  IPScanner
//
//  Created by Alain Lima on 15/08/2026.
//

import Foundation

#if canImport(MessageUI)
import MessageUI
#endif
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Composes an email with an optional CSV/JSON attachment.
///
/// iOS: MFMailComposeViewController (falls back to a mailto: link if no mail
/// account is configured). macOS: NSSharingService(.composeEmail).
public enum EmailService {
    public static func compose(
        subject: String,
        body: String,
        attachmentName: String? = nil,
        attachmentData: Data? = nil,
        attachmentMime: String = "text/csv"
    ) {
        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            let controller = MFMailComposeViewController()
            controller.setSubject(subject)
            controller.setMessageBody(body, isHTML: false)
            if let attachmentName, let attachmentData {
                controller.addAttachmentData(attachmentData, mimeType: attachmentMime, fileName: attachmentName)
            }
            presentOniOS(controller)
        } else {
            openMailto(subject: subject, body: body)
        }
        #elseif os(macOS)
        guard let service = NSSharingService(named: .composeEmail) else { return }
        var items: [Any] = [body]
        if let attachmentName, let attachmentData, let url = writeTempFile(data: attachmentData, name: attachmentName) {
            items.insert(url, at: 0)
        }
        service.perform(withItems: items)
        #endif
    }

    #if os(iOS)
    private static func presentOniOS(_ controller: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(controller, animated: true)
    }

    private static func openMailto(subject: String, body: String) {
        let subjectQuery = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyQuery = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:?subject=\(subjectQuery)&body=\(bodyQuery)") else { return }
        UIApplication.shared.open(url)
    }
    #endif

    #if os(macOS)
    private static func writeTempFile(data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
    #endif
}
