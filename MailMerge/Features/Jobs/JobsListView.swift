import SwiftUI
import SwiftData
import FlexStore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitService<MailMergeTier>.self) private var store

    init(pendingJobID: Binding<UUID?> = .constant(nil)) {
        _pendingJobID = pendingJobID
    }
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]

    @Binding private var pendingJobID: UUID?
    @SceneStorage("navigationPath") private var navigationPathData: Data = Data()
    @State private var navigationPath: [UUID] = []
    @State private var searchText = ""
    @State private var hasEnsuredDefaults = false
    @State private var showingNewJobSheet = false
    @State private var newJobCategoryID: UUID?

    @State private var showingCategoryEditor = false
    @State private var categoryEditorMode: CategoryEditorMode = .add
    @State private var categoryName = ""
    @State private var categoryIconName = "folder"
    @State private var categoryColorName = "gray"
    @State private var pendingDeleteCategory: Category?
    @State private var showingJobRename = false
    @State private var jobRenameName = ""
    @State private var jobToRename: MailMergeJob?

    @State private var showingCategoryManager = false
    @State private var showingPaywall = false
    @State private var showingLimitAlert = false
    @State private var showingPaywallAfterAlert = false
    @State private var isStoreReady = false

    @AppStorage("jobCreationCount") private var jobCreationCount = 0
    @AppStorage("cachedSubscriptionTier") private var cachedSubscriptionTier = 0

    private let freeJobLimit = 3

    private var filteredJobs: [MailMergeJob] {
        guard !searchText.isEmpty else { return jobs }
        return jobs.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(categories) { category in
                    categorySection(for: category)
                }
            }
            .listStyle(.inset)
            .navigationTitle("Jobs")
            .searchable(text: $searchText, prompt: "Search Jobs")
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(action: createJob) {
                            Label("New Job", systemImage: "plus")
                        }
                        Button("Manage Categories") {
                            showingCategoryManager = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createJob) {
                        Label("New Job", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Manage Categories") { showingCategoryManager = true }
                }
#endif
            }
            .navigationDestination(for: UUID.self) { jobID in
                if let job = jobs.first(where: { $0.id == jobID }) {
                    JobDetailView(job: job)
                } else {
                    ContentUnavailableView {
                        Label("Job Not Found", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("This job may have been deleted.")
                    }
                }
            }
            .onChange(of: pendingJobID) { _, newValue in
                guard let newValue else { return }
                navigationPath = [newValue]
                pendingJobID = nil
            }
            .sheet(isPresented: $showingNewJobSheet) {
                NewJobCategoryPickerView(
                    categories: categories,
                    selectedCategoryID: $newJobCategoryID,
                    onCreate: confirmCreateJob
                )
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
                JobRenameView(name: jobRenameName, onSave: saveJobRename)
            }
            .sheet(isPresented: $showingCategoryManager) {
                CategoryManagerView(
                    categories: categories,
                    onAdd: beginAdd,
                    onEdit: beginEdit,
                    onDelete: { category in pendingDeleteCategory = category },
                    onMove: moveCategory
                )
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("Free Job Limit Reached", isPresented: $showingLimitAlert) {
                Button("OK", role: .cancel) {
                    if showingPaywallAfterAlert {
                        showingPaywall = true
                        showingPaywallAfterAlert = false
                    }
                }
            } message: {
                Text("You have created 3 jobs. Upgrade to Pro or Lifetime to create more.")
            }
            .alert("Delete Category?", isPresented: Binding(
                get: { pendingDeleteCategory != nil },
                set: { if !$0 { pendingDeleteCategory = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let category = pendingDeleteCategory { deleteCategory(category) }
                    pendingDeleteCategory = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteCategory = nil }
            } message: {
                if let category = pendingDeleteCategory {
                    Text("\"\(category.name)\" will be removed. Jobs in this category will move to Uncategorized.")
                }
            }
        }
        .onAppear(perform: ensureDefaultCategoriesIfNeeded)
        .onAppear(perform: scheduleStoreReadyCheck)
        .onAppear(perform: cacheSubscriptionTier)
        .onAppear(perform: restoreNavigationPath)
        .onChange(of: navigationPath) { _, newPath in persistNavigationPath(newPath) }
        .onChange(of: store.subscriptionTier) { _, _ in
            isStoreReady = true
            cacheSubscriptionTier()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewJob)) { _ in createJob() }
        .focusedSceneValue(\.selectedJobID, navigationPath.last)
        .focusedSceneValue(\.deleteJobAction, focusedDeleteAction)
        .focusedSceneValue(\.renameJobAction, focusedRenameAction)
    }

    private var focusedDeleteAction: (() -> Void)? {
        guard let id = navigationPath.last,
              let job = jobs.first(where: { $0.id == id }) else { return nil }
        return { deleteJob(job) }
    }

    private var focusedRenameAction: (() -> Void)? {
        guard let id = navigationPath.last,
              let job = jobs.first(where: { $0.id == id }) else { return nil }
        return { beginRename(job) }
    }

    private var emptyCategory: some View {
        HStack {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("No jobs")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func restoreNavigationPath() {
        guard !navigationPathData.isEmpty else { return }
        if let ids = try? JSONDecoder().decode([UUID].self, from: navigationPathData) {
            navigationPath = ids
        }
    }

    @ViewBuilder
    private func categorySection(for category: Category) -> some View {
        let categoryJobs = filteredJobs.filter { ($0.category ?? uncategorizedCategory)?.id == category.id }
        Section {
            if categoryJobs.isEmpty {
                emptyCategory
            } else {
                ForEach(categoryJobs) { job in
                    NavigationLink(value: job.id) {
                        JobRowView(job: job)
                    }
                    .badge(jobBadge(job))
                    .contextMenu {
                        Button("Rename") { beginRename(job) }
                        Button("Delete", role: .destructive) { deleteJob(job) }
                    }
                }
                .onDelete { offsets in
                    deleteJobs(offsets: offsets, in: categoryJobs)
                }
            }
        } header: {
            CategoryHeaderView(
                category: category,
                onEdit: { beginEdit(category) },
                onDelete: { pendingDeleteCategory = category }
            )
        }
    }

    private func persistNavigationPath(_ path: [UUID]) {
        navigationPathData = (try? JSONEncoder().encode(path)) ?? Data()
    }

    private func createJob() {
        guard canCreateJob else {
            showLimitAlertAndPaywall()
            return
        }
        newJobCategoryID = (uncategorizedCategory ?? categories.first)?.id
        showingNewJobSheet = true
    }

    private func confirmCreateJob() {
        guard canCreateJob else {
            showLimitAlertAndPaywall()
            return
        }
        let category = categories.first(where: { $0.id == newJobCategoryID }) ?? uncategorizedCategory
        let job = MailMergeJob(name: "New Mergeform", category: category)
        modelContext.insert(job)
        navigationPath = [job.id]
        showingNewJobSheet = false
        recordJobCreation()
    }

    private func deleteJobs(offsets: IndexSet, in source: [MailMergeJob]) {
        for index in offsets {
            let job = source[index]
            modelContext.delete(job)
            navigationPath.removeAll(where: { $0 == job.id })
        }
    }

    private func deleteJob(_ job: MailMergeJob) {
        modelContext.delete(job)
        navigationPath.removeAll(where: { $0 == job.id })
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
    }

    private var uncategorizedCategory: Category? {
        categories.first(where: { $0.isLocked }) ?? categories.first(where: { $0.name == "Uncategorized" })
    }

    private var canCreateJob: Bool {
        if store.subscriptionTier >= .pro { return true }
        if !isStoreReady {
            if cachedSubscriptionTier >= MailMergeTier.pro.rawValue { return true }
            return jobCreationCount < freeJobLimit
        }
        return jobCreationCount < freeJobLimit
    }

    private func recordJobCreation() {
        if store.subscriptionTier < .pro {
            jobCreationCount += 1
        }
    }

    private func showLimitAlertAndPaywall() {
        showingPaywallAfterAlert = true
        showingLimitAlert = true
    }

    private func scheduleStoreReadyCheck() {
        guard !isStoreReady else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                isStoreReady = true
            }
        }
    }

    private func cacheSubscriptionTier() {
        cachedSubscriptionTier = store.subscriptionTier.rawValue
    }

    /// Returns a badge count for a job: shows last run record count for completed jobs,
    /// or the number of mapped fields for configured-but-unrun jobs.
    private func jobBadge(_ job: MailMergeJob) -> Int {
        if job.status == .completed, let count = job.lastRunRecordCount { return count }
        if job.status == .configured { return job.fieldMappings.count }
        return 0
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
            modelContext.insert(Category(
                name: trimmed,
                systemImageName: iconName,
                colorName: colorName,
                sortOrder: nextOrder,
                isLocked: false
            ))
        case .edit(let category):
            category.name = trimmed
            category.systemImageName = iconName
            category.colorName = colorName
        }
        showingCategoryEditor = false
    }

    private func deleteCategory(_ category: Category) {
        guard let fallback = uncategorizedCategory else { return }
        for job in jobs where job.category?.id == category.id {
            job.category = fallback
        }
        modelContext.delete(category)
    }

    private func moveCategory(from offsets: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
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
}

