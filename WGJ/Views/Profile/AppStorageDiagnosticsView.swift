import Foundation
import SwiftData
import SwiftUI

struct AppStorageDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState

    @State private var snapshot = AppStorageSnapshot.empty
    @State private var isLoading = false
    @State private var isClearing = false
    @State private var isRestoringCloudBackup = false
    @State private var showingStoreResetConfirmation = false
    @State private var showingCloudRestoreConfirmation = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Storage", subtitle: "Inspect local app data and clear disposable files.")

                VStack(alignment: .leading, spacing: 10) {
                    WGJActionHeader("Local Usage", subtitle: "Approximate on-device storage by bucket.") {
                        Button {
                            refresh()
                        } label: {
                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Refreshing")
                                }
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(WGJCompactGhostButtonStyle())
                        .disabled(isLoading)
                    }

                    ForEach(snapshot.rows) { row in
                        DisclosureGroup {
                            if row.files.isEmpty {
                                Text("No files found.")
                                    .font(.caption)
                                    .foregroundStyle(WGJTheme.textSecondary)
                            } else {
                                ForEach(row.files) { file in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(file.name)
                                                .foregroundStyle(WGJTheme.textPrimary)
                                                .lineLimit(2)
                                            Spacer()
                                            Text(file.formattedSize)
                                                .foregroundStyle(WGJTheme.textSecondary)
                                        }
                                        Text(file.path)
                                            .font(.caption2)
                                            .foregroundStyle(WGJTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .font(.caption)
                                    .padding(.top, 4)
                                }
                            }
                        } label: {
                            infoRow(row.title, value: row.formattedSize)
                        }
                        .tint(WGJTheme.accentBlue)
                    }

                    Text("Shared widget data is the app-group container used by WGJ and its widget for widget snapshots and shared history data.")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Cleanup", subtitle: "Clear cache, restore CloudKit backup, or schedule a full local reset.")

                    Button {
                        clearCaches()
                    } label: {
                        if isClearing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Clear Disposable Storage", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .disabled(isClearing)

                    Button {
                        showingCloudRestoreConfirmation = true
                    } label: {
                        if isRestoringCloudBackup {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Restore Latest Cloud Backup", systemImage: "icloud.and.arrow.down")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                    .disabled(!cloudSyncEnabled || isRestoringCloudBackup)

                    Button(role: .destructive) {
                        showingStoreResetConfirmation = true
                    } label: {
                        Label("Reset Local Stores on Next Launch", systemImage: "exclamationmark.triangle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WGJDestructiveButtonStyle())
                }
                .padding(14)
                .wgjCardContainer()
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
        }
        .confirmationDialog(
            "Restore latest CloudKit backup?",
            isPresented: $showingCloudRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Backup", role: .destructive) {
                restoreCloudBackup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This replaces local WGJ data on this device with the latest CloudKit backup. It does not delete the CloudKit backup.")
        }
        .confirmationDialog(
            "Reset local stores on next launch?",
            isPresented: $showingStoreResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Schedule Reset", role: .destructive) {
                AppStoreLayout.requestPersistentStoreResetOnNextLaunch()
                showAlert(
                    title: "Reset Scheduled",
                    message: "Fully close and reopen WGJ to delete the local SwiftData store files before the app starts."
                )
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes local profiles, workouts, templates, active drafts, history projections, and catalog stores from this device. It does not delete your CloudKit backup.")
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(WGJTheme.textPrimary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .font(.subheadline)
    }

    private func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let loadedSnapshot = AppStorageDiagnosticsService.snapshot()
            await MainActor.run {
                snapshot = loadedSnapshot
                isLoading = false
            }
        }
    }

    private func clearCaches() {
        guard !isClearing else { return }
        isClearing = true
        Task.detached(priority: .utility) {
            do {
                try AppStorageDiagnosticsService.clearCachesAndTemporaryFiles()
                let loadedSnapshot = AppStorageDiagnosticsService.snapshot()
                await MainActor.run {
                    snapshot = loadedSnapshot
                    isClearing = false
                    showAlert(title: "Storage Cleared", message: "Disposable cache and temporary files were removed.")
                }
            } catch {
                await MainActor.run {
                    isClearing = false
                    showAlert(title: "Cleanup Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func restoreCloudBackup() {
        guard cloudSyncEnabled, !isRestoringCloudBackup else { return }
        isRestoringCloudBackup = true
        let container = modelContext.container
        Task.detached(priority: .utility) {
            do {
                let restoreResult = try await UserDataCloudBackupService(
                    localContainer: container,
                    backupStore: CloudKitUserDataCloudBackupStore()
                ).restoreLatestBackup(replacingLocalData: true)
                let loadedSnapshot = AppStorageDiagnosticsService.snapshot()

                await MainActor.run {
                    snapshot = loadedSnapshot
                    isRestoringCloudBackup = false
                    if let restoreResult {
                        AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp(at: restoreResult.restoredAt))
                        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
                        WorkoutHistoryChangeBroadcaster.post()
                        TemplateLibraryChangeBroadcaster.post()
                        showAlert(title: "Backup Restored", message: "Latest CloudKit backup was restored on this device.")
                    } else {
                        showAlert(title: "No Backup Found", message: "WGJ could not find a CloudKit backup to restore.")
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoringCloudBackup = false
                    showAlert(title: "Restore Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

nonisolated private enum AppStorageDiagnosticsService {
    static func snapshot(fileManager: FileManager = .default) -> AppStorageSnapshot {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporary = fileManager.temporaryDirectory
        let appGroup = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppStoreLayout.appGroupIdentifier)
        let exerciseImages = caches?.appendingPathComponent("ExerciseImages", isDirectory: true)

        let rows = [
            row(title: "Documents", url: documents, fileManager: fileManager),
            row(title: "Application Support", url: applicationSupport, fileManager: fileManager),
            row(title: "Caches", url: caches, fileManager: fileManager),
            row(title: "Temporary Files", url: temporary, fileManager: fileManager),
            row(title: "Shared Widget Data", url: appGroup, fileManager: fileManager),
            persistentStoreRow(fileManager: fileManager),
            row(title: "Exercise Image Cache", url: exerciseImages, fileManager: fileManager),
        ]

        return AppStorageSnapshot(rows: rows)
    }

    static func clearCachesAndTemporaryFiles(fileManager: FileManager = .default) throws {
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try removeContents(of: caches, fileManager: fileManager)
        }
        try removeContents(of: fileManager.temporaryDirectory, fileManager: fileManager)
    }

    private static func row(title: String, url: URL?, fileManager: FileManager) -> AppStorageRow {
        let contents = files(in: url, fileManager: fileManager) { _ in true }
        return AppStorageRow(
            title: title,
            bytes: contents.bytes,
            files: contents.files
        )
    }

    private static func persistentStoreRow(fileManager: FileManager) -> AppStorageRow {
        let contents = AppStoreLayout.persistentStoreDirectories(fileManager: fileManager)
            .map { directory in
                files(in: directory, fileManager: fileManager, matching: AppStoreLayout.isPersistentStoreFile)
            }
        let bytes = contents.reduce(0) { $0 + $1.bytes }
        let largestFiles = contents
            .flatMap { $0.files }
            .sorted { $0.bytes > $1.bytes }

        return AppStorageRow(title: "SwiftData Stores", bytes: bytes, files: Array(largestFiles.prefix(25)))
    }

    private static func removeContents(of directory: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func files(
        in directory: URL?,
        fileManager: FileManager,
        matching shouldCount: (URL) -> Bool
    ) -> (bytes: Int64, files: [AppStorageFileRow]) {
        guard let directory,
              fileManager.fileExists(atPath: directory.path),
              let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return (0, [])
        }

        var bytes: Int64 = 0
        var rows: [AppStorageFileRow] = []
        for case let fileURL as URL in enumerator where shouldCount(fileURL) {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            let fileSize = Int64(values.fileSize ?? 0)
            bytes += fileSize
            rows.append(AppStorageFileRow(
                name: fileURL.lastPathComponent,
                path: relativePath(for: fileURL, in: directory),
                bytes: fileSize
            ))
        }
        return (bytes, Array(rows.sorted { $0.bytes > $1.bytes }.prefix(25)))
    }

    private static func relativePath(for fileURL: URL, in directory: URL) -> String {
        let root = directory.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(root) else { return fileURL.lastPathComponent }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

nonisolated private struct AppStorageSnapshot {
    static let empty = AppStorageSnapshot(rows: [])
    let rows: [AppStorageRow]
}

nonisolated private struct AppStorageRow: Identifiable {
    let id = UUID()
    let title: String
    let bytes: Int64
    let files: [AppStorageFileRow]

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated private struct AppStorageFileRow: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let bytes: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        AppStorageDiagnosticsView()
    }
}
