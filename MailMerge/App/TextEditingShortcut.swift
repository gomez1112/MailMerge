import AppKit

/// Routes menu shortcuts that also mean something while editing text.
enum TextEditingShortcut {
    /// Whether Delete Job's Command-Delete was meant for a text field, in which case it
    /// has been passed on to the field.
    ///
    /// Menu shortcuts are handled before the focused field sees the key, so without this
    /// Command-Delete (delete to the beginning of the line) would delete the job instead.
    /// Choosing the menu item with the pointer still deletes the job.
    @MainActor
    static func forwardsDeleteToText(responder: NSResponder?, isKeyEquivalent: Bool) -> Bool {
        guard isKeyEquivalent, let textView = responder as? NSTextView, textView.isEditable else {
            return false
        }
        textView.deleteToBeginningOfLine(nil)
        return true
    }
}
