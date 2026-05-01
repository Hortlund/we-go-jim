import Testing
@testable import WGJ

struct ExerciseBodyMapRegionMapperTests {
    @Test
    func mapsEverySeedMuscleGroupToAtLeastOneBodyMapRegion() {
        for muscleID in 1...14 {
            let spec = ExerciseBodyMapRegionMapper.highlightSpec(
                primaryMuscleIDs: [muscleID],
                secondaryMuscleIDs: []
            )

            #expect(!spec.primaryRegions.isEmpty)
            #expect(spec.secondaryRegions.isEmpty)
        }
    }

    @Test
    func mapsCompoundExerciseMusclesAndKeepsPrimaryStrongerThanSecondary() {
        let spec = ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: [5],
            secondaryMuscleIDs: [7, 6, 5]
        )

        #expect(spec.primaryRegions == [.quadriceps])
        #expect(spec.secondaryRegions == [.gluteal, .hamstring])
    }

    @Test
    func mapsBackAndAbsToUsefulCompoundRegions() {
        let back = ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: [4],
            secondaryMuscleIDs: []
        )
        let abs = ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: [10],
            secondaryMuscleIDs: []
        )

        #expect(back.primaryRegions == [.lowerBack, .rhomboids, .upperBack])
        #expect(abs.primaryRegions == [.abs, .obliques])
    }
}