// MARK: - Category Header

private struct CategoryHeaderView: View {
    let category: Category
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var categoryColor: Color {
        CategoryColorOption.color(for: category.colorName)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(categoryColor)
                .frame(width: 3, height: 16)
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.12))
                Image(systemName: category.systemImageName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(categoryColor)
            }
            .frame(width: 18, height: 18)
            Text(category.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .contextMenu {
            Button("Rename") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Job Row

private struct JobRowView: View {
    let job: MailMergeJob

    private var iconColor: Color {
        switch job.status {
        case .completed: return .green
        case .running: return .mergeformOrange
        case .failed: return .red
        default: return .mergeformBlue
        }
    }

    private var iconName: String {
        switch job.status {
        case .completed: return "checkmark.circle.fill"
        case .running: return "arrow.trianglehead.2.clockwise"
        case .failed: return "exclamationmark.circle.fill"
        default: return "doc.text.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.15), iconColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Modified \(job.modifiedAt, format: .relative(presentation: .named))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                StatusBadge(status: job.status)
                if job.configurationProgress > 0 && job.configurationProgress < 1 {
                    ProgressIndicatorDots(progress: job.configurationProgress)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(job.status.label), Modified \(job.modifiedAt, format: .relative(presentation: .named))")
        .accessibilityHint("Double-tap to view and edit this job")
    }
}

private struct ProgressIndicatorDots: View {
    let progress: Double

    private let totalSteps = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<totalSteps, id: \.self) { index in
                let filled = Double(index) / Double(totalSteps) < progress
                Circle()
                    .fill(filled ? Color.mergeformBlue : Color.primary.opacity(0.12))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Category Manager Sheet

private struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    let onAdd: () -> Void
    let onEdit: (Category) -> Void
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
                        Button("Rename") { onEdit(category) }
                        Button("Delete", role: .destructive) { onDelete(category) }
                            .disabled(category.isLocked)
                    }
                    .moveDisabled(category.isLocked || !isReordering)
                }
                .onMove(perform: onMove)
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onAdd) {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(isReordering ? "Done Reordering" : "Reorder") {
                        isReordering.toggle()
                    }
                }
            }
        }
        .frame(width: 360, height: 460)
    }
}

// MARK: - Category Editor Sheet

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
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
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
    }
}

// MARK: - New Job Category Picker

private struct NewJobCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Job")
                    .font(.title3.bold())
                Text("Choose a category for your mail merge job.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(categories) { category in
                    let isSelected = selectedCategoryID == category.id
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(CategoryColorOption.color(for: category.colorName).opacity(0.15))
                                Image(systemName: category.systemImageName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CategoryColorOption.color(for: category.colorName))
                            }
                            .frame(width: 30, height: 30)
                            Text(category.name)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.mergeformBlue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.mergeformBlue.opacity(0.08) : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Job") {
                    onCreate()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCategoryID == nil)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        }
    }
}

// MARK: - Job Rename Sheet

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
                .font(.title3.bold())
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
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - Supporting Types

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

#Preview {
    ContentView(pendingJobID: .constant(nil))
        .modelContainer(for: MailMergeJob.self, inMemory: true)
}
