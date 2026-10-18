import SwiftUI
import UniformTypeIdentifiers

struct OutputConfigView: View {
    @Bindable var job: MailMergeJob
    @State private var showingFolderPicker = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    /// `{Row}` plus a token per column, without duplicates (a column may be named "Row").
    private var availableTokens: [String] {
        var seen: Set<String> = []
        return (["{Row}"] + job.availableColumns.map { "{\($0)}" }).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            SectionHeader(
                title: "Output",
                subtitle: "Choose where the PDFs are saved and how they’re named.",
                systemImageName: "folder",
                iconColor: .mergeformOrange
            )

            ConfigCard {
                VStack(alignment: .leading, spacing: Metrics.regular) {
                    CardLabel(title: "Output Folder", systemImage: "folder")
                    if let folderName = job.outputFolderName {
                        SelectedFileRow(
                            fileName: folderName,
                            subtitle: "PDFs are saved here",
                            systemImageName: "folder.fill",
                            color: .mergeformOrange
                        ) {
                            showingFolderPicker = true
                        }
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                    } else {
                        DropTargetView(
                            title: "Drop a folder here",
                            subtitle: "or click to choose where PDFs are saved",
                            systemImageName: "folder.badge.plus"
                        ) {
                            showingFolderPicker = true
                        }
                        .transition(.opacity)
                    }
                }
                .motion(Motion.standard, value: job.outputFolderName)
            }
            .revealOnAppear(order: 0)

            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    CardLabel(title: "File Names", systemImage: "textformat")

                    TextField("Pattern", text: $job.outputFileNamePattern, prompt: Text("Letter_{FirstName}_{LastName}"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .disabled(job.combineIntoSinglePDF)

                    VStack(alignment: .leading, spacing: Metrics.tight) {
                        Text("Click a token to add it to the pattern")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: Metrics.tight) {
                            ForEach(availableTokens, id: \.self) { token in
                                Button {
                                    job.outputFileNamePattern += token
                                } label: {
                                    PlaceholderTag(text: token)
                                }
                                .buttonStyle(.plain)
                                .help("Add \(token) to the pattern")
                            }
                        }
                    }
                    .disabled(job.combineIntoSinglePDF)
                    .opacity(job.combineIntoSinglePDF ? 0.5 : 1)

                    HStack(spacing: Metrics.tight) {
                        Image(systemName: "text.page.badge.magnifyingglass")
                            .foregroundStyle(Color.mergeformBlue)
                        Text("Example:")
                            .foregroundStyle(.secondary)
                        Text(previewFileName)
                            .monospaced()
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentTransition(.opacity)
                    }
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.mergeformBlue.opacity(0.06), in: .rect(cornerRadius: Metrics.tileRadius))

                    if job.combineIntoSinglePDF {
                        Text("The pattern names individual files. A combined PDF is named after the job.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .motion(Motion.standard, value: previewFileName)
                .motion(Motion.standard, value: job.combineIntoSinglePDF)
            }
            .revealOnAppear(order: 1)

            ConfigCard {
                VStack(alignment: .leading, spacing: 12) {
                    CardLabel(title: "Options", systemImage: "slider.horizontal.3")
                    Toggle(isOn: $job.combineIntoSinglePDF) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Combine into a single PDF")
                            Text("Put every record in one document instead of a file per record.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                }
            }
            .revealOnAppear(order: 2)
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
