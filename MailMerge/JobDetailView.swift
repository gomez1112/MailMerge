import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var selectedStep: MergeStep = .template
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
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
    }
    
    private var contentWithMetadata: some View {
        mainContent
            .alert("Something Went Wrong", isPresented: $showingErrorAlert) {
                errorAlertButtons
            } message: {
                Text(errorMessage)
            }
            .toolbar {
                primaryActionToolbar
            }
    }
    
    private var mainContent: some View {
        HSplitView {
            stepSidebar
                .layoutPriority(1)
            stepContent
                .layoutPriority(0)
        }
    }
    
    @ViewBuilder
    private var errorAlertButtons: some View {
        Button("OK", role: .cancel) { }
        if shouldShowRecoveryButton() {
            Button("Try Again") {
                retryLastAction()
            }
        }
    }
    
    @ToolbarContentBuilder
    private var primaryActionToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                selectedStep = .preview
            } label: {
                Label("Run Merge", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!job.isConfigured)
            .help("Generate all merged PDF documents")
            .accessibilityLabel("Run Merge")
            .accessibilityHint("Generate all merged PDF documents from the template and data")
        }
    }

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Steps")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.leading, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(MergeStep.allCases) { step in
                        StepButton(
                            step: step,
                            isSelected: selectedStep == step,
                            isComplete: stepCompletion(step),
                            isEnabled: stepIsEnabled(step)
                        ) {
                            selectedStep = step
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(.thinMaterial)
    }

    private var stepContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    stepHeader
                        .padding(.horizontal, 4)
                        .padding(.bottom, 12)
                    stepView
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
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

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(selectedStep.rawValue + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(selectedStep.title)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepCompletion(_ step: MergeStep) -> Bool {
        switch step {
        case .template: return job.templateBookmarkData != nil
        case .dataSource: return job.dataSourceBookmarkData != nil
        case .fieldMapping: return !job.fieldMappings.isEmpty
        case .output: return job.outputFolderBookmarkData != nil
        case .preview: return job.isConfigured
        }
    }

    private func stepIsEnabled(_ step: MergeStep) -> Bool {
        switch step {
        case .template:
            return true
        case .dataSource:
            return job.templateBookmarkData != nil
        case .fieldMapping:
            return job.dataSourceBookmarkData != nil
        case .output:
            return !job.fieldMappings.isEmpty
        case .preview:
            return job.outputFolderBookmarkData != nil
        }
    }

    private func selectPreviousStep() {
        guard let index = MergeStep.allCases.firstIndex(of: selectedStep),
              index > 0 else { return }
        selectedStep = MergeStep.allCases[index - 1]
    }

    private func selectNextStep() {
        guard let index = MergeStep.allCases.firstIndex(of: selectedStep),
              index < MergeStep.allCases.count - 1 else { return }
        let nextStep = MergeStep.allCases[index + 1]
        guard stepIsEnabled(nextStep) else { return }
        selectedStep = nextStep
    }

    private func handleError(_ error: Error) {
        if let mergeError = error as? MergeError {
            errorMessage = "\(mergeError.localizedDescription)\n\n\(recoveryInfo(for: mergeError))"
        } else {
            errorMessage = error.localizedDescription
        }
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
        }
    }
    
    private func shouldShowRecoveryButton() -> Bool {
        errorMessage.contains("Try selecting") || errorMessage.contains("try again")
    }
    
    private func retryLastAction() {
        switch selectedStep {
        case .template:
            break
        case .dataSource:
            break
        case .fieldMapping:
            break
        case .output:
            break
        case .preview:
            break
        }
    }


    private func updateStatus() {
        guard !isRestoring else { return }
        if job.isConfigured {
            if job.status == .draft {
                job.status = .configured
            }
        } else if job.status != .running {
            job.status = .draft
        }
        job.modifiedAt = Date()
    }

    private func captureSnapshotIfNeeded() {
        guard initialSnapshot == nil else { return }
        initialSnapshot = JobSnapshot(job: job)
    }

    private func cancelChanges() {
        if isBrandNewJob {
            modelContext.delete(job)
            do {
                try modelContext.save()
            } catch {
                handleError(error)
            }
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
        job.outputFolderBookmarkData = outputFolderBookmarkData
        job.outputFolderName = outputFolderName
        job.outputFileNamePattern = outputFileNamePattern
        job.status = status
        job.lastRunDate = lastRunDate
        job.lastRunRecordCount = lastRunRecordCount
        job.category = category

        for mapping in job.fieldMappings {
            modelContext.delete(mapping)
        }
        job.fieldMappings.removeAll()
        for mapping in fieldMappings {
            let restored = mapping.makeMapping(job: job)
            job.fieldMappings.append(restored)
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
