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

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer? = nil) {
        let resolvedContainer = container ?? CKContainer(identifier: AppRuntimeConfig.cloudKitContainerIdentifier)
        self.container = resolvedContainer
        self.database = resolvedContainer.privateCloudDatabase
    }

    func writeProbe(
        profileName: String?,
        templateCount: Int,
        workoutCount: Int
    ) async throws -> CloudSyncDebugProbeDescriptor {
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

    private func existingRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
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

    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }
}
