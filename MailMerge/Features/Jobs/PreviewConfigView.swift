import SwiftUI
import AppKit

struct PreviewConfigView: View {
    @Environment(\.services) private var services
    @Environment(MergeRunStore.self) private var mergeRuns
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var job: MailMergeJob

    @State private var previewData: Data?
    @State private var isGenerating = false
    @State private var currentRecordIndex = 0
    @State private var totalRecordCount = 0
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingEmailError = false
    @State private var emailErrorMessage = ""
    @State private var emailRecipient = ""
    @State private var emailSubject = "Merged Documents"
    @State private var emailBody = "Hi,\n\nAttached are the merged documents.\n\nThanks!"
    @State private var sendAfterMerge = false

    /// This job's latest merge, which outlives this view.
    private var run: MergeRun? {
        mergeRuns.run(for: job.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(
                title: "Preview & Run",
                subtitle: "Review a sample document, then run the full merge.",
                systemImageName: "play.rectangle"
            )

            // Stats row
            HStack(spacing: 12) {
                StatCard(
                    systemImageName: "doc.plaintext.fill",
                    value: "\(job.fieldMappings.count)",
                    label: "Fields",
                    iconColor: .mergeformBlue
                )
                StatCard(
                    systemImageName: "checkmark.circle.fill",
                    value: "\(job.fieldMappings.filter { $0.isMapped }.count)",
                    label: "Mapped",
                    iconColor: .green
                )
                StatCard(
                    systemImageName: "tablecells.fill",
                    value: "\(job.availableColumns.count)",
                    label: "Columns",
                    iconColor: .mergeformOrange
                )
            }

            Group {
                if horizontalSizeClass == .compact {
                    VStack(spacing: 16) {
                        previewPane
                        mergeSettingsCard
                        runMergeCard
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        previewPane

                        VStack(spacing: 12) {
                            mergeSettingsCard
                            runMergeCard
                        }
                        .frame(width: 260)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Merge Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Email Unavailable", isPresented: $showingEmailError) {
            Button("OK") { }
        } message: {
            Text(emailErrorMessage)
        }
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        ConfigCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardLabel(title: "Preview PDF", systemImage: "doc.richtext")
                    Spacer()
                    Button {
                        generatePreview()
                    } label: {
                        if isGenerating {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Generating…")
                            }
                        } else {
                            Label("Generate Preview", systemImage: "eye")
                        }
                    }
                    .font(.callout)
                    .disabled(isGenerating)
                }

                if let previewData {
                    PDFPreviewView(data: previewData)
                        .frame(minHeight: 550)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07))
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.mergeformSurface.opacity(0.5))
                            .frame(minHeight: 550)
                        VStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 36))
                                .foregroundStyle(.quaternary)
                            Text("Generate a preview to validate your merge.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if hasPreview {
                    recordNavigation
                }
            }
        }
    }

    private var recordNavigation: some View {
        HStack(spacing: 10) {
            Button {
                loadPreview(at: currentRecordIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!hasPreview || isGenerating || currentRecordIndex == 0)

            Text("Record \(currentRecordIndex + 1) of \(max(totalRecordCount, 1))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Button {
                loadPreview(at: currentRecordIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!hasPreview || isGenerating || currentRecordIndex >= max(totalRecordCount - 1, 0))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Merge Settings Card

    private var mergeSettingsCard: some View {
        ConfigCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: "Merge Settings", systemImage: "slider.horizontal.3")

                Toggle(isOn: $job.combineIntoSinglePDF) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Combine into single PDF")
                            .font(.callout)
                        Text("All records in one file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    CardLabel(title: "Email Delivery", systemImage: "paperplane")
                    Toggle("Send after merge", isOn: $sendAfterMerge)
                        .font(.callout)
                    TextField("Recipient (optional)", text: $emailRecipient)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    TextField("Subject", text: $emailSubject)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    TextEditor(text: $emailBody)
                        .font(.callout)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                }

                if let run {
                    mergeStatus(for: run)
                }
            }
        }
    }

    @ViewBuilder
    private func mergeStatus(for run: MergeRun) -> some View {
        if run.isActive {
            if run.progress.total == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(run.isCancelling ? "Stopping…" : "Loading data…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                Divider()
                    .padding(.vertical, 4)
                MergeProgressView(
                    current: run.progress.completed,
                    total: run.progress.total,
                    recordsPerSecond: run.recordsPerSecond,
                    estimatedTimeRemaining: run.estimatedTimeRemaining,
                    isStopping: run.isCancelling
                )
            }
        } else if let outcome = run.outcome {
            Divider()
                .padding(.vertical, 4)
            switch outcome {
            case .completed(let result):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))
                        Text("Merge complete")
                            .font(.callout)
                            .bold()
                    }
                    Text("\(result.recordCount) records in \(result.duration, format: .number.precision(.fractionLength(1)))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button {
                    emailMergeResult(result)
                } label: {
                    Label("Email Output", systemImage: "paperplane.fill")
                        .font(.callout)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(result.attachmentURL == nil)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .cancelled:
                Label("Merge cancelled.", systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Run Merge Card

    private var runMergeCard: some View {
        ConfigCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: "Run Merge", systemImage: "play.fill")
                Text(job.isConfigured
                    ? "All steps complete. Ready to generate your documents."
                    : "Complete all configuration steps before running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if job.isConfigured, unmappedFieldCount > 0 {
                    Label(
                        unmappedFieldCount == 1
                            ? "1 field isn't mapped and will be left blank."
                            : "\(unmappedFieldCount) fields aren't mapped and will be left blank.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let run, run.isActive {
                    Button {
                        run.cancel()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text(run.isCancelling ? "Stopping…" : "Cancel Merge")
                                .font(.callout)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(run.isCancelling)
                } else {
                    Button {
                        startMerge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Start Merge")
                                .font(.callout)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(job.isConfigured ? Color.mergeformBlue : .secondary)
                    .disabled(!job.isConfigured)
                }
            }
        }
    }

    // MARK: - Actions

    private func generatePreview() {
        loadPreview(at: currentRecordIndex)
    }

    private func loadPreview(at recordIndex: Int) {
        let targetIndex = max(recordIndex, 0)
        isGenerating = true
        Task {
            do {
                let result = try await services.mergeEngine.generatePreview(job: job, recordIndex: targetIndex)
                await MainActor.run {
                    previewData = result.data
                    totalRecordCount = result.totalRecords
                    currentRecordIndex = min(max(targetIndex, 0), max(result.totalRecords - 1, 0))
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isGenerating = false
                }
            }
        }
    }

    private func startMerge() {
        // Capture the email now: the merge can finish after this step is closed.
        let draft = sendAfterMerge ? emailDraft : nil
        mergeRuns.start(job: job, singleDocument: job.combineIntoSinglePDF, engine: services.mergeEngine) { result in
            if let draft {
                // Failures here can only be noticed when the step is open to show them.
                _ = Self.send(result, draft: draft)
            }
        }
    }

    private var hasPreview: Bool { previewData != nil }

    private var unmappedFieldCount: Int {
        job.fieldMappings.count - job.mappedFieldCount
    }

    private var emailDraft: EmailDraft {
        EmailDraft(recipient: emailRecipient, subject: emailSubject, body: emailBody)
    }

    private func emailMergeResult(_ result: MergeResult) {
        if let problem = Self.send(result, draft: emailDraft) {
            emailErrorMessage = problem
            showingEmailError = true
        }
    }

    /// Opens a new email with the merge's output attached. Returns a description of the
    /// problem when it can't.
    private static func send(_ result: MergeResult, draft: EmailDraft) -> String? {
        guard let attachmentURL = result.attachmentURL else {
            return "No output file is available to attach."
        }
        guard let service = NSSharingService(named: .composeEmail) else {
            return "No email sharing service is available."
        }
        service.recipients = draft.recipient.isEmpty ? [] : [draft.recipient]
        service.subject = draft.subject
        service.perform(withItems: [draft.body, attachmentURL])
        return nil
    }
}

private struct EmailDraft {
    var recipient: String
    var subject: String
    var body: String
}

// MARK: - Merge Progress View

private struct MergeProgressView: View {
    let current: Int
    let total: Int
    let recordsPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?
    let isStopping: Bool

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: percentage)
                        .stroke(
                            LinearGradient(
                                colors: [Color.mergeformBlue, Color.mergeformOrange.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: percentage)
                    
                    Text("\(Int(percentage * 100))%")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(Color.mergeformBlue)
                        .monospacedDigit()
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(current)")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("/ \(total)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Text("records processed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                if let recordsPerSecond {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 11))
                        Text("\(Int(recordsPerSecond)) rows/sec")
                            .font(.caption)
                            .bold()
                    }
                    .foregroundStyle(Color.mergeformOrange)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            
            VStack(spacing: 8) {
                ProgressView(value: percentage)
                    .tint(Color.mergeformOrange)
                    .animation(.spring(duration: 0.5), value: percentage)
                
                HStack {
                    if let estimatedTimeRemaining, estimatedTimeRemaining > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text(formatTimeRemaining(estimatedTimeRemaining))
                                .font(.caption)
                                .bold()
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Text(isStopping ? "Stopping…" : "Processing…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 12)
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        if rounded < 60 {
            return "\(rounded)s remaining"
        } else if rounded < 3600 {
            let minutes = rounded / 60
            let secs = rounded % 60
            return "\(minutes)m \(secs)s remaining"
        } else {
            let hours = rounded / 3600
            let minutes = (rounded % 3600) / 60
            return "\(hours)h \(minutes)m remaining"
        }
    }
}
