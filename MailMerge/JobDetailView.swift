import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var selectedStep: MergeStep = .template
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @Bindable var job: MailMergeJob

    var body: some View {
        contentWithMetadata
            .onChange(of: job.templateBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.dataSourceBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.selectedSheetName) { _, _ in updateStatus() }
            .onChange(of: job.outputFolderBookmarkData) { _, _ in updateStatus() }
            .onChange(of: job.fieldMappings.count) { _, _ in updateStatus() }
    }
    
    private var contentWithMetadata: some View {
        mainContent
            .navigationTitle(job.name)
            .navigationSubtitle("Last updated \(job.modifiedAt, format: .relative(presentation: .named))")
            .alert("Something Went Wrong", isPresented: $showingErrorAlert) {
                errorAlertButtons
            } message: {
                Text(errorMessage)
            }
            .toolbar {
                navigationToolbar
                principalToolbar
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
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                selectPreviousStep()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous Step (⌘[)")
            .keyboardShortcut("[", modifiers: .command)
            .disabled(selectedStep == MergeStep.allCases.first)

            Button {
                selectNextStep()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next Step (⌘])")
            .keyboardShortcut("]", modifiers: .command)
            .disabled(selectedStep == MergeStep.allCases.last)
        }
    }
    
    @ToolbarContentBuilder
    private var principalToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(selectedStep.title)
                .font(.headline)
        }
    }
    
    @ToolbarContentBuilder
    private var primaryActionToolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            StatusBadge(status: job.status)
        }
        
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
                        StepSidebarRow(
                            step: step,
                            isSelected: selectedStep == step,
                            isComplete: stepCompletion(step),
                            isEnabled: stepIsEnabled(step),
                            badgeText: stepCompletion(step) ? "Done" : "\(step.rawValue + 1)"
                        ) {
                            selectedStep = step
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 260)
        .background(.thinMaterial)
    }

    private var stepContent: some View {
        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
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
        selectedStep = MergeStep.allCases[index + 1]
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
        if job.isConfigured {
            if job.status == .draft {
                job.status = .configured
            }
        } else if job.status != .running {
            job.status = .draft
        }
        job.modifiedAt = Date()
    }
}

private struct StepSidebarRow: View {
    let step: MergeStep
    let isSelected: Bool
    let isComplete: Bool
    let isEnabled: Bool
    let badgeText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: step.systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(step.title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                StepBadge(text: badgeText, isComplete: isComplete)
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !isEnabled {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}

private struct StepBadge: View {
    let text: String
    let isComplete: Bool

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(isComplete ? Color.green.opacity(0.18) : Color.secondary.opacity(0.18))
            )
            .foregroundStyle(isComplete ? .green : .secondary)
    }
}


