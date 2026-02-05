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
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                stepsSidebar
                Divider()
                stepContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Something went wrong", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: job.templateBookmarkData) { _, _ in updateStatus() }
        .onChange(of: job.dataSourceBookmarkData) { _, _ in updateStatus() }
        .onChange(of: job.selectedSheetName) { _, _ in updateStatus() }
        .onChange(of: job.outputFolderBookmarkData) { _, _ in updateStatus() }
        .onChange(of: job.fieldMappings.count) { _, _ in updateStatus() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Job Name", text: $job.name)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onChange(of: job.name) { _, _ in
                        job.modifiedAt = Date()
                    }
                HStack(spacing: 12) {
                    StatusBadge(status: job.status)
                    Text("Last updated \(job.modifiedAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            CircularProgressView(progress: job.configurationProgress)
        }
        .padding(24)
        .background(Color.secondary.opacity(0.05))
    }

    private var stepsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MergeStep.allCases) { step in
                StepButton(
                    step: step,
                    isSelected: selectedStep == step,
                    isComplete: stepCompletion(step),
                    isEnabled: stepIsEnabled(step),
                    action: { selectedStep = step }
                )
            }
            Spacer()
        }
        .frame(width: 220)
        .padding(16)
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(24)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Preview") {
                    selectedStep = .preview
                }
                .disabled(!job.isConfigured)

                Button("Run Merge") {
                    selectedStep = .preview
                }
                .buttonStyle(.borderedProminent)
                .disabled(!job.isConfigured)
            }
        }
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

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingErrorAlert = true
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
