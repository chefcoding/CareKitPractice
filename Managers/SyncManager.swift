import CareKitStore
import Foundation
import HealthKit

// HealthKit ↔︎ CareKit 양방향 동기화를 담당하는 매니저
// - 백그라운드 전달 설정 (HealthKit -> 앱 깨우기)
// - HealthKit → CareKit 동기화
// - CareKit → HealthKit 동기화
// - 상태 바인딩(isSyncing, lastSyncDate)로 UI 연동
class SyncManager: ObservableObject {
    private let healthKitManager = HealthKitManager.shared
    private let careKitManager = CareKitManager.shared

    @Published var isSyncing = false   // 동기화 중 UI 스피너 등에 사용
    @Published var lastSyncDate: Date? // 마지막 동기화 완료 시각

    init() {
        setupBackgroundSync()
    }

    // MARK: - 백그라운드 동기화 준비
    // 앱이 포그라운드가 아니어도 HealthKit에 새 데이터가 들어오면
    // 앱이 깨워질 수 있도록 '백그라운드 전달'을 활성화
    // (실제 콜백 처리는 HKObserverQuery 등록이 필요하며, Background Modes도 설정해야 함)
    private func setupBackgroundSync() {
        Task {
            try? await healthKitManager.enableBackgroundDelivery()
        }
    }

    // MARK: - HealthKit → CareKit 동기화
    // 최근 30일 HealthKit 혈당 샘플을 읽어 CareKit Outcome으로 저장
    func syncFromHealthKitToCareKit() async throws {
        // 재진입 방지: 동시 실행으로 인한 중복/경쟁 상태를 예방
        guard !isSyncing else { return }

        // UI 상태는 메인 액터에서 업데이트
        await MainActor.run { isSyncing = true }
        // 함수가 어떤 이유로든 종료될 때 isSyncing=false 복구 보장
        defer { Task { await MainActor.run { isSyncing = false } } }

        // 동기화 구간: 종료=지금, 시작=30일 전
        let endDate = Date()
        let startDate =
            Calendar.current.date(byAdding: .day, value: -30, to: endDate)
            ?? endDate

        // 1) HealthKit에서 혈당 샘플 읽기
        let healthKitSamples = try await healthKitManager.fetchBloodGlucoseData(
            from: startDate,
            to: endDate
        )

        // 2) 각 샘플을 CareKit Outcome으로 저장
        for sample in healthKitSamples {
            // 필요 단위로 변환(mg/dL). mmol/L 등이 필요하다면 변환 로직 고려
            let value = sample.quantity.doubleValue(for: HKUnit(from: "mg/dL"))
            let date = sample.startDate // 점 측정의 기준 시각으로 사용

            // CareKit에 Outcome 기록(현재 구현은 단순 추가)
            // ⚠️ 실서비스에서는 '중복 방지'가 필요함:
            //  - HealthKit 샘플의 UUID를 CareKit Outcome.externalID로 저장해
            //    다음 동기화 때 동일 UUID 존재 여부로 중복 삽입 차단하는 전략 권장
            try await careKitManager.saveBloodGlucoseOutcome(
                value: value,
                date: date
            )
        }

        // 동기화 완료 시각 업데이트 (UI 반영)
        await MainActor.run {
            lastSyncDate = Date()
        }
    }

    // MARK: - CareKit → HealthKit 동기화
    // 최근 30일 CareKit Outcome을 읽어 HealthKit 샘플로 저장
    func syncFromCareKitToHealthKit() async throws {
        guard !isSyncing else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { await MainActor.run { isSyncing = false } } }

        let endDate = Date()
        let startDate =
            Calendar.current.date(byAdding: .day, value: -30, to: endDate)
            ?? endDate

        // 1) CareKit에서 Outcome 조회
        let careKitOutcomes =
            try await careKitManager.fetchBloodGlucoseOutcomes(
                from: startDate,
                to: endDate
            )

        // 2) Outcome → HealthKit 샘플 저장
        for outcome in careKitOutcomes {
            // Outcome에 여러 값이 있을 수 있으나 여기선 첫 번째만 사용
            if let value = outcome.values.first?.doubleValue {
                // createdDate를 샘플 시각으로 사용(없으면 지금 시각)
                // ⚠️ 데이터의 '의미 있는 시각'이 따로 있다면(예: 측정 시각),
                //    해당 메타데이터를 Outcome에 별도 저장해 사용하는 것이 이상적
                let date = outcome.createdDate ?? Date()

                // HealthKit에 기록(중복 방지/충돌 해결 전략은 서비스 요건에 맞게 보완)
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

    // MARK: - 양방향 전체 동기화
    // 순차 실행: HK→CK 먼저, 그 다음 CK→HK
    // ⚠️ 충돌 정책(conflict resolution)과 중복 정책(idempotency)은
    //     서비스 요건에 맞게 정의 필요
    func performBidirectionalSync() async throws {
        try await syncFromHealthKitToCareKit()
        try await syncFromCareKitToHealthKit()
    }
}
