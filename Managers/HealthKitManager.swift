import Foundation
import HealthKit

// HealthKit과 상호작용하는 매니저 클래스
// - 앱 전역에서 하나만 쓰도록 Singleton( shared ) 패턴
// - 권한 요청/상태 확인/데이터 저장/조회/백그라운드 전달 설정까지 한 곳에서 관리
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    // HealthKit과 대화하는 핵심 객체
    let store = HKHealthStore()

    // UI 바인딩용 상태 값
    @Published var isAuthorized = false        // 권한 상태(대략적)
    @Published var authorizationError: Error?  // 권한 요청 중 에러 저장

    private init() {
        // 앱 시작 시 현재 권한 상태를 한 번 읽어 UI에 반영
        checkAuthorizationStatus()
    }

    // MARK: - 권한에 사용할 읽기/쓰기 타입 정의 (여기서는 혈당만)
    // 읽기 권한으로 요청할 타입(샘플 조회)
    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) {
            s.insert(glucose)
        }
        return s
    }

    // 쓰기 권한으로 요청할 타입(샘플 저장)
    private var writeTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = []
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) {
            s.insert(glucose)
        }
        return s
    }

    // MARK: - 권한 요청 (버튼 탭 등에서 호출)
    // 권한 요청 → 결과 반영까지 메인 액터에서 UI 상태 업데이트
    func requestAuthorization() async {
        print(" HealthKit 권한 요청 시작")
        print(" HealthKit 사용 가능: \(HKHealthStore.isHealthDataAvailable())")
        print(" 읽기 타입: \(readTypes)")
        print(" 쓰기 타입: \(writeTypes)")

        do {
            try await _requestAuthorization()
            await MainActor.run {
                // 권한 요청 이후 상태를 다시 계산해 UI에 반영
                self.checkAuthorizationStatus()
                self.authorizationError = nil
                print(" 권한 요청 완료. 현재 상태: \(self.authorizationStatusForBloodGlucose().rawValue)")
            }
        } catch {
            print(" 권한 요청 실패: \(error.localizedDescription)")
            await MainActor.run {
                self.authorizationError = error
                self.isAuthorized = false
            }
        }
    }

    // 실제 권한 요청 로직(검증 + 요청 + 결과 로그)
    private func _requestAuthorization() async throws {
        // 기기에서 HealthKit 사용 가능 여부(예: 일부 iPad 등은 불가)
        guard HKHealthStore.isHealthDataAvailable() else {
            print(" HealthKit 사용 불가")
            throw NSError(
                domain: "HealthKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "이 기기에서는 HealthKit을 사용할 수 없습니다."]
            )
        }

        // 요청 전 상태 확인 (디버깅용)
        let currentStatus = authorizationStatusForBloodGlucose()
        print(" 요청 전 권한 상태: \(currentStatus.rawValue)")

        // 요청할 타입이 비어 있으면 예외 처리
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

        // 실제 권한 요청
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        print(" 권한 요청 응답 받음")

        // 요청 후 상태 로그
        let newStatus = authorizationStatusForBloodGlucose()
        print(" 요청 후 권한 상태: \(newStatus.rawValue)")
    }

    // MARK: - 권한 상태 확인(혈당 타입 기준)
    // .notDetermined / .sharingDenied / .sharingAuthorized 중 하나 반환
    func authorizationStatusForBloodGlucose() -> HKAuthorizationStatus {
        guard let t = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            return .notDetermined
        }
        return store.authorizationStatus(for: t)
    }

    // 내부적으로 isAuthorized 값을 업데이트
    // (간편 표시용: notDetermined만 false, 나머지는 true로 취급)
    private func checkAuthorizationStatus() {
        let status = authorizationStatusForBloodGlucose()
        isAuthorized = status != .notDetermined
    }

    // MARK: - 데이터 쓰기 (혈당 저장)
    // 권한 체크 → 타입 생성 → 샘플 생성 → 저장
    func saveBloodGlucose(value: Double, date: Date = Date()) async throws {
        let status = authorizationStatusForBloodGlucose()
        guard status != .notDetermined else {
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit 권한이 필요합니다."]
            )
        }

        guard let bloodGlucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        // 단위 설정: mg/dL (필요 시 mmol/L 등으로 교체 가능)
        let unit = HKUnit(from: "mg/dL")
        let quantity = HKQuantity(unit: unit, doubleValue: value)

        // 시작/종료 시간을 동일하게 두면 '점 측정' 형태의 샘플
        let sample = HKQuantitySample(
            type: bloodGlucoseType,
            quantity: quantity,
            start: date,
            end: date
        )

        // 저장
        try await store.save(sample)
    }

    // MARK: - 데이터 읽기 (기간 조회)
    // 기간 조건 + 정렬 조건으로 HKSampleQuery 수행
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

        guard let bloodGlucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        // 조회 기간(시작~끝)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        // 최신 내림차순 정렬
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        // HealthKit의 콜백 기반 쿼리를 async/await로 감싸서 사용
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
                    let bloodGlucoseSamples = samples as? [HKQuantitySample] ?? []
                    continuation.resume(returning: bloodGlucoseSamples)
                }
            }

            // 쿼리 실행
            store.execute(query)
        }
    }

    // MARK: - 백그라운드 전달(enableBackgroundDelivery)
    // Health 앱/다른 소스에서 새로운 혈당 데이터가 들어오면
    // 앱이 백그라운드에 있어도 알림을 받을 수 있도록 설정
    // (실제 알림 처리: HKObserverQuery + 앱 권한/백그라운드 모드 설정 필요)
    func enableBackgroundDelivery() async throws {
        let status = authorizationStatusForBloodGlucose()
        guard status != .notDetermined else {
            throw NSError(
                domain: "HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit 권한이 필요합니다."]
            )
        }

        guard let bloodGlucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            throw NSError(
                domain: "HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "혈당 타입을 찾을 수 없습니다."]
            )
        }

        // frequency: .immediate → 데이터가 들어오면 즉시 전달 시도
        // 주의: 실제로는 ObserverQuery 등록 및 Background Modes 설정(HealthKit/Background fetch 등)이 함께 필요
        try await store.enableBackgroundDelivery(for: bloodGlucoseType, frequency: .immediate)
    }
}
