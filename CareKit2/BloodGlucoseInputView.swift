import HealthKit
import SwiftUI

struct BloodGlucoseInputView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var bloodGlucoseValue = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                headerView

                if !healthKitManager.isAuthorized {
                    authorizationView
                } else {
                    inputSection
                    actionButton
                }

                Spacer()
            }
            .padding()
            .navigationTitle("혈당 관리")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("알림", isPresented: $showAlert) {
            Button("확인") {}
        } message: {
            Text(alertMessage)
        }
        .task {
            await healthKitManager.requestAuthorization()
        }
    }

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

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("혈당 수치")
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                TextField("혈당 수치를 입력하세요", text: $bloodGlucoseValue)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.title3)

                Text("mg/dL")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Text("정상 범위: 70-100 mg/dL (공복시)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

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

            // 디버깅 정보 표시
            VStack(alignment: .leading, spacing: 4) {
                Text("디버깅 정보:")
                    .font(.caption)
                    .fontWeight(.bold)
                Text(
                    "HealthKit 사용 가능: \(HKHealthStore.isHealthDataAvailable() ? "예" : "아니오")"
                )
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

    private var actionButton: some View {
        Button(action: saveBloodGlucose) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(tint: .white)
                        )
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
            .background(isInputValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isInputValid || isLoading)
    }

    private var isInputValid: Bool {
        guard let value = Double(bloodGlucoseValue) else { return false }
        return value > 0 && value <= 1000
    }

    private func saveBloodGlucose() {
        guard let value = Double(bloodGlucoseValue) else { return }

        isLoading = true

        Task {
            do {
                try await healthKitManager.saveBloodGlucose(value: value)
                try await CareKitManager.shared.saveBloodGlucoseOutcome(
                    value: value
                )

                await MainActor.run {
                    isLoading = false
                    bloodGlucoseValue = ""
                    alertMessage = "혈당 수치가 성공적으로 기록되었습니다."
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertMessage =
                        "기록 저장 중 오류가 발생했습니다: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    BloodGlucoseInputView()
}
