import Foundation

public struct AscendKitVersionReport: Codable, Equatable, Sendable {
    public var version: String
    public var platform: String
    public var architecture: String
    public var releaseURL: String
    public var installCommand: String
    public var verifyCommand: String

    public init(
        version: String = AscendKitVersion.current,
        platform: String = "macOS",
        architecture: String = Self.currentArchitecture()
    ) {
        self.version = version
        self.platform = platform
        self.architecture = architecture
        self.releaseURL = "https://github.com/rushairer/AscendKit/releases/tag/v\(version)"
        self.installCommand = "scripts/install-ascendkit.sh --version \(version)"
        self.verifyCommand = "scripts/verify-release-assets.sh --version \(version)"
    }

    public static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return ProcessInfo.processInfo.machineHardwareName
        #endif
    }
}

extension ProcessInfo {
    fileprivate var machineHardwareName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "unknown"
            }
        }
    }
}
