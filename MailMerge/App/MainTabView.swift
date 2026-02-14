import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct MainTabView: View {
    @State private var selection: AppTab = .jobs
    @State private var pendingJobID: UUID?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Jobs", systemImage: "tray.full", value: AppTab.jobs) {
                ContentView(pendingJobID: $pendingJobID)
            }

            Tab("Templates", systemImage: "doc.richtext", value: AppTab.templates) {
                TemplateLibraryView { jobID in
                    pendingJobID = jobID
                    selection = .jobs
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            SidebarAppHeader()
        }
        .tabViewSidebarFooter {
            SidebarAppFooter()
        }
    }
}

// MARK: - Sidebar App Header

private struct SidebarAppHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mail Merge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Document automation")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Sidebar App Footer

private struct SidebarAppFooter: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
            Text("Mail Merge \(appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - App Tab Enum

private enum AppTab: Hashable {
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
                VStack(alignment: .leading, spacing: 2) {
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
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            if templateItems.isEmpty {
                templateEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)
                    ], spacing: 16) {
                        ForEach(templateItems) { item in
                            TemplateCard(item: item) {
                                if let jobID = createJob(from: item) {
                                    onOpenJobs(jobID)
                                }
                            } onReveal: {
                                revealTemplate(item)
                            }
                        }
                    }
                    .padding(24)
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
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var uncategorizedCategory: Category? {
        categories.first(where: { $0.isLocked }) ?? categories.first(where: { $0.name == "Uncategorized" })
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let item: TemplateItem
    let onUse: () -> Void
    let onReveal: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                    Text("DOCX")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .tracking(1.5)
                }
            }
            .frame(height: 110)
            .padding(.bottom, 12)

            // File name and meta
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
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
            .padding(.bottom, 12)

            // Action buttons
            HStack(spacing: 8) {
                Button("Use Template") { onUse() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Reveal") { onReveal() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isHovering ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

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
