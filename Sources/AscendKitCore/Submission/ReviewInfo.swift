import Foundation

public struct ReviewerContact: Codable, Equatable, Sendable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var phone: String

    public init(firstName: String = "", lastName: String = "", email: String = "", phone: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
    }

    public var isComplete: Bool {
        !firstName.isBlank && !lastName.isBlank && !email.isBlank && !phone.isBlank
    }
}

public struct ReviewerAccess: Codable, Equatable, Sendable {
    public var requiresLogin: Bool
    public var credentialReference: SecretRef?
    public var instructions: String

    public init(requiresLogin: Bool = false, credentialReference: SecretRef? = nil, instructions: String = "") {
        self.requiresLogin = requiresLogin
        self.credentialReference = credentialReference
        self.instructions = instructions
    }

    public var isComplete: Bool {
        if requiresLogin {
            return credentialReference != nil && !instructions.isBlank
        }
        return true
    }
}

public struct ReviewInfo: Codable, Equatable, Sendable {
    public var contact: ReviewerContact
    public var access: ReviewerAccess
    public var notes: String

    public init(contact: ReviewerContact = ReviewerContact(), access: ReviewerAccess = ReviewerAccess(), notes: String = "") {
        self.contact = contact
        self.access = access
        self.notes = notes
    }

    public static let template = ReviewInfo(
        contact: ReviewerContact(),
        access: ReviewerAccess(),
        notes: "Explain paywalls, hardware requirements, regional limitations, or special review steps."
    )
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
