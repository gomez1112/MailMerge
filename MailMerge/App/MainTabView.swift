import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FlexStore
import AppKit
import StoreKit

struct MainTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var jobs: [MailMergeJob]
    @State private var selection: SidebarDestination = .jobs
    @State private var pendingJobID: UUID?
    @State private var windowCommands = WindowCommandRouter()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            detailContent
                .id(selection)
                .transition(.opacity)
        }
        .navigationSplitViewStyle(.balanced)
        .symbolEffectsRemoved(reduceMotion)
        .focusedSceneValue(\.windowCommands, FocusedWindowCommands(router: windowCommands))
        .onChange(of: windowCommands.isNewJobRequested) { _, isRequested in
            // New jobs are created from the Jobs list, so show it.
            if isRequested { selection = .jobs }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: sidebarSelection) {
            Section("Library") {
                Label("Jobs", systemImage: "tray.full")
                    .badge(jobs.count)
                    .tag(SidebarDestination.jobs)
                Label("Templates", systemImage: "doc.richtext")
                    .tag(SidebarDestination.templates)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            SidebarBrandHeader()
        }
    }

    private var sidebarSelection: Binding<SidebarDestination?> {
        Binding {
            selection
        } set: { newValue in
            guard let newValue else { return }
            withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) {
                selection = newValue
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .jobs:
            ContentView(pendingJobID: $pendingJobID, newJobRequested: $windowCommands.isNewJobRequested)
        case .templates:
            TemplateLibraryView { jobID in
                pendingJobID = jobID
                withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) {
                    selection = .jobs
                }
            }
        }
    }
}

// MARK: - Sidebar Brand Header

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: Metrics.compact) {
            IconTile(systemImage: "point.3.connected.trianglepath.dotted", size: 34, isProminent: true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mergeform")
                    .font(.headline)
                Text("Document automation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.regular)
        .padding(.top, Metrics.tight)
        .padding(.bottom, Metrics.compact)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - App Tab Enum

private enum SidebarDestination: Hashable {
    case jobs
    case templates
}

// MARK: - Template Library View

private struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]

    let onOpenJobs: (UUID) -> Void

    @State private var showingImporter = false
    @State private var importErrorMessage: String?
    @State private var showingPaywall = false
    @State private var showingLimitAlert = false
    @State private var showingPaywallAfterAlert = false
    @State private var entitlementHasPro = false
    @State private var entitlementObserverTask: Task<Void, Never>?

    @AppStorage("jobCreationCount") private var jobCreationCount = 0


    init(onOpenJobs: @escaping (UUID) -> Void) {
        self.onOpenJobs = onOpenJobs
    }

    private var templateItems: [TemplateLibraryItem] {
        let sources: [TemplateLibraryItem.Source] = jobs.compactMap { job in
            guard let bookmarkData = job.templateBookmarkData,
                  let fileName = job.templateFileName else { return nil }
            return TemplateLibraryItem.Source(bookmarkData: bookmarkData, fileName: fileName, lastUsed: job.modifiedAt)
        }
        return TemplateLibraryItem.items(from: sources, fileIdentity: SecurityScopedAccess.filePath(for:))
    }

    var body: some View {
        NavigationStack {
            Group {
                if templateItems.isEmpty {
                    templateEmptyState
                } else {
                    templateGrid
                }
            }
            .navigationTitle("Templates")
            .navigationSubtitle(templateItems.count == 1 ? "1 template" : "\(templateItems.count) templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import Template", systemImage: "square.and.arrow.down") {
                        showingImporter = true
                    }
                    .help("Import a DOCX template")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mergeformBackground)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            if let importErrorMessage {
                Text(importErrorMessage)
            }
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
        .onAppear(perform: refreshEntitlementFallback)
        .onAppear(perform: startEntitlementObserver)
        .onChange(of: store.subscriptionTier) { _, _ in
            refreshEntitlementFallback()
        }
        .onDisappear(perform: stopEntitlementObserver)
    }

    private var templateGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: Metrics.section)],
                spacing: Metrics.section
            ) {
                ForEach(templateItems.enumerated(), id: \.element.id) { index, item in
                    TemplateCard(
                        item: item,
                        onUse: {
                            Task { @MainActor in
                                if let jobID = await createJob(from: item) {
                                    onOpenJobs(jobID)
                                }
                            }
                        },
                        onReveal: {
                            revealTemplate(item)
                        }
                    )
                    .revealOnAppear(order: index)
                }
            }
            .padding(Metrics.page)
        }
        .scrollIndicators(.hidden)
    }

    private var templateEmptyState: some View {
        ContentUnavailableView {
            Label("No Templates Yet", systemImage: "doc.richtext")
        } description: {
            Text("Import a DOCX template, or use one in a job, to see it here.")
        } actions: {
            Button("Import Template") { showingImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        Task { @MainActor in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                if let jobID = try await storeTemplateURL(url) {
                    onOpenJobs(jobID)
                }
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func storeTemplateURL(_ url: URL) async throws -> UUID? {
        guard await canCreateJobNow() else {
            showLimitAlertAndPaywall()
            return nil
        }
        let bookmarkData = try SecurityScopedAccess.makeBookmark(for: url)
        let category = uncategorizedCategory
        let job = MailMergeJob.makeNew(name: "New Mergeform", category: category)
        job.templateBookmarkData = bookmarkData
        job.templateFileName = url.lastPathComponent
        job.modifiedAt = Date()
        modelContext.insert(job)
        recordJobCreation()
        return job.id
    }

    private func createJob(from item: TemplateLibraryItem) async -> UUID? {
        guard await canCreateJobNow() else {
            showLimitAlertAndPaywall()
            return nil
        }
        let category = uncategorizedCategory
        let job = MailMergeJob.makeNew(name: "New Mergeform", category: category)
        job.templateBookmarkData = item.bookmarkData
        job.templateFileName = item.fileName
        job.modifiedAt = Date()
        modelContext.insert(job)
        recordJobCreation()
        return job.id
    }

    private func revealTemplate(_ item: TemplateLibraryItem) {
        guard let url = try? SecurityScopedAccess.startAccessing(bookmarkData: item.bookmarkData) else { return }
        defer { SecurityScopedAccess.stopAccessing(url) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
}

// MARK: - Template Card

private struct TemplateCard: View {
    let item: TemplateLibraryItem
    let onUse: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.mergeformBlue.opacity(0.14), Color.mergeformBlue.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                DocumentThumbnail()
            }
            .frame(height: 136)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(usageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Use Template", systemImage: "plus", action: onUse)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                Button("Show in Finder", systemImage: "folder", action: onReveal)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            }
        }
        .cardSurface(padding: Metrics.regular)
        .hoverLift()
    }

    private var usageDescription: String {
        let lastUsed = item.lastUsed.formatted(date: .abbreviated, time: .omitted)
        let jobs = item.usageCount == 1 ? "1 job" : "\(item.usageCount) jobs"
        return "\(jobs) · Last used \(lastUsed)"
    }
}

/// A miniature page, standing in for a template's first page.
private struct DocumentThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white)
            .frame(width: 66, height: 86)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(Color.mergeformBlue.opacity(0.8))
                        .frame(width: 30, height: 4)
                        .padding(.bottom, 3)
                    ForEach(0..<6, id: \.self) { line in
                        Capsule()
                            .fill(.black.opacity(0.12))
                            .frame(width: line == 5 ? 24 : 46, height: 3)
                    }
                }
                .padding(10)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Data Models

