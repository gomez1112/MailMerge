import SwiftUI
import SwiftData
import OnboardingKit
import FlexStore
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let createNewJob = Notification.Name("com.mailmerge.createNewJob")
}

// MARK: - Focused Values

extension FocusedValues {
    @Entry var selectedJobID: UUID? = nil
    @Entry var deleteJobAction: (() -> Void)? = nil
    @Entry var renameJobAction: (() -> Void)? = nil
}

// MARK: - App Entry Point

@main
struct MailMergeApp: App {
    @State private var loadError: Error?
    private let container: ModelContainer?
    private let store = StoreKitService<MailMergeTier>()

    init() {
        let schema = Schema(versionedSchema: MailMergeSchemaV3.self)
        let storeURL = Self.storeURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: MailMergeMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            if let fallbackContainer = try? ModelContainer(
                for: schema,
                configurations: [configuration]
            ) {
                container = fallbackContainer
            } else {
                container = nil
                _loadError = State(initialValue: error)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                OnboardingWrapper(
                    appName: "Mergeform",
                    currentVersion: appVersion,
                    pages: OnboardingPage.mailMergePages,
                    features: FeatureItem.mailMergeFeatures,
                    tint: .accentColor
                ) {
                    MainTabView()
                        .modelContainer(container)
                        .environment(\.services, ServiceContainer.shared)
#if os(macOS)
                        .frame(minWidth: 1200, idealWidth: 1400, maxWidth: 1800, minHeight: 740, idealHeight: 840)
#endif
                        .attachStoreKit(
                            manager: store,
                            groupID: MailMergeProductIDs.subscriptionGroupID,
                            ids: MailMergeProductIDs.all
                        )
                }
            } else {
                ContentUnavailableView {
                    Label("Unable to Load Data", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The app couldn't open its data store. Please restart the app or contact support.")
                } actions: {
#if os(macOS)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
#endif
                }
#if os(macOS)
                .frame(minWidth: 680, idealWidth: 820, minHeight: 420, idealHeight: 520)
#endif
            }
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ToolbarCommands()
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Job") {
                    NotificationCenter.default.post(name: .createNewJob, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            MailMergeCommands()
        }
#endif

#if os(macOS)
        Settings {
            AppSettingsView()
                .environment(store)
        }
#endif
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
    @FocusedValue(\.deleteJobAction) private var deleteJobAction: (() -> Void)?
    @FocusedValue(\.renameJobAction) private var renameJobAction: (() -> Void)?
    @FocusedValue(\.selectedJobID) private var selectedJobID: UUID?

    var body: some Commands {
        CommandMenu("Job") {
            Button("Rename Job") {
                renameJobAction?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(selectedJobID == nil)

            Divider()

            Button("Delete Job") {
                deleteJobAction?()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedJobID == nil)
        }
    }
}

// MARK: - App Settings View

struct AppSettingsView: View {
    @Environment(StoreKitService<MailMergeTier>.self) private var store
    @AppStorage("defaultOutputPattern") private var defaultOutputPattern = "Letter_{FirstName}_{LastName}"
    @AppStorage("showRelativeDates") private var showRelativeDates = true
    @AppStorage("autoMatchFields") private var autoMatchFields = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @State private var showingPaywall = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            mergeTab
                .tabItem { Label("Merge", systemImage: "doc.on.doc") }
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
                        if store.subscriptionTier >= .pro {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Pro")
                                .foregroundStyle(.primary)
                        } else {
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
                if store.subscriptionTier >= .pro {
                    LabeledContent("Renewal", value: store.renewalStatusString)
                }
            }
            Section("Manage") {
                ManageSubscriptionsButton()
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                RestorePurchasesButton<MailMergeTier>()
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            Section("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://transfinite.us/policies/MergeformPrivacy/")!)
                Link("Terms of Use", destination: URL(string: "https://transfinite.us/policies/MergeformTerms/")!)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
            }
            Section {
                LabeledContent("Developer", value: "Gerard Gomez")
                Link("Send Feedback", destination: URL(string: "mailto:gerardgomez11@outlook.com")!)
            }
        }
        .formStyle(.grouped)
    }
}
