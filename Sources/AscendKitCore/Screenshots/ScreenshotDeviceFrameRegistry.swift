import Foundation
import AppKit

public struct DeviceFrameSpecification: Codable, Equatable, Sendable {
    public var platform: ApplePlatform
    public var displayType: String // e.g. "APP_IPHONE_67"
    public var marketingName: String
    public var screenPixelSize: NSSize
    public var bezelWidth: CGFloat
    public var cornerRadius: CGFloat
    public var dynamicIslandSize: NSSize?
    public var notchSize: NSSize?
    public var hasHomeIndicator: Bool

    public init(
        platform: ApplePlatform,
        displayType: String,
        marketingName: String,
        screenPixelSize: NSSize,
        bezelWidth: CGFloat,
        cornerRadius: CGFloat,
        dynamicIslandSize: NSSize? = nil,
        notchSize: NSSize? = nil,
        hasHomeIndicator: Bool = true
    ) {
        self.platform = platform
        self.displayType = displayType
        self.marketingName = marketingName
        self.screenPixelSize = screenPixelSize
        self.bezelWidth = bezelWidth
        self.cornerRadius = cornerRadius
        self.dynamicIslandSize = dynamicIslandSize
        self.notchSize = notchSize
        self.hasHomeIndicator = hasHomeIndicator
    }

    /// Computes the overall dimensions of the framed device including bezels.
    public var packageSize: NSSize {
        NSSize(
            width: screenPixelSize.width + (bezelWidth * 2),
            height: screenPixelSize.height + (bezelWidth * 2)
        )
    }
}

public struct DeviceFrameRegistry: Sendable {
    public static let shared = DeviceFrameRegistry()

    public let specifications: [DeviceFrameSpecification]

    private init() {
        self.specifications = [
            // iPhone 6.7" (iPhone 17 Pro Max / 16 Pro Max / 15 Pro Max)
            DeviceFrameSpecification(
                platform: .iOS,
                displayType: "APP_IPHONE_67",
                marketingName: "iPhone 6.7\"",
                screenPixelSize: NSSize(width: 1290, height: 2796),
                bezelWidth: 42.0,
                cornerRadius: 110.0,
                dynamicIslandSize: NSSize(width: 330, height: 92),
                hasHomeIndicator: true
            ),
            // iPhone 6.5" (iPhone 11 Pro Max / Xs Max)
            DeviceFrameSpecification(
                platform: .iOS,
                displayType: "APP_IPHONE_65",
                marketingName: "iPhone 6.5\"",
                screenPixelSize: NSSize(width: 1242, height: 2688),
                bezelWidth: 46.0,
                cornerRadius: 100.0,
                notchSize: NSSize(width: 580, height: 80),
                hasHomeIndicator: true
            ),
            // iPad Pro 13-inch (M5 / M4 / 3rd+ Gen 12.9")
            DeviceFrameSpecification(
                platform: .iPadOS,
                displayType: "APP_IPAD_PRO_3GEN_129",
                marketingName: "iPad Pro 13-inch",
                screenPixelSize: NSSize(width: 2064, height: 2752),
                bezelWidth: 72.0,
                cornerRadius: 80.0,
                hasHomeIndicator: true
            ),
            // Mac Desktop
            DeviceFrameSpecification(
                platform: .macOS,
                displayType: "APP_DESKTOP",
                marketingName: "Mac Desktop",
                screenPixelSize: NSSize(width: 2560, height: 1600),
                bezelWidth: 80.0,
                cornerRadius: 16.0,
                hasHomeIndicator: false
            )
        ]
    }

    public func specification(for displayType: String) -> DeviceFrameSpecification? {
        specifications.first { $0.displayType == displayType }
    }

    public func specification(for platform: ApplePlatform, size: NSSize) -> DeviceFrameSpecification? {
        // Tolerant matching on screen size dimensions (accounting for orientation differences)
        specifications.first { spec in
            spec.platform == platform && (
                (abs(spec.screenPixelSize.width - size.width) < 5 && abs(spec.screenPixelSize.height - size.height) < 5) ||
                (abs(spec.screenPixelSize.width - size.height) < 5 && abs(spec.screenPixelSize.height - size.width) < 5)
            )
        }
    }

    public func defaultSpecification(for platform: ApplePlatform) -> DeviceFrameSpecification? {
        specifications.first { $0.platform == platform }
    }
}
