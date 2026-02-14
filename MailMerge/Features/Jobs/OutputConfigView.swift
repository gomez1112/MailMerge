import SwiftUI
import UniformTypeIdentifiers

struct OutputConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var showingFolderPicker = false

    private var availableTokens: [String] {
        ["{Row}"] + job.availableColumns.map { "{\($0)}" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Output",
                subtitle: "Choose where the generated PDFs will be saved.",
                systemImageName: "folder"
            )

            // Output folder card
            ConfigCard {
                VStack(alignment: .leading, spacing: 16) {
                    CardLabel(title: "Output Folder", systemImage: "folder")
                    if let folderName = job.outputFolderName {
                        SelectedFileRow(
                            fileName: folderName,
                            subtitle: "Output folder",
                            systemImageName: "folder",
                            color: .orange
                        ) {
                            showingFolderPicker = true
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
            }

            // File naming card
            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    CardLabel(title: "File Naming", systemImage: "textformat")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pattern")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Pattern", text: $job.outputFileNamePattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available tokens")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(Array(availableTokens.enumerated()), id: \.offset) { _, token in
                                PlaceholderTag(text: token)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.preview")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Preview: ")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(previewFileName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 2)
                }
            }

            // Options card
            ConfigCard {
                VStack(alignment: .leading, spacing: 12) {
                    CardLabel(title: "Options", systemImage: "slider.horizontal.3")

                    Toggle(isOn: $job.combineIntoSinglePDF) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Combine into single PDF")
                                .font(.system(size: 13))
                            Text("Merges all records into one PDF document instead of individual files.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
            #if os(macOS)
            guard url.startAccessingSecurityScopedResource() else {
                job.outputFolderBookmarkData = nil
                job.outputFolderName = nil
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            job.outputFolderBookmarkData = bookmarkData
            job.outputFolderName = url.lastPathComponent
            job.modifiedAt = Date()
        } catch {
            job.outputFolderBookmarkData = nil
            job.outputFolderName = nil
        }
    }
}
