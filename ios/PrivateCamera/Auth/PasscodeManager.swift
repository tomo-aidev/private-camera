import LocalAuthentication
import Foundation
import os.log

/// Manages passcode and biometric (FaceID/TouchID) authentication.
@MainActor
final class PasscodeManager: ObservableObject {

    static let shared = PasscodeManager()

    @Published var isAuthenticated = false
    @Published var isPasscodeSet = false
    @Published var biometricType: BiometricType = .none
    @Published var authError: String?

    enum BiometricType {
        case none, faceID, touchID
    }

    private let logger = Logger(subsystem: "com.privatecamera", category: "Passcode")
    private let passcodeKey = "com.privatecamera.passcode.hash"

    private init() {
        isPasscodeSet = KeychainHelper.read(key: passcodeKey) != nil
        detectBiometricType()
    }

    // MARK: - Biometric Detection

    private func detectBiometricType() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: biometricType = .faceID
            case .touchID: biometricType = .touchID
            default: biometricType = .none
            }
        }
    }

    // MARK: - Passcode

    func setPasscode(_ code: String) {
        let hash = hashPasscode(code)
        KeychainHelper.save(key: passcodeKey, data: hash)
        isPasscodeSet = true

        // Derive encryption key
        SecureStorage.shared.deriveKey(from: code)

        logger.info("Passcode set")
    }

    func verifyPasscode(_ code: String) -> Bool {
        guard let storedHash = KeychainHelper.read(key: passcodeKey) else {
            return false
        }

        let inputHash = hashPasscode(code)
        let match = storedHash == inputHash

        if match {
            isAuthenticated = true
            SecureStorage.shared.deriveKey(from: code)
        }

        return match
    }

    func resetPasscode() {
        KeychainHelper.delete(key: passcodeKey)
        isPasscodeSet = false
        isAuthenticated = false
    }

    // MARK: - Biometric Auth

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        let reason = "プライベートBOXにアクセス"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success {
                isAuthenticated = true
            }
            return success
        } catch {
            logger.error("Biometric auth failed: \(error.localizedDescription)")
            authError = error.localizedDescription
            return false
        }
    }

    // MARK: - Lock

    func lock() {
        isAuthenticated = false
    }

    // MARK: - Private

    private func hashPasscode(_ code: String) -> Data {
        let data = Data(code.utf8)
        // Use SHA256 for passcode hashing
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}

// Need to import CryptoKit for SHA256
import CryptoKit
