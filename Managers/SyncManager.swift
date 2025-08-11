import CareKitStore
import Foundation
import HealthKit

class SyncManager: ObservableObject {
    private let healthKitManager = HealthKitManager.shared
    private let careKitManager = CareKitManager.shared

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    init() {
        setupBackgroundSync()
    }

    private func setupBackgroundSync() {
        Task {
            try? await healthKitManager.enableBackgroundDelivery()
        }
    }

    func syncFromHealthKitToCareKit() async throws {
        guard !isSyncing else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { await MainActor.run { isSyncing = false } } }

        let endDate = Date()
        let startDate =
            Calendar.current.date(byAdding: .day, value: -30, to: endDate)
            ?? endDate

        let healthKitSamples = try await healthKitManager.fetchBloodGlucoseData(
            from: startDate,
            to: endDate
        )

        for sample in healthKitSamples {
            let value = sample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))
            let date = sample.startDate

            try await careKitManager.saveBloodGlucoseOutcome(
                value: value,
                date: date
            )
        }

        await MainActor.run {
            lastSyncDate = Date()
        }
    }

    func syncFromCareKitToHealthKit() async throws {
        guard !isSyncing else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { await MainActor.run { isSyncing = false } } }

        let endDate = Date()
        let startDate =
            Calendar.current.date(byAdding: .day, value: -30, to: endDate)
            ?? endDate

        let careKitOutcomes =
            try await careKitManager.fetchBloodGlucoseOutcomes(
                from: startDate,
                to: endDate
            )

        for outcome in careKitOutcomes {
            if let value = outcome.values.first?.doubleValue {
                let date = outcome.createdDate ?? Date()
                try await healthKitManager.saveBloodGlucose(
                    value: value,
                    date: date
                )
            }
        }

        await MainActor.run {
            lastSyncDate = Date()
        }
    }

    func performBidirectionalSync() async throws {
        try await syncFromHealthKitToCareKit()
        try await syncFromCareKitToHealthKit()
    }
}
