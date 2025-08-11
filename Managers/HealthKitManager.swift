import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var authorizationError: Error?

    private init() {
        checkAuthorizationStatus()
    }

    // 읽기/쓰기 타입 정의 (예: 혈당)
    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        {
            s.insert(glucose)
        }
        return s
    }

    private var writeTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = []
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        {
            s.insert(glucose)
        }
        return s
    }

    func requestAuthorization() async {
        print(" HealthKit 권한 요청 시작")
        print(" HealthKit 사용 가능: \(HKHealthStore.isHealthDataAvailable())")
        print(" 읽기 타입: \(readTypes)")
        print(" 쓰기 타입: \(writeTypes)")

        do {
            try await _requestAuthorization()
            await MainActor.run {
                self.checkAuthorizationStatus()
                self.authorizationError = nil
                print(
                    " 권한 요청 완료. 현재 상태: \(self.authorizationStatusForBloodGlucose().rawValue)"
                )
            }
        } catch {
            print(" 권한 요청 실패: \(error.localizedDescription)")
            await MainActor.run {
                self.authorizationError = error
                self.isAuthorized = false
            }
        }
    }

    private func _requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            print(" HealthKit 사용 불가")
            throw NSError(
                domain: "HealthKit",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "이 기기에서는 HealthKit을 사용할 수 없습니다."
                ]
            )
        }

        // 권한 요청 전 현재 상태 확인
        let currentStatus = authorizationStatusForBloodGlucose()
        print(" 요청 전 권한 상태: \(currentStatus.rawValue)")

        // 빈 세트가 아닌지 확인
        guard !readTypes.isEmpty && !writeTypes.isEmpty else {
            print(" 권한 타입이 비어있음")
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "권한 타입이 설정되지 않았습니다."]
            )
        }

        print(" 권한 요청 중...")
        print(" 요청할 읽기 권한: \(readTypes.count)개")
        print(" 요청할 쓰기 권한: \(writeTypes.count)개")

        try await store.requestAuthorization(
            toShare: writeTypes,
            read: readTypes
        )
        print(" 권한 요청 응답 받음")

        // 권한 요청 후 상태 확인
        let newStatus = authorizationStatusForBloodGlucose()
        print(" 요청 후 권한 상태: \(newStatus.rawValue)")
    }

    func authorizationStatusForBloodGlucose() -> HKAuthorizationStatus {
        guard let t = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        else { return .notDetermined }
        return store.authorizationStatus(for: t)
    }

    private func checkAuthorizationStatus() {
        let status = authorizationStatusForBloodGlucose()
        isAuthorized = status != .notDetermined
    }

    func saveBloodGlucose(value: Double, date: Date = Date()) async throws {
        let status = authorizationStatusForBloodGlucose()
        guard status != .notDetermined else {
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit 권한이 필요합니다."]
            )
        }

        guard
            let bloodGlucoseType = HKObjectType.quantityType(
                forIdentifier: .bloodGlucose
            )
        else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        let unit = HKUnit(from: "mg/dL")
        let quantity = HKQuantity(unit: unit, doubleValue: value)

        let sample = HKQuantitySample(
            type: bloodGlucoseType,
            quantity: quantity,
            start: date,
            end: date
        )

        try await store.save(sample)
    }

    func fetchBloodGlucoseData(from startDate: Date, to endDate: Date)
        async throws -> [HKQuantitySample]
    {
        let status = authorizationStatusForBloodGlucose()
        guard status != .notDetermined else {
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit 권한이 필요합니다."]
            )
        }

        guard
            let bloodGlucoseType = HKObjectType.quantityType(
                forIdentifier: .bloodGlucose
            )
        else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate
        )
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bloodGlucoseType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let bloodGlucoseSamples =
                        samples as? [HKQuantitySample] ?? []
                    continuation.resume(returning: bloodGlucoseSamples)
                }
            }

            store.execute(query)
        }
    }

    func enableBackgroundDelivery() async throws {
        let status = authorizationStatusForBloodGlucose()
        guard status != .notDetermined else {
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit 권한이 필요합니다."]
            )
        }

        guard
            let bloodGlucoseType = HKObjectType.quantityType(
                forIdentifier: .bloodGlucose
            )
        else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        try await store.enableBackgroundDelivery(
            for: bloodGlucoseType,
            frequency: .immediate
        )
    }
}
