import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    @State private var displayName = ""
    @State private var savedDisplayName = ""
    @State private var athleteType: ProfileAthleteType?
    @State private var savedAthleteType: ProfileAthleteType?
    @State private var avatarImageData: Data?
    @State private var savedAvatarImageData: Data?
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

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(trimmedDisplayName.isEmpty || !hasPendingChanges)
                    .accessibilityIdentifier("profile-save-button")
                }
                .padding(14)
                .wgjCardContainer(strong: true)
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
        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
            Label(avatarImageData == nil ? "Choose Avatar" : "Change Avatar", systemImage: "photo")
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
    }

    @ViewBuilder
    private var removeAvatarButton: some View {
        if avatarImageData != nil {
            Button(role: .destructive) {
                avatarImageData = nil
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

    private var identityPreviewName: String {
        trimmedDisplayName.isEmpty ? "Athlete" : trimmedDisplayName
    }

    private var hasPendingChanges: Bool {
        trimmedDisplayName != savedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            || athleteType != savedAthleteType
            || avatarImageData != savedAvatarImageData
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
                                  avatarImageData == savedAvatarImageData else {
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
        do {
            try profileRepository.saveProfile(
                name: displayName,
                athleteType: athleteType,
                avatarImageData: avatarImageData
            )
            if let profile = try profileRepository.currentProfile() {
                apply(profile: ProfileIdentitySnapshot(profile: profile))
            }
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func stageAvatar(from item: PhotosPickerItem) async {
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self) else {
                avatarImageData = nil
                return
            }
            avatarImageData = await AvatarImageCodec.compressedAvatarData(
                from: rawData,
                maxPixelSize: 640
            ) ?? rawData
        } catch {
            showError(error)
        }
    }

    private func stageAvatarSelection(_ item: PhotosPickerItem) {
        Task {
            await stageAvatar(from: item)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    @MainActor
    private func apply(profile: ProfileIdentitySnapshot) {
        displayName = profile.displayName
        savedDisplayName = profile.displayName
        athleteType = profile.athleteType
        savedAthleteType = profile.athleteType
        avatarImageData = profile.avatarImageData
        savedAvatarImageData = profile.avatarImageData
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
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
    .environment(\.cloudSyncEnabled, false)
}
