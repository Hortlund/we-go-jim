import SwiftUI

struct ProfileAthleteTypePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedAthleteType: ProfileAthleteType?

    private var trainingStyles: [ProfileAthleteType] {
        [
            .strengthTraining,
            .powerlifting,
            .olympicLifting,
            .bodybuilding,
            .hybridAthlete,
            .strongman,
            .calisthenics,
            .running,
            .functionalFitness,
            .endurance,
        ]
    }

    private var funTypes: [ProfileAthleteType] {
        [
            .garageGymRat,
            .benchMerchant,
            .legDaySurvivor,
            .deadliftEnthusiast,
            .cardioCriminal,
            .machineMaxxer,
            .mobilityMonk,
            .weekendWarrior,
            .dadStrength,
            .chaosGoblin,
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    optionRow(title: "None", subtitle: "Keep the profile clean without a type badge.", value: nil)
                } header: {
                    sectionHeader("Optional", subtitle: "You can skip this and add it later.")
                }

                Section {
                    ForEach(trainingStyles) { athleteType in
                        optionRow(title: athleteType.title, subtitle: "Training style", value: athleteType)
                    }
                } header: {
                    sectionHeader("Training Styles", subtitle: "Grounded options for how you train.")
                }

                Section {
                    ForEach(funTypes) { athleteType in
                        optionRow(title: athleteType.title, subtitle: "Fun profile flavor", value: athleteType)
                    }
                } header: {
                    sectionHeader("Fun Types", subtitle: "A little meme energy without wrecking the app feel.")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        WGJSectionHeader(title, subtitle: subtitle)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func optionRow(
        title: String,
        subtitle: String,
        value: ProfileAthleteType?
    ) -> some View {
        Button {
            selectedAthleteType = value
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                Spacer()

                if selectedAthleteType == value {
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
            .wgjCardContainer(cornerRadius: WGJRadius.control)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
