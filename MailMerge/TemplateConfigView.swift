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
                subtitle: "Choose a DOCX template with merge placeholders.",
                systemImageName: "doc.richtext"
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    if let fileName = job.templateFileName {
                        HStack(spacing: 12) {
                            FileIconView(systemImageName: "doc.richtext", color: .accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileName)
                                    .font(.headline)
                                Text("Template selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showingImporter = true
                            }
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
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Detected placeholders")
                            .font(.headline)
                        Spacer()
                        Button {
                            scanTemplate()
                        } label: {
                            Label("Scan Template", systemImage: "wand.and.stars")
                        }
                        .disabled(job.templateBookmarkData == nil || isScanning)
                    }

                    if detectedPlaceholders.isEmpty {
                        Text("Scan the template to discover merge fields.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(detectedPlaceholders, id: \.self) { placeholder in
                                PlaceholderTag(text: placeholder)
                            }
                        }
                    }
                }
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Supported placeholder formats")
                        .font(.headline)
                    Text("Use any of the following styles in your DOCX template:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("{{FirstName}}, <<FirstName>>, ${FirstName}, [[FirstName]]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
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
                try? storeTemplateURL(url)
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
                detectedPlaceholders = placeholders
                syncMappings(with: placeholders)
            } catch {
                onError(error)
            }
            isScanning = false
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
