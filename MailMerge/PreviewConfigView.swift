import SwiftUI

struct PreviewConfigView: View {
    @Environment(\.services) private var services
    @Bindable var job: MailMergeJob

    @State private var previewData: Data?
    @State private var isGenerating = false
    @State private var currentRecordIndex = 0
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var mergeProgress: (current: Int, total: Int) = (0, 0)
    @State private var mergeResult: MergeResult?
    @State private var combineIntoSinglePDF = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(
                title: "Preview",
                subtitle: "Review the generated PDF before running the full merge.",
                systemImageName: "doc.richtext"
            )

            HStack(spacing: 16) {
                StatCard(systemImageName: "doc.plaintext", value: "\(job.fieldMappings.count)", label: "Fields")
                StatCard(systemImageName: "checkmark.circle", value: "\(job.fieldMappings.filter { $0.isMapped }.count)", label: "Mapped")
                StatCard(systemImageName: "tablecells", value: "\(job.availableColumns.count)", label: "Columns")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    if let previewData {
                        PDFPreviewView(data: previewData)
                            .frame(height: 360)
                    } else {
                        Text("Generate a preview PDF to validate the merge.")
                            .foregroundStyle(.secondary)
                            .frame(height: 360)
                            .frame(maxWidth: .infinity)
                    }

                    HStack {
                        Button("Previous") {
                            currentRecordIndex = max(currentRecordIndex - 1, 0)
                        }
                        .disabled(currentRecordIndex == 0)
                        Text("Record \(currentRecordIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Next") {
                            currentRecordIndex += 1
                        }
                        Spacer()
                        Button("Generate Preview") {
                            generatePreview()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating)
                    }
                }
                .padding(16)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Combine into single PDF", isOn: $combineIntoSinglePDF)
                    if mergeProgress.total > 0 {
                        ProgressView(value: Double(mergeProgress.current), total: Double(mergeProgress.total))
                        Text("Merging record \(mergeProgress.current) of \(mergeProgress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let mergeResult {
                        Text("Completed \(mergeResult.recordCount) records in \(mergeResult.duration, format: .number.precision(.fractionLength(1)))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Start Merge") {
                        startMerge()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!job.isConfigured)
                }
                .padding(16)
            }
            Spacer()
        }
        .alert("Merge Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func generatePreview() {
        isGenerating = true
        Task {
            defer {
                Task { @MainActor in
                    isGenerating = false
                }
            }
            do {
                let data = try await services.mergeEngine.generatePreview(job: job)
                await MainActor.run {
                    previewData = data
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }

    private func startMerge() {
        mergeProgress = (0, 0)
        mergeResult = nil
        Task {
            do {
                let result = try await services.mergeEngine.performMerge(job: job, singleDocument: combineIntoSinglePDF) { current, total in
                    mergeProgress = (current, total)
                }
                mergeResult = result
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
}
