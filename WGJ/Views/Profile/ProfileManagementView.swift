import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    @State private var displayName = ""
    @State private var savedDisplayName = ""
    @State private var athleteType: ProfileAthleteType?
    @State private var savedAthleteType: ProfileAthleteType?
    @State private var avatarSelection = AvatarSelectionCoordinator()
    @State private var savedAvatarImageData: Data?
    @State private var calorieDetailsDraft = ProfileCalorieDetailsDraft()
    @State private var savedCalorieDetailsDraft = ProfileCalorieDetailsDraft()
    @State private var savedShowsCalorieEstimates = true
    @State private var calorieDetailsValidationError: ProfileCalorieDetailsDraftError?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var hasLoadedProfile = false
    @State private var showingAthleteTypePicker = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var profileRepository: ProfileRepository {
        ProfileRepository(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Edit Profile", subtitle: "Update your profile details.")

                VStack(alignment: .leading, spacing: 14) {
                    avatarSection

                    TextField("Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()
                        .accessibilityIdentifier("profile-display-name-field")

                    athleteTypePickerButton

                    Text("Your name, avatar, and athlete type shape your profile.")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                ProfileCalorieDetailsSection(
                    draft: $calorieDetailsDraft,
                    validationError: calorieDetailsValidationError
                )

                Button("Save Profile") {
                    saveProfile()
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .disabled(trimmedDisplayName.isEmpty || !hasPendingChanges)
                .accessibilityIdentifier("profile-save-button")
            }
            .padding(.top, 8)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .wgjMinimalKeyboardToolbar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .task {
            await loadProfileIfNeeded()
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            stageAvatarSelection(newItem)
        }
        .onChange(of: avatarSelection.errorDescription) { _, errorDescription in
            guard let errorDescription else { return }
            errorMessage = errorDescription
            showingError = true
        }
        .onChange(of: calorieDetailsDraft) { _, _ in
            refreshCalorieDetailsValidationIfNeeded()
        }
        .onDisappear {
            avatarSelection.cancel()
        }
        .sheet(isPresented: $showingAthleteTypePicker) {
            ProfileAthleteTypePickerView(selectedAthleteType: $athleteType)
                .wgjSheetSurface()
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var avatarSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(imageData: avatarImageData)
                    .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 10) {
                    Text(identityPreviewName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)

                    if let athleteType {
                        ProfileAthleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
                    }

                    avatarActionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 14) {
                ProfileAvatarView(imageData: avatarImageData)
                    .frame(width: 88, height: 88)

                Text(identityPreviewName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .lineLimit(2)

                if let athleteType {
                    ProfileAthleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
                }

                avatarActionRow
            }
        }
    }

    private var avatarActionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                changeAvatarButton
                removeAvatarButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                changeAvatarButton
                if avatarImageData != nil {
                    removeAvatarButton
                }
            }
        }
    }

    private var changeAvatarButton: some View {
        let pickerTitle = avatarImageData == nil ? "Choose Avatar" : "Change Avatar"
        return PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
            Label(pickerTitle, systemImage: "photo")
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
    }

    @ViewBuilder
    private var removeAvatarButton: some View {
        if avatarImageData != nil {
            Button(role: .destructive) {
                avatarSelection.remove()
                selectedAvatarItem = nil
            } label: {
                Image(systemName: "trash")
                    .accessibilityLabel("Remove Avatar")
            }
            .buttonStyle(
                WGJIconButtonStyle(
                    tint: WGJTheme.danger,
                    background: WGJTheme.destructiveField,
                    outline: WGJTheme.danger.opacity(0.28)
                )
            )
        }
    }

    private var athleteTypePickerButton: some View {
        Button {
            showingAthleteTypePicker = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Athlete Type")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(athleteType?.title ?? "Optional. Pick one that fits your training vibe.")
                        .font(.caption)
                        .foregroundStyle(athleteType == nil ? WGJTheme.textSecondary : WGJTheme.accentGold)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }
            .wgjPillField()
        }
        .buttonStyle(.plain)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var avatarImageData: Data? {
        avatarSelection.imageData
    }

    private var identityPreviewName: String {
        trimmedDisplayName.isEmpty ? "Athlete" : trimmedDisplayName
    }

    private var hasPendingChanges: Bool {
        trimmedDisplayName != savedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            || athleteType != savedAthleteType
            || avatarImageData != savedAvatarImageData
            || calorieDetailsDraft != savedCalorieDetailsDraft
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        do {
            let profile = try profileRepository.currentProfileSnapshot()
                ?? ProfileIdentitySnapshot(profile: try profileRepository.loadOrCreateProfile())
            apply(profile: profile)

            if cloudSyncEnabled {
                Task {
                    do {
                        let published = try await profileRepository.bootstrapProfileIdentity(
                            cloudSyncEnabled: cloudSyncEnabled
                        )
                        await MainActor.run {
                            guard hasLoadedProfile else { return }
                            guard displayName == savedDisplayName,
                                  athleteType == savedAthleteType,
                                  avatarImageData == savedAvatarImageData,
                                  calorieDetailsDraft == savedCalorieDetailsDraft else {
                                return
                            }
                            apply(profile: ProfileIdentitySnapshot(profile: published))
                        }
                    } catch {
                        // Keep the local-first profile snapshot if cloud bootstrap fails.
                    }
                }
            }
        } catch {
            showError(error)
        }
    }

    private func saveProfile() {
        let calorieProfile: WorkoutCalorieProfileSnapshot
        switch calorieDetailsDraft.canonicalSnapshot(
            showsCalorieEstimates: savedShowsCalorieEstimates,
            referenceDate: .now,
            calendar: .current
        ) {
        case let .success(snapshot):
            calorieProfile = snapshot
            calorieDetailsValidationError = nil
        case let .failure(error):
            calorieDetailsValidationError = error
            return
        }

        do {
            try profileRepository.saveProfile(
                name: displayName,
                athleteType: athleteType,
                avatarImageData: avatarImageData,
                calorieProfile: calorieProfile
            )
            dismiss()
            scheduleCalorieHistoryRefreshAndBackfill()
        } catch {
            showError(error)
        }
    }

    private func stageAvatarSelection(_ item: PhotosPickerItem) {
        avatarSelection.select {
            try await item.loadTransferable(type: Data.self)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func refreshCalorieDetailsValidationIfNeeded() {
        guard calorieDetailsValidationError != nil else { return }
        switch calorieDetailsDraft.canonicalSnapshot(
            showsCalorieEstimates: savedShowsCalorieEstimates,
            referenceDate: .now,
            calendar: .current
        ) {
        case .success:
            calorieDetailsValidationError = nil
        case let .failure(error):
            calorieDetailsValidationError = error
        }
    }

    private func scheduleCalorieHistoryRefreshAndBackfill() {
        let container = modelContext.container
        let backgroundStore = appBackgroundStore ?? AppBackgroundStore(container: container)
        Task { @MainActor in
            HistoryAnalyticsCache.shared.invalidate(container: container)
            WorkoutHistoryChangeBroadcaster.post()
            WorkoutCalorieBackfillScheduler.schedule(
                backgroundStore: backgroundStore,
                container: container,
                reason: .profileSaved
            )
        }
    }

    @MainActor
    private func apply(profile: ProfileIdentitySnapshot) {
        displayName = profile.displayName
        savedDisplayName = profile.displayName
        athleteType = profile.athleteType
        savedAthleteType = profile.athleteType
        avatarSelection.reset(to: profile.avatarImageData)
        savedAvatarImageData = profile.avatarImageData
        let loadedCalorieDetails = ProfileCalorieDetailsDraft(
            snapshot: WorkoutCalorieProfileSnapshot(
                sex: profile.calorieEstimateSex,
                dateOfBirth: profile.dateOfBirth,
                heightCentimeters: profile.heightCentimeters,
                bodyWeightKilograms: profile.bodyWeightKilograms,
                showsCalorieEstimates: profile.showsCalorieEstimates
            ),
            preferredWeightUnit: profile.preferredWeightUnit,
            locale: .current
        )
        calorieDetailsDraft = loadedCalorieDetails
        savedCalorieDetailsDraft = loadedCalorieDetails
        savedShowsCalorieEstimates = profile.showsCalorieEstimates
        calorieDetailsValidationError = nil
    }
}

struct ProfileAvatarView: View {
    private struct LoadKey: Hashable {
        let dataFingerprint: String?
        let pixelSize: Int
    }

    let imageData: Data?
    @State private var image: UIImage?

    init(imageData: Data?) {
        self.imageData = imageData
        _image = State(initialValue: Self.cachedThumbnail(for: imageData))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                    }
            } else {
                Circle()
                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    .overlay {
                        Circle()
                            .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                    }
            }
        }
        .task(id: loadKey) {
            await loadImage()
        }
    }

    private var loadKey: LoadKey {
        LoadKey(
            dataFingerprint: imageData.map { AvatarThumbnailCacheService.fingerprint(for: $0) },
            pixelSize: 176
        )
    }

    private static func cachedThumbnail(for imageData: Data?) -> UIImage? {
        guard let imageData else { return nil }
        return AvatarThumbnailCacheService.shared.cachedThumbnail(
            for: AvatarThumbnailCacheService.fingerprint(for: imageData),
            maxPixelSize: 176
        )
    }

    @MainActor
    private func loadImage() async {
        guard let imageData else {
            image = nil
            return
        }

        let fingerprint = AvatarThumbnailCacheService.fingerprint(for: imageData)
        if let cachedImage = AvatarThumbnailCacheService.shared.cachedThumbnail(
            for: fingerprint,
            maxPixelSize: 176
        ) {
            image = cachedImage
            return
        }

        let decodedImage = await AvatarImageCodec.thumbnail(
            from: imageData,
            maxPixelSize: 176
        )

        guard !Task.isCancelled else { return }
        AvatarThumbnailCacheService.shared.store(
            decodedImage,
            for: fingerprint,
            maxPixelSize: 176
        )
        image = decodedImage
    }
}

#Preview {
    NavigationStack {
        ProfileManagementView()
    }
    .wgjPreviewModelContainer()
    .environment(\.cloudSyncEnabled, false)
}
