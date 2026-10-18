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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(
                title: "Template",
                subtitle: "Choose a DOCX file with merge placeholders.",
                systemImageName: "doc.richtext"
            )

            // File selection card
            ConfigCard {
                VStack(alignment: .leading, spacing: 16) {
                    CardLabel(title: "Document Template", systemImage: "doc.richtext")
                    if let fileName = job.templateFileName {
                        SelectedFileRow(
                            fileName: fileName,
                            subtitle: "DOCX template",
                            systemImageName: "doc.richtext",
                            color: .accentColor
                        ) {
                            showingImporter = true
                        }
                    } else {
                        DropTargetView(
                            title: "Drop your DOCX template",
                            subtitle: "or click to browse",
                            systemImageName: "doc.richtext"
                        ) {
                            showingImporter = true
                        }
                    }
                }
            }

            // Placeholder scanner card
            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Merge Fields", systemImage: "wand.and.stars")
                        Spacer()
                        Button {
                            scanTemplate()
                        } label: {
                            if isScanning {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Scanning…")
                                }
                            } else {
                                Label("Scan Template", systemImage: "wand.and.stars")
                            }
                        }
                        .font(.callout)
                        .disabled(job.templateBookmarkData == nil || isScanning)
                    }

                    if detectedPlaceholders.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                            Text("Scan the template to discover merge fields.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(detectedPlaceholders.count) field\(detectedPlaceholders.count == 1 ? "" : "s") found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(detectedPlaceholders.enumerated(), id: \.offset) { _, placeholder in
                                    PlaceholderTag(text: placeholder)
                                }
                            }
                        }
                    }
                }
            }

            // Supported formats card
            ConfigCard {
                VStack(alignment: .leading, spacing: 10) {
                    CardLabel(title: "Supported Formats", systemImage: "info.circle")
                    Text("Use any of these placeholder styles in your DOCX template:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(["{{Field}}", "<<Field>>", "${Field}", "[[Field]]"], id: \.self) { format in
                            Text(format)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.mergeformBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.mergeformBlue.opacity(0.08))
                                )
                        }
                    }
                }
            }

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
            do {
                let placeholders = try await services.mergeEngine.analyzeTemplate(bookmarkData: bookmarkData)
                await MainActor.run {
                    detectedPlaceholders = placeholders
                    syncMappings(with: placeholders)
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    onError(error, { scanTemplate() })
                    isScanning = false
                }
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

// MARK: - Reusable Selected File Row

struct SelectedFileRow: View {
    let fileName: String
    let subtitle: String
    let systemImageName: String
    let color: Color
    let onChangeTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FileIconView(systemImageName: systemImageName, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(fileName)
                    .font(.callout)
                    .bold()
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") {
                onChangeTap()
            }
            .font(.callout)
            .foregroundStyle(Color.mergeformBlue)
            .buttonStyle(.plain)
        }
    }
}
