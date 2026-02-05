import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @State private var searchText = ""
    @State private var selectedJob: MailMergeJob?
    @State private var showingNewJobSheet = false

    private var filteredJobs: [MailMergeJob] {
        guard !searchText.isEmpty else { return jobs }
        return jobs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                jobs: filteredJobs,
                searchText: $searchText,
                selectedJob: $selectedJob,
                onCreate: createJob,
                onDelete: deleteJobs
            )
        } detail: {
            if let job = selectedJob {
                JobDetailView(job: job)
            } else {
                EmptyStateView(onCreate: createJob)
            }
        }
        .onAppear {
            if selectedJob == nil {
                selectedJob = jobs.first
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createJob) {
                    Label("New Job", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private func createJob() {
        let job = MailMergeJob(name: "New Mail Merge")
        modelContext.insert(job)
        selectedJob = job
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            let job = filteredJobs[index]
            modelContext.delete(job)
        }
        if selectedJob != nil, jobs.isEmpty {
            selectedJob = nil
        }
    }
}

private struct SidebarView: View {
    let jobs: [MailMergeJob]
    @Binding var searchText: String
    @Binding var selectedJob: MailMergeJob?
    let onCreate: () -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mail Merge")
                    .font(.title3.bold())
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            List(selection: $selectedJob) {
                ForEach(jobs) { job in
                    HStack(spacing: 12) {
                        FileIconView(systemImageName: "doc.richtext", color: .accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.name)
                                .font(.headline)
                            Text(job.modifiedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: job.status)
                    }
                    .tag(job as MailMergeJob?)
                }
                .onDelete(perform: onDelete)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar)
        }
    }
}

private struct EmptyStateView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Create your first mail merge job")
                .font(.title2.bold())
            Text("Combine a DOCX template and Excel data to produce personalized PDFs.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("New Job", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MailMergeJob.self, inMemory: true)
}
