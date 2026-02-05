import SwiftUI
import UniformTypeIdentifiers

struct DataSourceConfigView: View {
    @Environment(\.services) private var services
    @Bindable var job: MailMergeJob
    let onError: (Error) -> Void

    @State private var showingImporter = false
    @State private var previewData = SheetData(headers: [], rows: [])
    @State private var isLoadingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Data Source",
                subtitle: "Pick an Excel file and the sheet you want to merge.",
                systemImageName: "tablecells"
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    if let fileName = job.dataSourceFileName {
                        HStack(spacing: 12) {
                            FileIconView(systemImageName: "tablecells", color: .accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileName)
                                    .font(.headline)
                                Text("Spreadsheet selected")
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
                            title: "Drop your XLSX file",
                            subtitle: "or click to browse",
                            systemImageName: "tablecells"
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
                        Text("Sheet selection")
                            .font(.headline)
                        Spacer()
                        Button("Load Sheets") {
                            loadSheetNames()
                        }
                        .disabled(job.dataSourceBookmarkData == nil)
                    }

                    Picker("Sheet", selection: $job.selectedSheetName) {
                        Text("Select sheet").tag(String?.none)
                        ForEach(job.availableSheets, id: \.self) { sheet in
                            Text(sheet).tag(Optional(sheet))
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(job.availableSheets.isEmpty)
                    .onChange(of: job.selectedSheetName) { _, newValue in
                        guard let newValue else { return }
                        loadPreview(sheetName: newValue)
                    }
                }
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Preview")
                            .font(.headline)
                        Spacer()
                        if isLoadingPreview {
                            ProgressView()
                        }
                    }

                    if previewData.headers.isEmpty {
                        Text("Load a sheet to preview the first five rows.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        DataPreviewTable(headers: previewData.headers, rows: previewData.rows)
                        Text("Columns: \(previewData.headers.count) · Rows: \(previewData.rows.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            Spacer()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data],
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
            try storeSpreadsheetURL(url)
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
                try? storeSpreadsheetURL(url)
            }
        }
        return true
    }

    private func storeSpreadsheetURL(_ url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw MergeError.securityScopeUnavailable
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        job.dataSourceBookmarkData = bookmarkData
        job.dataSourceFileName = url.lastPathComponent
        job.availableSheets = []
        job.availableColumns = []
        job.selectedSheetName = nil
        previewData = SheetData(headers: [], rows: [])
        job.modifiedAt = Date()
    }

    private func loadSheetNames() {
        guard let bookmarkData = job.dataSourceBookmarkData else { return }
        Task {
            do {
                let names = try await services.mergeEngine.getSheetNames(bookmarkData: bookmarkData)
                job.availableSheets = names
            } catch {
                onError(error)
            }
        }
    }

    private func loadPreview(sheetName: String) {
        guard let bookmarkData = job.dataSourceBookmarkData else { return }
        isLoadingPreview = true
        Task {
            do {
                let preview = try await services.mergeEngine.getSheetPreview(
                    bookmarkData: bookmarkData,
                    sheetName: sheetName,
                    rowCount: 5
                )
                previewData = preview
                job.availableColumns = preview.headers
            } catch {
                onError(error)
            }
            isLoadingPreview = false
        }
    }
}
