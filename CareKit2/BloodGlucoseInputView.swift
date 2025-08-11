import HealthKit
import SwiftUI

// 혈당 값을 입력해서 HealthKit과 CareKit 모두에 저장하는 화면
// - 처음 진입 시 권한을 요청(.task 모디파이어)
// - 권한이 없으면 권한 안내 UI 노출
// - 권한이 있으면 혈당 입력 + 저장 버튼 노출
struct BloodGlucoseInputView: View {
    // HealthKit 매니저 (싱글턴). @StateObject로 관찰하여 권한/오류 변화에 반응
    @StateObject private var healthKitManager = HealthKitManager.shared

    // 사용자가 입력하는 혈당 텍스트(숫자 문자열)
    @State private var bloodGlucoseValue = ""

    // 저장 중 로딩 인디케이터 상태
    @State private var isLoading = false

    // 저장 성공/실패 결과를 사용자에게 알려줄 알럿 상태
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                headerView // 상단 타이틀/아이콘

                // 권한 유무에 따라 다른 섹션 표시
                if !healthKitManager.isAuthorized {
                    // 권한이 없으면: 권한 안내 + 요청 버튼
                    authorizationView
                } else {
                    // 권한이 있으면: 입력 필드 + 저장 버튼
                    inputSection
                    actionButton
                }

                Spacer()
            }
            .padding()
            .navigationTitle("혈당 관리")
            .navigationBarTitleDisplayMode(.large)
        }
        // 저장 결과를 사용자에게 알려주는 알럿
        .alert("알림", isPresented: $showAlert) {
            Button("확인") {}
        } message: {
            Text(alertMessage)
        }
        // 화면이 나타나면 권한 요청(최초 1회). 시스템 다이얼로그가 나타남
        .task {
            await healthKitManager.requestAuthorization()
        }
    }

    // MARK: - 헤더 뷰 (아이콘 + 제목)
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 60))

            Text("혈당 수치를 입력하세요")
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - 입력 섹션 (권한 허용 후 표시)
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("혈당 수치")
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                // 숫자만 입력하도록 decimalPad 사용
                TextField("혈당 수치를 입력하세요", text: $bloodGlucoseValue)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.title3)

                // 단위 표기: 여기서는 mg/dL (필요 시 mmol/L 변환 로직 추가 가능)
                Text("mg/dL")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // 참고용 텍스트 (고정 문구이므로 실제 의료적 판단에는 사용 금지)
            Text("정상 범위: 70-100 mg/dL (공복시)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 권한 안내 뷰 (권한 미허용 시 표시)
    private var authorizationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 50))

            Text("HealthKit 권한이 필요합니다")
                .font(.title2)
                .fontWeight(.medium)

            Text("혈당 데이터를 건강 앱에 저장하려면\nHealthKit 접근 권한이 필요합니다.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // 개발 중 문제 파악을 위한 간단한 디버깅 정보(릴리스 빌드에서는 숨기는 것을 권장)
            VStack(alignment: .leading, spacing: 4) {
                Text("디버깅 정보:")
                    .font(.caption)
                    .fontWeight(.bold)
                Text("HealthKit 사용 가능: \(HKHealthStore.isHealthDataAvailable() ? "예" : "아니오")")
                    .font(.caption)
                Text("현재 권한 상태: \(authorizationStatusText)")
                    .font(.caption)
                if let error = healthKitManager.authorizationError {
                    Text("오류: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // 사용자 액션으로 권한 다이얼로그를 재요청
            Button("권한 요청하기") {
                print("사용자가 권한 요청 버튼 클릭")
                Task {
                    await healthKitManager.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    // 권한 상태를 사람이 읽기 쉬운 문자열로 변환
    private var authorizationStatusText: String {
        let status = healthKitManager.authorizationStatusForBloodGlucose()
        switch status {
        case .notDetermined:
            return "권한 미결정"
        case .sharingDenied:
            return "권한 거부됨"
        case .sharingAuthorized:
            return "권한 허용됨"
        @unknown default:
            return "알 수 없음"
        }
    }

    // MARK: - 저장 버튼 (입력 유효성/로딩 상태에 따라 모양과 enable 상태 변경)
    private var actionButton: some View {
        Button(action: saveBloodGlucose) {
            HStack {
                if isLoading {
                    // 저장 중이면 스피너 표시
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }

                Text(isLoading ? "저장 중..." : "혈당 기록하기")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isInputValid ? Color.blue : Color.gray) // 유효하지 않으면 회색
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isInputValid || isLoading) // 입력이 유효하지 않거나 저장 중이면 비활성화
    }

    // 사용자가 입력한 값 검증(0 < value ≤ 1000)
    private var isInputValid: Bool {
        guard let value = Double(bloodGlucoseValue) else { return false }
        return value > 0 && value <= 1000
    }

    // MARK: - 저장 액션
    // 1) HealthKit에 혈당 샘플 저장
    // 2) CareKit에도 Outcome으로 동시 기록
    // 3) 결과 알럿 표시
    private func saveBloodGlucose() {
        // 텍스트를 Double로 변환(다시 한 번 방어적 체크)
        guard let value = Double(bloodGlucoseValue) else { return }

        isLoading = true

        Task {
            do {
                // 1) HealthKit 저장
                try await healthKitManager.saveBloodGlucose(value: value)

                // 2) CareKit 저장 (동일 시각, 동일 값으로 Outcome 기록)
                try await CareKitManager.shared.saveBloodGlucoseOutcome(value: value)

                // 3) UI 업데이트 및 성공 알림
                await MainActor.run {
                    isLoading = false
                    bloodGlucoseValue = "" // 입력창 초기화
                    alertMessage = "혈당 수치가 성공적으로 기록되었습니다."
                    showAlert = true
                }
            } catch {
                // 오류 발생 시 사용자에게 안내
                await MainActor.run {
                    isLoading = false
                    alertMessage = "기록 저장 중 오류가 발생했습니다: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    BloodGlucoseInputView()
}
