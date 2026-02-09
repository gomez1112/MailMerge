import SwiftUI
import SwiftData

@main
struct MailMergeApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([MailMergeJob.self, FieldMapping.self, Category.self])
        let storeURL = Self.storeURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            try? FileManager.default.removeItem(at: storeURL)
            container = try! ModelContainer(for: schema, configurations: [configuration])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(\.services, ServiceContainer.shared)
                .frame(minWidth: 980, idealWidth: 1160, maxWidth: 1400, minHeight: 680, idealHeight: 760)
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

    private static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let folderURL = appSupport[0].appendingPathComponent("MailMerge", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL.appendingPathComponent("MailMerge.sqlite")
    }
}
