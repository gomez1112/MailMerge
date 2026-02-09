import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MailMergeJob.modifiedAt, order: .reverse) private var jobs: [MailMergeJob]
    @State private var searchText = ""
    @State private var selectedCategory: JobCategory?
    @State private var selectedJob: MailMergeJob?

    private var filteredJobs: [MailMergeJob] {
        guard let selectedCategory else { return [] }
        let categoryJobs = jobs.filter { ($0.category ?? .uncategorized) == selectedCategory }
        guard !searchText.isEmpty else { return categoryJobs }
        return categoryJobs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var jobCountsByCategory: [JobCategory: Int] {
        Dictionary(grouping: jobs, by: { $0.category ?? .uncategorized })
            .mapValues { $0.count }
    }

    var body: some View {
        NavigationSplitView(
            sidebar: {
                UnifiedSidebarView(
                    selectedCategory: $selectedCategory,
                    selectedJob: $selectedJob,
                    searchText: $searchText,
                    jobCountsByCategory: jobCountsByCategory,
                    filteredJobs: filteredJobs,
                    onCreate: createJob,
                    onDelete: deleteJobs
                )
            },
            detail: {
                if let job = selectedJob {
                    JobDetailView(job: job)
                } else {
                    JobEmptyStateView(onCreate: createJob)
                }
            }
        )
        .onAppear(perform: applyCategoryMigrationIfNeeded)
        .onChange(of: selectedCategory) { _, _ in
            syncSelection()
        }
        .onChange(of: searchText) { _, _ in
            syncSelection()
        }
        .onChange(of: jobs.count) { _, _ in
            syncSelection()
        }
        .onDeleteCommand {
            if let selectedJob, let index = filteredJobs.firstIndex(where: { $0.id == selectedJob.id }) {
                deleteJobs(at: IndexSet(integer: index))
            }
        }
    }

    private func createJob() {
        let category = selectedCategory ?? .uncategorized
        let job = MailMergeJob(name: "New Mail Merge", category: category)
        modelContext.insert(job)
        selectedJob = job
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            let job = filteredJobs[index]
            modelContext.delete(job)
        }
        syncSelection()
    }

    private func applyCategoryMigrationIfNeeded() {
        // Migration: Set default category for existing jobs
        for job in jobs where job.category == nil {
            job.category = .uncategorized
        }
        if selectedCategory == nil {
            selectedCategory = jobs.first?.category ?? .uncategorized
        }
        syncSelection()
    }

    private func syncSelection() {
        if selectedCategory == nil {
            selectedCategory = jobs.first?.category ?? .uncategorized
        }
        if let selectedJob, filteredJobs.contains(where: { $0.id == selectedJob.id }) {
            return
        }
        selectedJob = filteredJobs.first
    }
}

private struct UnifiedSidebarView: View {
    @Binding var selectedCategory: JobCategory?
    @Binding var selectedJob: MailMergeJob?
    @Binding var searchText: String
    let jobCountsByCategory: [JobCategory: Int]
    let filteredJobs: [MailMergeJob]
    let onCreate: () -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        List(selection: $selectedJob) {
            Section {
                ForEach(JobCategory.allCases) { category in
                    DisclosureGroup(isExpanded: .constant(selectedCategory == category)) {
                        let categoryJobs = filteredJobs.filter { ($0.category ?? .uncategorized) == category }
                        if categoryJobs.isEmpty {
                            Text("No jobs")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(categoryJobs) { job in
                                JobRowView(job: job)
                                    .tag(job as MailMergeJob?)
                            }
                            .onDelete { offsets in
                                onDelete(offsets)
                            }
                        }
                    } label: {
                        Label(category.label, systemImage: category.systemImageName)
                            .badge(jobCountsByCategory[category, default: 0])
                    }
                    .onTapGesture {
                        selectedCategory = category
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mail Merge")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Label("New Job", systemImage: "plus")
                }
                .help("Create New Job")
                .accessibilityLabel("Create New Job")
                .accessibilityHint("Creates a new mail merge job in the selected category")
            }
        }
    }
}





private struct JobRowView: View {
    let job: MailMergeJob
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.body)
                Text("Updated \(job.modifiedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: job.status)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.name), \(job.status.label), Updated \(job.modifiedAt, format: .relative(presentation: .named))")
        .accessibilityHint("Double-tap to view and edit this job")
    }
}

private struct JobEmptyStateView: View {
    let onCreate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Job Selected", systemImage: "doc.text")
        } description: {
            Text("Select a job from the sidebar or create a new one")
        } actions: {
            Button("New Job", action: onCreate)
                .keyboardShortcut("n", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MailMergeJob.self, inMemory: true)
}
