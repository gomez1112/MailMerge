import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif
#if canImport(AppKit)
import AppKit
#endif

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
    @State private var mergeResult: MergeResult?
    @State private var isMerging = false
    @State private var showingEmailComposer = false
    @State private var emailAttachment: EmailAttachment?
    @State private var showingEmailError = false
    @State private var emailErrorMessage = ""
    @State private var emailRecipient = ""
    @State private var emailSubject = "Merged Documents"
    @State private var emailBody = "Hi,\n\nAttached are the merged documents.\n\nThanks!"
    @State private var sendAfterMerge = false
#if canImport(UIKit)
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
#endif

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
#if canImport(MessageUI)
        .sheet(isPresented: $showingEmailComposer) {
            if let emailAttachment {
                MailComposeView(
                    attachment: emailAttachment,
                    recipient: emailRecipient,
                    subject: emailSubject,
                    body: emailBody
                )
            }
        }
#endif
#if canImport(UIKit)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: shareItems)
        }
#endif
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
                        .frame(minHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07))
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .frame(minHeight: 380)
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

                if mergeProgress.total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Merging…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(mergeProgress.current) / \(mergeProgress.total)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        ProgressView(
                            value: Double(mergeProgress.current),
                            total: Double(mergeProgress.total)
                        )
                        .progressViewStyle(.linear)
                        .tint(Color.mergeformBlue)
                    }
                }

                if let mergeResult {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 13))
                            Text("Merge complete")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text("\(mergeResult.recordCount) records in \(mergeResult.duration, format: .number.precision(.fractionLength(1)))s")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                    Button {
                        emailMergeResult(mergeResult)
                    } label: {
                        Label("Email Output", systemImage: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
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

                Button {
                    startMerge()
                } label: {
                    HStack(spacing: 8) {
                        if isMerging {
                            ProgressView().controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isMerging ? "Merging…" : "Start Merge")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(job.isConfigured ? Color.mergeformBlue : .secondary)
                .disabled(!job.isConfigured || isMerging)
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
        Task {
            do {
                let result = try await services.mergeEngine.performMerge(
                    job: job,
                    singleDocument: job.combineIntoSinglePDF
                ) { current, total in
                    mergeProgress = (current, total)
                }
                await MainActor.run {
                    mergeResult = result
                    isMerging = false
                    emailAttachment = makeEmailAttachment(from: result)
                    if sendAfterMerge {
                        emailMergeResult(result)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isMerging = false
                }
            }
        }
    }

    private var hasPreview: Bool { previewData != nil }

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
#if canImport(MessageUI)
        guard MFMailComposeViewController.canSendMail() else {
            shareItems = [emailSubject, emailBody, attachment.url]
            showingShareSheet = true
            return
        }
        emailAttachment = attachment
        showingEmailComposer = true
#elseif canImport(AppKit)
        let service = NSSharingService(named: .composeEmail)
        service?.recipients = emailRecipient.isEmpty ? [] : [emailRecipient]
        service?.subject = emailSubject
        service?.perform(withItems: [emailBody, attachment.url])
        if service == nil {
            emailErrorMessage = "No email sharing service is available."
            showingEmailError = true
        }
#else
        emailErrorMessage = "Email is not supported on this platform."
        showingEmailError = true
#endif
    }
}

private struct EmailAttachment {
    let url: URL
    let filename: String
    let mimeType: String
}

#if canImport(MessageUI)
private struct MailComposeView: UIViewControllerRepresentable {
    let attachment: EmailAttachment
    let recipient: String
    let subject: String
    let body: String

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        if !recipient.isEmpty {
            controller.setToRecipients([recipient])
        }
        controller.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachment.url) {
            controller.addAttachmentData(data, mimeType: attachment.mimeType, fileName: attachment.filename)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
        }
    }
}
#endif
