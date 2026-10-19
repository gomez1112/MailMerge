import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TemplateConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.services) private var services
    @AppStorage("autoMatchFields") private var autoMatchFields = true
    @Bindable var job: MailMergeJob
    let onError: (Error, (() -> Void)?) -> Void

    @State private var showingImporter = false
    @State private var detectedPlaceholders: [String] = []
    @State private var isScanning = false

    /// The template's fields: from the latest scan, or the ones the job already has.
    private var fieldNames: [String] {
        if !detectedPlaceholders.isEmpty {
            return detectedPlaceholders
        }
        return job.fieldMappings.map(\.displayName).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            SectionHeader(
                title: "Template",
                subtitle: "Choose a Word document (.docx) with merge placeholders.",
                systemImageName: "richtext.page"
            )

            ConfigCard {
                VStack(alignment: .leading, spacing: Metrics.regular) {
                    CardLabel(title: "Document Template", systemImage: "richtext.page")
                    if let fileName = job.templateFileName {
                        SelectedFileRow(
                            fileName: fileName,
                            subtitle: "Word template",
                            systemImageName: "richtext.page",
                            color: .mergeformBlue
                        ) {
                            showingImporter = true
                        }
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                    } else {
                        DropTargetView(
                            title: "Drop your Word template here",
                            subtitle: "or click to choose a .docx file",
                            systemImageName: "document.badge.plus"
                        ) {
                            showingImporter = true
                        }
                        .transition(.opacity)
                    }
                }
                .motion(Motion.standard, value: job.templateFileName)
            }
            .revealOnAppear(order: 0)

            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Merge Fields", systemImage: "wand.and.sparkles")
                        Spacer()
                        Button {
                            scanTemplate()
                        } label: {
                            Label(isScanning ? "Scanning…" : "Scan Template", systemImage: "wand.and.sparkles")
                                .symbolEffect(.breathe, isActive: isScanning)
                        }
                        .disabled(job.templateBookmarkData == nil || isScanning)
                    }

                    if fieldNames.isEmpty {
                        Label("Scan the template to find its merge fields.", systemImage: "text.magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: Metrics.compact) {
                            Text(fieldNames.count == 1 ? "1 field found" : "\(fieldNames.count) fields found")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                            FlowLayout(spacing: Metrics.tight) {
                                ForEach(fieldNames, id: \.self) { placeholder in
                                    PlaceholderTag(text: placeholder)
                                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                .motion(Motion.lively, value: fieldNames)
            }
            .revealOnAppear(order: 1)

            ConfigCard {
                VStack(alignment: .leading, spacing: Metrics.compact) {
                    CardLabel(title: "Supported Formats", systemImage: "info.circle")
                    Text("Write placeholders in your template in any of these styles:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Metrics.tight) {
                        ForEach(["{{Field}}", "<<Field>>", "${Field}", "[[Field]]"], id: \.self) { format in
                            PlaceholderTag(text: format)
                        }
                    }
                }
            }
            .revealOnAppear(order: 2)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            try storeTemplateURL(url)
        } catch {
            onError(error, nil)
        }
    }

    private func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            try storeTemplateURL(url)
        } catch {
            onError(error, nil)
        }
    }

    private func storeTemplateURL(_ url: URL) throws {
        guard isValidDocxURL(url) else {
            throw MergeError.invalidTemplate
        }
        let bookmarkData = try SecurityScopedAccess.makeBookmark(for: url)
        job.templateBookmarkData = bookmarkData
        job.templateFileName = url.lastPathComponent
        job.modifiedAt = Date()
        detectedPlaceholders = []
        // Fields from the previous template no longer apply, so rescan right away.
        scanTemplate()
    }

    private func scanTemplate() {
        guard let bookmarkData = job.templateBookmarkData else { return }
        isScanning = true
        Task {
            defer { isScanning = false }
            do {
                let placeholders = try await services.mergeEngine.analyzeTemplate(bookmarkData: bookmarkData)
                guard !Task.isCancelled, !job.isDeleted, job.modelContext != nil,
                      job.templateBookmarkData == bookmarkData else { return }
                detectedPlaceholders = placeholders
                syncMappings(with: placeholders)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, !job.isDeleted, job.modelContext != nil else { return }
                onError(error, { scanTemplate() })
            }
        }
    }

    private func isValidDocxURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "docx"
    }

    private func syncMappings(with placeholders: [String]) {
        job.syncFieldMappings(with: placeholders, in: modelContext, autoMatch: autoMatchFields)
    }
}
