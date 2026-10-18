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
        VStack(alignment: .leading, spacing: Metrics.section) {
            SectionHeader(
                title: "Preview & Run",
                subtitle: "Check a sample document, then create every PDF.",
                systemImageName: "play.rectangle",
                iconColor: .green
            )

            HStack(spacing: Metrics.regular) {
                StatCard(
                    systemImageName: "text.badge.checkmark",
                    value: job.fieldMappings.count.formatted(.number),
                    label: "Fields",
                    iconColor: .mergeformBlue
                )
                .revealOnAppear(order: 0)
                StatCard(
                    systemImageName: "checkmark.circle.fill",
                    value: job.mappedFieldCount.formatted(.number),
                    label: "Mapped",
                    iconColor: .green
                )
                .revealOnAppear(order: 1)
                StatCard(
                    systemImageName: "tablecells.fill",
                    value: job.availableColumns.count.formatted(.number),
                    label: "Columns",
                    iconColor: .mergeformOrange
                )
                .revealOnAppear(order: 2)
            }

            Group {
                if horizontalSizeClass == .compact {
                    VStack(spacing: Metrics.regular) {
                        runMergeCard
                        previewPane
                        mergeSettingsCard
                    }
                } else {
                    HStack(alignment: .top, spacing: Metrics.regular) {
                        previewPane
                        VStack(spacing: Metrics.regular) {
                            runMergeCard
                            mergeSettingsCard
                        }
                        .frame(width: 300)
                    }
                }
            }
            .revealOnAppear(order: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Preview Error", isPresented: $showingErrorAlert) {
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
                    CardLabel(title: "Sample Document", systemImage: "doc.richtext")
                    Spacer()
                    if hasPreview {
                        Button {
                            generatePreview()
                        } label: {
                            Label(isGenerating ? "Updating…" : "Refresh", systemImage: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: isGenerating)
                        }
                        .disabled(isGenerating)
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                    if let previewData {
                        PDFPreviewView(data: previewData)
                            .clipShape(.rect(cornerRadius: Metrics.tileRadius))
                            .transition(.opacity)
                    } else {
                        VStack(spacing: Metrics.regular) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(Color.mergeformBlue.gradient)
                                .symbolEffect(.breathe, isActive: isGenerating)
                            VStack(spacing: 4) {
                                Text("See a merged document before you run")
                                    .font(.headline)
                                Text("The preview fills the template with one row of your data.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            Button {
                                generatePreview()
                            } label: {
                                Label(isGenerating ? "Generating…" : "Generate Preview", systemImage: "eye")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)
                        }
                        .padding(Metrics.section)
                        .transition(.opacity)
                    }
                }
                .frame(minHeight: 560)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                        .strokeBorder(Color.mergeformStroke)
                }

                if hasPreview {
                    recordNavigation
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .motion(Motion.standard, value: hasPreview)
        }
    }

    private var recordNavigation: some View {
        HStack(spacing: Metrics.compact) {
            Button("Previous Record", systemImage: "chevron.left") {
                loadPreview(at: currentRecordIndex - 1)
            }
            .labelStyle(.iconOnly)
            .disabled(isGenerating || currentRecordIndex == 0)

            Text("Record \(currentRecordIndex + 1) of \(max(totalRecordCount, 1))")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(currentRecordIndex)))
                .frame(maxWidth: .infinity)

            Button("Next Record", systemImage: "chevron.right") {
                loadPreview(at: currentRecordIndex + 1)
            }
            .labelStyle(.iconOnly)
            .disabled(isGenerating || currentRecordIndex >= max(totalRecordCount - 1, 0))
        }
        .buttonStyle(.bordered)
        .motion(Motion.quick, value: currentRecordIndex)
    }

    // MARK: - Run Merge Card

    private var runMergeCard: some View {
        ConfigCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(title: "Run Merge", systemImage: "play.fill")

                if let run, run.isActive {
                    mergeProgress(for: run)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    Button(role: .cancel) {
                        run.cancel()
                    } label: {
                        Label(run.isCancelling ? "Stopping…" : "Cancel Merge", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(run.isCancelling)
                } else {
                    if let outcome = run?.outcome {
                        mergeOutcome(outcome)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else {
                        Text(job.isConfigured
                            ? "Everything is set. Create a PDF for every row in your sheet."
                            : "Finish the setup steps to run the merge.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if job.isConfigured, unmappedFieldCount > 0 {
                        Label(
                            unmappedFieldCount == 1
                                ? "1 field isn't mapped and will be left blank."
                                : "\(unmappedFieldCount) fields aren't mapped and will be left blank.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.mergeformOrange)
                    }

                    Button {
                        startMerge()
                    } label: {
                        Label(run?.outcome == nil ? "Start Merge" : "Run Again", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!job.isConfigured)
                }
            }
            .motion(Motion.standard, value: run?.isActive)
        }
    }

    @ViewBuilder
    private func mergeProgress(for run: MergeRun) -> some View {
        if run.progress.total == 0 {
            HStack(spacing: Metrics.compact) {
                ProgressView()
                    .controlSize(.small)
                Text(run.isCancelling ? "Stopping…" : "Reading your data…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Metrics.tight)
        } else {
            MergeProgressView(
                current: run.progress.completed,
                total: run.progress.total,
                recordsPerSecond: run.recordsPerSecond,
                estimatedTimeRemaining: run.estimatedTimeRemaining,
                isStopping: run.isCancelling
            )
        }
    }

    @ViewBuilder
    private func mergeOutcome(_ outcome: MergeRun.Outcome) -> some View {
        switch outcome {
        case .completed(let result):
            VStack(spacing: Metrics.compact) {
                CompletionMark()
                Text("Merge complete")
                    .font(.headline)
                Text("\(result.recordCount.formatted(.number)) documents in \(Duration.seconds(result.duration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, fractionalPart: .show(length: 1))))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    emailMergeResult(result)
                } label: {
                    Label("Email Output", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(result.attachmentURL == nil)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.tight)
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

    // MARK: - Merge Settings Card

    private var mergeSettingsCard: some View {
        ConfigCard {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: "Settings", systemImage: "slider.horizontal.3")
                Toggle(isOn: $job.combineIntoSinglePDF) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Combine into a single PDF")
                        Text("Every record in one document")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $sendAfterMerge) {
                    Text("Email after merging")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                if sendAfterMerge {
                    VStack(alignment: .leading, spacing: Metrics.tight) {
                        TextField("Recipient (optional)", text: $emailRecipient)
                        TextField("Subject", text: $emailSubject)
                        TextEditor(text: $emailBody)
                            .font(.body)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
                    }
                    .textFieldStyle(.roundedBorder)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .motion(Motion.standard, value: sendAfterMerge)
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

/// A merge in progress: a ring that fills as records are written, with the count, the
/// rate, and the time left.
private struct MergeProgressView: View {
    let current: Int
    let total: Int
    let recordsPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?
    let isStopping: Bool

    private var fraction: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }

    private var detail: String {
        if isStopping { return "Stopping…" }
        var parts: [String] = []
        if let recordsPerSecond {
            parts.append("\(recordsPerSecond.formatted(.number.precision(.fractionLength(0)))) per second")
        }
        if let estimatedTimeRemaining, estimatedTimeRemaining >= 1 {
            let remaining = Duration.seconds(estimatedTimeRemaining.rounded())
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
            parts.append("about \(remaining) left")
        }
        return parts.isEmpty ? "Working…" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressRing(progress: fraction, size: 96, lineWidth: 8, tint: isStopping ? .secondary : .mergeformBlue)
            VStack(spacing: 2) {
                Text("\(current.formatted(.number)) of \(total.formatted(.number))")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(current)))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.tight)
        .motion(Motion.standard, value: current)
        .accessibilityElement(children: .combine)
    }
}

/// A checkmark that draws itself in when a merge completes.
private struct CompletionMark: View {
    @State private var isDrawn = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(.green)
            .symbolEffect(.drawOn, isActive: !isDrawn)
            .symbolEffect(.bounce, value: isDrawn)
            .onAppear { isDrawn = true }
            .accessibilityHidden(true)
    }
}
