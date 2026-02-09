import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]
    @State private var searchText = ""
    @State private var selectedSidebarSelection: SidebarSelection?
    @State private var selectedJob: MailMergeJob?
    @State private var hasEnsuredDefaults = false
    @State private var showingNewJobSheet = false
    @State private var newJobCategoryID: UUID?

    private var filteredJobs: [MailMergeJob] {
        guard let selectedSidebarSelection else { return [] }
        let baseJobs: [MailMergeJob]
        switch selectedSidebarSelection {
        case .category(let category):
            baseJobs = jobs.filter { ($0.category ?? uncategorizedCategory)?.id == category.id }
        case .recent(let filter):
            baseJobs = filter.apply(to: jobs)
        }
        guard !searchText.isEmpty else { return baseJobs }
        return baseJobs.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var jobCountsByCategory: [UUID: Int] {
        guard let uncategorizedCategory else { return [:] }
        return Dictionary(grouping: jobs, by: { ($0.category ?? uncategorizedCategory).id })
            .mapValues { $0.count }
    }

    var body: some View {
        NavigationSplitView(
            sidebar: {
                UnifiedSidebarView(
                    selectedSelection: $selectedSidebarSelection,
                    selectedJob: $selectedJob,
                    searchText: $searchText,
                    categories: categories,
                    allJobs: jobs,
                    uncategorizedCategory: uncategorizedCategory,
                    jobCountsByCategory: jobCountsByCategory,
                    filteredJobs: filteredJobs,
                    onCreate: createJob,
                    onDelete: deleteJobs
                )
            },
            detail: {
                if let job = selectedJob {
                    JobDetailView(job: job)
                } else {
                    JobEmptyStateView(onCreate: createJob)
                }
            }
        )
        .sheet(isPresented: $showingNewJobSheet) {
            NewJobCategoryPickerView(
                categories: categories,
                selectedCategoryID: $newJobCategoryID,
                onCreate: confirmCreateJob
            )
        }
        .onAppear(perform: ensureDefaultCategoriesIfNeeded)
        .onChange(of: selectedSidebarSelection) { _, _ in
            syncSelection()
        }
        .onChange(of: searchText) { _, _ in
            syncSelection()
        }
        .onChange(of: jobs.count) { _, _ in
            syncSelection()
        }
        .onDeleteCommand {
            if let selectedJob, let index = filteredJobs.firstIndex(where: { $0.id == selectedJob.id }) {
                deleteJobs(at: IndexSet(integer: index))
            }
        }
        .onChange(of: categories.count) { _, _ in
            syncSelection()
        }
    }

    private func createJob() {
        newJobCategoryID = (selectedCategory ?? uncategorizedCategory ?? categories.first)?.id
        showingNewJobSheet = true
    }

    private func confirmCreateJob() {
        let category = categories.first(where: { $0.id == newJobCategoryID }) ?? uncategorizedCategory
        let job = MailMergeJob(name: "New Mail Merge", category: category)
        modelContext.insert(job)
        selectedJob = job
        if let category {
            selectedSidebarSelection = .category(category)
        }
        showingNewJobSheet = false
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            let job = filteredJobs[index]
            modelContext.delete(job)
        }
        syncSelection()
    }

    private func ensureDefaultCategoriesIfNeeded() {
        guard !hasEnsuredDefaults else { return }
        hasEnsuredDefaults = true

        if categories.isEmpty {
            for seed in DefaultCategorySeed.defaults {
                let category = Category(
                    name: seed.name,
                    systemImageName: seed.systemImageName,
                    colorName: seed.colorName,
                    sortOrder: seed.sortOrder,
                    isLocked: seed.isLocked
                )
                modelContext.insert(category)
            }
        }
        if let uncategorizedCategory {
            for job in jobs where job.category == nil {
                job.category = uncategorizedCategory
            }
        }
        if selectedSidebarSelection == nil, let category = uncategorizedCategory ?? categories.first {
            selectedSidebarSelection = .category(category)
        }
        syncSelection()
    }

    private func syncSelection() {
        if selectedSidebarSelection == nil, let category = uncategorizedCategory ?? categories.first {
            selectedSidebarSelection = .category(category)
        }
        if case .category(let category) = selectedSidebarSelection,
           categories.contains(where: { $0.id == category.id }) == false {
            if let fallback = uncategorizedCategory ?? categories.first {
                selectedSidebarSelection = .category(fallback)
            }
        }
        if let selectedJob, filteredJobs.contains(where: { $0.id == selectedJob.id }) {
            return
        }
        selectedJob = filteredJobs.first
    }

    private var selectedCategory: Category? {
        guard case .category(let category) = selectedSidebarSelection else { return nil }
        return category
    }

    private var uncategorizedCategory: Category? {
        categories.first(where: { $0.isLocked }) ?? categories.first(where: { $0.name == "Uncategorized" })
    }
}

