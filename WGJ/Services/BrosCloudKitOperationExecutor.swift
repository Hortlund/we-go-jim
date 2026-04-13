import CloudKit
import Foundation

enum BrosCloudKitOperationExecutor {
    static func queryRecords(
        in database: CKDatabase,
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor],
        request: BrosCloudKitRequestProfile,
        cursor: CKQueryOperation.Cursor? = nil
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<([CKRecord], CKQueryOperation.Cursor?), Error>) in
            var didResume = false
            func finish(_ result: Result<([CKRecord], CKQueryOperation.Cursor?), Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: recordType, predicate: predicate)
                query.sortDescriptors = sortDescriptors
                operation = CKQueryOperation(query: query)
            }
            operation.resultsLimit = request.resultsLimit
            operation.qualityOfService = request.qualityOfService
            operation.desiredKeys = request.desiredKeys

            var fetched: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    fetched.append(record)
                case .failure(let error):
                    finish(.failure(error))
                }
            }

            operation.queryResultBlock = { result in
                finish(result.map { cursor in (fetched, cursor) })
            }

            database.add(operation)
        }
    }

    static func fetchRecords(
        in database: CKDatabase,
        recordIDs: [CKRecord.ID],
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord] {
        guard !recordIDs.isEmpty else { return [] }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
            var didResume = false
            func finish(_ result: Result<[CKRecord], Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.desiredKeys = request.desiredKeys
            operation.qualityOfService = request.qualityOfService

            var recordsByID: [CKRecord.ID: CKRecord] = [:]
            operation.perRecordResultBlock = { recordID, result in
                switch result {
                case .success(let record):
                    recordsByID[recordID] = record
                case .failure(let error):
                    finish(.failure(error))
                }
            }

            operation.fetchRecordsResultBlock = { result in
                finish(result.map { _ in
                    recordsByID.values.sorted {
                        $0.recordID.recordName.localizedStandardCompare($1.recordID.recordName) == .orderedAscending
                    }
                })
            }

            database.add(operation)
        }
    }

    static func saveRecords(
        in database: CKDatabase,
        records: [CKRecord],
        deleting recordIDs: [CKRecord.ID]
    ) async throws {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            func finish(_ result: Result<Void, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: recordIDs)
            operation.savePolicy = .allKeys
            operation.isAtomic = true
            operation.qualityOfService = .userInitiated
            operation.modifyRecordsResultBlock = { result in
                finish(result.map { _ in })
            }
            database.add(operation)
        }
    }

    static func saveSubscriptions(
        in database: CKDatabase,
        subscriptions: [CKSubscription],
        deleting subscriptionIDs: [CKSubscription.ID]
    ) async throws {
        guard !subscriptions.isEmpty || !subscriptionIDs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false
            func finish(_ result: Result<Void, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let operation = CKModifySubscriptionsOperation(
                subscriptionsToSave: subscriptions,
                subscriptionIDsToDelete: subscriptionIDs
            )
            operation.qualityOfService = .userInitiated
            operation.modifySubscriptionsResultBlock = { result in
                finish(result.map { _ in })
            }
            database.add(operation)
        }
    }
}
