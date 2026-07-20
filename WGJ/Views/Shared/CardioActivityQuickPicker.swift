import SwiftUI

nonisolated struct CardioActivityQuickChoice: Identifiable, Equatable, Sendable {
    let remoteUUID: String
    let displayName: String
    let equipmentSummary: String
    let systemImage: String
    let trackingProfile: WorkoutCardioTrackingProfile

    var id: String { remoteUUID }

    var selection: ExerciseCatalogSelection {
        ExerciseCatalogSelection(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: "Cardio",
            equipmentSummary: equipmentSummary,
            primaryMuscleNames: "",
            cardioTrackingProfileRaw: trackingProfile.rawValue
        )
    }

    static let all: [CardioActivityQuickChoice] = [
        .init(
            remoteUUID: "seed-treadmill-walk",
            displayName: "Treadmill Walk",
            equipmentSummary: "Treadmill",
            systemImage: "figure.walk",
            trackingProfile: .treadmill
        ),
        .init(
            remoteUUID: "seed-treadmill-run",
            displayName: "Treadmill Run",
            equipmentSummary: "Treadmill",
            systemImage: "figure.run",
            trackingProfile: .treadmill
        ),
        .init(
            remoteUUID: "seed-outdoor-walk",
            displayName: "Outdoor Walk",
            equipmentSummary: "Outdoor",
            systemImage: "figure.walk",
            trackingProfile: .walkRun
        ),
        .init(
            remoteUUID: "seed-outdoor-run",
            displayName: "Outdoor Run",
            equipmentSummary: "Outdoor",
            systemImage: "figure.run",
            trackingProfile: .walkRun
        ),
        .init(
            remoteUUID: "seed-bike",
            displayName: "Bike",
            equipmentSummary: "Bike",
            systemImage: "bicycle",
            trackingProfile: .machineDistance
        ),
        .init(
            remoteUUID: "seed-crosstrainer",
            displayName: "Crosstrainer",
            equipmentSummary: "Crosstrainer",
            systemImage: "figure.elliptical",
            trackingProfile: .machineDistance
        ),
        .init(
            remoteUUID: "seed-row-machine",
            displayName: "Row Machine",
            equipmentSummary: "Rower",
            systemImage: "figure.rower",
            trackingProfile: .rower
        ),
        .init(
            remoteUUID: "seed-stair-climber",
            displayName: "Stair Climber",
            equipmentSummary: "Stair Climber",
            systemImage: "figure.stair.stepper",
            trackingProfile: .stairClimber
        ),
    ]
}

struct CardioActivityQuickPicker: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ExerciseCatalogSelection) -> Void

    @State private var path: [Destination] = []

    private enum Destination: Hashable {
        case catalog
        case custom
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WGJSectionHeader(
                        "Quick choices",
                        subtitle: "Pick an activity now, or open the full Cardio catalog."
                    )

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CardioActivityQuickChoice.all) { choice in
                            quickChoiceButton(choice)
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            path.append(.catalog)
                        } label: {
                            Label("More Cardio", systemImage: "list.bullet.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                        .accessibilityIdentifier("cardio-quick-picker-more")

                        Button {
                            path.append(.custom)
                        } label: {
                            Label("Create Custom Cardio", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("cardio-quick-picker-custom")
                    }
                }
                .padding(16)
            }
            .wgjScreenBackground()
            .navigationTitle("Choose Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .catalog:
                    ExercisesCatalogView(
                        mode: .pick(actionTitle: "Add Cardio", onSelect: select),
                        initialFilters: ExerciseFilters(
                            categoryName: "Cardio",
                            includeUncurated: true
                        ),
                        customCreationMode: .cardio
                    )
                    .navigationTitle("More Cardio")
                    .navigationBarTitleDisplayMode(.inline)
                case .custom:
                    CardioCustomExerciseCreationView(onSelect: select)
                }
            }
        }
        .wgjSheetSurface()
    }

    private func quickChoiceButton(_ choice: CardioActivityQuickChoice) -> some View {
        Button {
            select(choice.selection)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: choice.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)

                Text(choice.displayName)
                    .font(.headline)
                    .foregroundStyle(WGJTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .wgjCardContainer(strong: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardio-quick-choice-\(choice.remoteUUID)")
    }

    private func select(_ selection: ExerciseCatalogSelection) {
        onSelect(selection)
        dismiss()
    }
}
