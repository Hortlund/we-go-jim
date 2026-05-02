import Testing
@testable import WGJ

struct ExerciseBodyMapRegionMapperTests {
    @Test
    func mapsEverySeedMuscleGroupToAtLeastOneBodyMapRegion() {
        for muscleID in 1...13 {
            let spec = ExerciseBodyMapRegionMapper.highlightSpec(
                primaryMuscleIDs: [muscleID],
                secondaryMuscleIDs: []
            )

            #expect(!spec.primaryRegions.isEmpty)
            #expect(spec.secondaryRegions.isEmpty)
        }
    }

    @Test
    func mapsSeedMuscleGroupsToExpectedBodyMapRegions() {
        let expectedRegionsByMuscleID: [Int: Set<ExerciseBodyMapRegion>] = [
            1: [.biceps],
            2: [.deltoids],
            3: [.chest],
            4: [.lowerBack, .rhomboids, .upperBack],
            5: [.quadriceps],
            6: [.hamstring],
            7: [.gluteal],
            8: [.triceps],
            9: [.calves],
            10: [.abs, .obliques],
            11: [.forearm],
            12: [.trapezius],
            13: [.adductors],
            14: [],
        ]

        for (muscleID, expectedRegions) in expectedRegionsByMuscleID {
            let spec = ExerciseBodyMapRegionMapper.highlightSpec(
                primaryMuscleIDs: [muscleID],
                secondaryMuscleIDs: []
            )

            #expect(spec.primaryRegions == expectedRegions)
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

    @Test
    func resolvesBodyMapRegionToAvailableCatalogMuscleID() {
        let muscles = [
            ExerciseBodyMapFilterOption(id: 3, name: "Chest"),
            ExerciseBodyMapFilterOption(id: 10, name: "Abs"),
        ]

        #expect(ExerciseBodyMapRegionMapper.catalogMuscleID(for: .chest, availableMuscles: muscles) == 3)
        #expect(ExerciseBodyMapRegionMapper.catalogMuscleID(for: .obliques, availableMuscles: muscles) == 10)
        #expect(ExerciseBodyMapRegionMapper.catalogMuscleID(for: .quadriceps, availableMuscles: muscles) == nil)
    }

    @Test
    func resolvesTappedMuscleMapSubgroupsBeforeParentGroups() {
        let muscles = [
            ExerciseBodyMapFilterOption(id: 6, name: "Hamstrings"),
            ExerciseBodyMapFilterOption(id: 7, name: "Glutes"),
            ExerciseBodyMapFilterOption(id: 13, name: "Adductors"),
        ]

        #expect(
            ExerciseBodyMapRegionMapper.catalogMuscleID(
                muscleMapRawValue: "adductors",
                parentMuscleMapRawValue: "hamstring",
                availableMuscles: muscles
            ) == 13
        )
        #expect(
            ExerciseBodyMapRegionMapper.catalogMuscleID(
                muscleMapRawValue: "gluteal",
                parentMuscleMapRawValue: nil,
                availableMuscles: muscles
            ) == 7
        )
    }

    @Test
    func prefersExactCatalogNameWhenMultipleMusclesShareBodyMapRegion() {
        let muscles = [
            ExerciseBodyMapFilterOption(id: 14, name: "Abductors"),
            ExerciseBodyMapFilterOption(id: 7, name: "Glutes"),
        ]

        #expect(ExerciseBodyMapRegionMapper.catalogMuscleID(for: .gluteal, availableMuscles: muscles) == 7)
    }

    @Test
    func abductorsDoNotPretendToBeGlutesOnBodyMap() {
        let spec = ExerciseBodyMapRegionMapper.highlightSpec(
            primaryMuscleIDs: [14],
            secondaryMuscleIDs: []
        )

        #expect(spec.primaryRegions.isEmpty)
        #expect(spec.secondaryRegions.isEmpty)
    }
}
