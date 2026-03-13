import Foundation

protocol ExerciseSeedLoading {
    func loadSeed() throws -> ExerciseSeedPayload
}

struct BundleExerciseSeedLoader: ExerciseSeedLoading {
    let bundle: Bundle
    let fileName: String

    init(bundle: Bundle = .main, fileName: String = "ExercisesSeed") {
        self.bundle = bundle
        self.fileName = fileName
    }

    func loadSeed() throws -> ExerciseSeedPayload {
        if let url = bundle.url(forResource: fileName, withExtension: "json") {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ExerciseSeedPayload.self, from: data)
        }

        guard let fallbackData = fallbackSeedJSON.data(using: .utf8) else {
            throw ExerciseSeedLoaderError.seedNotFound
        }
        return try JSONDecoder().decode(ExerciseSeedPayload.self, from: fallbackData)
    }
}

enum ExerciseSeedLoaderError: Error {
    case seedNotFound
}

struct ExerciseSeedPayload: Decodable, Sendable {
    let version: Int
    let generatedAt: String?
    let muscles: [SeedMuscle]
    let exercises: [SeedExercise]
}

struct SeedMuscle: Decodable, Sendable {
    let id: Int
    let name: String
    let nameEn: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameEn = "name_en"
    }
}

struct SeedExercise: Decodable, Sendable {
    let remoteID: Int?
    let uuid: String
    let name: String
    let aliases: [String]
    let categoryName: String
    let equipmentSummary: String
    let instructions: String?
    let primaryMuscleIDs: [Int]
    let secondaryMuscleIDs: [Int]
    let imageURL: String?
    let sourceURL: String
    let licenseName: String
    let licenseURL: String
    let licenseAuthor: String
    let isCurated: Bool

    enum CodingKeys: String, CodingKey {
        case remoteID = "remote_id"
        case uuid
        case name
        case aliases
        case categoryName = "category"
        case equipmentSummary = "equipment"
        case instructions
        case primaryMuscleIDs = "primary_muscles"
        case secondaryMuscleIDs = "secondary_muscles"
        case imageURL = "image_url"
        case sourceURL = "source_url"
        case licenseName = "license_name"
        case licenseURL = "license_url"
        case licenseAuthor = "license_author"
        case isCurated = "is_curated"
    }
}

private let fallbackSeedJSON = #"""
{
  "version": 1,
  "generatedAt": "2026-02-06T00:00:00Z",
  "muscles": [
    { "id": 1, "name": "Biceps", "name_en": "Biceps" },
    { "id": 2, "name": "Shoulders", "name_en": "Shoulders" },
    { "id": 3, "name": "Chest", "name_en": "Chest" },
    { "id": 4, "name": "Back", "name_en": "Back" },
    { "id": 5, "name": "Quadriceps", "name_en": "Quadriceps" },
    { "id": 6, "name": "Hamstrings", "name_en": "Hamstrings" },
    { "id": 7, "name": "Glutes", "name_en": "Glutes" }
  ],
  "exercises": [
    {
      "remote_id": 1,
      "uuid": "seed-back-squat",
      "name": "Barbell Back Squat",
      "aliases": ["Squat"],
      "category": "Legs",
      "equipment": "Barbell,Rack",
      "instructions": "Brace your torso, sit between your hips, keep the bar over mid-foot, and drive up without letting your knees cave in.",
      "primary_muscles": [5],
      "secondary_muscles": [7,6],
      "image_url": "",
      "source_url": "",
      "license_name": "Bundled with WGJ",
      "license_url": "",
      "license_author": "WGJ",
      "is_curated": true
    }
  ]
}
"""#
