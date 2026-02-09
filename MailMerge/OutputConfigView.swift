import SwiftUI
import UniformTypeIdentifiers

struct OutputConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var showingFolderPicker = false
    @State private var combineIntoSinglePDF = false

    private var availableTokens: [String] {
        ["{Row}"] + job.availableColumns.map { "{\($0)}" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Output",
                subtitle: "Choose where the PDFs should be saved.",
                systemImageName: "folder"
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    if let folderName = job.outputFolderName {
                        HStack(spacing: 12) {
                            FileIconView(systemImageName: "folder", color: .accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folderName)
                                    .font(.headline)
                                Text("Output folder selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showingFolderPicker = true
                            }
                        }
                    } else {
                        DropTargetView(
                            title: "Drop an output folder",
                            subtitle: "or click to browse",
                            systemImageName: "folder"
                        ) {
                            showingFolderPicker = true
                        }
                    }
                }
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("File naming pattern")
                        .font(.headline)
                    TextField("Pattern", text: $job.outputFileNamePattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Available tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(Array(availableTokens.enumerated()), id: \.offset) { _, token in
                            PlaceholderTag(text: token)
                        }
                    }
                    Text("Preview: \(previewFileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            GroupBox {
                Toggle("Combine into single PDF", isOn: $combineIntoSinglePDF)
                    .padding(16)
            }
            Spacer()
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
    }

    private var previewFileName: String {
        let base = job.outputFileNamePattern
            .replacingOccurrences(of: "{Row}", with: "1")
        let sanitized = FileNameSanitizer.sanitize(base)
        return "\(sanitized).pdf"
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                job.outputFolderBookmarkData = nil
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            job.outputFolderBookmarkData = bookmarkData
            job.outputFolderName = url.lastPathComponent
            job.modifiedAt = Date()
        } catch {
            job.outputFolderBookmarkData = nil
        }
    }
}
