import Foundation

protocol ExerciseCatalogRemoteClient {
    func fetchMuscles() async throws -> [RemoteMuscle]
    func fetchCategories() async throws -> [RemoteCategory]
    func fetchEquipment() async throws -> [RemoteEquipment]
    func fetchExerciseImages() async throws -> [RemoteExerciseImage]
    func fetchExercises(updatedAfter: Date?) async throws -> [RemoteExercise]
    func fetchDeletedExercises(deletedAfter: Date?) async throws -> RemoteDeletionBatch
}

struct RemoteMuscle: Sendable {
    let id: Int
    let name: String
    let nameEn: String
}

struct RemoteCategory: Sendable {
    let id: Int
    let name: String
}

struct RemoteEquipment: Sendable {
    let id: Int
    let name: String
}

struct RemoteExerciseImage: Sendable {
    let id: Int?
    let exerciseBaseID: Int
    let imageURL: String
    let licenseName: String
    let licenseURL: String
    let licenseAuthor: String
}

struct RemoteExercise: Sendable {
    let id: Int
    let exerciseBaseID: Int?
    let uuid: String
    let lastUpdateGlobal: Date?
    let name: String
    let aliases: [String]
    let categoryID: Int?
    let categoryName: String?
    let primaryMuscleIDs: [Int]
    let secondaryMuscleIDs: [Int]
    let equipmentIDs: [Int]
    let inlineImageURLs: [String]
}

struct RemoteDeletionBatch: Sendable {
    let deletedExerciseIDs: Set<Int>
    let deletedExerciseUUIDs: Set<String>

    static let empty = RemoteDeletionBatch(deletedExerciseIDs: [], deletedExerciseUUIDs: [])
}

final class WgerRemoteClient: ExerciseCatalogRemoteClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://wger.de/api/v2/")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchMuscles() async throws -> [RemoteMuscle] {
        let path = "muscle/"
        let pages: [WgerMuscleDTO] = try await fetchPaginated(path: path, queryItems: [URLQueryItem(name: "limit", value: "200")])
        return pages.map {
            RemoteMuscle(
                id: $0.id,
                name: $0.name ?? $0.nameEn ?? "Unknown",
                nameEn: $0.nameEn ?? $0.name ?? "Unknown"
            )
        }
    }

    func fetchCategories() async throws -> [RemoteCategory] {
        let path = "exercisecategory/"
        let pages: [WgerNamedEntityDTO] = try await fetchPaginated(path: path, queryItems: [URLQueryItem(name: "limit", value: "200")])
        return pages.map { RemoteCategory(id: $0.id, name: $0.name ?? "Unknown") }
    }

    func fetchEquipment() async throws -> [RemoteEquipment] {
        let path = "equipment/"
        let pages: [WgerNamedEntityDTO] = try await fetchPaginated(path: path, queryItems: [URLQueryItem(name: "limit", value: "200")])
        return pages.map { RemoteEquipment(id: $0.id, name: $0.name ?? "Unknown") }
    }

    func fetchExerciseImages() async throws -> [RemoteExerciseImage] {
        let path = "exerciseimage/"
        let pages: [WgerExerciseImageDTO] = try await fetchPaginated(path: path, queryItems: [URLQueryItem(name: "limit", value: "200")])
        return pages.compactMap { item in
            guard let exerciseBaseID = item.exerciseBaseID,
                  let imageURL = normalizeImageURL(item.imageURL)
            else {
                return nil
            }
            return RemoteExerciseImage(
                id: item.id,
                exerciseBaseID: exerciseBaseID,
                imageURL: imageURL,
                licenseName: item.license?.name ?? "Unknown",
                licenseURL: item.license?.url ?? "",
                licenseAuthor: item.licenseAuthor ?? ""
            )
        }
    }

    func fetchExercises(updatedAfter: Date?) async throws -> [RemoteExercise] {
        var queryItems = [URLQueryItem(name: "limit", value: "100")]
        if let updatedAfter {
            queryItems.append(URLQueryItem(
                name: "last_update_global__gte",
                value: WgerDateFormatter.queryString(from: updatedAfter)
            ))
        }

        let path = "exerciseinfo/"
        let pages: [WgerExerciseInfoDTO] = try await fetchPaginated(path: path, queryItems: queryItems)
        return pages.compactMap { item in
            let exerciseName = item.preferredName
            guard !exerciseName.isEmpty else { return nil }

            let aliases = item.aliases.filter { $0.caseInsensitiveCompare(exerciseName) != .orderedSame }
            let remoteUUID = item.uuid?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackUUID = "wger-\(item.id)"
            let parsedUpdateDate = item.lastUpdateGlobal.flatMap { WgerDateFormatter.parseISODate($0) }
            let normalizedInlineImageURLs = Array(Set(item.inlineImageURLs.compactMap(normalizeImageURL))).sorted()

            return RemoteExercise(
                id: item.id,
                exerciseBaseID: item.exerciseBaseID,
                uuid: (remoteUUID?.isEmpty == false ? remoteUUID! : fallbackUUID),
                lastUpdateGlobal: parsedUpdateDate,
                name: exerciseName,
                aliases: aliases,
                categoryID: item.categoryID,
                categoryName: item.categoryName,
                primaryMuscleIDs: item.primaryMuscleIDs,
                secondaryMuscleIDs: item.secondaryMuscleIDs,
                equipmentIDs: item.equipmentIDs,
                inlineImageURLs: normalizedInlineImageURLs
            )
        }
    }

    func fetchDeletedExercises(deletedAfter: Date?) async throws -> RemoteDeletionBatch {
        var queryItems = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "model", value: "exercisebase")
        ]

        if let deletedAfter {
            queryItems.append(URLQueryItem(
                name: "deleted_at__gte",
                value: WgerDateFormatter.queryString(from: deletedAfter)
            ))
        }

        let path = "deletion-log/"
        let pages: [WgerDeletionLogDTO] = try await fetchPaginated(path: path, queryItems: queryItems)
        let deletedIDs = Set(pages.compactMap(\.deletedObjectID))
        let deletedUUIDs = Set(pages.compactMap(\.deletedUUID))
        return RemoteDeletionBatch(deletedExerciseIDs: deletedIDs, deletedExerciseUUIDs: deletedUUIDs)
    }

    private func fetchPaginated<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> [T] {
        var allResults: [T] = []
        var nextURL: URL? = try makeURL(path: path, queryItems: queryItems)

        while let pageURL = nextURL {
            let (data, response) = try await session.data(from: pageURL)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw WgerRemoteClientError.invalidResponse
            }

            let page = try JSONDecoder.wger.decode(WgerPage<T>.self, from: data)
            allResults.append(contentsOf: page.results)

            if let next = page.next, let parsed = URL(string: next) {
                nextURL = parsed
            } else {
                nextURL = nil
            }
        }

        return allResults
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let endpointURL = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw WgerRemoteClientError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw WgerRemoteClientError.invalidURL
        }
        return url
    }

    private func normalizeImageURL(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            return normalizedAbsoluteHTTPURL(from: "https:\(trimmed)")
        }

        if let absolute = normalizedAbsoluteHTTPURL(from: trimmed) {
            return absolute
        }

        guard let resolved = URL(string: trimmed, relativeTo: originURL)?.absoluteURL else {
            return nil
        }

        return normalizedAbsoluteHTTPURL(from: resolved.absoluteString)
    }

    private func normalizedAbsoluteHTTPURL(from value: String) -> String? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil
        else {
            return nil
        }

        return url.absoluteString
    }

    private var originURL: URL {
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        return components.url ?? URL(string: "https://wger.de")!
    }
}

