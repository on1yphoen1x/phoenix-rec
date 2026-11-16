import AppKit

enum Clipboard {
    // Writing the file URL lets Finder, Messages, Slack and Discord paste the
    // actual file. Screenshots also get raw PNG data so image editors and
    // browsers that ignore file URLs still receive the picture.
    static func copyFile(_ capture: Capture) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString(capture.fileURL.absoluteString, forType: .fileURL)
        if capture.kind == .screenshot, let data = try? Data(contentsOf: capture.fileURL) {
            item.setData(data, forType: .png)
        }
        pasteboard.writeObjects([item])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
