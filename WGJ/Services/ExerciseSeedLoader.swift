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
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            throw ExerciseSeedLoaderError.seedNotFound
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExerciseSeedPayload.self, from: data)
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
