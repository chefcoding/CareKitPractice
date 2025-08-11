import CareKit         // CareKit: 헬스케어 앱에서 '활동(Task)'과 '결과(Outcome)'를 관리하는 UI/로직 프레임워크
import CareKitStore    // CareKitStore: CareKit의 데이터 저장소. Task, Outcome 등을 저장/조회 가능
import Foundation      // Swift 기본 기능 제공

// CareKit 데이터와 상호작용하는 매니저 클래스
// 앱 전역에서 하나만 존재하도록 Singleton 패턴 사용 (shared 인스턴스)
class CareKitManager: ObservableObject {
    static let shared = CareKitManager()  // 전역에서 접근할 수 있는 인스턴스

    let store: OCKStore   // CareKit의 핵심 데이터베이스 역할

    // 생성자: OCKStore 초기화 및 기본 Task 등록
    private init() {
        // 로컬 저장소 생성 (이름: BloodGlucoseStore)
        store = OCKStore(name: "BloodGlucoseStore")
        setupTasks() // 앱 실행 시 기본 Task(혈당 측정) 생성
    }

    // 앱 시작 시 Task 생성 작업 실행
    private func setupTasks() {
        // Swift Concurrency를 사용해 비동기 작업 실행
        Task {
            await createBloodGlucoseTask()
        }
    }

    // '혈당 측정' Task를 CareKit에 등록하는 메서드
    private func createBloodGlucoseTask() async {
        // OCKTask: 사용자가 해야 하는 활동 정의
        let bloodGlucoseTask = OCKTask(
            id: "bloodGlucose",              // Task 식별자
            title: "혈당 측정",                 // UI에 표시될 제목
            carePlanUUID: nil,               // Care Plan(관리 계획)에 연결할 경우 UUID 필요
            schedule: OCKSchedule.dailyAtTime( // 매일 특정 시간에 반복되는 스케줄 생성
                hour: 0,
                minutes: 0,
                start: Date(),               // 오늘부터 시작
                end: nil,                     // 종료일 없음
                text: "혈당을 기록하세요"       // Task 설명
            )
        )

        do {
            // Task를 데이터베이스에 추가
            _ = try await store.addTask(bloodGlucoseTask)
        } catch {
            // 이미 존재하는 Task라면 추가하지 않음
            if error.localizedDescription.contains("already exists")
                || error.localizedDescription.contains("duplicate") {
                return
            }
            print("Failed to add blood glucose task: \(error)")
        }
    }

    // '혈당 측정' 결과(Outcome) 저장
    func saveBloodGlucoseOutcome(value: Double, date: Date = Date())
        async throws
    {
        // OCKOutcomeValue: Task 수행 결과 값 (혈당 값과 단위)
        let outcomeValue = OCKOutcomeValue(value, units: "mg/dL")

        // OCKOutcome: 실제 수행된 Task의 결과 기록
        let outcome = OCKOutcome(
            taskUUID: try await getTaskUUID(for: "bloodGlucose"), // Task 식별용 UUID 가져오기
            taskOccurrenceIndex: 0, // 하루에 여러 번 반복되는 Task일 경우 순번 (0 = 첫 번째)
            values: [outcomeValue]
        )

        // Outcome을 저장소에 추가
        try await store.addOutcome(outcome)
    }

    // Task의 UUID를 조회하는 헬퍼 메서드
    private func getTaskUUID(for taskID: String) async throws -> UUID {
        // 오늘 날짜를 기준으로 Task 조회
        var query = OCKTaskQuery(for: Date())
        query.ids = [taskID] // 특정 ID의 Task만 검색

        let tasks = try await store.fetchTasks(query: query)
        guard let task = tasks.first else {
            throw CareKitError.taskNotFound // Task를 찾지 못한 경우
        }

        return task.uuid // Task 식별용 UUID 반환
    }

    // 특정 기간(startDate ~ endDate)의 혈당 측정 결과를 가져오기
    func fetchBloodGlucoseOutcomes(from startDate: Date, to endDate: Date)
        async throws -> [OCKOutcome]
    {
        // Outcome 검색 조건 생성 (기간 지정)
        let query = OCKOutcomeQuery(
            dateInterval: DateInterval(start: startDate, end: endDate)
        )

        // Outcome 목록 반환
        return try await store.fetchOutcomes(query: query)
    }
}

// CareKit 관련 에러 정의
enum CareKitError: Error, LocalizedError {
    case taskNotFound     // Task를 찾지 못한 경우
    case invalidOutcome   // 잘못된 Outcome 데이터

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            return "Task not found"
        case .invalidOutcome:
            return "Invalid outcome data"
        }
    }
}
