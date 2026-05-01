import Foundation

enum ExerciseBodyMapRegion: String, CaseIterable {
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
}

struct ExerciseBodyMapHighlightSpec: Equatable {
    let primaryRegions: Set<ExerciseBodyMapRegion>
    let secondaryRegions: Set<ExerciseBodyMapRegion>
}

enum ExerciseBodyMapRegionMapper {
    nonisolated static func highlightSpec(
        primaryMuscleIDs: Set<Int>,
        secondaryMuscleIDs: Set<Int>
    ) -> ExerciseBodyMapHighlightSpec {
        let primary = regions(for: primaryMuscleIDs)
        let secondary = regions(for: secondaryMuscleIDs).subtracting(primary)
        return ExerciseBodyMapHighlightSpec(primaryRegions: primary, secondaryRegions: secondary)
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