private struct UnifiedSidebarView: View {
    @Binding var selectedSelection: SidebarSelection?
    @Binding var selectedJob: MailMergeJob?
    @Binding var searchText: String
    let categories: [Category]
    let allJobs: [MailMergeJob]
    let uncategorizedCategory: Category?
    let jobCountsByCategory: [UUID: Int]
    let filteredJobs: [MailMergeJob]
    let onCreate: () -> Void
    let onDelete: (IndexSet) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showingCategoryEditor = false
    @State private var categoryEditorMode: CategoryEditorMode = .add
    @State private var categoryName = ""
    @State private var categoryIconName = "folder"
    @State private var categoryColorName = "gray"
    @State private var isReordering = false
    @State private var pendingDeleteCategory: Category?
    @State private var showingJobRename = false
    @State private var jobRenameName = ""
    @State private var jobToRename: MailMergeJob?

    var body: some View {
        List(selection: $selectedJob) {
            Section("Recents") {
                ForEach(RecentFilter.allCases) { filter in
                    Button {
                        selectedSelection = .recent(filter)
                    } label: {
                        HStack(spacing: 10) {
                            Label(filter.title, systemImage: filter.systemImageName)
                            Spacer()
                            if selectedSelection == .recent(filter) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .recent = selectedSelection {
                Section("Recent Jobs") {
                    if filteredJobs.isEmpty {
                        Text("No recent jobs")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(filteredJobs) { job in
                            JobRowView(job: job)
                                .tag(job as MailMergeJob?)
                                .contextMenu {
                                    Button("Rename") {
                                        beginRename(job)
                                    }
                                }
                        }
                        .onDelete { offsets in
                            onDelete(offsets)
                        }
                    }
                }
            }

            Section {
                ForEach(categories) { category in
                    DisclosureGroup(isExpanded: .constant(selectedSelection == .category(category))) {
                        let categoryJobs = allJobs.filter { ($0.category ?? uncategorizedCategory)?.id == category.id }
                        if categoryJobs.isEmpty {
                            Text("No jobs")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(categoryJobs) { job in
                                JobRowView(job: job)
                                    .tag(job as MailMergeJob?)
                                    .contextMenu {
                                        Button("Rename") {
                                            beginRename(job)
                                        }
                                    }
                            }
                            .onDelete { offsets in
                                onDelete(offsets)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CategoryColorOption.color(for: category.colorName))
                                .frame(width: 8, height: 8)
                            Label(category.name, systemImage: category.systemImageName)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(CategoryColorOption.color(for: category.colorName), .primary)
                        }
                        .badge(jobCountsByCategory[category.id, default: 0])
                        .contextMenu {
                            Button("Rename") {
                                beginEdit(category)
                            }
                            Button("Delete", role: .destructive) {
                                pendingDeleteCategory = category
                            }
                            .disabled(category.isLocked)
                        }
                    }
                    .onTapGesture {
                        selectedSelection = .category(category)
                    }
                    .moveDisabled(category.isLocked)
                }
                .onMove(perform: moveCategory)
                .moveDisabled(!isReordering)
            } header: {
                HStack {
                    Text("Categories")
                    Spacer()
                    Button {
                        toggleReorder()
                    } label: {
                        Image(systemName: isReordering ? "checkmark" : "line.3.horizontal")
                    }
                    .buttonStyle(.plain)
                    .help(isReordering ? "Done Reordering" : "Reorder Categories")
                    Button {
                        beginAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Category")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mail Merge")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Label("New Job", systemImage: "plus")
                }
                .help("Create New Job")
                .accessibilityLabel("Create New Job")
                .accessibilityHint("Creates a new mail merge job in the selected category")
            }
        }
        .sheet(isPresented: $showingCategoryEditor) {
            CategoryEditorView(
                title: categoryEditorMode.title,
                name: categoryName,
                iconName: categoryIconName,
                colorName: categoryColorName,
                onSave: saveCategory
            )
        }
        .sheet(isPresented: $showingJobRename) {
            JobRenameView(
                name: jobRenameName,
                onSave: saveJobRename
            )
        }
        .alert("Delete Category?", isPresented: Binding(get: {
            pendingDeleteCategory != nil
        }, set: { newValue in
            if !newValue { pendingDeleteCategory = nil }
        })) {
            Button("Delete", role: .destructive) {
                if let category = pendingDeleteCategory {
                    deleteCategory(category)
                }
                pendingDeleteCategory = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteCategory = nil
            }
        } message: {
            if let category = pendingDeleteCategory {
                Text("“\(category.name)” will be removed. Jobs in this category will move to Uncategorized.")
            }
        }
    }

    private func beginAdd() {
        categoryEditorMode = .add
        categoryName = ""
        categoryIconName = "folder"
        categoryColorName = "gray"
        showingCategoryEditor = true
    }

    private func beginEdit(_ category: Category) {
        categoryEditorMode = .edit(category)
        categoryName = category.name
        categoryIconName = category.systemImageName
        categoryColorName = category.colorName
        showingCategoryEditor = true
    }

    private func saveCategory(_ name: String, iconName: String, colorName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch categoryEditorMode {
        case .add:
            let nextOrder = (categories.map(\.sortOrder).max() ?? 0) + 1
            let category = Category(
                name: trimmed,
                systemImageName: iconName,
                colorName: colorName,
                sortOrder: nextOrder,
                isLocked: false
            )
            modelContext.insert(category)
            selectedSelection = .category(category)
        case .edit(let category):
            category.name = trimmed
            category.systemImageName = iconName
            category.colorName = colorName
        }
        showingCategoryEditor = false
    }

    private func beginRename(_ job: MailMergeJob) {
        jobToRename = job
        jobRenameName = job.name
        showingJobRename = true
    }

    private func saveJobRename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        jobToRename?.name = trimmed
        showingJobRename = false
        jobToRename = nil
    }

    private func deleteCategory(_ category: Category) {
        guard let fallback = uncategorizedCategory else { return }
        for job in allJobs where job.category?.id == category.id {
            job.category = fallback
        }
        modelContext.delete(category)
        if selectedSelection == .category(category) {
            selectedSelection = .category(fallback)
        }
    }

    private func moveCategory(from offsets: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
    }

    private func toggleReorder() {
        isReordering.toggle()
    }
}

private enum SidebarSelection: Equatable {
    case category(Category)
    case recent(RecentFilter)

    static func == (lhs: SidebarSelection, rhs: SidebarSelection) -> Bool {
        switch (lhs, rhs) {
        case (.recent(let left), .recent(let right)):
            return left == right
        case (.category(let left), .category(let right)):
            return left.id == right.id
        default:
            return false
        }
    }
}

private enum RecentFilter: String, CaseIterable, Identifiable {
    case all
    case last7Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Jobs"
        case .last7Days: return "Last 7 Days"
        }
    }

    var systemImageName: String {
        switch self {
        case .all: return "tray.full"
        case .last7Days: return "clock"
        }
    }

    func apply(to jobs: [MailMergeJob]) -> [MailMergeJob] {
        switch self {
        case .all:
            return jobs
        case .last7Days:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return jobs.filter { $0.modifiedAt >= cutoff }
        }
    }
}

private enum CategoryEditorMode {
    case add
    case edit(Category)

