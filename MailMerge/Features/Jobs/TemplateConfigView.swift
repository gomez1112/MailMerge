import SwiftUI
import UniformTypeIdentifiers

struct TemplateConfigView: View {
    @Environment(\.services) private var services
    @Bindable var job: MailMergeJob
    let onError: (Error) -> Void

    @State private var showingImporter = false
    @State private var detectedPlaceholders: [String] = []
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                        .font(.system(size: 12))
                        .disabled(job.templateBookmarkData == nil || isScanning)
                    }

                    if detectedPlaceholders.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                            Text("Scan the template to discover merge fields.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(detectedPlaceholders.count) field\(detectedPlaceholders.count == 1 ? "" : "s") found")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(Array(detectedPlaceholders.enumerated()), id: \.offset) { _, placeholder in
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
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(["{{Field}}", "<<Field>>", "${Field}", "[[Field]]"], id: \.self) { format in
                            Text(format)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.08))
                                )
                        }
                    }
                }
            }

            Spacer()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            try storeTemplateURL(url)
        } catch {
            onError(error)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                DispatchQueue.main.async { onError(error) }
                return
            }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                do {
                    try storeTemplateURL(url)
                } catch {
                    onError(error)
                }
            }
        }
        return true
    }

    private func storeTemplateURL(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        job.templateBookmarkData = bookmarkData
        job.templateFileName = url.lastPathComponent
        job.modifiedAt = Date()
        detectedPlaceholders = []
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
                    onError(error)
                    isScanning = false
                }
            }
        }
    }

    private func syncMappings(with placeholders: [String]) {
        let existing = Set(job.fieldMappings.map { $0.placeholderText })
        let toAdd = placeholders.filter { !existing.contains($0) }
        if !toAdd.isEmpty {
            for placeholder in toAdd {
                let mapping = FieldMapping(placeholderText: placeholder, job: job)
                job.fieldMappings.append(mapping)
            }
        }
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
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") {
                onChangeTap()
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
    }
}
