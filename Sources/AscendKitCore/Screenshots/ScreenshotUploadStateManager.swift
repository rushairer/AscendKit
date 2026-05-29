import Foundation

public struct ScreenshotUploadStateManager {
    private let fileManager: FileManager
    
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    public func load(from path: String) throws -> ScreenshotUploadProgressState? {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try AscendKitJSON.decoder.decode(ScreenshotUploadProgressState.self, from: data)
    }
    
    public func save(_ state: ScreenshotUploadProgressState, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try AscendKitJSON.encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }
}
