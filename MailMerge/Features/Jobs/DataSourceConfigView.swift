import SwiftUI
import UniformTypeIdentifiers

struct DataSourceConfigView: View {
    @Environment(\.services) private var services
    @AppStorage("autoMatchFields") private var autoMatchFields = true
    @Bindable var job: MailMergeJob
    let onError: (Error, (() -> Void)?) -> Void

    @State private var showingImporter = false
    @State private var previewData = SheetData(headers: [], rows: [])
    @State private var isLoadingPreview = false
    @State private var isLoadingSheets = false
    @Namespace private var sheetSelection

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            SectionHeader(
                title: "Data Source",
                subtitle: "Pick an Excel spreadsheet (.xlsx) and the sheet to merge.",
                systemImageName: "tablecells",
                iconColor: .green
            )

            ConfigCard {
                VStack(alignment: .leading, spacing: Metrics.regular) {
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
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                    } else {
                        DropTargetView(
                            title: "Drop your Excel spreadsheet here",
                            subtitle: "or click to choose an .xlsx file",
                            systemImageName: "tablecells.badge.ellipsis"
                        ) {
                            showingImporter = true
                        }
                        .transition(.opacity)
                    }
                }
                .motion(Motion.standard, value: job.dataSourceFileName)
            }
            .revealOnAppear(order: 0)

            ConfigCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardLabel(title: "Sheet", systemImage: "rectangle.split.3x1")
                        Spacer()
                        Button {
                            loadSheetNames()
                        } label: {
                            Label(isLoadingSheets ? "Loading…" : "Reload Sheets", systemImage: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: isLoadingSheets)
                        }
                        .disabled(job.dataSourceBookmarkData == nil || isLoadingSheets)
                    }

                    if job.availableSheets.isEmpty {
                        Label(
                            job.dataSourceBookmarkData == nil ? "Choose a spreadsheet first." : "Loading the workbook’s sheets…",
                            systemImage: "rectangle.split.3x1"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    } else {
                        sheetSelector
                    }
                }
                .motion(Motion.standard, value: job.availableSheets)
            }
            .revealOnAppear(order: 1)

            if !previewData.headers.isEmpty {
                ConfigCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            CardLabel(title: "Data Preview", systemImage: "eye")
                            Spacer()
                            if isLoadingPreview {
                                ProgressView().controlSize(.small)
                            }
                            Text("\(previewData.headers.count) columns · first \(previewData.rows.count) rows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        DataPreviewTable(headers: previewData.headers, rows: previewData.rows)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let sheetName = job.selectedSheetName {
                ConfigCard {
                    HStack(spacing: Metrics.compact) {
                        ProgressView().controlSize(.small)
                        Text("Loading “\(sheetName)”…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .motion(Motion.standard, value: previewData)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .onChange(of: job.selectedSheetName) { _, newValue in
            guard let newValue else {
                previewData = SheetData(headers: [], rows: [])
                job.availableColumns = []
                return
            }
            loadPreview(sheetName: newValue, matchesFields: autoMatchFields)
        }
        .task {
            // Show the selected sheet's preview again when returning to this step.
            if let sheetName = job.selectedSheetName, previewData.headers.isEmpty {
                loadPreview(sheetName: sheetName, matchesFields: false)
            }
        }
    }

    // MARK: - Sheet Selector

    private var sheetSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.tight) {
                ForEach(job.availableSheets, id: \.self) { sheet in
                    let isSelected = job.selectedSheetName == sheet
                    Button {
                        job.selectedSheetName = sheet
                    } label: {
                        Label(sheet, systemImage: "tablecells")
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.mergeformBlue.gradient)
                                        .matchedGeometryEffect(id: "selectedSheet", in: sheetSelection)
                                } else {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .motion(Motion.quick, value: job.selectedSheetName)
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

    private func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            try storeSpreadsheetURL(url)
        } catch {
            onError(error, nil)
        }
    }

    private func storeSpreadsheetURL(_ url: URL) throws {
        guard isValidXlsxURL(url) else {
            throw MergeError.invalidSpreadsheet
        }
        let bookmarkData = try SecurityScopedAccess.makeBookmark(for: url)
        job.dataSourceBookmarkData = bookmarkData
        job.dataSourceFileName = url.lastPathComponent
        job.availableSheets = []
        job.availableColumns = []
        job.selectedSheetName = nil
        previewData = SheetData(headers: [], rows: [])
        job.modifiedAt = Date()
        loadSheetNames()
    }

    private func loadSheetNames() {
        guard let bookmarkData = job.dataSourceBookmarkData else { return }
        isLoadingSheets = true
        Task {
            do {
                let names = try await services.mergeEngine.getSheetNames(bookmarkData: bookmarkData)
                job.availableSheets = names
                // A workbook with one sheet has nothing to choose.
                if job.selectedSheetName == nil, names.count == 1 {
                    job.selectedSheetName = names[0]
                }
            } catch {
                onError(error, { loadSheetNames() })
            }
            isLoadingSheets = false
        }
    }

    /// Loads a sheet's first rows and columns. `matchesFields` auto-matches unmapped
    /// fields to the columns, for when the user has just chosen the sheet.
    private func loadPreview(sheetName: String, matchesFields: Bool) {
        guard let bookmarkData = job.dataSourceBookmarkData else { return }
        isLoadingPreview = true
        Task {
            do {
                let preview = try await services.mergeEngine.getSheetPreview(
                    bookmarkData: bookmarkData,
                    sheetName: sheetName,
                    rowCount: 5
                )
                // Ignore a result for a sheet that's no longer selected.
                guard job.selectedSheetName == sheetName else { return }
                previewData = preview
                job.updateAvailableColumns(preview.headers)
                if matchesFields {
                    job.autoMatchUnmappedFields()
                }
            } catch {
                // A sheet that can't be read can't be merged, so don't leave it selected
                // with the previous sheet's preview and columns.
                if job.selectedSheetName == sheetName {
                    job.selectedSheetName = nil
                }
                onError(error, { loadPreview(sheetName: sheetName, matchesFields: matchesFields) })
            }
            isLoadingPreview = false
        }
    }

    private func isValidXlsxURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "xlsx"
    }
}