enum WgerRemoteClientError: Error {
    case invalidURL
    case invalidResponse
}

private struct WgerPage<T: Decodable>: Decodable {
    let results: [T]
    let next: String?
}

private struct WgerNamedEntityDTO: Decodable {
    let id: Int
    let name: String?
}

private struct WgerMuscleDTO: Decodable {
    let id: Int
    let name: String?
    let nameEn: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameEn = "name_en"
    }
}

private struct WgerLicenseDTO: Decodable {
    let id: Int?
    let name: String?
    let url: String?

    init(id: Int? = nil, name: String? = nil, url: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
    }

    init(from decoder: Decoder) throws {
        if let intContainer = try? decoder.singleValueContainer(), let id = try? intContainer.decode(Int.self) {
            self = WgerLicenseDTO(id: id, name: nil, url: nil)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackName = try? container.decode(String.self, forKey: .licenseTitle)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? (try? container.decode(String.self, forKey: .id)).flatMap(Int.init)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? fallbackName
        self.url = try? container.decode(String.self, forKey: .url)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case licenseTitle = "full_name"
    }
}

private struct WgerExerciseImageDTO: Decodable {
    let id: Int?
    let exerciseBaseID: Int?
    let imageURL: String?
    let licenseAuthor: String?
    let license: WgerLicenseDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseBaseID = "exercise_base"
        case imageURL = "image"
        case licenseAuthor = "license_author"
        case license
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = WgerLossyDecode.decodeInt(container: container, key: .id)
        exerciseBaseID = WgerLossyDecode.decodeInt(container: container, key: .exerciseBaseID)
        imageURL = WgerLossyDecode.decodeString(container: container, key: .imageURL)
        licenseAuthor = WgerLossyDecode.decodeString(container: container, key: .licenseAuthor)
        license = (try? container.decode(WgerLicenseDTO.self, forKey: .license))
    }
}

private struct WgerExerciseInfoDTO: Decodable {
    let id: Int
    let exerciseBaseID: Int?
    let uuid: String?
    let lastUpdateGlobal: String?
    let categoryID: Int?
    let categoryName: String?
    let primaryMuscleIDs: [Int]
    let secondaryMuscleIDs: [Int]
    let equipmentIDs: [Int]
    let translations: [WgerExerciseTranslationDTO]
    let inlineImageURLs: [String]

