import SwiftUI
import UniformTypeIdentifiers

struct OutputConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var showingFolderPicker = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    private var availableTokens: [String] {
        ["{Row}"] + job.availableColumns.map { "{\($0)}" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Pattern", text: $job.outputFileNamePattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(availableTokens.enumerated(), id: \.offset) { _, token in
                                PlaceholderTag(text: token)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Preview: ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(previewFileName)
                            .font(.caption.monospaced())
                            .bold()
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 2)

                    if job.combineIntoSinglePDF {
                        Text("The pattern names individual files. A combined PDF is named after the job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Options card
            ConfigCard {
                VStack(alignment: .leading, spacing: 12) {
                    CardLabel(title: "Options", systemImage: "slider.horizontal.3")

                    Toggle(isOn: $job.combineIntoSinglePDF) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Combine into single PDF")
                                .font(.callout)
                            Text("Merges all records into one PDF document instead of individual files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return }
            storeOutputFolder(url)
        }
        .alert("Output Folder Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var previewFileName: String {
        MergeEngine.previewFileName(
            pattern: job.outputFileNamePattern,
            combinesIntoSinglePDF: job.combineIntoSinglePDF,
            jobName: job.name
        )
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            storeOutputFolder(url)
        } catch {
            presentOutputError(error.localizedDescription)
        }
    }

    /// Saves a picked or dropped folder. A failure keeps the previously chosen folder.
    private func storeOutputFolder(_ url: URL) {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            presentOutputError("Choose a folder for the merged PDFs.")
            return
        }
        do {
            job.outputFolderBookmarkData = try SecurityScopedAccess.makeBookmark(for: url)
            job.outputFolderName = url.lastPathComponent
            job.modifiedAt = Date()
        } catch {
            presentOutputError(error.localizedDescription)
        }
    }


    private func presentOutputError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}
