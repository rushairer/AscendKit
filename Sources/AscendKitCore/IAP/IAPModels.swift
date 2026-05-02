import Foundation

public enum SubscriptionCadence: String, Codable, Equatable, Sendable {
    case weekly
    case monthly
    case yearly
}

public struct SubscriptionTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var referenceName: String
    public var productID: String
    public var cadence: SubscriptionCadence
    public var displayName: String
    public var reviewNotes: String?

    public init(
        id: String,
        referenceName: String,
        productID: String,
        cadence: SubscriptionCadence,
        displayName: String,
        reviewNotes: String? = nil
    ) {
        self.id = id
        self.referenceName = referenceName
        self.productID = productID
        self.cadence = cadence
        self.displayName = displayName
        self.reviewNotes = reviewNotes
    }
}

public struct IAPValidationReport: Codable, Equatable, Sendable {
    public var ascendKitVersion: String?
    public var valid: Bool
    public var findings: [String]

    public init(ascendKitVersion: String? = AscendKitVersion.current, templates: [SubscriptionTemplate]) {
        var findings: [String] = []
        let productIDs = templates.map(\.productID)
        if Set(productIDs).count != productIDs.count {
            findings.append("Subscription product IDs must be unique.")
        }
        if templates.contains(where: { $0.productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            findings.append("Subscription product IDs are required.")
        }
        let missingReviewNotes = templates.filter {
            $0.reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        if !templates.isEmpty && !missingReviewNotes.isEmpty {
            findings.append("Subscription review notes should be prepared for each local template.")
        }
        self.ascendKitVersion = ascendKitVersion
        self.valid = findings.isEmpty
        self.findings = findings
    }
}

public enum SubscriptionTemplateFactory {
    public static func starter(appBundleID: String = "com.example.app") -> [SubscriptionTemplate] {
        [
            SubscriptionTemplate(
                id: "monthly",
                referenceName: "Monthly Subscription",
                productID: "\(appBundleID).subscription.monthly",
                cadence: .monthly,
                displayName: "Monthly",
                reviewNotes: "Describe what the subscription unlocks and how reviewers can verify access."
            ),
            SubscriptionTemplate(
                id: "yearly",
                referenceName: "Yearly Subscription",
                productID: "\(appBundleID).subscription.yearly",
                cadence: .yearly,
                displayName: "Yearly",
                reviewNotes: "Describe what the subscription unlocks and how reviewers can verify access."
            )
        ]
    }
}
