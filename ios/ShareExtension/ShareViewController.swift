import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedFile()
    }


    private func handleSharedFile() {

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            complete()
            return
        }

        let groupId = "group.com.vaibhs.smartreceipt"

        for provider in attachments {

            // Handle image
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, _ in
                    self?.saveAndOpenApp(data: data, groupId: groupId)
                }
                return
            }

            // Handle PDF
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] data, _ in
                    self?.saveAndOpenApp(data: data, groupId: groupId)
                }
                return
            }
        }

        complete()
    }

    private func saveAndOpenApp(data: Any?, groupId: String) {

        guard let url = data as? URL else {
            complete()
            return
        }

        let fileManager = FileManager.default

        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: groupId
        ) else {
            complete()
            return
        }

        // Use unique filename to avoid collision
        let uniqueName = UUID().uuidString + "_" + url.lastPathComponent
        let destURL = containerURL.appendingPathComponent(uniqueName)

        do {
            try fileManager.copyItem(at: url, to: destURL)

            DispatchQueue.main.async {
                self.openMainApp(with: destURL)
            }

        } catch {
            print("File copy failed: \(error)")
            complete()
        }
    }

    private func openMainApp(with fileURL: URL) {
        let encodedPath = fileURL.path.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed
        ) ?? ""

        guard let url = URL(string: "receiptnest://share?file=\(encodedPath)") else {
            complete()
            return
        }

        var responder: UIResponder? = self

        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url)
                break
            }
            responder = responder?.next
        }

        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    
}