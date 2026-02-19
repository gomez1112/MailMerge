import SwiftUI
import UniformTypeIdentifiers

struct DataSourceConfigView: View {
    @Environment(\.services) private var services
    @Bindable var job: MailMergeJob
    let onError: (Error, (() -> Void)?) -> Void

    @State private var showingImporter = false
    @State private var previewData = SheetData(headers: [], rows: [])
    @State private var isLoadingPreview = false
    @State private var isLoadingSheets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Data Source",
                subtitle: "Pick an Excel spreadsheet and the sheet to merge.",
                systemImageName: "tablecells"
            )

            // File selection card
            ConfigCard {
                VStack(alignment: .leading, spacing: 16) {
                    CardLabel(title: "Spreadsheet File", systemImage: "tablecells")
                    if let fileName = job.dataSourceFileName {
                        SelectedFileRow(
                            fileName: fileName,
                            subtitle: "Excel spreadsheet",
                            systemImageName: "tablecells",
                            color: .green
                        ) {
                            showingImporter = true
                        }
                    } else {
                        DropTargetView(
                            title: "Drop your XLSX spreadsheet",
                            subtitle: "or click to browse",
                            systemImageName: "tablecells"
                        ) {
                            showingImporter = true
                        }
                    }
                }
            }

            // Sheet selection card
            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Sheet Selection", systemImage: "rectangle.split.3x1")
                        Spacer()
                        Button {
                            loadSheetNames()
                        } label: {
                            if isLoadingSheets {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Loading…")
                                }
                            } else {
                                Label("Load Sheets", systemImage: "arrow.clockwise")
                            }
                        }
                        .font(.system(size: 12))
                        .disabled(job.dataSourceBookmarkData == nil || isLoadingSheets)
                    }

                    if job.availableSheets.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.split.3x1")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                            Text(job.dataSourceBookmarkData == nil
                                ? "Select a spreadsheet first."
                                : "Click \"Load Sheets\" to discover available sheets.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select a sheet to merge:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            sheetSelector
                        }
                    }
                }
            }

            // Preview card
            if !previewData.headers.isEmpty {
                ConfigCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            CardLabel(title: "Data Preview", systemImage: "eye")
                            Spacer()
                            if isLoadingPreview {
                                ProgressView().controlSize(.mini)
                            }
                            Text("\(previewData.headers.count) columns · \(previewData.rows.count) rows shown")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        DataPreviewTable(headers: previewData.headers, rows: previewData.rows)
                    }
                }
            } else if let sheetName = job.selectedSheetName {
                ConfigCard {
                    HStack(spacing: 10) {
                        if isLoadingPreview {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Text(isLoadingPreview ? "Loading preview for \"\(sheetName)\"…" : "Sheet \"\(sheetName)\" selected.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
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

    // MARK: - Sheet Selector

    private var sheetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(job.availableSheets, id: \.self) { sheet in
                    let isSelected = job.selectedSheetName == sheet
                    Button {
                        job.selectedSheetName = sheet
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tablecells")
                                .font(.system(size: 10, weight: .medium))
                            Text(sheet)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.mergeformBlue : Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .animation(.smooth(duration: 0.15), value: isSelected)
                }
            }
        }
        .onChange(of: job.selectedSheetName) { _, newValue in
            guard let newValue else {
                previewData = SheetData(headers: [], rows: [])
                job.availableColumns = []
                return
            }
            loadPreview(sheetName: newValue)
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            try storeSpreadsheetURL(url)
        } catch {
            onError(error, nil)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                Task { @MainActor in
                    onError(error, nil)
                }
                return
            }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                do {
                    try storeSpreadsheetURL(url)
                } catch {
                    onError(error, nil)
                }
            }
        }
        return true
    }

    private func storeSpreadsheetURL(_ url: URL) throws {
        guard isValidXlsxURL(url) else {
            throw MergeError.invalidSpreadsheet
        }
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
        isLoadingSheets = true
        Task.detached(priority: .utility) {
            do {
                let names = try await services.mergeEngine.getSheetNames(bookmarkData: bookmarkData)
                await MainActor.run {
                    job.availableSheets = names
                    isLoadingSheets = false
                }
            } catch {
                await MainActor.run {
                    onError(error, { loadSheetNames() })
                    isLoadingSheets = false
                }
            }
        }
    }

    private func loadPreview(sheetName: String) {
        guard let bookmarkData = job.dataSourceBookmarkData else { return }
        isLoadingPreview = true
        Task.detached(priority: .utility) {
            do {
                let preview = try await services.mergeEngine.getSheetPreview(
                    bookmarkData: bookmarkData,
                    sheetName: sheetName,
                    rowCount: 5
                )
                await MainActor.run {
                    previewData = preview
                    let cleanedHeaders = preview.headers
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    var seen: Set<String> = []
                    let uniqueHeaders = cleanedHeaders.filter { seen.insert($0).inserted }
                    job.availableColumns = uniqueHeaders
                    normalizeColumnMappings(using: uniqueHeaders)
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    onError(error, { loadPreview(sheetName: sheetName) })
                    isLoadingPreview = false
                }
            }
        }
    }

    private func isValidXlsxURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "xlsx"
    }

    private func normalizeColumnMappings(using headers: [String]) {
        let headerSet = Set(headers)
        for mapping in job.fieldMappings {
            if let columnName = mapping.columnName, !headerSet.contains(columnName) {
                mapping.columnName = nil
                mapping.isAutoMatched = false
                mapping.matchConfidence = 0
            }
        }
    }
}
