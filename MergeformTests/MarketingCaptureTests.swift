#if DEBUG
import AppKit
import StoreKit
import StoreKitTest
import SwiftData
import SwiftUI
import Testing
@testable import Mergeform

/// Opt-in visual fixture, never included in the shipping app. The companion capture
/// script saves actual windows while this harness navigates through their real controls.
@MainActor
@Suite("Marketing captures", .serialized, .enabled(if: ProcessInfo.processInfo.environment["MERGEFORM_MARKETING_CAPTURES"] == "1"))
struct MarketingCaptureTests {
    @Test("Capture the six App Store screens with fictional data")
    func captureScreens() async throws {
        let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let bundle = Bundle(for: MarketingResources.self)
        let templateResource = try #require(bundle.url(forResource: "Thank You Letter", withExtension: "docx"))
        let dataResource = try #require(bundle.url(forResource: "Customers", withExtension: "xlsx"))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Security-scoped bookmarks should reference ordinary files, not resources
        // nested inside Bitrig's temporary, signed test host bundle.
        let template = directory.appending(path: "Thank You Letter.docx")
        let data = directory.appending(path: "Customers.xlsx")
        try FileManager.default.copyItem(at: templateResource, to: template)
        try FileManager.default.copyItem(at: dataResource, to: data)
        let output = directory.appending(path: "Order confirmations", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = MergeFixture.makeEngine()
        let dataBookmark = try SecurityScopedAccess.makeBookmark(for: data)
        let templateBookmark = try SecurityScopedAccess.makeBookmark(for: template)
        let headers = try await engine.getColumnHeaders(bookmarkData: dataBookmark, sheetName: "Customers")
        let work = Mergeform.Category(name: "Work", systemImageName: "briefcase", colorName: "purple", sortOrder: 1)
        let events = Mergeform.Category(name: "Events", systemImageName: "calendar", colorName: "green", sortOrder: 2)
        context.insert(work)
        context.insert(events)

        let job = try await engine.createJobFromTemplate(bookmark: templateBookmark, fileName: "Thank You Letter.docx", category: work, in: context)
        job.name = "Order confirmations"
        job.dataSourceBookmarkData = dataBookmark
        job.dataSourceFileName = "Customers.xlsx"
        job.availableSheets = ["Customers", "Events"]
        job.selectedSheetName = "Customers"
        job.updateAvailableColumns(headers)
        job.autoMatchUnmappedFields()
        job.outputFolderBookmarkData = try SecurityScopedAccess.makeBookmark(for: output)
        job.outputFolderName = "Order confirmations"
        job.outputFileNamePattern = "ThankYou_{FirstName}_{LastName}"
        job.status = .configured

        for (name, category, paragraphs) in [
            ("Customer welcome letters", work, ["Welcome, {{First Name}}!", "We’re glad to be working with {{Company}}."]),
            ("Autumn launch invitations", events, ["You’re invited, {{First Name}}.", "Join us for an evening of new ideas."])
        ] {
            let url = try DOCXFixture(paragraphs: paragraphs).write()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let copy = directory.appending(path: name + ".docx")
            try FileManager.default.copyItem(at: url, to: copy)
            let other = try await engine.createJobFromTemplate(bookmark: SecurityScopedAccess.makeBookmark(for: copy), fileName: copy.lastPathComponent, category: category, in: context)
            other.name = name
            other.status = .draft
        }
        try context.save()
        let runs = MergeRunStore()
        let run = try #require(runs.start(job: job, singleDocument: false, engine: engine))
        await run.waitUntilFinished()
        guard case .completed = run.outcome else { Issue.record("Demo merge failed"); return }

        let purchases = PurchaseStore()
        let storeConfig = try #require(Bundle.main.url(forResource: "Mergeform", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: storeConfig)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { purchases.stop(); session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MailMergeProductIDs.lifetimePurchase)
        _ = try await purchases.completePurchase(.success(.verified(transaction)))

        let suite = "MergeformMarketing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let presentation = MarketingPresentation(jobID: job.id)
        let root = MainTabView()
            .modelContainer(container)
            .environment(purchases)
            .environment(runs)
            .environment(\.services, ServiceContainer.shared)
            .environment(\.usesDemoFeatureRequests, true)
            .environment(\.marketingPresentation, presentation)
            .defaultAppStorage(defaults)
            .preferredColorScheme(.light)
        let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 1440, height: 900), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: root.frame(width: 1440, height: 900))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.center()
        defer { window.orderOut(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        try await Task.sleep(for: .seconds(2))
        let selection = ProcessInfo.processInfo.environment["MERGEFORM_MARKETING_SECTION"] ?? "all"
        let screens: [MarketingPresentation.Screen] = selection == "library" ? [.templates, .requests] : [.jobs, .mapping, .data, .run, .templates, .requests]
        for screen in screens {
            presentation.screen = screen
            try await stage(screen.rawValue, in: window)
        }
    }

    private func stage(_ name: String, in window: NSWindow) async throws {
        // Allow SwiftUI layout and loading to settle before making the stage visible to
        // the external screen-capture process. This is an opt-in visual workflow.
        try await Task.sleep(for: .seconds(2))
        window.title = "MergeformShot:\(name)"
        window.displayIfNeeded()
        try await Task.sleep(for: .seconds(5))
        window.title = "MergeformShot:transition"
    }


}

private final class MarketingResources: NSObject { }
#endif
