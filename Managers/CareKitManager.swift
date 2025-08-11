import CareKit
import CareKitStore
import Foundation

class CareKitManager: ObservableObject {
    static let shared = CareKitManager()

    let store: OCKStore

    private init() {
        store = OCKStore(name: "BloodGlucoseStore")
        setupTasks()
    }

    private func setupTasks() {
        Task {
            await createBloodGlucoseTask()
        }
    }

    private func createBloodGlucoseTask() async {
        let bloodGlucoseTask = OCKTask(
            id: "bloodGlucose",
            title: "혈당 측정",
            carePlanUUID: nil,
            schedule: OCKSchedule.dailyAtTime(
                hour: 0,
                minutes: 0,
                start: Date(),
                end: nil,
                text: "혈당을 기록하세요"
            )
        )

        do {
            _ = try await store.addTask(bloodGlucoseTask)
        } catch {
            if error.localizedDescription.contains("already exists")
                || error.localizedDescription.contains("duplicate")
            {
                return
            }
            print("Failed to add blood glucose task: \(error)")
        }
    }

    func saveBloodGlucoseOutcome(value: Double, date: Date = Date())
        async throws
    {
        let outcomeValue = OCKOutcomeValue(value, units: "mg/dL")
        let outcome = OCKOutcome(
            taskUUID: try await getTaskUUID(for: "bloodGlucose"),
            taskOccurrenceIndex: 0,
            values: [outcomeValue]
        )

        try await store.addOutcome(outcome)
    }

    private func getTaskUUID(for taskID: String) async throws -> UUID {
        var query = OCKTaskQuery(for: Date())
        query.ids = [taskID]

        let tasks = try await store.fetchTasks(query: query)
        guard let task = tasks.first else {
            throw CareKitError.taskNotFound
        }

        return task.uuid
    }

    func fetchBloodGlucoseOutcomes(from startDate: Date, to endDate: Date)
        async throws -> [OCKOutcome]
    {
        let query = OCKOutcomeQuery(
            dateInterval: DateInterval(start: startDate, end: endDate)
        )
        return try await store.fetchOutcomes(query: query)
    }
}

enum CareKitError: Error, LocalizedError {
    case taskNotFound
    case invalidOutcome

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            return "Task not found"
        case .invalidOutcome:
            return "Invalid outcome data"
        }
    }
}
