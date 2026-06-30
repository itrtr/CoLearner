import Foundation

public enum AnthropicMessagesError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Int, String)
    case malformedStream(String)
    case missingMetadata

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Anthropic Messages endpoint URL is invalid"
        case let .requestFailed(status, body):
            "Anthropic API returned \(status): \(body)"
        case let .malformedStream(message):
            "Malformed streaming response: \(message)"
        case .missingMetadata:
            "Anthropic response did not include structured metadata"
        }
    }
}

public struct AnthropicMessage: Sendable, Encodable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AnthropicCacheControl: Sendable, Encodable {
    public let type: String

    public init(type: String = "ephemeral") {
        self.type = type
    }
}

public struct AnthropicSystemBlock: Sendable, Encodable {
    public let type: String
    public let text: String
    public let cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case cacheControl = "cache_control"
    }

    public init(text: String, cached: Bool = true) {
        self.type = "text"
        self.text = text
        self.cacheControl = cached ? AnthropicCacheControl() : nil
    }
}

public struct AnthropicToolDefinition: Sendable, Encodable {
    public let name: String
    public let description: String
    public let inputSchema: [String: AnyJSON]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String, inputSchema: [String: AnyJSON]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct AnthropicMessagesRequest: Sendable, Encodable {
    public let model: String
    public let maxTokens: Int
    public let system: [AnthropicSystemBlock]?
    public let messages: [AnthropicMessage]
    public let tools: [AnthropicToolDefinition]?
    public let toolChoice: ToolChoice?
    public let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case toolChoice = "tool_choice"
        case stream
    }

    public init(
        model: String,
        maxTokens: Int,
        system: [AnthropicSystemBlock]?,
        messages: [AnthropicMessage],
        tools: [AnthropicToolDefinition]?,
        toolChoice: ToolChoice?,
        stream: Bool
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.stream = stream
    }

    public struct ToolChoice: Sendable, Encodable {
        public let type: String
        public let name: String?

        public init(type: String, name: String? = nil) {
            self.type = type
            self.name = name
        }

        public static func tool(named name: String) -> ToolChoice {
            ToolChoice(type: "tool", name: name)
        }

        public static let auto = ToolChoice(type: "auto", name: nil)
    }
}

public enum AnthropicStreamEvent: Sendable {
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolUseDelta(String)
    case toolUseComplete(name: String, inputJSON: String)
    case messageDone(stopReason: String?)
}

public struct AnthropicMessagesClient: Sendable {
    public static let defaultBaseURL = "https://api.anthropic.com"
    public static let apiVersion = "2023-06-01"
    public static let claudeCodeVersion = "2.1.75"

    private let baseURL: String
    private let urlSession: URLSession

    public init(
        baseURL: String = AnthropicMessagesClient.defaultBaseURL,
        urlSession: URLSession = StreamingURLSession.shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    /// Stream a Messages API call using an OAuth (Claude Pro/Max) bearer token.
    public func stream(
        request requestBody: AnthropicMessagesRequest,
        accessToken: String
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await execute(request: requestBody, accessToken: accessToken, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(
        request requestBody: AnthropicMessagesRequest,
        accessToken: String,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        guard let endpoint = URL(string: baseURL + "/v1/messages") else {
            throw AnthropicMessagesError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/\(Self.claudeCodeVersion)", forHTTPHeaderField: "user-agent")
        request.setValue("cli", forHTTPHeaderField: "x-app")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicMessagesError.requestFailed(0, "non-http response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var collected = Data()
            for try await byte in bytes {
                collected.append(byte)
                if collected.count > 8192 { break }
            }
            let body = String(data: collected, encoding: .utf8) ?? ""
            throw AnthropicMessagesError.requestFailed(httpResponse.statusCode, body)
        }

        var currentEventName: String?
        var dataBuffer = ""
        var contentBlocks = [Int: ContentBlockState]()

        func dispatchPending() throws {
            guard let eventName = currentEventName, !dataBuffer.isEmpty else {
                return
            }
            try handle(
                eventName: eventName,
                payload: dataBuffer,
                contentBlocks: &contentBlocks,
                continuation: continuation
            )
        }

        // NOTE: URLSession.AsyncBytes.lines collapses consecutive newlines, so the SSE
        // blank-line separator between events never arrives. We dispatch on the next
        // `event:` line instead (and again after the stream ends).
        for try await line in bytes.lines {
            try Task.checkCancellation()

            if line.isEmpty {
                try dispatchPending()
                currentEventName = nil
                dataBuffer = ""
                continue
            }

            if line.hasPrefix("event:") {
                try dispatchPending()
                currentEventName = line.dropFirst("event:".count)
                    .trimmingCharacters(in: .whitespaces)
                dataBuffer = ""
            } else if line.hasPrefix("data:") {
                let chunk = line.dropFirst("data:".count)
                    .trimmingCharacters(in: .whitespaces)
                if dataBuffer.isEmpty {
                    dataBuffer = chunk
                } else {
                    dataBuffer += "\n" + chunk
                }
            }
        }

        try dispatchPending()
    }

    private func handle(
        eventName: String,
        payload: String,
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) throws {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch eventName {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any],
                  let type = block["type"] as? String else {
                return
            }
            switch type {
            case "text":
                contentBlocks[index] = .text
            case "tool_use":
                let id = (block["id"] as? String) ?? ""
                let name = (block["name"] as? String) ?? ""
                contentBlocks[index] = .toolUse(id: id, name: name, inputJSON: "")
                continuation.yield(.toolUseStart(id: id, name: name))
            default:
                contentBlocks[index] = .ignored
            }

        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String,
                  var state = contentBlocks[index] else {
                return
            }

            switch (deltaType, state) {
            case ("text_delta", .text):
                if let text = delta["text"] as? String, !text.isEmpty {
                    continuation.yield(.textDelta(text))
                }
            case ("input_json_delta", .toolUse(let id, let name, let inputJSON)):
                if let partial = delta["partial_json"] as? String {
                    state = .toolUse(id: id, name: name, inputJSON: inputJSON + partial)
                    contentBlocks[index] = state
                    if !partial.isEmpty {
                        continuation.yield(.toolUseDelta(partial))
                    }
                }
            default:
                break
            }

        case "content_block_stop":
            guard let index = json["index"] as? Int,
                  let state = contentBlocks[index] else {
                return
            }
            if case let .toolUse(_, name, inputJSON) = state {
                continuation.yield(.toolUseComplete(name: name, inputJSON: inputJSON))
            }
            contentBlocks[index] = nil

        case "message_delta":
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                continuation.yield(.messageDone(stopReason: stopReason))
            }

        case "message_stop":
            continuation.yield(.messageDone(stopReason: nil))

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AnthropicMessagesError.malformedStream(message)
            }

        default:
            break
        }
    }

    private enum ContentBlockState {
        case text
        case toolUse(id: String, name: String, inputJSON: String)
        case ignored
    }
}

/// Minimal JSON value used to encode the tool input schema without depending on a
/// full JSONValue type.
public enum AnyJSON: Sendable, Encodable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case array([AnyJSON])
    case object([String: AnyJSON])
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