    var title: String {
        switch self {
        case .add: return "New Category"
        case .edit: return "Edit Category"
        }
    }
}

private struct DefaultCategorySeed {
    let name: String
    let systemImageName: String
    let colorName: String
    let sortOrder: Int
    let isLocked: Bool

    static let defaults: [DefaultCategorySeed] = [
        DefaultCategorySeed(name: "Uncategorized", systemImageName: "tray", colorName: "gray", sortOrder: 0, isLocked: true),
        DefaultCategorySeed(name: "Personal", systemImageName: "person", colorName: "blue", sortOrder: 1, isLocked: false),
        DefaultCategorySeed(name: "Work", systemImageName: "briefcase", colorName: "purple", sortOrder: 2, isLocked: false),
        DefaultCategorySeed(name: "Marketing", systemImageName: "megaphone", colorName: "orange", sortOrder: 3, isLocked: false),
        DefaultCategorySeed(name: "Events", systemImageName: "calendar", colorName: "green", sortOrder: 4, isLocked: false),
        DefaultCategorySeed(name: "Archived", systemImageName: "archivebox", colorName: "brown", sortOrder: 5, isLocked: false)
    ]
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconName: String
    @State private var colorName: String
    let title: String
    let onSave: (String, String, String) -> Void

    init(title: String, name: String, iconName: String, colorName: String, onSave: @escaping (String, String, String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: name)
        _iconName = State(initialValue: iconName)
        _colorName = State(initialValue: colorName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            TextField("Category name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Icon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(CategoryIconOption.all) { option in
                    Button {
                        iconName = option.systemImageName
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(iconName == option.systemImageName ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                            Image(systemName: option.systemImageName)
                                .foregroundStyle(iconName == option.systemImageName ? Color.accentColor : .secondary)
                                .frame(width: 26, height: 26)
                        }
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                }
            }

            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(CategoryColorOption.all) { option in
                    Button {
                        colorName = option.colorName
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(colorName == option.colorName ? option.color.opacity(0.25) : Color.secondary.opacity(0.08))
                            Circle()
                                .fill(option.color)
                                .frame(width: 14, height: 14)
                            if colorName == option.colorName {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .offset(x: 10, y: -10)
                            }
                        }
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
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
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct JobRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let onSave: (String) -> Void

    init(name: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Job")
                .font(.headline)
            TextField("Job name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct NewJobCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Category")
                .font(.headline)
            Picker("Category", selection: $selectedCategoryID) {
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.systemImageName)
                        .tag(Optional(category.id))
                }
            }
            .pickerStyle(.inline)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    onCreate()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategoryID == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        }
    }
}

private struct CategoryIconOption: Identifiable {
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

private struct CategoryColorOption: Identifiable {
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




private struct JobRowView: View {
    let job: MailMergeJob
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.body)
                Text("Updated \(job.modifiedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: job.status)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(job.status.label), Updated \(job.modifiedAt, format: .relative(presentation: .named))")
        .accessibilityHint("Double-tap to view and edit this job")
    }
}

private struct JobEmptyStateView: View {
    let onCreate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Job Selected", systemImage: "doc.text")
        } description: {
            Text("Select a job from the sidebar or create a new one")
        } actions: {
            Button("New Job", action: onCreate)
                .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MailMergeJob.self, inMemory: true)
}
