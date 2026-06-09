import SwiftUI

struct ProfileAthleteTypePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedAthleteType: ProfileAthleteType?

    private static let sections: [AthleteTypePickerSection] = [
        AthleteTypePickerSection(
            title: "Optional",
            subtitle: "Skip it for now and keep the profile clean.",
            options: [.none]
        ),
        AthleteTypePickerSection(
            title: "Strength Sports",
            subtitle: "Classic gym identities built around iron, intent, and progressive overload.",
            options: [
                .athlete(.strengthTraining),
                .athlete(.powerlifting),
                .athlete(.olympicLifting),
                .athlete(.bodybuilding),
                .athlete(.strongman),
            ]
        ),
        AthleteTypePickerSection(
            title: "Hybrid and Conditioning",
            subtitle: "For people who lift, move, and keep the engine switched on.",
            options: [
                .athlete(.hybridAthlete),
                .athlete(.functionalFitness),
                .athlete(.calisthenics),
                .athlete(.running),
                .athlete(.endurance),
                .athlete(.cycling),
                .athlete(.swimming),
                .athlete(.trailRunning),
            ]
        ),
        AthleteTypePickerSection(
            title: "Skill and Movement",
            subtitle: "Precision, body control, and athletic identity beyond straight gym bro energy.",
            options: [
                .athlete(.climbing),
                .athlete(.martialArts),
                .athlete(.yogaFlow),
                .athlete(.racketSports),
            ]
        ),
        AthleteTypePickerSection(
            title: "Gym Lore",
            subtitle: "Still grounded, but with more personality and more stories behind the choice.",
            options: [
                .athlete(.garageGymRat),
                .athlete(.machineMaxxer),
                .athlete(.mobilityMonk),
                .athlete(.weekendWarrior),
                .athlete(.dadStrength),
                .athlete(.deadliftEnthusiast),
            ]
        ),
        AthleteTypePickerSection(
            title: "Meme Damage",
            subtitle: "High flavor, high gym-brain energy, still readable in your profile.",
            options: [
                .athlete(.benchMerchant),
                .athlete(.legDaySurvivor),
                .athlete(.cardioCriminal),
                .athlete(.chaosGoblin),
                .athlete(.squatSorcerer),
                .athlete(.chalkGoblin),
                .athlete(.proteinProphet),
                .athlete(.preworkoutAstronaut),
                .athlete(.deloadDenier),
                .athlete(.cableCowboy),
                .athlete(.pumpChaser),
                .athlete(.repRangeBandit),
                .athlete(.plateCollector),
                .athlete(.spreadsheetTactician),
                .athlete(.restDayRevisionist),
                .athlete(.latsCartographer),
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Self.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader(section.title, subtitle: section.subtitle)

                            LazyVStack(spacing: 8) {
                                ForEach(section.options) { option in
                                    optionRow(option)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle("Athlete Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        WGJCompactSectionHeader(title, subtitle: subtitle)
            .padding(.horizontal, 2)
    }

    private func optionRow(_ option: AthleteTypePickerOption) -> some View {
        Button {
            selectedAthleteType = option.value
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(1)

                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if selectedAthleteType == option.value {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(WGJTheme.accentBlue)
                } else {
                    Image(systemName: "circle")
                        .font(.headline)
                        .foregroundStyle(WGJTheme.outlineStrong)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(
                        selectedAthleteType == option.value
                            ? WGJTheme.accentBlue.opacity(0.10)
                            : Color.clear
                    )
            }
            .wgjCardContainer(cornerRadius: WGJRadius.control)
            .overlay {
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .stroke(
                        selectedAthleteType == option.value
                            ? WGJTheme.accentBlue.opacity(0.36)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AthleteTypePickerSection: Identifiable {
    let title: String
    let subtitle: String
    let options: [AthleteTypePickerOption]

    var id: String { title }
}

private struct AthleteTypePickerOption: Identifiable {
    let value: ProfileAthleteType?
    let title: String
    let subtitle: String

    var id: String { value?.id ?? "none" }

    static let none = AthleteTypePickerOption(
        value: nil,
        title: "None",
        subtitle: "Keep the profile clean without an athlete-type badge."
    )

    static func athlete(_ athleteType: ProfileAthleteType) -> AthleteTypePickerOption {
        AthleteTypePickerOption(
            value: athleteType,
            title: athleteType.title,
            subtitle: athleteType.pickerSubtitle
        )
    }
}
