import Foundation

enum PasswordCredentials {
    // Match Python str.strip() exactly; Foundation includes zero-width space.
    private static let usernameWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{001C}\u{001D}\u{001E}\u{001F} \u{0085}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}")

    static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: usernameWhitespace).lowercased()
    }

    static func isValidUsername(_ value: String) -> Bool {
        let raw = value.trimmingCharacters(in: usernameWhitespace)
        guard raw.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        let normalized = normalizedUsername(value)
        return normalized.range(of: "^[a-z0-9_]{4,32}$", options: .regularExpression) != nil
    }

    static func isValidPassword(_ value: String) -> Bool { (15...128).contains(value.unicodeScalars.count) }

    static func isValidRecoveryCode(_ value: String) -> Bool {
        guard value.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        let normalized = value.uppercased().filter { !"- \t\r\n\u{000B}\u{000C}".contains($0) }
        return normalized.range(of: "^[A-Z2-7]{32}$", options: .regularExpression) != nil
    }
}

struct RecoveryMaterial: Identifiable, Sendable, Equatable {
    let id = UUID()
    let username: String
    let code: String
}

struct PasswordRegistration: Codable, Sendable {
    var session: AccountSession
    let recoveryCode: String
}

typealias RecoveryRotation = PasswordRegistration

struct RecoveryResponse: Decodable, Sendable {
    let username: String
    let recoveryCode: String
}

struct BindingResult: Codable, Sendable {
    let account: AppAccount
    let session: AccountSession?
}
