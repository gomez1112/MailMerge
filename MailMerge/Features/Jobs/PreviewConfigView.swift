import SwiftUI

struct PreviewConfigView: View {
    @Environment(\.services) private var services
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
                    systemImageName: "doc.plaintext",
                    value: "\(job.fieldMappings.count)",
                    label: "Fields"
                )
                StatCard(
                    systemImageName: "checkmark.circle",
                    value: "\(job.fieldMappings.filter { $0.isMapped }.count)",
                    label: "Mapped"
                )
                StatCard(
                    systemImageName: "tablecells",
                    value: "\(job.availableColumns.count)",
                    label: "Columns"
                )
            }

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
        .alert("Merge Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
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
                        .tint(.accentColor)
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
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isMerging ? "Merging…" : "Start Merge")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!job.isConfigured || isMerging)
                .tint(job.isConfigured ? .accentColor : .secondary)
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
}
