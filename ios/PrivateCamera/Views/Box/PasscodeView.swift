import SwiftUI

/// Passcode entry screen matching box_1/code.html design.
struct PasscodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var passcodeManager = PasscodeManager.shared

    @State private var enteredDigits: [Int] = []
    @State private var isSettingPasscode = false
    @State private var newPasscode: String = ""
    @State private var confirmPasscode: String = ""
    @State private var shake = false
    @State private var navigateToBox = false
    @State private var showAutoRecord = false
    @State private var suppressAutoRecord = true

    private let passcodeLength = 4

    var body: some View {
        ZStack {
            // Background with glass effect
            AppTheme.backgroundDark
                .ignoresSafeArea()
                .overlay(
                    Color.black.opacity(0.4)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    Text("Kesu Camera")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.3)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                // Lock icon
                ZStack {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.primary.opacity(0.2), radius: 16)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 24)

                // Instruction text
                Text(instructionText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 48)

                // Passcode dots
                HStack(spacing: 24) {
                    ForEach(0..<passcodeLength, id: \.self) { index in
                        Circle()
                            .stroke(
                                index < enteredDigits.count ? AppTheme.primary : Color.white.opacity(0.3),
                                lineWidth: 2
                            )
                            .background(
                                Circle()
                                    .fill(index < enteredDigits.count ? AppTheme.primary : .clear)
                            )
                            .frame(width: 16, height: 16)
                    }
                }
                .offset(x: shake ? -10 : 0)
                .padding(.bottom, 48)

                Spacer()

                // Number pad
                numberPad
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)

                // Biometric / Forgot
                bottomActions
                    .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $navigateToBox) {
            PrivateBoxView(onDismissToCamera: {
                // Dismiss PasscodeView — this cascades and also dismisses PrivateBoxView
                dismiss()
            })
        }
        .fullScreenCover(isPresented: $showAutoRecord) {
            AutoRecordView(navigateToBoxAfterSave: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active &&
               !suppressAutoRecord &&
               PrivacySettingsManager.shared.autoRecordOnLaunch &&
               !showAutoRecord && !navigateToBox {
                showAutoRecord = true
            }
        }
        .onAppear {
            // Suppress auto-record for 3 seconds to avoid false triggers during view transitions
            suppressAutoRecord = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                suppressAutoRecord = false
            }
            if !passcodeManager.isPasscodeSet {
                isSettingPasscode = true
            }
            // Try biometric first
            if passcodeManager.isPasscodeSet && passcodeManager.biometricType != .none {
                Task {
                    let success = await passcodeManager.authenticateWithBiometrics()
                    if success {
                        navigateToBox = true
                    }
                }
            }
        }
    }

    private var instructionText: String {
        if isSettingPasscode {
            if newPasscode.isEmpty {
                return "新しいパスコードを\n入力してください"
            } else {
                return "確認のためもう一度\n入力してください"
            }
        }
        return "BOXを表示するにはパスコードを\n入力してください"
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 16) {
            ForEach(0..<4) { row in
                HStack(spacing: 32) {
                    if row < 3 {
                        ForEach(1...3, id: \.self) { col in
                            let number = row * 3 + col
                            numberButton(number)
                        }
                    } else {
                        // Bottom row: empty, 0, backspace
                        Color.clear.frame(width: 64, height: 64)
                        numberButton(0)
                        backspaceButton
                    }
                }
            }
        }
    }

    private func numberButton(_ number: Int) -> some View {
        Button {
            AppTheme.lightImpact()
            appendDigit(number)
        } label: {
            Text("\(number)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
        }
    }

    private var backspaceButton: some View {
        Button {
            AppTheme.lightImpact()
            if !enteredDigits.isEmpty {
                enteredDigits.removeLast()
            }
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 16) {
            if passcodeManager.biometricType != .none && passcodeManager.isPasscodeSet {
                Button {
                    Task {
                        let success = await passcodeManager.authenticateWithBiometrics()
                        if success {
                            navigateToBox = true
                        }
                    }
                } label: {
                    Image(systemName: passcodeManager.biometricType == .faceID ? "faceid" : "touchid")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            if !isSettingPasscode {
                Button {
                    // Forgot passcode flow
                } label: {
                    Text("パスコードを忘れましたか？")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Logic

    private func appendDigit(_ digit: Int) {
        guard enteredDigits.count < passcodeLength else { return }
        enteredDigits.append(digit)

        if enteredDigits.count == passcodeLength {
            let code = enteredDigits.map(String.init).joined()
            validateCode(code)
        }
    }

    private func validateCode(_ code: String) {
        if isSettingPasscode {
            if newPasscode.isEmpty {
                newPasscode = code
                enteredDigits = []
            } else if confirmPasscode.isEmpty {
                confirmPasscode = code
                if newPasscode == confirmPasscode {
                    passcodeManager.setPasscode(newPasscode)
                    AppTheme.successNotification()
                    navigateToBox = true
                } else {
                    // Mismatch
                    shakeAndReset()
                    newPasscode = ""
                    confirmPasscode = ""
                }
            }
        } else {
            if passcodeManager.verifyPasscode(code) {
                AppTheme.successNotification()
                navigateToBox = true
            } else {
                shakeAndReset()
            }
        }
    }

    private func shakeAndReset() {
        AppTheme.heavyImpact()
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shake = false
            enteredDigits = []
        }
    }
}
