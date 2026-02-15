import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedStep: MergeStep = .template
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
                        .frame(minWidth: 220, idealWidth: 256, maxWidth: 296)
                    Divider()
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
            // Job name header
            VStack(alignment: .leading, spacing: 6) {
                Text(job.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                StatusBadge(status: job.status)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 18)

            // Progress bar (3pt, rounded caps, brand gradient)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: job.configurationProgress == 1
                                    ? [Color.green, Color.green.opacity(0.75)]
                                    : [Color.mergeformBlue, Color.mergeformOrange.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * job.configurationProgress, height: 3)
                        .animation(.smooth(duration: 0.5), value: job.configurationProgress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 18)
            .padding(.bottom, 4)

            HStack {
                Text("\(Int(job.configurationProgress * 100))% complete")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            Divider()
                .padding(.bottom, 12)

            Text("Setup Steps")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(MergeStep.allCases) { step in
                        StepButton(
                            step: step,
                            isSelected: selectedStep == step,
                            isComplete: stepCompletion(step),
                            isEnabled: stepIsEnabled(step)
                        ) {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                selectedStep = step
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            // Only show the shortcut when not already on the preview step
            if selectedStep != .preview {
                VStack(spacing: 10) {
                    Divider()
                    runMergeButton
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var runMergeButton: some View {
        let label = Label("Run Merge", systemImage: "play.fill")
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
#if os(macOS)
        if #available(macOS 26.0, *) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) { selectedStep = .preview }
            } label: {
                label
            }
            .buttonStyle(GlassProminentButtonStyle())
            .disabled(!job.isConfigured)
            .help(job.isConfigured ? "Go to Preview & Run" : "Complete all setup steps first")
        } else {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) { selectedStep = .preview }
            } label: {
                label
            }
            .buttonStyle(.borderedProminent)
            .tint(job.isConfigured ? Color.mergeformBlue : .secondary)
            .disabled(!job.isConfigured)
            .help(job.isConfigured ? "Go to Preview & Run" : "Complete all setup steps first")
        }
#else
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { selectedStep = .preview }
        } label: {
            label
        }
        .buttonStyle(.borderedProminent)
        .tint(job.isConfigured ? Color.mergeformBlue : .secondary)
        .disabled(!job.isConfigured)
#endif
    }

    // MARK: - Step Content

    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stepBreadcrumb
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 22)
                stepView
                    .id(selectedStep)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mergeformBackground.opacity(0.5))
    }

    private var stepBreadcrumb: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.mergeformBlue.opacity(0.10))
                Image(systemName: selectedStep.systemImageName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.mergeformBlue)
            }
            .frame(width: 22, height: 22)
            Text("Step \(selectedStep.rawValue + 1) of \(MergeStep.allCases.count)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)
            Text(selectedStep.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .animation(.smooth(duration: 0.2), value: selectedStep)
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
        case .template: return job.templateBookmarkData != nil
        case .dataSource: return job.dataSourceBookmarkData != nil
        case .fieldMapping: return !job.fieldMappings.isEmpty
        case .output: return job.outputFolderBookmarkData != nil
        case .preview: return job.isConfigured
        }
    }

    private func stepIsEnabled(_ step: MergeStep) -> Bool {
        // Once a job is fully configured, all steps are freely accessible for review and editing.
        if job.isConfigured { return true }
        // For partially configured jobs, enforce sequential unlocking.
        switch step {
        case .template: return true
        case .dataSource: return job.templateBookmarkData != nil
        case .fieldMapping: return job.dataSourceBookmarkData != nil
        case .output: return !job.fieldMappings.isEmpty
        case .preview: return job.outputFolderBookmarkData != nil
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
