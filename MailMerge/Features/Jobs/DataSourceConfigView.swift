import SwiftUI
import SwiftData

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
    @State private var sheetReload = 0
    @State private var previewReload = 0
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
                            sheetReload += 1
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
        .task(id: SheetRequest(bookmark: job.dataSourceBookmarkData, reload: sheetReload)) {
            await loadSheetNames()
        }
        .task(id: PreviewRequest(bookmark: job.dataSourceBookmarkData, sheet: job.selectedSheetName, reload: previewReload)) {
            previewData = SheetData(headers: [], rows: [])
            guard let name = job.selectedSheetName else { return }
            await loadPreview(sheetName: name)
        }
    }

    // MARK: - Sheet Selector

    private var sheetSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.tight) {
                ForEach(job.availableSheets, id: \.self) { sheet in
                    let isSelected = job.selectedSheetName == sheet
                    Button {
                        job.selectSheet(sheet)
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
        job.resetSpreadsheet()
        previewData = SheetData(headers: [], rows: [])
        job.modifiedAt = Date()
    }

    private struct SheetRequest: Equatable {
        var bookmark: Data?
        var reload: Int
    }

    private struct PreviewRequest: Equatable {
        var bookmark: Data?
        var sheet: String?
        var reload: Int
    }

    private func loadSheetNames() async {
        guard let bookmark = job.dataSourceBookmarkData else { return }
        isLoadingSheets = true
        defer { isLoadingSheets = false }
        do {
            let names = try await services.mergeEngine.getSheetNames(bookmarkData: bookmark)
            try Task.checkCancellation()
            guard !job.isDeleted, job.modelContext != nil, job.dataSourceBookmarkData == bookmark else { return }
            job.updateAvailableSheets(names)
            if sheetReload > 0 { previewReload += 1 }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !job.isDeleted, job.modelContext != nil else { return }
            onError(error, { sheetReload += 1 })
        }
    }

    private func loadPreview(sheetName: String) async {
        guard let bookmark = job.dataSourceBookmarkData else { return }
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            let preview = try await services.mergeEngine.getSheetPreview(bookmarkData: bookmark, sheetName: sheetName, rowCount: 5)
            try Task.checkCancellation()
            guard !job.isDeleted, job.modelContext != nil,
                  job.selectedSheetName == sheetName, job.dataSourceBookmarkData == bookmark else { return }
            previewData = preview
            job.updateAvailableColumns(preview.headers)
            if autoMatchFields { job.autoMatchUnmappedFields() }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !job.isDeleted, job.modelContext != nil else { return }
            // A transient read error must preserve the chosen sheet so retry can work.
            onError(error, { previewReload += 1 })
        }
    }

    private func isValidXlsxURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "xlsx"
    }
}
