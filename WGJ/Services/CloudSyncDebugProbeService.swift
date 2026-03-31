import CloudKit
import Foundation
import UIKit

struct CloudSyncDebugProbeDescriptor: Equatable {
    static let recordType = "WGJDebugSyncProbe"
    static let recordName = "current-user"
    static let zoneName = "_defaultZone"

    let updatedAt: Date
    let profileName: String
    let templateCount: Int
    let workoutCount: Int

    var databaseName: String { "Private Database" }
    var consoleEnvironmentName: String { "Development" }
}

struct CloudSyncDebugProbeVerification: Equatable {
    let verifiedAt: Date
    let directLookupStatus: String
    let indexedQueryStatus: String
}

struct CloudSyncDebugProbeService {
    private enum Field {
        static let probeKey = "probeKey"
        static let profileName = "profileName"
        static let templateCount = "templateCount"
        static let workoutCount = "workoutCount"
        static let updatedAt = "updatedAt"
        static let deviceName = "deviceName"
        static let buildConfiguration = "buildConfiguration"
    }

    private let database: CKDatabase?

    init(container: CKContainer? = nil) {
        self.database = (container ?? AppRuntimeConfig.makeCloudKitContainer())?.privateCloudDatabase
    }

    func writeProbe(
        profileName: String?,
        templateCount: Int,
        workoutCount: Int
    ) async throws -> CloudSyncDebugProbeDescriptor {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: CloudSyncDebugProbeDescriptor.recordName)
        let record = try await existingRecord(recordID: recordID)
            ?? CKRecord(recordType: CloudSyncDebugProbeDescriptor.recordType, recordID: recordID)

        let updatedAt = Date()
        let normalizedProfileName = normalizedProfileName(from: profileName)

        record[Field.probeKey] = CloudSyncDebugProbeDescriptor.recordName as CKRecordValue
        record[Field.profileName] = normalizedProfileName as CKRecordValue
        record[Field.templateCount] = NSNumber(value: templateCount)
        record[Field.workoutCount] = NSNumber(value: workoutCount)
        record[Field.updatedAt] = updatedAt as CKRecordValue
        record[Field.deviceName] = UIDevice.current.name as CKRecordValue
        record[Field.buildConfiguration] = buildConfiguration as CKRecordValue

        _ = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )

        return CloudSyncDebugProbeDescriptor(
            updatedAt: updatedAt,
            profileName: normalizedProfileName,
            templateCount: templateCount,
            workoutCount: workoutCount
        )
    }

    func verifyProbe() async throws -> CloudSyncDebugProbeVerification {
        _ = try requireDatabase()
        let recordID = CKRecord.ID(recordName: CloudSyncDebugProbeDescriptor.recordName)
        let directRecord = try await existingRecord(recordID: recordID)

        let directLookupStatus: String
        if directRecord != nil {
            directLookupStatus = "Succeeded"
        } else {
            directLookupStatus = "Missing"
        }

        let indexedQueryStatus: String
        do {
            let record = try await queriedProbeRecord()
            indexedQueryStatus = record == nil ? "No match" : "Succeeded"
        } catch {
            indexedQueryStatus = Self.describe(error)
        }

        return CloudSyncDebugProbeVerification(
            verifiedAt: Date(),
            directLookupStatus: directLookupStatus,
            indexedQueryStatus: indexedQueryStatus
        )
    }

    private func existingRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        let database = try requireDatabase()
        do {
            let results = try await database.records(for: [recordID])
            guard let result = results[recordID] else {
                return nil
            }

            switch result {
            case let .success(record):
                return record
            case let .failure(error as CKError) where error.code == .unknownItem:
                return nil
            case let .failure(error):
                throw error
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func normalizedProfileName(from profileName: String?) -> String {
        let trimmed = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func queriedProbeRecord() async throws -> CKRecord? {
        let database = try requireDatabase()
        let query = CKQuery(
            recordType: CloudSyncDebugProbeDescriptor.recordType,
            predicate: NSPredicate(
                format: "%K == %@",
                Field.probeKey,
                CloudSyncDebugProbeDescriptor.recordName
            )
        )

        let result = try await database.records(matching: query, resultsLimit: 1)
        for (_, matchResult) in result.matchResults {
            switch matchResult {
            case let .success(record):
                return record
            case let .failure(error):
                throw error
            }
        }

        return nil
    }

    private func requireDatabase() throws -> CKDatabase {
        guard let database else {
            throw CloudKitContainerAvailabilityError.unavailable
        }

        return database
    }

    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }
}
