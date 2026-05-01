import Testing
@testable import AscendKitCore

@Suite("IAP local templates")
struct IAPTests {
    @Test("creates starter subscription templates from bundle id")
    func createsStarterTemplates() {
        let templates = SubscriptionTemplateFactory.starter(appBundleID: "com.example.demo")

        #expect(templates.map(\.productID) == [
            "com.example.demo.subscription.monthly",
            "com.example.demo.subscription.yearly"
        ])
        #expect(IAPValidationReport(templates: templates).valid)
    }

    @Test("detects duplicate subscription product ids")
    func detectsDuplicateProductIDs() {
        let templates = [
            SubscriptionTemplate(id: "a", referenceName: "A", productID: "com.example.sub", cadence: .monthly, displayName: "A", reviewNotes: "Review A"),
            SubscriptionTemplate(id: "b", referenceName: "B", productID: "com.example.sub", cadence: .yearly, displayName: "B", reviewNotes: "Review B")
        ]

        let report = IAPValidationReport(templates: templates)

        #expect(report.valid == false)
        #expect(report.findings.contains("Subscription product IDs must be unique."))
    }

    @Test("requires review notes for local subscription templates")
    func requiresReviewNotes() {
        let templates = [
            SubscriptionTemplate(id: "monthly", referenceName: "Monthly", productID: "com.example.monthly", cadence: .monthly, displayName: "Monthly")
        ]

        let report = IAPValidationReport(templates: templates)

        #expect(report.valid == false)
        #expect(report.findings.contains("Subscription review notes should be prepared for each local template."))
    }
}
