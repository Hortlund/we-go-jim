import Foundation
import SwiftUI

nonisolated enum ProfileHeightDisplayUnit: String, Equatable, Sendable {
    case centimeters
    case feetAndInches

    static func regionalDefault(locale: Locale) -> ProfileHeightDisplayUnit {
        locale.measurementSystem == .us ? .feetAndInches : .centimeters
    }
}

nonisolated struct ProfileCalorieDetailsDraftError: Error, Equatable, Sendable {
    let invalidFields: [WorkoutCalorieProfileField]

    init(invalidFields: [WorkoutCalorieProfileField]) {
        self.invalidFields = invalidFields.reduce(into: []) { fields, field in
            guard !fields.contains(field) else { return }
            fields.append(field)
        }
    }

    func contains(_ field: WorkoutCalorieProfileField) -> Bool {
        invalidFields.contains(field)
    }
}

nonisolated struct ProfileCalorieDetailsDraft: Equatable, Sendable {
    var sex: CalorieEstimateSex?
    var dateOfBirth: Date?
    var heightCentimetersText: String
    var heightFeetText: String
    var heightInchesText: String
    var bodyWeightText: String

    let heightDisplayUnit: ProfileHeightDisplayUnit
    let preferredWeightUnit: PreferredWeightUnit

    private let localeIdentifier: String
    private let originalHeightCentimeters: Double?
    private let originalBodyWeightKilograms: Double?
    private let originalHeightCentimetersText: String
    private let originalHeightFeetText: String
    private let originalHeightInchesText: String
    private let originalBodyWeightText: String

    init(
        heightDisplayUnit: ProfileHeightDisplayUnit = .regionalDefault(locale: .current),
        preferredWeightUnit: PreferredWeightUnit = .kg,
        locale: Locale = .current
    ) {
        self.init(
            snapshot: WorkoutCalorieProfileSnapshot(
                sex: nil,
                dateOfBirth: nil,
                heightCentimeters: nil,
                bodyWeightKilograms: nil,
                showsCalorieEstimates: true
            ),
            heightDisplayUnit: heightDisplayUnit,
            preferredWeightUnit: preferredWeightUnit,
            locale: locale
        )
    }

    init(
        snapshot: WorkoutCalorieProfileSnapshot,
        heightDisplayUnit: ProfileHeightDisplayUnit = .regionalDefault(locale: .current),
        preferredWeightUnit: PreferredWeightUnit,
        locale: Locale = .current
    ) {
        sex = snapshot.sex
        dateOfBirth = snapshot.dateOfBirth
        self.heightDisplayUnit = heightDisplayUnit
        self.preferredWeightUnit = preferredWeightUnit
        localeIdentifier = locale.identifier
        originalHeightCentimeters = snapshot.heightCentimeters
        originalBodyWeightKilograms = snapshot.bodyWeightKilograms

        switch heightDisplayUnit {
        case .centimeters:
            heightCentimetersText = snapshot.heightCentimeters
                .map { Self.displayText($0, locale: locale) } ?? ""
            heightFeetText = ""
            heightInchesText = ""
        case .feetAndInches:
            let components: (feet: Int, inches: Double)? = snapshot.heightCentimeters.flatMap { centimeters in
                guard centimeters.isFinite,
                      abs(centimeters) <= 1_000_000 else {
                    return nil
                }
                return Self.feetAndInches(fromCentimeters: centimeters)
            }
            heightCentimetersText = ""
            heightFeetText = components.map { String($0.feet) } ?? ""
            heightInchesText = components.map { Self.displayText($0.inches, locale: locale) } ?? ""
        }

        if let bodyWeightKilograms = snapshot.bodyWeightKilograms,
           bodyWeightKilograms.isFinite {
            let displayWeight: Double
            switch preferredWeightUnit {
            case .kg:
                displayWeight = bodyWeightKilograms
            case .lb:
                displayWeight = Measurement(value: bodyWeightKilograms, unit: UnitMass.kilograms)
                    .converted(to: .pounds)
                    .value
            }
            bodyWeightText = Self.displayText(displayWeight, locale: locale)
        } else {
            bodyWeightText = ""
        }

        originalHeightCentimetersText = heightCentimetersText
        originalHeightFeetText = heightFeetText
        originalHeightInchesText = heightInchesText
        originalBodyWeightText = bodyWeightText
    }

    func canonicalSnapshot(
        showsCalorieEstimates: Bool,
        referenceDate: Date,
        calendar: Calendar
    ) -> Result<WorkoutCalorieProfileSnapshot, ProfileCalorieDetailsDraftError> {
        var invalidFields: [WorkoutCalorieProfileField] = []
        let heightCentimeters: Double?
        let bodyWeightKilograms: Double?

        do {
            heightCentimeters = try canonicalHeightCentimeters()
        } catch {
            heightCentimeters = nil
            invalidFields.append(.height)
        }

        do {
            bodyWeightKilograms = try canonicalBodyWeightKilograms()
        } catch {
            bodyWeightKilograms = nil
            invalidFields.append(.bodyWeight)
        }

        let snapshot = WorkoutCalorieProfileSnapshot(
            sex: sex,
            dateOfBirth: dateOfBirth,
            heightCentimeters: heightCentimeters,
            bodyWeightKilograms: bodyWeightKilograms,
            showsCalorieEstimates: showsCalorieEstimates
        )

        for issue in snapshot.validationIssues(referenceDate: referenceDate, calendar: calendar) {
            guard case let .invalid(field) = issue else { continue }
            invalidFields.append(field)
        }

        guard invalidFields.isEmpty else {
            return .failure(ProfileCalorieDetailsDraftError(invalidFields: invalidFields))
        }
        return .success(snapshot)
    }

    func ageYears(referenceDate: Date, calendar: Calendar) -> Int? {
        guard let dateOfBirth else { return nil }
        return calendar.dateComponents([.year], from: dateOfBirth, to: referenceDate).year
    }

    private func canonicalHeightCentimeters() throws -> Double? {
        switch heightDisplayUnit {
        case .centimeters:
            if heightCentimetersText == originalHeightCentimetersText {
                return originalHeightCentimeters
            }
            return try optionalNumber(from: heightCentimetersText)

        case .feetAndInches:
            if heightFeetText == originalHeightFeetText,
               heightInchesText == originalHeightInchesText {
                return originalHeightCentimeters
            }

            let feetText = heightFeetText.trimmingCharacters(in: .whitespacesAndNewlines)
            let inchesText = heightInchesText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !feetText.isEmpty || !inchesText.isEmpty else { return nil }

            let feet = feetText.isEmpty ? 0 : try requiredNumber(from: feetText)
            let inches = inchesText.isEmpty ? 0 : try requiredNumber(from: inchesText)
            guard feet >= 0,
                  feet.rounded(.towardZero) == feet,
                  inches >= 0,
                  inches < 12 else {
                throw NumericInputError.invalid
            }

            return Measurement(value: feet * 12 + inches, unit: UnitLength.inches)
                .converted(to: .centimeters)
                .value
        }
    }

    private func canonicalBodyWeightKilograms() throws -> Double? {
        if bodyWeightText == originalBodyWeightText {
            return originalBodyWeightKilograms
        }
        guard let displayWeight = try optionalNumber(from: bodyWeightText) else { return nil }

        switch preferredWeightUnit {
        case .kg:
            return displayWeight
        case .lb:
            return Measurement(value: displayWeight, unit: UnitMass.pounds)
                .converted(to: .kilograms)
                .value
        }
    }

    private func optionalNumber(from text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try requiredNumber(from: trimmed)
    }

    private func requiredNumber(from text: String) throws -> Double {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.removeAll(where: \.isWhitespace)
        guard !normalized.isEmpty else { throw NumericInputError.invalid }

        let locale = Locale(identifier: localeIdentifier)
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        if decimalSeparator == "." {
            if groupingSeparator != "." {
                normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
            }
        } else if normalized.contains(decimalSeparator) {
            if groupingSeparator != decimalSeparator {
                normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
            }
            normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        } else if groupingSeparator != "." {
            normalized = normalized.replacingOccurrences(of: groupingSeparator, with: "")
        }

        guard let value = Double(normalized), value.isFinite else {
            throw NumericInputError.invalid
        }
        return value
    }

    private static func feetAndInches(fromCentimeters centimeters: Double) -> (feet: Int, inches: Double) {
        let totalInches = Measurement(value: centimeters, unit: UnitLength.centimeters)
            .converted(to: .inches)
            .value
        var feet = Int(floor(totalInches / 12))
        var inches = ((totalInches - Double(feet) * 12) * 100).rounded() / 100
        if inches >= 12 {
            feet += 1
            inches = 0
        }
        return (feet, inches)
    }

    private static func displayText(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private enum NumericInputError: Error {
        case invalid
    }
}

struct ProfileCalorieDetailsSection: View {
    @Binding private var draft: ProfileCalorieDetailsDraft
    let validationError: ProfileCalorieDetailsDraftError?

    init(
        draft: Binding<ProfileCalorieDetailsDraft>,
        validationError: ProfileCalorieDetailsDraftError?
    ) {
        _draft = draft
        self.validationError = validationError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WGJSectionHeader(
                "Calorie Estimate Details",
                subtitle: "Optional details for a more personal calorie guesstimate."
            )

            sexInput
            dateOfBirthInput
            heightInput
            bodyWeightInput

            Label(
                "These values are optional and used only to estimate workout calories. The result is not a medical measurement.",
                systemImage: "hand.raised.fill"
            )
            .font(.caption)
            .foregroundStyle(WGJTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("profile-calorie-privacy-copy")
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("profile-calorie-details-section")
    }

    private var sexInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sex used for estimate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            Picker("Sex used for estimate", selection: $draft.sex) {
                Text("Not set").tag(nil as CalorieEstimateSex?)
                ForEach(CalorieEstimateSex.allCases) { option in
                    Text(option.title).tag(option as CalorieEstimateSex?)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("profile-calorie-sex-picker")
        }
    }

    private var dateOfBirthInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Date of birth")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Spacer()

                if let age = draft.ageYears(referenceDate: .now, calendar: .current), age >= 0 {
                    Text("Age \(age)")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }

            if draft.dateOfBirth != nil {
                DatePicker(
                    "Date of birth",
                    selection: dateOfBirthBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .accessibilityLabel("Date of birth")
                .accessibilityIdentifier("profile-calorie-date-of-birth-picker")

                Button("Remove date of birth", role: .destructive) {
                    draft.dateOfBirth = nil
                }
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("profile-calorie-date-of-birth-remove-button")
            } else {
                Button {
                    draft.dateOfBirth = defaultDateOfBirth
                } label: {
                    Label("Add date of birth", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
                .accessibilityIdentifier("profile-calorie-date-of-birth-add-button")
            }

            validationMessage(
                for: .dateOfBirth,
                text: "Choose a date of birth for an age from 18 through 100."
            )
        }
    }

    @ViewBuilder
    private var heightInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Height")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            switch draft.heightDisplayUnit {
            case .centimeters:
                measurementField(
                    placeholder: "Optional",
                    text: $draft.heightCentimetersText,
                    unit: "cm",
                    accessibilityLabel: "Height in centimeters",
                    accessibilityIdentifier: "profile-calorie-height-centimeters-field"
                )
            case .feetAndInches:
                HStack(spacing: 10) {
                    measurementField(
                        placeholder: "Feet",
                        text: $draft.heightFeetText,
                        unit: "ft",
                        accessibilityLabel: "Height in feet",
                        accessibilityIdentifier: "profile-calorie-height-feet-field"
                    )
                    measurementField(
                        placeholder: "Inches",
                        text: $draft.heightInchesText,
                        unit: "in",
                        accessibilityLabel: "Height in inches",
                        accessibilityIdentifier: "profile-calorie-height-inches-field"
                    )
                }
            }

            validationMessage(
                for: .height,
                text: "Enter a height equivalent to 120 through 230 cm."
            )
        }
    }

    private var bodyWeightInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            measurementField(
                placeholder: "Optional",
                text: $draft.bodyWeightText,
                unit: draft.preferredWeightUnit.shortLabel,
                accessibilityLabel: "Body weight in \(draft.preferredWeightUnit.shortLabel)",
                accessibilityIdentifier: "profile-calorie-body-weight-field"
            )

            validationMessage(
                for: .bodyWeight,
                text: "Enter a weight equivalent to 35 through 300 kg."
            )
        }
    }

    private func measurementField(
        placeholder: String,
        text: Binding<String>,
        unit: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .wgjPillField()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityIdentifier)

            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func validationMessage(
        for field: WorkoutCalorieProfileField,
        text: String
    ) -> some View {
        if validationError?.contains(field) == true {
            Label(text, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("profile-calorie-\(field.rawValue)-error")
        }
    }

    private var dateOfBirthBinding: Binding<Date> {
        Binding(
            get: { draft.dateOfBirth ?? defaultDateOfBirth },
            set: { draft.dateOfBirth = $0 }
        )
    }

    private var defaultDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    }
}
