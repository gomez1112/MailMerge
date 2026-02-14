import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct MainTabView: View {
    @State private var selection: SidebarDestination = .jobs
    @State private var pendingJobID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 300)
        } detail: {
            detailContent
                .animation(.smooth(duration: 0.25), value: selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Brand header
            SidebarBrandHeader()
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Navigation rows
            VStack(spacing: 3) {
                sidebarRow(
                    destination: .jobs,
                    title: "Jobs",
                    systemImage: "tray.full.fill"
                )
                sidebarRow(
                    destination: .templates,
                    title: "Templates",
                    systemImage: "doc.richtext.fill"
                )
            }
            .padding(.horizontal, 10)

            Spacer()

            // Version footer
            SidebarVersionFooter()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .listStyle(.sidebar)
        .background(
            LinearGradient(
                colors: [Color.mergeformBackground, Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .jobs:
            ContentView(pendingJobID: $pendingJobID)
        case .templates:
            TemplateLibraryView { jobID in
                pendingJobID = jobID
                selection = .jobs
            }
        }
    }

    private func sidebarRow(
        destination: SidebarDestination,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = selection == destination
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                selection = destination
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected
                              ? Color.mergeformBlue
                              : Color.primary.opacity(0.07))
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                .frame(width: 28, height: 28)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.mergeformBlue.opacity(0.10)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.18), value: isSelected)
    }
}

// MARK: - Sidebar Brand Header

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            // Two-tone icon matching the app icon
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.65, blue: 0.95),
                                Color(red: 0.40, green: 0.50, blue: 0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // Orange shape (back)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.mergeformOrange.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .offset(x: -3, y: 3)
                    .rotationEffect(.degrees(-8))
                // Blue shape (front)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.mergeformBlue.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .offset(x: 3, y: -3)
                    .rotationEffect(.degrees(8))
            }
            .frame(width: 36, height: 36)
            .shadow(color: Color.mergeformBlue.opacity(0.25), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mergeform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Document automation")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Sidebar Version Footer

private struct SidebarVersionFooter: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Text("Mergeform \(appVersion)")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity, alignment: .center)
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
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]

    let onOpenJobs: (UUID) -> Void

    @State private var showingImporter = false
    @State private var importErrorMessage: String?
#if os(iOS)
    @State private var shareItem: ShareItem?
#endif

    init(onOpenJobs: @escaping (UUID) -> Void) {
        self.onOpenJobs = onOpenJobs
    }

    private var templateItems: [TemplateItem] {
        let sources: [TemplateSource] = jobs.compactMap { job in
            guard let bookmarkData = job.templateBookmarkData,
                  let fileName = job.templateFileName else { return nil }
            return TemplateSource(bookmarkData: bookmarkData, fileName: fileName, lastUsed: job.modifiedAt)
        }
        let grouped = Dictionary(grouping: sources, by: { $0.bookmarkData })
        return grouped.compactMap { key, values in
            guard let latest = values.max(by: { $0.lastUsed < $1.lastUsed }) else { return nil }
            return TemplateItem(
                id: key,
                fileName: latest.fileName,
                lastUsed: latest.lastUsed,
                usageCount: values.count,
                bookmarkData: key
            )
        }
        .sorted(by: { $0.lastUsed > $1.lastUsed })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Templates")
                        .font(.title2.bold())
                    Text("\(templateItems.count) template\(templateItems.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label("Import Template", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.mergeformBlue)
                .controlSize(.regular)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)

            Divider()

            if templateItems.isEmpty {
                templateEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18)
                    ], spacing: 18) {
                        ForEach(templateItems) { item in
#if os(macOS)
                            let revealTitle = "Reveal"
#else
                            let revealTitle = "Share"
#endif
                            TemplateCard(
                                item: item,
                                onUse: {
                                    if let jobID = createJob(from: item) {
                                        onOpenJobs(jobID)
                                    }
                                },
                                revealTitle: revealTitle,
                                onReveal: {
                                    revealTemplate(item)
                                }
                            )
                        }
                    }
                    .padding(32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
#if os(iOS)
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
#endif
    }

    private var templateEmptyState: some View {
        ContentUnavailableView {
            Label("No Templates Yet", systemImage: "doc.richtext")
        } description: {
            Text("Import a DOCX template or use one in a job to see it here.")
        } actions: {
            Button("Import Template") { showingImporter = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            if let jobID = try storeTemplateURL(url) {
                onOpenJobs(jobID)
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func storeTemplateURL(_ url: URL) throws -> UUID? {
        #if os(macOS)
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        let category = uncategorizedCategory
        let job = MailMergeJob(name: "New Mail Merge", category: category)
        job.templateBookmarkData = bookmarkData
        job.templateFileName = url.lastPathComponent
        job.modifiedAt = Date()
        modelContext.insert(job)
        return job.id
    }

    private func createJob(from item: TemplateItem) -> UUID? {
        let category = uncategorizedCategory
        let job = MailMergeJob(name: "New Mail Merge", category: category)
        job.templateBookmarkData = item.bookmarkData
        job.templateFileName = item.fileName
        job.modifiedAt = Date()
        modelContext.insert(job)
        return job.id
    }

    private func revealTemplate(_ item: TemplateItem) {
        guard let url = try? SecurityScopedAccess.startAccessing(bookmarkData: item.bookmarkData) else { return }
        defer { SecurityScopedAccess.stopAccessing(url) }
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
#else
        shareItem = ShareItem(url: url)
#endif
    }

    private var uncategorizedCategory: Category? {
        categories.first(where: { $0.isLocked }) ?? categories.first(where: { $0.name == "Uncategorized" })
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let item: TemplateItem
    let onUse: () -> Void
    let revealTitle: String
    let onReveal: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.mergeformBlue.opacity(0.09),
                                Color.mergeformBlue.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.mergeformBlue.opacity(0.55))
                    Text("DOCX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.mergeformBlue.opacity(0.45))
                        .tracking(2)
                }
            }
            .frame(height: 120)
            .padding(.bottom, 14)

            // File name and meta
            VStack(alignment: .leading, spacing: 5) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text("Last used \(item.lastUsed, format: .dateTime.month().day().year())")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    if item.usageCount > 1 {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("\(item.usageCount) jobs")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.bottom, 14)

            // Action buttons
            HStack(spacing: 8) {
                Button("Use Template") { onUse() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.mergeformBlue)
                    .controlSize(.small)
                Button(revealTitle) { onReveal() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.055 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isHovering ? Color.mergeformBlue.opacity(0.35) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.2), value: isHovering)
    }
}

#if os(iOS)
private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
#endif

// MARK: - Data Models

private struct TemplateItem: Identifiable {
    let id: Data
    let fileName: String
    let lastUsed: Date
    let usageCount: Int
    let bookmarkData: Data
}

private struct TemplateSource {
    let bookmarkData: Data
    let fileName: String
    let lastUsed: Date
}


#Preview {
    MainTabView()
        .modelContainer(for: MailMergeJob.self, inMemory: true)
}
