import Foundation

nonisolated enum ExerciseBodyMapRegion: String, CaseIterable, Sendable {
    case abs
    case adductors
    case biceps
    case calves
    case chest
    case deltoids
    case forearm
    case gluteal
    case hamstring
    case lowerBack = "lower-back"
    case obliques
    case quadriceps
    case rhomboids
    case trapezius
    case triceps
    case upperBack = "upper-back"

    var displayName: String {
        switch self {
        case .abs:
            return "Abs"
        case .adductors:
            return "Adductors"
        case .biceps:
            return "Biceps"
        case .calves:
            return "Calves"
        case .chest:
            return "Chest"
        case .deltoids:
            return "Shoulders"
        case .forearm:
            return "Forearms"
        case .gluteal:
            return "Glutes"
        case .hamstring:
            return "Hamstrings"
        case .lowerBack:
            return "Lower Back"
        case .obliques:
            return "Obliques"
        case .quadriceps:
            return "Quadriceps"
        case .rhomboids:
            return "Rhomboids"
        case .trapezius:
            return "Traps"
        case .triceps:
            return "Triceps"
        case .upperBack:
            return "Upper Back"
        }
    }
}

struct ExerciseBodyMapHighlightSpec: Equatable {
    let primaryRegions: Set<ExerciseBodyMapRegion>
    let secondaryRegions: Set<ExerciseBodyMapRegion>
}

enum ExerciseBodyMapRegionMapper {
    private nonisolated static let primarySetWeight = 1.0
    private nonisolated static let secondarySetWeight = 0.35

    nonisolated static func highlightSpec(
        primaryMuscleIDs: Set<Int>,
        secondaryMuscleIDs: Set<Int>
    ) -> ExerciseBodyMapHighlightSpec {
        let primary = regions(for: primaryMuscleIDs)
        let secondary = regions(for: secondaryMuscleIDs).subtracting(primary)
        return ExerciseBodyMapHighlightSpec(primaryRegions: primary, secondaryRegions: secondary)
    }

    nonisolated static func regionScores(
        primaryMuscleIDs: Set<Int>,
        secondaryMuscleIDs: Set<Int>
    ) -> [ExerciseBodyMapRegion: Double] {
        let spec = highlightSpec(
            primaryMuscleIDs: primaryMuscleIDs,
            secondaryMuscleIDs: secondaryMuscleIDs
        )
        var scores: [ExerciseBodyMapRegion: Double] = [:]
        for region in spec.primaryRegions {
            scores[region, default: 0] += primarySetWeight
        }
        for region in spec.secondaryRegions {
            scores[region, default: 0] += secondarySetWeight
        }
        return scores
    }

    private nonisolated static func regions(for muscleIDs: Set<Int>) -> Set<ExerciseBodyMapRegion> {
        Set(muscleIDs.flatMap(regions(for:)))
    }

    private nonisolated static func regions(for muscleID: Int) -> [ExerciseBodyMapRegion] {
        switch muscleID {
        case 1:
            return [.biceps]
        case 2:
            return [.deltoids]
        case 3:
            return [.chest]
        case 4:
            return [.lowerBack, .rhomboids, .upperBack]
        case 5:
            return [.quadriceps]
        case 6:
            return [.hamstring]
        case 7:
            return [.gluteal]
        case 8:
            return [.triceps]
        case 9:
            return [.calves]
        case 10:
            return [.abs, .obliques]
        case 11:
            return [.forearm]
        case 12:
            return [.trapezius]
        case 13:
            return [.adductors]
        case 14:
            return [.gluteal]
        default:
            return []
        }
    }
}
