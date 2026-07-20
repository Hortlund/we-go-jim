import Foundation
import SwiftUI

nonisolated struct WorkoutCardioSetupDraft: Equatable, Sendable {
    var role: WorkoutCardioRole
    var goalKind: WorkoutCardioGoalKind
    var durationMinutesText: String
    var distanceText: String
    var distanceUnit: WorkoutDistanceUnit
    var trackingProfile: WorkoutCardioTrackingProfile

    private let originalDistanceMeters: Double?
    private let originalDistanceText: String?
    private let originalDistanceUnit: WorkoutDistanceUnit?

    init(
        role: WorkoutCardioRole,
        goalKind: WorkoutCardioGoalKind,
        durationMinutesText: String,
        distanceText: String,
        distanceUnit: WorkoutDistanceUnit,
        trackingProfile: WorkoutCardioTrackingProfile
    ) {
        self.role = role
        self.goalKind = goalKind
        self.durationMinutesText = durationMinutesText
        self.distanceText = distanceText
        self.distanceUnit = distanceUnit
        self.trackingProfile = trackingProfile
        self.originalDistanceMeters = nil
        self.originalDistanceText = nil
        self.originalDistanceUnit = nil
    }

    init(
        templateCardio: TemplateCardioBlockDraft,
        fallbackDistanceUnit: WorkoutDistanceUnit = .regionalDefault(locale: .current)
    ) {
        let distanceUnit = templateCardio.preferredDistanceUnit ?? fallbackDistanceUnit
        let distanceText = templateCardio.targetDistanceMeters.map {
            WorkoutCardioSetupNumericCodec.distanceText(meters: $0, unit: distanceUnit)
        } ?? ""

        self.role = templateCardio.role
        self.goalKind = templateCardio.goalKind
        self.durationMinutesText = WorkoutCardioSetupNumericCodec.durationMinutesText(
            seconds: templateCardio.targetDurationSeconds
        )
        self.distanceText = distanceText
        self.distanceUnit = distanceUnit
        self.trackingProfile = templateCardio.trackingProfile ?? .machineDistance
        self.originalDistanceMeters = templateCardio.targetDistanceMeters
        self.originalDistanceText = distanceText
        self.originalDistanceUnit = distanceUnit
    }

    fileprivate var unchangedOriginalDistanceMeters: Double? {
        guard distanceText == originalDistanceText,
              distanceUnit == originalDistanceUnit,
              let originalDistanceMeters,
              originalDistanceMeters.isFinite,
              originalDistanceMeters > 0 else {
            return nil
        }
        return originalDistanceMeters
    }
}

nonisolated struct ValidatedWorkoutCardioSetup: Equatable, Sendable {
    let role: WorkoutCardioRole
    let goalKind: WorkoutCardioGoalKind
    let targetDurationSeconds: Int
    let targetDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit
    let trackingProfile: WorkoutCardioTrackingProfile
}

nonisolated enum WorkoutCardioSetupValidator {
    static func validated(
        _ draft: WorkoutCardioSetupDraft,
        locale: Locale = .current
    ) throws -> ValidatedWorkoutCardioSetup {
        let targetDurationSeconds: Int
        let targetDistanceMeters: Double?

        switch draft.goalKind {
        case .time:
            guard let durationSeconds = WorkoutCardioSetupNumericCodec.durationSeconds(
                fromMinutesText: draft.durationMinutesText,
                locale: locale
            ) else {
                throw WorkoutCardioSetupValidationError.durationMustBePositive
            }
            targetDurationSeconds = durationSeconds
            targetDistanceMeters = nil
        case .distance:
            guard let parsedDistanceMeters = WorkoutCardioSetupNumericCodec.distanceMeters(
                from: draft.distanceText,
                unit: draft.distanceUnit,
                locale: locale
            ) else {
                throw WorkoutCardioSetupValidationError.distanceMustBePositive(unit: draft.distanceUnit)
            }
            targetDurationSeconds = 0
            targetDistanceMeters = draft.unchangedOriginalDistanceMeters ?? parsedDistanceMeters
        case .open:
            targetDurationSeconds = 0
            targetDistanceMeters = nil
        }

        return ValidatedWorkoutCardioSetup(
            role: draft.role,
            goalKind: draft.goalKind,
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            preferredDistanceUnit: draft.distanceUnit,
            trackingProfile: draft.trackingProfile
        )
    }
}

struct WorkoutCardioSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let activityName: String
    let onSave: (ValidatedWorkoutCardioSetup) -> Void

    @State private var draft: WorkoutCardioSetupDraft
    @State private var validationMessage: String?

    init(
        activityName: String,
        draft: WorkoutCardioSetupDraft,
        onSave: @escaping (ValidatedWorkoutCardioSetup) -> Void
    ) {
        self.activityName = activityName
        self.onSave = onSave
        self._draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    setupCard

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WGJTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cardio-setup-validation-error")
                    }
                }
                .padding(16)
            }
            .wgjScreenBackground()
            .navigationTitle("Cardio Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .accessibilityIdentifier("cardio-setup-save-button")
                }
            }
        }
        .wgjSheetSurface()
        .onChange(of: draft) { _, _ in
            validationMessage = nil
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            WGJSectionHeader(
                String(localized: "Plan \(activityName)"),
                subtitle: String(localized: "Choose where it fits and what to aim for.")
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Role")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Picker("Role", selection: $draft.role) {
                    ForEach(WorkoutCardioRole.allCases) { role in
                        Text(role.compactTitle).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cardio-setup-role-picker")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Picker("Goal", selection: $draft.goalKind) {
                    ForEach(WorkoutCardioGoalKind.allCases) { goalKind in
                        Text(goalKind.title).tag(goalKind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cardio-setup-goal-picker")
            }

            goalInput
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var goalInput: some View {
        switch draft.goalKind {
        case .time:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Minutes", text: $draft.durationMinutesText)
                    .keyboardType(.decimalPad)
                    .wgjPillField()
                    .accessibilityIdentifier("cardio-setup-duration-field")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        presetTimeButtons
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        presetTimeButtons
                    }
                }
            }
        case .distance:
            HStack(spacing: 10) {
                TextField("Distance", text: $draft.distanceText)
                    .keyboardType(.decimalPad)
                    .wgjPillField()
                    .accessibilityIdentifier("cardio-setup-distance-field")

                Picker("Unit", selection: $draft.distanceUnit) {
                    ForEach(WorkoutDistanceUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("cardio-setup-distance-unit-picker")
            }
        case .open:
            Label("No target. Track the activity freely when you work out.", systemImage: "scope")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var presetTimeButtons: some View {
        ForEach([5, 10, 20], id: \.self) { minutes in
            Button("\(minutes) min") {
                draft.durationMinutesText = String(minutes)
            }
            .buttonStyle(WGJGhostButtonStyle())
        }
    }

    private func save() {
        do {
            let validated = try WorkoutCardioSetupValidator.validated(draft)
            onSave(validated)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
