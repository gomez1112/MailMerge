import AppKit
import SwiftUI
import Testing
@testable import Mergeform

/// The state a parent view keeps for the Manage Categories sheet.
@Observable
private final class ManagerHostState {
    var isShowingManager = false
    var editorTarget: CategoryEditorTarget?
    var pendingDeletion: Mergeform.Category?
}

private struct ManagerHost: View {
    @Bindable var state: ManagerHostState
    let categories: [Mergeform.Category]

    var body: some View {
        Color.clear
            .frame(width: 600, height: 500)
            .sheet(isPresented: $state.isShowingManager) {
                CategoryManagerView(
                    categories: categories,
                    editorTarget: $state.editorTarget,
                    pendingDeletion: $state.pendingDeletion,
                    onSave: { _, _, _, _ in },
                    onDelete: { _ in },
                    onMove: { _, _ in }
                )
            }
    }
}

@MainActor
@Suite("Manage Categories sheet", .serialized)
struct CategoryManagerTests {
    /// Waits up to five seconds for `condition`, checking every tenth of a second.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<50 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    @Test("Add, Rename, and Delete show their dialogs over the open Manage Categories sheet")
    func dialogsAppearOverTheManager() async throws {
        let work = Mergeform.Category(name: "Work", sortOrder: 2)
        let state = ManagerHostState()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ManagerHost(state: state, categories: [work]))
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        state.isShowingManager = true
        #expect(try await eventually { window.attachedSheet != nil })
        let manager = try #require(window.attachedSheet)

        let dialogs: [(name: String, show: () -> Void, hide: () -> Void)] = [
            ("Add", { state.editorTarget = .add }, { state.editorTarget = nil }),
            ("Rename", { state.editorTarget = .edit(work) }, { state.editorTarget = nil }),
            ("Delete", { state.pendingDeletion = work }, { state.pendingDeletion = nil })
        ]
        for dialog in dialogs {
            dialog.show()
            #expect(try await eventually { manager.attachedSheet != nil }, "\(dialog.name) didn't appear over the manager")
            dialog.hide()
            #expect(try await eventually { manager.attachedSheet == nil }, "\(dialog.name) didn't close")
        }

        #expect(window.attachedSheet === manager)
        state.isShowingManager = false
        _ = try await eventually { window.attachedSheet == nil }
    }

    @Test("The editor starts with the category's current name, icon, and color")
    func editTargetPrefillsTheEditor() {
        let work = Mergeform.Category(name: "Work", systemImageName: "briefcase", colorName: "purple", sortOrder: 2)
        let edit = CategoryEditorTarget.edit(work)
        #expect(edit.title == "Edit Category")
        #expect(edit.initialName == "Work")
        #expect(edit.initialIconName == "briefcase")
        #expect(edit.initialColorName == "purple")
        #expect(CategoryEditorTarget.add.initialName.isEmpty)
    }
}