    var preferredName: String {
        let english = translations.first(where: { $0.language == 2 && !$0.name.isEmpty })
        if let englishName = english?.name {
            return englishName
        }
        return translations.first(where: { !$0.name.isEmpty })?.name ?? ""
    }

    var aliases: [String] {
        let names = translations.map(\.name)
        return Array(Set(names)).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseBase = "exercise_base"
        case uuid
        case lastUpdateGlobal = "last_update_global"
        case category
        case muscles
        case secondaryMuscles = "muscles_secondary"
        case equipment
        case translations
        case images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = WgerLossyDecode.decodeInt(container: container, key: .id) ?? -1
        exerciseBaseID = WgerLossyDecode.decodeInt(container: container, key: .exerciseBase)
        uuid = WgerLossyDecode.decodeString(container: container, key: .uuid)
        lastUpdateGlobal = WgerLossyDecode.decodeString(container: container, key: .lastUpdateGlobal)

        if let categoryObject = try? container.decode(WgerCategoryRefDTO.self, forKey: .category) {
            categoryID = categoryObject.id
            categoryName = categoryObject.name
        } else if let categoryID = WgerLossyDecode.decodeInt(container: container, key: .category) {
            self.categoryID = categoryID
            self.categoryName = nil
        } else {
            self.categoryID = nil
            self.categoryName = nil
        }

        primaryMuscleIDs = WgerLossyDecode.decodeIntArray(container: container, key: .muscles)
        secondaryMuscleIDs = WgerLossyDecode.decodeIntArray(container: container, key: .secondaryMuscles)
        equipmentIDs = WgerLossyDecode.decodeIntArray(container: container, key: .equipment)
        translations = (try? container.decode([WgerExerciseTranslationDTO].self, forKey: .translations)) ?? []

        let inlineImages = (try? container.decode([WgerInlineImageDTO].self, forKey: .images)) ?? []
        inlineImageURLs = inlineImages.compactMap(\.image)
    }
}

private struct WgerCategoryRefDTO: Decodable {
    let id: Int?
    let name: String?
}

private struct WgerExerciseTranslationDTO: Decodable {
    let language: Int?
    let name: String

    enum CodingKeys: String, CodingKey {
        case language
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = WgerLossyDecode.decodeInt(container: container, key: .language)
        name = WgerLossyDecode.decodeString(container: container, key: .name) ?? ""
    }
}

private struct WgerInlineImageDTO: Decodable {
    let image: String?
}

private struct WgerDeletionLogDTO: Decodable {
    let model: String?
    let deletedObjectID: Int?
    let deletedUUID: String?

    enum CodingKeys: String, CodingKey {
        case model
        case objectID = "object_id"
        case deletedObjectID = "deleted_object_id"
        case objectPK = "object_pk"
        case deletedUUID = "uuid"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = WgerLossyDecode.decodeString(container: container, key: .model)
        deletedUUID = WgerLossyDecode.decodeString(container: container, key: .deletedUUID)

        if let id = WgerLossyDecode.decodeInt(container: container, key: .deletedObjectID)
            ?? WgerLossyDecode.decodeInt(container: container, key: .objectID)
            ?? WgerLossyDecode.decodeInt(container: container, key: .objectPK) {
            deletedObjectID = id
        } else {
            deletedObjectID = nil
        }
    }
}

private enum WgerLossyDecode {
    static func decodeInt<Key: CodingKey>(container: KeyedDecodingContainer<Key>, key: Key) -> Int? {
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Int(stringValue)
        }
        if let nested = try? container.decode(WgerIDContainer.self, forKey: key) {
            return nested.id
        }
        return nil
    }

    static func decodeString<Key: CodingKey>(container: KeyedDecodingContainer<Key>, key: Key) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }
        return nil
    }

    static func decodeIntArray<Key: CodingKey>(container: KeyedDecodingContainer<Key>, key: Key) -> [Int] {
        if let values = try? container.decode([Int].self, forKey: key) {
            return values
        }

        if let stringValues = try? container.decode([String].self, forKey: key) {
            return stringValues.compactMap(Int.init)
        }

        if let objectValues = try? container.decode([WgerIDContainer].self, forKey: key) {
            return objectValues.compactMap(\.id)
        }

        return []
    }
}

private struct WgerIDContainer: Decodable {
    let id: Int?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let intValue = try? single.decode(Int.self) {
            id = intValue
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(Int.self, forKey: .id)) ?? (try? container.decode(String.self, forKey: .id)).flatMap(Int.init)
    }

    enum CodingKeys: String, CodingKey {
        case id
    }
}

enum WgerDateFormatter {
    static func parseISODate(_ value: String) -> Date? {
        if let withFractions = isoWithFractions.date(from: value) {
            return withFractions
        }
        return isoBasic.date(from: value)
    }

    static func queryString(from date: Date) -> String {
        isoWithFractions.string(from: date)
    }

    private static let isoWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension JSONDecoder {
    static var wger: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
