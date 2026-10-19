import OSLog
import SwiftUI
import SwiftData
import OnboardingKit
import StoreKit
import AppKit

// MARK: - Focused Values

/// Focused values that expose context-sensitive actions to menu commands.
///
/// The focused window and the job it shows publish command objects up the focus chain,
/// so `MailMergeCommands` can run them from the File and Job menus. When no view
/// supplies one, the matching menu items are disabled.
///
/// ## Publishing commands from a focused view
/// ```swift
/// jobContent
///     .focusedSceneValue(\.jobCommands, FocusedJobCommands(jobID: job.id, router: jobCommandRouter))
/// ```
extension FocusedValues {
    /// Rename and delete for the job shown in the focused window, for the Job menu's
    /// Rename Job (⌘R) and Delete Job (⌘⌫). Nil when no job is shown.
    @Entry var jobCommands: FocusedJobCommands? = nil

    /// Window-level actions, such as New Job (⌘N) in the File menu. Nil when no
    /// Mergeform window is focused.
    @Entry var windowCommands: FocusedWindowCommands? = nil
}

// MARK: - App Entry Point

@main
struct MailMergeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadError: Error?
    @State private var mergeRuns = MergeRunStore()
    @State private var purchases = PurchaseStore()
    private let container: ModelContainer?

    init() {
        let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
        // Hosted tests must not open the user's database or start a second StoreKit
        // listener that competes with the test's isolated store.
        let configuration = Self.isTesting
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: Self.storeURL())
        do {
            let modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: MailMergeMigrationPlan.self,
                configurations: [configuration]
            )
            container = modelContainer
            Self.resetInterruptedRuns(in: modelContainer)
        } catch {
            if let fallbackContainer = try? ModelContainer(
                for: schema,
                configurations: [configuration]
            ) {
                container = fallbackContainer
                Self.resetInterruptedRuns(in: fallbackContainer)
            } else {
                container = nil
                _loadError = State(initialValue: error)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// A merge can't still be running at launch, so a job marked "Running" was
    /// interrupted by a quit or crash.
    private static func resetInterruptedRuns(in container: ModelContainer) {
        do {
            try MailMergeJob.resetInterruptedRuns(in: container.mainContext)
        } catch {
            // The jobs keep their "Running" badge until they're run again; nothing
            // else depends on it, so launching continues.
            Logger(subsystem: "com.transfinite.MailMerge", category: "Persistence")
                .error("Couldn't reset interrupted merges: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            if let container {
                OnboardingWrapper(
                    appName: "Mergeform",
                    currentVersion: appVersion,
                    pages: OnboardingPage.mailMergePages,
                    features: FeatureItem.mailMergeFeatures,
                    tint: .mergeformBlue
                ) {
                    MainTabView()
                        .modelContainer(container)
                        .environment(mergeRuns)
                        .environment(\.services, ServiceContainer.shared)
                        .environment(purchases)
                        .frame(minWidth: 1200, idealWidth: 1400, maxWidth: 1800, minHeight: 740, idealHeight: 840)
                        .task(id: scenePhase) {
                            guard !Self.isTesting, scenePhase == .active else { return }
                            await purchases.waitUntilChecked()
                            await purchases.refresh()
                        }
                }
            } else {
                ContentUnavailableView {
                    Label("Unable to Load Data", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The app couldn't open its data store. Please restart the app or contact support.")
                } actions: {
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .frame(minWidth: 680, idealWidth: 820, minHeight: 420, idealHeight: 520)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ToolbarCommands()
            SidebarCommands()
            MailMergeCommands()
        }

        Settings {
            AppSettingsView()
                .environment(purchases)
                .task(id: scenePhase) {
                            guard !Self.isTesting, scenePhase == .active else { return }
                            await purchases.waitUntilChecked()
                            await purchases.refresh()
                        }
        }
    }

    private static var isTesting: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let folderURL = appSupport[0].appending(path: "MailMerge", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL.appending(path: "MailMerge.sqlite")
    }
}

// MARK: - Commands

struct MailMergeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.jobCommands) private var jobCommands: FocusedJobCommands?
    @FocusedValue(\.windowCommands) private var windowCommands: FocusedWindowCommands?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Job") {
                windowCommands?.newJob()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(windowCommands == nil)
        }

        CommandMenu("Job") {
            Button("Rename Job") {
                jobCommands?.rename()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(jobCommands == nil)

            Divider()

            Button("Delete Job") {
                let isKeyEquivalent = NSApp.currentEvent?.type == .keyDown
                if TextEditingShortcut.forwardsDeleteToText(responder: NSApp.keyWindow?.firstResponder, isKeyEquivalent: isKeyEquivalent) {
                    return
                }
                jobCommands?.delete()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(jobCommands == nil)
        }
    }
}

// MARK: - App Settings View

struct AppSettingsView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.openURL) private var openURL
    @AppStorage("defaultOutputPattern") private var defaultOutputPattern = "Letter_{FirstName}_{LastName}"
    @AppStorage("showRelativeDates") private var showRelativeDates = true
    @AppStorage("autoMatchFields") private var autoMatchFields = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage = ""
    @State private var showingRestoreMessage = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            mergeTab
                .tabItem { Label("Merge", systemImage: "document.on.document") }
            subscriptionTab
                .tabItem { Label("Subscription", systemImage: "star.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 320)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show relative dates in job list", isOn: $showRelativeDates)
                Toggle("Confirm before deleting jobs", isOn: $confirmBeforeDelete)
            }
        }
        .formStyle(.grouped)
    }

    private var mergeTab: some View {
        Form {
            Section {
                Toggle("Auto-match fields by name", isOn: $autoMatchFields)
            }
            Section("Default Output Filename Pattern") {
                TextField("Pattern", text: $defaultOutputPattern)
                    .font(.system(.body, design: .monospaced))
                Text("Use {ColumnName} as placeholders. Example: Letter_{FirstName}_{LastName}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var subscriptionTab: some View {
        Form {
            Section("Plan") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        switch purchases.access {
                        case .unknown:
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking…")
                                .foregroundStyle(.secondary)
                        case .pro(let source):
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(source == .lifetime ? "Pro (Lifetime)" : "Pro")
                                .foregroundStyle(.primary)
                        case .free:
                            Text("Free")
                                .foregroundStyle(.secondary)
                            Button("Upgrade to Pro") {
                                showingPaywall = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                if let renewal = purchases.renewal {
                    LabeledContent("Renewal", value: renewal.description)
                }
            }
            Section("Manage") {
                Button("Manage Subscriptions") {
                    openURL(MergeformLinks.manageSubscriptions)
                }
                Button(isRestoring ? "Restoring…" : "Restore Purchases", action: restorePurchases)
                    .disabled(isRestoring)
            }
            .buttonStyle(.bordered)
            Section("Legal") {
                Link("Privacy Policy", destination: MergeformLinks.privacyPolicy)
                Link("Terms of Use", destination: MergeformLinks.termsOfUse)
            }
        }
        .formStyle(.grouped)
        .alert("Restore Purchases", isPresented: $showingRestoreMessage) {
            Button("OK") { }
        } message: {
            Text(restoreMessage)
        }
    }

    private func restorePurchases() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await purchases.restorePurchases()
                restoreMessage = purchases.hasProAccess
                    ? "Your purchases have been restored."
                    : "No purchases were found for this Apple Account."
            } catch StoreKitError.userCancelled {
                return
            } catch {
                restoreMessage = error.localizedDescription
            }
            showingRestoreMessage = true
        }
    }

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AppIconImage(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mergeform")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                LabeledContent("Developer", value: "Gerard Gomez")
                Link("Send Feedback", destination: URL(string: "mailto:gerardgomez11@outlook.com")!)
            }
        }
        .formStyle(.grouped)
    }
}
