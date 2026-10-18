import SwiftUI
import SwiftData
import KickstartExchange
import StoreKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseStore.self) private var purchases
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
    @State private var jobCommandRouter = JobCommandRouter()

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
        .onAppear(perform: applyInitialNavigation)
        .onChange(of: navigationPath) { _, newPath in
            persistNavigationPath(newPath)
        }
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

    private func persistNavigationPath(_ path: [UUID]) {
        navigationPathData = (try? JSONEncoder().encode(path)) ?? Data()
    }

    private var jobsList: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView {
                    Label("No Jobs Yet", systemImage: "tray")
                } description: {
                    Text("A job merges a Word template with a spreadsheet to make a PDF for every row.")
                } actions: {
                    Button("New Job", systemImage: "plus", action: createJob)
                        .buttonStyle(.borderedProminent)
                }
            } else if visibleCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.section) {
                        jobsOverview
                        ForEach(visibleCategories.enumerated(), id: \.element.id) { index, category in
                            categorySection(for: category)
                                .revealOnAppear(order: index + 3)
                        }
                        // Free users see one cross-promotion banner below their jobs; Pro
                        // customers, including lifetime buyers, never see adverts.
                        if purchases.showsFreePlanContent {
                            ExchangeBannerAdView(apiKey: "ks_live_oiOXxPHxxpQT2eV42Z-LAVU4oTCahb_AUiLTpQ7vcuU")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(Metrics.page)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .motion(Motion.standard, value: filteredJobs.map(\.id))
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mergeformBackground)
    }

    /// Categories with jobs to show, after searching. Empty categories are hidden; they're
    /// still available in Manage Categories and when creating a job.
    private var visibleCategories: [Category] {
        categories.filter { !jobs(in: $0).isEmpty }
    }

    private func jobs(in category: Category) -> [MailMergeJob] {
        filteredJobs.filter { ($0.category ?? uncategorizedCategory)?.id == category.id }
    }

    private var jobsOverview: some View {
        HStack(alignment: .top, spacing: Metrics.regular) {
            StatCard(
                systemImageName: "tray.full.fill",
                value: jobs.count.formatted(.number),
                label: "Jobs",
                iconColor: .mergeformBlue
            )
            .revealOnAppear(order: 0)
            StatCard(
                systemImageName: JobStatus.configured.systemImageName,
                value: jobs.filter(\.isConfigured).count.formatted(.number),
                label: "Ready to Run",
                iconColor: JobStatus.configured.tint
            )
            .revealOnAppear(order: 1)
            StatCard(
                systemImageName: JobStatus.completed.systemImageName,
                value: jobs.filter { $0.status == .completed }.count.formatted(.number),
                label: "Completed",
                iconColor: JobStatus.completed.tint
            )
            .revealOnAppear(order: 2)
        }
    }

    @ViewBuilder
    private func categorySection(for category: Category) -> some View {
        let categoryJobs = jobs(in: category)
        VStack(alignment: .leading, spacing: Metrics.compact) {
            CategoryHeaderView(
                category: category,
                jobCount: categoryJobs.count,
                onEdit: { categoryEditorTarget = .edit(category) },
                onDelete: { pendingDeleteCategory = category }
            )
            VStack(spacing: 0) {
                ForEach(categoryJobs.enumerated(), id: \.element.id) { index, job in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 68)
                    }
                    jobRow(for: job)
                        .contextMenu {
                            Button("Rename…") { beginRename(job) }
                            Button("Delete", role: .destructive) { requestDelete(job) }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
            .clipShape(.rect(cornerRadius: Metrics.cardRadius))
            .cardSurface(padding: 0)
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

    /// Whether another job can be created; Pro has no limit. Waits for purchases to be
    /// checked, so a Pro user isn't held to the free limit just after launch.
    private func canCreateJobNow() async -> Bool {
        await purchases.canCreateJob()
    }

    private func recordJobCreation() {
        purchases.recordJobCreation()
    }

    private func showLimitAlertAndPaywall() {
        showingPaywallAfterAlert = true
        showingLimitAlert = true
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

// MARK: - Category Header

private struct CategoryHeaderView: View {
    let category: Category
    let jobCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var categoryColor: Color {
        CategoryColorOption.color(for: category.colorName)
    }

    var body: some View {
        HStack(spacing: Metrics.compact) {
            IconTile(systemImage: category.systemImageName, tint: categoryColor, size: 26)
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(jobCount.formatted(.number))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: .capsule)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.leading, 2)
        .motion(Motion.standard, value: jobCount)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .contextMenu {
            Button("Rename…") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
                .disabled(category.isLocked)
        }
    }
}

// MARK: - Job Row

private struct JobRowView: View {
    let job: MailMergeJob
    @AppStorage("showRelativeDates") private var showRelativeDates = true
    @State private var isHovering = false

    private var tint: Color {
        job.status == .draft ? .mergeformBlue : job.status.tint
    }

    private var subtitle: String {
        let template = job.templateFileName ?? "No template yet"
        return "\(template) · \(job.modifiedDescription(relative: showRelativeDates))"
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: job.status.systemImageName, tint: tint, size: 40)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.rotate, isActive: job.status == .running)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Metrics.regular)

            if job.status == .draft {
                HStack(spacing: 8) {
                    Text("Setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressRing(progress: job.configurationProgress, size: 26, lineWidth: 3.5, showsPercentage: false)
                }
            } else {
                StatusBadge(status: job.status)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .offset(x: isHovering ? 3 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
        .motion(Motion.standard, value: job.status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(job.status.label), \(job.modifiedDescription(relative: showRelativeDates))")
        .accessibilityHint("Opens the job")
    }
}

// MARK: - New Job Category Picker

private struct NewJobCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    @Binding var jobName: String
    let onCreate: () -> Void
    @Namespace private var selectionHighlight

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
                                IconTile(
                                    systemImage: category.systemImageName,
                                    tint: CategoryColorOption.color(for: category.colorName),
                                    size: 30
                                )
                                Text(category.name)
                                    .font(.callout.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.mergeformBlue)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(.rect(cornerRadius: Metrics.tileRadius))
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                                        .fill(Color.mergeformBlue.opacity(0.10))
                                        .matchedGeometryEffect(id: "selectedCategory", in: selectionHighlight)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .motion(Motion.quick, value: selectedCategoryID)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
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
