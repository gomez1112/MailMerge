import SwiftUI
import AppKit

struct PreviewConfigView: View {
    @Environment(\.services) private var services
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var job: MailMergeJob

    @State private var previewData: Data?
    @State private var isGenerating = false
    @State private var currentRecordIndex = 0
    @State private var totalRecordCount = 0
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var mergeProgress: (current: Int, total: Int) = (0, 0)
    @State private var mergeStartTime: Date?
    @State private var estimatedTimeRemaining: TimeInterval?
    @State private var mergeResult: MergeResult?
    @State private var isMerging = false
    @State private var showingEmailError = false
    @State private var emailErrorMessage = ""
    @State private var emailRecipient = ""
    @State private var emailSubject = "Merged Documents"
    @State private var emailBody = "Hi,\n\nAttached are the merged documents.\n\nThanks!"
    @State private var sendAfterMerge = false
    @State private var mergeProgressTracker: Progress?
    @State private var mergeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                    // PDF Preview pane
                    previewPane

                    // Run merge sidebar
                    VStack(spacing: 12) {
                        mergeSettingsCard
                        runMergeCard
                    }
                    .frame(width: 240)
                }
            }
        }
        }
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
                    .font(.system(size: 12))
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
                            .fill(Color.primary.opacity(0.03))
                            .frame(minHeight: 550)
                        VStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 36))
                                .foregroundStyle(.quaternary)
                            Text("Generate a preview to validate your merge.")
                                .font(.system(size: 13))
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
                .font(.system(size: 12))
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
                            .font(.system(size: 12))
                        Text("All records in one file")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    CardLabel(title: "Email Delivery", systemImage: "paperplane")
                    Toggle("Send after merge", isOn: $sendAfterMerge)
                        .font(.system(size: 12))
                    TextField("Recipient (optional)", text: $emailRecipient)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    TextField("Subject", text: $emailSubject)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    TextEditor(text: $emailBody)
                        .font(.system(size: 12))
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                }

                if isMerging && mergeProgress.total == 0 {
                    // Loading state before first progress update
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading data…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                if mergeProgress.total > 0 {
                    Divider()
                        .padding(.vertical, 4)
                    
                    MergeProgressView(
                        current: mergeProgress.current,
                        total: mergeProgress.total,
                        startTime: mergeStartTime,
                        estimatedTimeRemaining: estimatedTimeRemaining
                    )
                }

                if let mergeResult {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                            Text("Merge complete")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Text("\(mergeResult.recordCount) records in \(mergeResult.duration, format: .number.precision(.fractionLength(1)))s")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Button {
                        emailMergeResult(mergeResult)
                    } label: {
                        Label("Email Output", systemImage: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mergeResult.attachmentURL == nil)
                }
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if isMerging {
                    Button {
                        cancelMerge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Cancel Merge")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        startMerge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Start Merge")
                                .font(.system(size: 13, weight: .semibold))
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
        mergeProgress = (0, 0)
        mergeResult = nil
        isMerging = true
        mergeStartTime = Date()
        estimatedTimeRemaining = nil
        
        // Create NSProgress for cancellation support
        let progressTracker = Progress(totalUnitCount: 100)
        progressTracker.localizedDescription = "Merging documents"
        mergeProgressTracker = progressTracker
        
        let task = Task {
            do {
                let result = try await services.mergeEngine.performMerge(
                    job: job,
                    singleDocument: job.combineIntoSinglePDF,
                    progress: { current, total in
                        mergeProgress = (current, total)
                        
                        // Calculate estimated time remaining
                        if let startTime = mergeStartTime, current > 0 {
                            let elapsed = Date().timeIntervalSince(startTime)
                            let rate = Double(current) / elapsed
                            let remaining = Double(total - current) / rate
                            estimatedTimeRemaining = remaining
                        }
                    },
                    nsProgress: progressTracker
                )
                await MainActor.run {
                    mergeResult = result
                    isMerging = false
                    mergeProgressTracker = nil
                    mergeTask = nil
                    if sendAfterMerge {
                        emailMergeResult(result)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    errorMessage = "Merge operation was cancelled"
                    showingErrorAlert = true
                    isMerging = false
                    mergeProgressTracker = nil
                    mergeTask = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isMerging = false
                    mergeProgressTracker = nil
                    mergeTask = nil
                }
            }
        }
        mergeTask = task
    }

    private var hasPreview: Bool { previewData != nil }
    
    private func cancelMerge() {
        mergeProgressTracker?.cancel()
        mergeTask?.cancel()
        mergeProgress = (0, 0)
        isMerging = false
        mergeProgressTracker = nil
        mergeTask = nil
    }

    private func makeEmailAttachment(from result: MergeResult) -> EmailAttachment? {
        guard let url = result.attachmentURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let mimeType = ext == "zip" ? "application/zip" : "application/pdf"
        return EmailAttachment(
            url: url,
            filename: url.lastPathComponent,
            mimeType: mimeType
        )
    }

    private func emailMergeResult(_ result: MergeResult) {
        guard let attachment = makeEmailAttachment(from: result) else {
            emailErrorMessage = "No output file is available to attach."
            showingEmailError = true
            return
        }
        let service = NSSharingService(named: .composeEmail)
        service?.recipients = emailRecipient.isEmpty ? [] : [emailRecipient]
        service?.subject = emailSubject
        service?.perform(withItems: [emailBody, attachment.url])
        if service == nil {
            emailErrorMessage = "No email sharing service is available."
            showingEmailError = true
        }
    }
}

private struct EmailAttachment {
    let url: URL
    let filename: String
    let mimeType: String
}

// MARK: - Merge Progress View

private struct MergeProgressView: View {
    let current: Int
    let total: Int
    let startTime: Date?
    let estimatedTimeRemaining: TimeInterval?
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    private var rowsPerSecond: Double? {
        guard let startTime, current > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0 else { return nil }
        return Double(current) / elapsed
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Circular progress centered
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.mergeformBlue)
                        .monospacedDigit()
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(current)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("/ \(total)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Text("records processed")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                
                if let rowsPerSecond {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 11))
                        Text("\(Int(rowsPerSecond)) rows/sec")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.mergeformOrange)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Progress bar
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.mergeformBlue, Color.mergeformOrange.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * percentage, height: 8)
                            .animation(.spring(duration: 0.5), value: percentage)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    if let estimatedTimeRemaining, estimatedTimeRemaining > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text(formatTimeRemaining(estimatedTimeRemaining))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Text("Processing…")
                        .font(.system(size: 11))
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
