public struct ASCAgentCapability: Codable, Equatable, Sendable {
    public let domain: String
    public let helpCommand: String
    public let startCommand: String
    public let useWhen: String
    public let nextSteps: String

    init(_ domain: String, _ action: String, useWhen: String, nextSteps: String) {
        self.domain = domain
        self.helpCommand = "ascendkit asc \(domain) --help"
        self.startCommand = "ascendkit asc \(domain) \(action) --workspace \"$WORKSPACE\" --json"
        self.useWhen = useWhen
        self.nextSteps = nextSteps
    }
}

public struct ASCAgentGuidance: Codable, Equatable, Sendable {
    public let guideURL: String
    public let capabilities: [ASCAgentCapability]
    public let executionGuidance: String
    public let chinaMainlandAppCompliance: String

    public static let discoveryCommand = "ascendkit asc capabilities --json"
    public static let current = ASCAgentGuidance(
        guideURL: "https://github.com/rushairer/AscendKit/blob/main/docs/recent-asc-apis.md",
        capabilities: [
            .init("age-rating", "app-infos", useWhen: "Age rating or regional content descriptors.",
                  nextSteps: "Use the app info ID for observe and territories. Use the declaration ID from observe to plan set with explicit answers."),
            .init("accessibility", "list", useWhen: "App Store accessibility labels.",
                  nextSteps: "Select the device family and review declared support. Use create or set with an Apple JSON request file."),
            .init("asset-library", "observe", useWhen: "Reusable screenshots, previews, creative assets, or placements for an app using the Asset Library.",
                  nextSteps: "Read ref-data and the target localization's placements. Use image-upload or video-upload, read processing state, and plan placement-create and placement-order using returned IDs. Resume an existing AWAITING_UPLOAD reservation with the same file."),
            .init("retention", "list", useWhen: "Subscription cancellation messaging or retention offers.",
                  nextSteps: "Discover the subscription with asc subscriptions groups and list. Manage the message, version, localizations and applicable offer assignments. Use review-create, review-add and review-submit for the message version."),
            .init("subscriptions", "groups", useWhen: "Subscription pricing, plan availability, organization markets, or multiseat settings.",
                  nextSteps: "Use list with the group ID. Read prices and tiers, use price-change-preview before scheduling a change, and plan writes only for the requested subscription."),
            .init("purchase-versions", "iap-list", useWhen: "Versioned IAP, subscription, or subscription group metadata, media, or review.",
                  nextSteps: "For subscriptions and subscription groups, discover IDs with asc subscriptions groups and list. Read the relevant *-versions, then use the matching version, localization, image and dedicated review actions."),
            .init("game-center-moderation", "detail", useWhen: "Game Center player blocking or leaderboard score moderation.",
                  nextSteps: "Read blocked-players by Game Center detail ID or scores by leaderboard ID. Use the returned player or score ID and an explicit --blocked value."),
            .init("app-performance", "overview", useWhen: "App performance review or comparison with app or build metrics.",
                  nextSteps: "Use app-metrics or build-metrics when the request needs metric detail."),
            .init("background-assets", "list", useWhen: "Background Asset discovery, including localized versions.",
                  nextSteps: "Use --query 'filter[versions.locale]=LOCALE' when the request targets a locale.")
        ],
        executionGuidance: "Select capabilities that match the user's task. Use asc apps lookup with the current workspace, or pass an explicit --app-id when the app is ambiguous. Start with the observation and use real resource IDs from responses[].data. Inspect each mutation's JSON plan before executing an authorized change with --confirm-remote-mutation. Dedicated review-submit also requires --confirm-remote-submission.",
        chinaMainlandAppCompliance: "For applicable China mainland AIGC filings and security assessment declarations, hand off to App Store Connect > App Compliance. The public API cannot observe or submit these declarations, and App Privacy status and age ratings do not establish their completion."
    )
}
