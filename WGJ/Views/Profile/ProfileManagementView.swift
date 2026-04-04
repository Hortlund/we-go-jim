import PhotosUI
import ImageIO
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

                    Text("Your name, avatar, and athlete type are shown in Bros.")
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
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .wgjMinimalKeyboardToolbar()
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
                        athleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
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
                    athleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
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
            let profile = try await profileRepository.bootstrapProfileIdentity(cloudSyncEnabled: cloudSyncEnabled)
            displayName = profile.displayName
            savedDisplayName = profile.displayName
            athleteType = profile.athleteType
            savedAthleteType = profile.athleteType
            avatarImageData = profile.avatarImageData
            savedAvatarImageData = profile.avatarImageData
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
                displayName = profile.displayName
                savedDisplayName = profile.displayName
                athleteType = profile.athleteType
                savedAthleteType = profile.athleteType
                avatarImageData = profile.avatarImageData
                savedAvatarImageData = profile.avatarImageData
            }
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func stageAvatar(from item: PhotosPickerItem) async {
        do {
            avatarImageData = try await item.loadTransferable(type: Data.self)
        } catch {
            showError(error)
        }
    }

    private func stageAvatarSelection(_ item: PhotosPickerItem) {
        Task {
            await stageAvatar(from: item)
        }
    }

    private func athleteTypeBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .wgjCapsuleGlass(tint: tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

struct ProfileAvatarView: View {
    let imageData: Data?
    @State private var image: UIImage?

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
        .task(id: imageData) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let imageData else {
            image = nil
            return
        }

        let decodedImage = await AvatarImageDecoder.decode(
            imageData,
            maxPixelSize: 176
        )

        guard !Task.isCancelled else { return }
        image = decodedImage
    }
}

private enum AvatarImageDecoder {
    static func decode(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        let displayScale = await MainActor.run { UIScreen.main.scale }

        return await Task.detached(priority: .utility) {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
                return UIImage(data: data)
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
            ] as CFDictionary

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                return UIImage(cgImage: cgImage, scale: displayScale, orientation: .up)
            }

            return UIImage(data: data)
        }
        .value
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
        BlockedBro.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
    .environment(\.cloudSyncEnabled, false)
}
