import Foundation

public struct CommandInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let standardInput: String?
    public let currentDirectory: URL?

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        standardInput: String? = nil,
        currentDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.currentDirectory = currentDirectory
    }
}

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public protocol CommandRunning: Sendable {
    func run(_ invocation: CommandInvocation) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await Task.detached {
            try Self.runSynchronously(invocation)
        }.value
    }

    private static func runSynchronously(_ invocation: CommandInvocation) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        var inputFileHandle: FileHandle?
        var inputFileURL: URL?

        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardOutput = standardOutput
        process.standardError = standardError

        if let input = invocation.standardInput {
            let inputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CoLearner-\(UUID().uuidString).stdin")
            let inputData = Data(input.utf8)
            guard FileManager.default.createFile(
                atPath: inputURL.path,
                contents: inputData,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            inputFileURL = inputURL
            inputFileHandle = try FileHandle(forReadingFrom: inputURL)
            process.standardInput = inputFileHandle
        }

        if let currentDirectory = invocation.currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        defer {
            try? inputFileHandle?.close()
            if let inputFileURL {
                try? FileManager.default.removeItem(at: inputFileURL)
            }
        }

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}
