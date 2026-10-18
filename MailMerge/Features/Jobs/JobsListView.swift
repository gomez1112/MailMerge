import SwiftUI
import SwiftData
import FlexStore
import StoreKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @Environment(MergeRunStore.self) private var mergeRuns

    init(pendingJobID: Binding<UUID?> = .constant(nil), newJobRequested: Binding<Bool> = .constant(false)) {
        _pendingJobID = pendingJobID
        _newJobRequested = newJobRequested
    }
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]

    @Binding private var pendingJobID: UUID?
    /// Set by File > New Job; the list starts creating a job and clears it.
    @Binding private var newJobRequested: Bool
    @SceneStorage("navigationPath") private var navigationPathData: Data = Data()
    @State private var navigationPath: [UUID] = []
    @State private var searchText = ""
    @State private var hasEnsuredDefaults = false
    @State private var showingNewJobSheet = false
    @State private var newJobCategoryID: UUID?
    @State private var newJobName = ""

    /// The category being added or renamed from a section header.
    @State private var categoryEditorTarget: CategoryEditorTarget?
    @State private var pendingDeleteCategory: Category?
    /// The same, for the Manage Categories sheet, which presents its own dialogs.
    @State private var managerEditorTarget: CategoryEditorTarget?
    @State private var managerPendingDeletion: Category?
    @State private var showingJobRename = false
    @State private var jobRenameName = ""
    @State private var jobToRename: MailMergeJob?

    @State private var showingCategoryManager = false
    @State private var showingPaywall = false
    @State private var showingLimitAlert = false
    @State private var showingPaywallAfterAlert = false
    @State private var entitlementHasPro = false
    @State private var entitlementObserverTask: Task<Void, Never>?
    @State private var jobCommandRouter = JobCommandRouter()

    @AppStorage("jobCreationCount") private var jobCreationCount = 0
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var jobPendingDeletion: MailMergeJob?


    private var filteredJobs: [MailMergeJob] {
        guard !searchText.isEmpty else { return jobs }
        return jobs.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            jobsList
            .navigationTitle("Jobs")
            .searchable(text: $searchText, prompt: "Search Jobs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createJob) {
                        Label("New Job", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Manage Categories") { showingCategoryManager = true }
                }
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
            .sheet(item: $categoryEditorTarget) { target in
                CategoryEditorView(target: target) { name, iconName, colorName in
                    saveCategory(target, name: name, iconName: iconName, colorName: colorName)
                }
            }
            .sheet(isPresented: $showingCategoryManager) {
                CategoryManagerView(
                    categories: categories,
                    editorTarget: $managerEditorTarget,
                    pendingDeletion: $managerPendingDeletion,
                    onSave: saveCategory,
                    onDelete: deleteCategory,
                    onMove: moveCategory
                )
            }
            .categoryDeletionConfirmation($pendingDeleteCategory, onDelete: deleteCategory)
        }
        // Menu commands can fire while a job is open, so these presentations live outside
        // the navigation stack, where they can appear over any pushed screen.
        .sheet(isPresented: $showingNewJobSheet) {
            NewJobCategoryPickerView(
                categories: categories,
                selectedCategoryID: $newJobCategoryID,
                jobName: $newJobName,
                onCreate: confirmCreateJob
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
            Text(JobAllowance.limitReachedMessage)
        }
        .sheet(isPresented: $showingJobRename) {
            JobRenameView(name: jobRenameName, onSave: saveJobRename)
        }
        .alert(
            "Delete Job?",
            isPresented: Binding(
                get: { jobPendingDeletion != nil },
                set: { if !$0 { jobPendingDeletion = nil } }
            ),
            presenting: jobPendingDeletion
        ) { job in
            Button("Delete", role: .destructive) { deleteJob(job) }
            Button("Cancel", role: .cancel) { }
        } message: { job in
            Text("“\(job.name)” will be permanently deleted. Your template, spreadsheet, and generated PDFs won’t be affected.")
        }
        .onAppear(perform: ensureDefaultCategoriesIfNeeded)
        .onAppear(perform: refreshEntitlementFallback)
        .onAppear(perform: startEntitlementObserver)
        .onAppear(perform: applyInitialNavigation)
        .onChange(of: navigationPath) { _, newPath in
            persistNavigationPath(newPath)
        }
        .onChange(of: store.subscriptionTier) { _, _ in
            refreshEntitlementFallback()
        }
        .onDisappear(perform: stopEntitlementObserver)
        .onChange(of: newJobRequested, initial: true) { _, isRequested in
            guard isRequested else { return }
            newJobRequested = false
            createJob()
        }
        .focusedSceneValue(\.jobCommands, focusedJobCommands)
        .onChange(of: jobCommandRouter.pendingCommand) { _, command in
            guard let command else { return }
            jobCommandRouter.pendingCommand = nil
            perform(command)
        }
    }

    /// Targets the open job for the Job menu.
    private var focusedJobCommands: FocusedJobCommands? {
        guard let id = focusedJobID, jobs.contains(where: { $0.id == id }) else { return nil }
        return FocusedJobCommands(jobID: id, router: jobCommandRouter)
    }

    private var focusedJobID: UUID? {
        JobNavigation.focusedJobID(path: navigationPath)
    }

    private var emptyCategory: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.body)
                .foregroundStyle(.tertiary)
            Text("No jobs")
                .foregroundStyle(.tertiary)
                .font(.callout)
            Spacer()
        }
        .padding()
        .background(Color.mergeformSurface.opacity(0.42), in: .rect(cornerRadius: 10))
    }

    // MARK: - Actions

    /// Opens the job handed over from the Templates tab, or restores this window's path.
    private func applyInitialNavigation() {
        // An unreadable saved path just means starting at the list.
        let savedPath = (try? JSONDecoder().decode([UUID].self, from: navigationPathData)) ?? []
        navigationPath = JobNavigation.initialPath(
            pendingJobID: pendingJobID,
            savedPath: savedPath,
            existingJobIDs: Set(jobs.map(\.id))
        )
        pendingJobID = nil
    }

    @ViewBuilder
    private func categorySection(for category: Category) -> some View {
        let categoryJobs = filteredJobs.filter { ($0.category ?? uncategorizedCategory)?.id == category.id }
        VStack(alignment: .leading, spacing: 10) {
            CategoryHeaderView(
                category: category,
                onEdit: { categoryEditorTarget = .edit(category) },
                onDelete: { pendingDeleteCategory = category }
            )
            if categoryJobs.isEmpty {
                emptyCategory
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(categoryJobs) { job in
                        jobRow(for: job)
                            .contextMenu {
                                Button("Rename") { beginRename(job) }
                                Button("Delete", role: .destructive) { requestDelete(job) }
                            }
                    }
                }
            }
        }
    }

    private func persistNavigationPath(_ path: [UUID]) {
        navigationPathData = (try? JSONEncoder().encode(path)) ?? Data()
    }

    private var jobsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                jobsOverview
                ForEach(categories) { category in
                    categorySection(for: category)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color.mergeformBackground)
    }

    private var jobsOverview: some View {
        HStack(alignment: .top, spacing: 14) {
            OverviewMetricCard(
                title: "Jobs",
                value: jobs.count.formatted(.number),
                systemImageName: "rectangle.stack.fill",
                tint: .mergeformBlue
            )
            OverviewMetricCard(
                title: "Ready",
                value: jobs.filter(\.isConfigured).count.formatted(.number),
                systemImageName: "checkmark.seal.fill",
                tint: .green
            )
            OverviewMetricCard(
                title: "Completed",
                value: jobs.filter { $0.status == .completed }.count.formatted(.number),
                systemImageName: "doc.badge.gearshape.fill",
                tint: .mergeformOrange
            )
        }
    }

    private func createJob() {
        Task { @MainActor in
            guard await canCreateJobNow() else {
                showLimitAlertAndPaywall()
                return
            }
            newJobCategoryID = (uncategorizedCategory ?? categories.first)?.id
            newJobName = ""
            showingNewJobSheet = true
        }
    }

    private func confirmCreateJob() {
        Task { @MainActor in
            guard await canCreateJobNow() else {
                showLimitAlertAndPaywall()
                return
            }
            let category = categories.first(where: { $0.id == newJobCategoryID }) ?? uncategorizedCategory
            let jobName = newJobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Mergeform" : newJobName.trimmingCharacters(in: .whitespacesAndNewlines)
            let job = MailMergeJob.makeNew(name: jobName, category: category)
            modelContext.insert(job)
            navigationPath = [job.id]
            showingNewJobSheet = false
            recordJobCreation()
        }
    }

    private func deleteJobs(offsets: IndexSet, in source: [MailMergeJob]) {
        for index in offsets {
            let job = source[index]
            modelContext.delete(job)
            navigationPath.removeAll(where: { $0 == job.id })
        }
    }

    private func perform(_ command: JobCommand) {
        guard let job = jobs.first(where: { $0.id == command.jobID }) else { return }
        switch command.kind {
        case .rename:
            beginRename(job)
        case .delete:
            requestDelete(job)
        }
    }

    /// Deletes right away, or asks first when "Confirm before deleting jobs" is on.
    private func requestDelete(_ job: MailMergeJob) {
        if confirmBeforeDelete {
            jobPendingDeletion = job
        } else {
            deleteJob(job)
        }
    }

    private func deleteJob(_ job: MailMergeJob) {
        // Stop the job's merge so it doesn't keep writing files for a deleted job.
        mergeRuns.cancel(jobID: job.id)
        modelContext.delete(job)
        navigationPath.removeAll(where: { $0 == job.id })
    }

    private func ensureDefaultCategoriesIfNeeded() {
        guard !hasEnsuredDefaults else { return }
        hasEnsuredDefaults = true
        Category.ensureDefaults(categories: categories, jobs: jobs, in: modelContext)
    }

    private var uncategorizedCategory: Category? {
        categories.first(where: { $0.isLocked }) ?? categories.first(where: { $0.name == "Uncategorized" })
    }

    private var hasProAccess: Bool {
        store.hasProAccess || entitlementHasPro
    }

    private var canCreateJob: Bool {
        hasProAccess || jobCreationCount < JobAllowance.freeJobLimit
    }

    private func recordJobCreation() {
        if !hasProAccess {
            jobCreationCount += 1
        }
    }

    private func showLimitAlertAndPaywall() {
        showingPaywallAfterAlert = true
        showingLimitAlert = true
    }

    private func refreshEntitlementFallback() {
        Task {
            entitlementHasPro = await hasCurrentProEntitlement()
        }
    }

    private func startEntitlementObserver() {
        guard entitlementObserverTask == nil else { return }
        entitlementObserverTask = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if MailMergeTier(productID: transaction.productID) == .pro {
                    await transaction.finish()
                }
                refreshEntitlementFallback()
            }
        }
    }

    private func stopEntitlementObserver() {
        entitlementObserverTask?.cancel()
        entitlementObserverTask = nil
    }

    private func hasCurrentProEntitlement() async -> Bool {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if MailMergeTier(productID: transaction.productID) == .pro {
                hasPro = true
                await transaction.finish()
            }
        }
        return hasPro
    }

    private func canCreateJobNow() async -> Bool {
        if canCreateJob { return true }
        entitlementHasPro = await hasCurrentProEntitlement()
        return canCreateJob
    }

    /// Returns a badge count for a job: shows last run record count for completed jobs,
    /// or the number of mapped fields for configured-but-unrun jobs.
    private func jobBadge(_ job: MailMergeJob) -> Int {
        if job.status == .completed, let count = job.lastRunRecordCount { return count }
        if job.status == .configured { return job.fieldMappings.count }
        return 0
    }

    private func saveCategory(_ target: CategoryEditorTarget, name: String, iconName: String, colorName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch target {
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
    }

    private func deleteCategory(_ category: Category) {
        Category.delete(category, jobs: jobs, fallback: uncategorizedCategory, in: modelContext)
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

    private func jobRow(for job: MailMergeJob) -> some View {
        NavigationLink(value: job.id) {
            JobRowView(job: job)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview Metric Card

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let systemImageName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImageName)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.largeTitle)
                .bold()
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mergeformPanel, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.mergeformStroke)
        )
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
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(categoryColor)
                .frame(width: 4, height: 18)
            Image(systemName: category.systemImageName)
                .font(.callout)
                .foregroundStyle(categoryColor)
            Text(category.name)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .contextMenu {
            Button("Rename") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
                .disabled(category.isLocked)
        }
    }
}

// MARK: - Job Row

private struct JobRowView: View {
    let job: MailMergeJob
    @AppStorage("showRelativeDates") private var showRelativeDates = true

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
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.12), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(job.modifiedDescription(relative: showRelativeDates))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                StatusBadge(status: job.status)
                if job.configurationProgress > 0 && job.configurationProgress < 1 {
                    ProgressView(value: job.configurationProgress)
                        .tint(Color.mergeformBlue)
                        .frame(width: 68)
                }
            }
        }
        .padding()
        .background(Color.mergeformPanel, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.mergeformStroke)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(job.status.label), \(job.modifiedDescription(relative: showRelativeDates))")
        .accessibilityHint("Double-tap to view and edit this job")
    }
}

// MARK: - New Job Category Picker

private struct NewJobCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    @Binding var jobName: String
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Job")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                Text("Name your job and choose a category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
                TextField("Job name (optional)", text: $jobName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)
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
                                    .font(.callout)
                                    .bold(isSelected)
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
        .background(Color.mergeformBackground)
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
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
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
        .background(Color.mergeformBackground)
    }
}
