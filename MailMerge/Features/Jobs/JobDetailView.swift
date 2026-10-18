import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStep: MergeStep = .template
    /// The edge the next step slides in from: trailing when moving forward.
    @State private var stepEdge: Edge = .trailing
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var retryAction: (() -> Void)?
    @State private var initialSnapshot: JobSnapshot?
    @State private var isRestoring = false
    @Bindable var job: MailMergeJob

    var body: some View {
        contentWithMetadata
            .onAppear(perform: captureSnapshotIfNeeded)
            .onChange(of: job.templateBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.dataSourceBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.selectedSheetName) { _, _ in updateStatus() }
            .onChange(of: job.outputFolderBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.fieldMappings.count) { _, _ in updateStatus() }
            .onChange(of: job.mappedFieldCount) { _, _ in updateStatus() }
            .task(id: ColumnSource(bookmarkData: job.dataSourceBookmarkData, sheetName: job.selectedSheetName)) {
                await loadColumnsIfNeeded()
            }
    }

    private var contentWithMetadata: some View {
        mainContent
            .alert("Something Went Wrong", isPresented: $showingErrorAlert) {
                errorAlertButtons
            } message: {
                Text(errorMessage)
            }
    }

    private var mainContent: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(spacing: 0) {
                    stepSidebar
                    Divider()
                    stepContent
                }
            } else {
                HStack(spacing: 0) {
                    stepSidebar
                        .frame(width: 272)
                    Rectangle()
                        .fill(Color.mergeformStroke)
                        .frame(width: 1)
                    stepContent
                }
            }
        }
        .navigationTitle(job.name)
    }

    @ViewBuilder
    private var errorAlertButtons: some View {
        Button("OK", role: .cancel) {
            retryAction = nil
        }
        if let retryAction {
            Button("Try Again") { retryAction() }
        }
    }

    // MARK: - Step Sidebar

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            jobSummary
                .padding(Metrics.regular)
                .padding(.top, Metrics.tight)

            Divider()
                .padding(.horizontal, Metrics.regular)

            ScrollView {
                StepRail(
                    selection: selectedStep,
                    isComplete: stepCompletion,
                    isEnabled: stepIsEnabled,
                    onSelect: select
                )
                .padding(Metrics.compact)
            }
            .scrollIndicators(.hidden)

            if selectedStep != .preview {
                runMergeButton
                    .padding(Metrics.regular)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.mergeformPanel)
        .motion(Motion.standard, value: selectedStep == .preview)
    }

    private var jobSummary: some View {
        HStack(spacing: 14) {
            ProgressRing(
                progress: job.configurationProgress,
                size: 54,
                tint: job.isConfigured ? .green : .mergeformBlue
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(job.name)
                    .font(.headline)
                    .lineLimit(2)
                StatusBadge(status: job.status)
            }
            Spacer(minLength: 0)
        }
    }

    private var runMergeButton: some View {
        Button {
            select(.preview)
        } label: {
            Label("Run Merge", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .symbolEffect(.bounce, value: job.isConfigured)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!job.isConfigured)
        .help(job.isConfigured ? "Go to Preview & Run" : "Complete all setup steps first")
    }

    // MARK: - Step Content

    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.section) {
                stepProgress
                stepView
                    .id(selectedStep)
                    .transition(stepTransition)
            }
            .padding(Metrics.page)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mergeformBackground)
    }

    /// Steps slide in from the direction of travel, or cross-fade with Reduce Motion.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let removalEdge: Edge = stepEdge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: stepEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    /// Where the current step sits among all five, as a row of segments.
    private var stepProgress: some View {
        HStack(spacing: Metrics.compact) {
            Text("Step \(selectedStep.rawValue + 1) of \(MergeStep.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(selectedStep.rawValue)))
            HStack(spacing: 4) {
                ForEach(MergeStep.allCases) { step in
                    Capsule()
                        .fill(segmentColor(for: step))
                        .frame(width: step == selectedStep ? 22 : 10, height: 5)
                }
            }
        }
        .motion(Motion.standard, value: selectedStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(selectedStep.rawValue + 1) of \(MergeStep.allCases.count), \(selectedStep.title)")
    }

    private func segmentColor(for step: MergeStep) -> Color {
        if step == selectedStep { return .mergeformBlue }
        return stepCompletion(step) ? .green.opacity(0.7) : Color.primary.opacity(0.12)
    }

    private func select(_ step: MergeStep) {
        guard step != selectedStep else { return }
        stepEdge = step.rawValue > selectedStep.rawValue ? .trailing : .leading
        // Change the step in the next update so the outgoing step already uses the new
        // direction for its exit.
        Task { @MainActor in
            withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) {
                selectedStep = step
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch selectedStep {
        case .template:
            TemplateConfigView(job: job, onError: handleError)
        case .dataSource:
            DataSourceConfigView(job: job, onError: handleError)
        case .fieldMapping:
            FieldMappingConfigView(job: job)
        case .output:
            OutputConfigView(job: job)
        case .preview:
            PreviewConfigView(job: job)
        }
    }

    // MARK: - Step Logic

    private func stepCompletion(_ step: MergeStep) -> Bool {
        switch step {
        case .template: return job.hasTemplate
        case .dataSource: return job.hasDataSource
        case .fieldMapping: return job.hasFieldMappings
        case .output: return job.hasOutputFolder
        case .preview: return job.isConfigured
        }
    }

    private func stepIsEnabled(_ step: MergeStep) -> Bool {
        // Once a job is fully configured, all steps are freely accessible for review and editing.
        if job.isConfigured { return true }
        // For partially configured jobs, enforce sequential unlocking.
        switch step {
        case .template: return true
        case .dataSource: return job.hasTemplate
        case .fieldMapping: return job.hasDataSource
        case .output: return job.hasFieldMappings
        case .preview: return job.hasOutputFolder
        }
    }

    // MARK: - Columns

    private struct ColumnSource: Hashable {
        var bookmarkData: Data?
        var sheetName: String?
    }

    /// Loads the selected sheet's column names, which aren't saved with the job, so every
    /// step can offer them right after the app relaunches.
    private func loadColumnsIfNeeded() async {
        guard job.availableColumns.isEmpty,
              let bookmarkData = job.dataSourceBookmarkData,
              let sheetName = job.selectedSheetName else {
            return
        }
        do {
            let headers = try await services.mergeEngine.getColumnHeaders(bookmarkData: bookmarkData, sheetName: sheetName)
            guard !Task.isCancelled, job.selectedSheetName == sheetName else { return }
            job.updateAvailableColumns(headers)
        } catch is CancellationError {
            return
        } catch {
            handleError(error) {
                Task { await loadColumnsIfNeeded() }
            }
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, retry: (() -> Void)? = nil) {
        if let mergeError = error as? MergeError {
            errorMessage = "\(mergeError.localizedDescription)\n\n\(recoveryInfo(for: mergeError))"
        } else {
            errorMessage = error.localizedDescription
        }
        retryAction = retry
        showingErrorAlert = true
    }

    private func recoveryInfo(for error: MergeError) -> String {
        switch error {
        case .invalidTemplate:
            return "Try selecting a different DOCX file or ensure the file isn't corrupted."
        case .invalidSpreadsheet:
            return "Try selecting a different Excel file or ensure the file isn't corrupted."
        case .emptySheet:
            return "Select a different sheet or add data to the current sheet."
        case .sheetNotFound:
            return "The sheet may have been renamed or deleted. Please reselect your data source."
        case .staleBookmark:
            return "The file may have moved. Try selecting the file again."
        case .outputAccessDenied:
            return "Check folder permissions or select a different output folder."
        case .noRecords:
            return "Add rows to your spreadsheet and try again."
        case .pdfGenerationFailed:
            return "Check that your template and data are valid, then try again."
        case .securityScopeUnavailable:
            return "The app needs permission to access this file. Try selecting it again."
        case .featureUnavailable:
            return "Try again on macOS, where DOCX parsing is supported."
        }
    }

    private func updateStatus() {
        guard !isRestoring else { return }
        if job.isConfigured {
            if job.status == .draft { job.status = .configured }
        } else if job.status != .running {
            job.status = .draft
        }
        job.modifiedAt = Date()
    }

    private func captureSnapshotIfNeeded() {
        job.refreshStaleBookmarks()
        guard initialSnapshot == nil else { return }
        initialSnapshot = JobSnapshot(job: job)
    }

    private func cancelChanges() {
        if isBrandNewJob {
            modelContext.delete(job)
            try? modelContext.save()
            return
        }
        guard let snapshot = initialSnapshot else { return }
        isRestoring = true
        snapshot.restore(into: job, modelContext: modelContext)
        isRestoring = false
    }

    private var isBrandNewJob: Bool {
        let hasNoConfiguration = job.templateBookmarkData == nil
            && job.dataSourceBookmarkData == nil
            && job.selectedSheetName == nil
            && job.fieldMappings.isEmpty
            && job.outputFolderBookmarkData == nil
        let isUntouched = job.createdAt == job.modifiedAt
        return hasNoConfiguration && isUntouched
    }
}

// MARK: - Snapshot Support

private struct JobSnapshot {
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let templateBookmarkData: Data?
    let templateFileName: String?
    let dataSourceBookmarkData: Data?
    let dataSourceFileName: String?
    let selectedSheetName: String?
    let availableSheets: [String]
    let combineIntoSinglePDF: Bool
    let fieldMappings: [FieldMappingSnapshot]
    let outputFolderBookmarkData: Data?
    let outputFolderName: String?
    let outputFileNamePattern: String
    let status: JobStatus
    let lastRunDate: Date?
    let lastRunRecordCount: Int?
    let category: Category?

    init(job: MailMergeJob) {
        name = job.name
        createdAt = job.createdAt
        modifiedAt = job.modifiedAt
        templateBookmarkData = job.templateBookmarkData
        templateFileName = job.templateFileName
        dataSourceBookmarkData = job.dataSourceBookmarkData
        dataSourceFileName = job.dataSourceFileName
        selectedSheetName = job.selectedSheetName
        availableSheets = job.availableSheets
        combineIntoSinglePDF = job.combineIntoSinglePDF
        fieldMappings = job.fieldMappings.map(FieldMappingSnapshot.init)
        outputFolderBookmarkData = job.outputFolderBookmarkData
        outputFolderName = job.outputFolderName
        outputFileNamePattern = job.outputFileNamePattern
        status = job.status
        lastRunDate = job.lastRunDate
        lastRunRecordCount = job.lastRunRecordCount
        category = job.category
    }

    func restore(into job: MailMergeJob, modelContext: ModelContext) {
        job.name = name
        job.createdAt = createdAt
        job.modifiedAt = modifiedAt
        job.templateBookmarkData = templateBookmarkData
        job.templateFileName = templateFileName
        job.dataSourceBookmarkData = dataSourceBookmarkData
        job.dataSourceFileName = dataSourceFileName
        job.selectedSheetName = selectedSheetName
        job.availableSheets = availableSheets
        job.combineIntoSinglePDF = combineIntoSinglePDF
        job.outputFolderBookmarkData = outputFolderBookmarkData
        job.outputFolderName = outputFolderName
        job.outputFileNamePattern = outputFileNamePattern
        job.status = status
        job.lastRunDate = lastRunDate
        job.lastRunRecordCount = lastRunRecordCount
        job.category = category

        for mapping in job.fieldMappings { modelContext.delete(mapping) }
        job.fieldMappings.removeAll()
        for mapping in fieldMappings {
            job.fieldMappings.append(mapping.makeMapping(job: job))
        }
    }
}

private struct FieldMappingSnapshot {
    let placeholderText: String
    let columnName: String?
    let isAutoMatched: Bool
    let matchConfidence: Double
    let transformation: FieldTransformation
    let formatString: String?

    init(mapping: FieldMapping) {
        placeholderText = mapping.placeholderText
        columnName = mapping.columnName
        isAutoMatched = mapping.isAutoMatched
        matchConfidence = mapping.matchConfidence
        transformation = mapping.transformation
        formatString = mapping.formatString
    }

    func makeMapping(job: MailMergeJob) -> FieldMapping {
        FieldMapping(
            placeholderText: placeholderText,
            columnName: columnName,
            isAutoMatched: isAutoMatched,
            matchConfidence: matchConfidence,
            transformation: transformation,
            formatString: formatString,
            job: job
        )
    }
}
