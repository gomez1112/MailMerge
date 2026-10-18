import SwiftUI

// MARK: - Category Manager Sheet

/// Lists categories for adding, renaming, deleting, and reordering.
///
/// The manager is itself a sheet, and macOS can't show another sheet or an alert from the
/// view underneath it while it's open. So the manager presents its editor and delete
/// confirmation from its own content.
struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var editorTarget: CategoryEditorTarget?
    @Binding var pendingDeletion: Category?
    let onSave: (_ target: CategoryEditorTarget, _ name: String, _ iconName: String, _ colorName: String) -> Void
    let onDelete: (Category) -> Void
    let onMove: (IndexSet, Int) -> Void
    @State private var isReordering = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CategoryColorOption.color(for: category.colorName).opacity(0.15))
                            Image(systemName: category.systemImageName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CategoryColorOption.color(for: category.colorName))
                        }
                        .frame(width: 28, height: 28)
                        Text(category.name)
                            .font(.system(size: 13))
                        if category.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .contextMenu {
                        Button("Rename") { editorTarget = .edit(category) }
                        Button("Delete", role: .destructive) { pendingDeletion = category }
                            .disabled(category.isLocked)
                    }
                    .moveDisabled(category.isLocked || !isReordering)
                }
                .onMove(perform: onMove)
            }
            .navigationTitle("Categories")
            .scrollContentBackground(.hidden)
            .background(Color.mergeformBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") {
                        editorTarget = .add
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(isReordering ? "Done Reordering" : "Reorder") {
                        isReordering.toggle()
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                CategoryEditorView(target: target) { name, iconName, colorName in
                    onSave(target, name, iconName, colorName)
                }
            }
            .categoryDeletionConfirmation($pendingDeletion, onDelete: onDelete)
        }
        .frame(width: 360, height: 460)
    }
}

extension View {
    /// Asks before deleting a category, explaining where its jobs go.
    func categoryDeletionConfirmation(_ pending: Binding<Category?>, onDelete: @escaping (Category) -> Void) -> some View {
        alert(
            "Delete Category?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            presenting: pending.wrappedValue
        ) { category in
            Button("Delete", role: .destructive) { onDelete(category) }
            Button("Cancel", role: .cancel) { }
        } message: { category in
            Text("“\(category.name)” will be removed. Jobs in this category will move to Uncategorized.")
        }
    }
}

// MARK: - Category Editor Sheet

/// Names a new category or edits an existing one.
struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (_ name: String, _ iconName: String, _ colorName: String) -> Void
    @State private var name: String
    @State private var iconName: String
    @State private var colorName: String

    init(target: CategoryEditorTarget, onSave: @escaping (_ name: String, _ iconName: String, _ colorName: String) -> Void) {
        title = target.title
        self.onSave = onSave
        name = target.initialName
        iconName = target.initialIconName
        colorName = target.initialColorName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Icon")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(CategoryIconOption.all) { option in
                        Button {
                            iconName = option.systemImageName
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(iconName == option.systemImageName
                                        ? Color.mergeformBlue.opacity(0.15)
                                        : Color.primary.opacity(0.06))
                                Image(systemName: option.systemImageName)
                                    .foregroundStyle(iconName == option.systemImageName
                                        ? Color.mergeformBlue
                                        : .secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        iconName == option.systemImageName
                                            ? Color.mergeformBlue.opacity(0.4)
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Color")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(CategoryColorOption.all) { option in
                        Button {
                            colorName = option.colorName
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                                if colorName == option.colorName {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .strokeBorder(
                                        colorName == option.colorName
                                            ? option.color
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                                    .padding(-4)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(name, iconName, colorName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.mergeformBackground)
    }
}

// MARK: - Supporting Types

/// What the category editor is for: a new category or an existing one.
enum CategoryEditorTarget: Identifiable {
    case add
    case edit(Category)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let category): return category.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add: return "New Category"
        case .edit: return "Edit Category"
        }
    }

    var initialName: String {
        if case .edit(let category) = self { return category.name }
        return ""
    }

    var initialIconName: String {
        if case .edit(let category) = self { return category.systemImageName }
        return "folder"
    }

    var initialColorName: String {
        if case .edit(let category) = self { return category.colorName }
        return "gray"
    }
}

struct CategoryIconOption: Identifiable {
    let id: String
    let title: String
    let systemImageName: String

    static let all: [CategoryIconOption] = [
        CategoryIconOption(id: "folder", title: "Folder", systemImageName: "folder"),
        CategoryIconOption(id: "tray", title: "Tray", systemImageName: "tray"),
        CategoryIconOption(id: "briefcase", title: "Briefcase", systemImageName: "briefcase"),
        CategoryIconOption(id: "person", title: "Person", systemImageName: "person"),
        CategoryIconOption(id: "megaphone", title: "Megaphone", systemImageName: "megaphone"),
        CategoryIconOption(id: "calendar", title: "Calendar", systemImageName: "calendar"),
        CategoryIconOption(id: "archivebox", title: "Archive", systemImageName: "archivebox"),
        CategoryIconOption(id: "tag", title: "Tag", systemImageName: "tag"),
        CategoryIconOption(id: "star", title: "Star", systemImageName: "star")
    ]
}

struct CategoryColorOption: Identifiable {
    let id: String
    let title: String
    let colorName: String
    let color: Color

    static let all: [CategoryColorOption] = [
        CategoryColorOption(id: "gray", title: "Gray", colorName: "gray", color: .gray),
        CategoryColorOption(id: "blue", title: "Blue", colorName: "blue", color: .blue),
        CategoryColorOption(id: "purple", title: "Purple", colorName: "purple", color: .purple),
        CategoryColorOption(id: "orange", title: "Orange", colorName: "orange", color: .orange),
        CategoryColorOption(id: "green", title: "Green", colorName: "green", color: .green),
        CategoryColorOption(id: "red", title: "Red", colorName: "red", color: .red),
        CategoryColorOption(id: "yellow", title: "Yellow", colorName: "yellow", color: .yellow),
        CategoryColorOption(id: "brown", title: "Brown", colorName: "brown", color: .brown)
    ]

    static func color(for name: String) -> Color {
        all.first(where: { $0.colorName == name })?.color ?? .gray
    }
}
