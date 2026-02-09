import SwiftUI
import SwiftData

@main
struct MailMergeApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([MailMergeJob.self, FieldMapping.self])
        container = try! ModelContainer(for: schema)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(\.services, ServiceContainer.shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ToolbarCommands()
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Divider()
            }
        }
    }
}
