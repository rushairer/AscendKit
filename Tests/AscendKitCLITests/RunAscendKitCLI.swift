import Foundation

func runAscendKitCLI(arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ".build/debug/ascendkit").standardizedFileURL
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
