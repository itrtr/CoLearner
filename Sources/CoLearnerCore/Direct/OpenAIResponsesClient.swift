import Foundation

public enum OpenAIResponsesError: Error, LocalizedError {
    case invalidURL
    case missingAccountID
    case requestFailed(Int, String)
    case malformedStream(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "OpenAI Responses endpoint URL is invalid"
        case .missingAccountID:
            "ChatGPT account ID was not present in the OAuth token"
        case let .requestFailed(status, body):
            "OpenAI API returned \(status): \(body)"
        case let .malformedStream(message):
            "Malformed streaming response: \(message)"
        }
    }
}

public struct OpenAIResponsesInputMessage: Sendable, Encodable {
    public let role: String
    public let content: [Content]

    public struct Content: Sendable, Encodable {
        public let type: String
        public let text: String

        public init(type: String = "input_text", text: String) {
            self.type = type
            self.text = text
        }
    }

    public init(role: String, text: String) {
        self.role = role
        self.content = [Content(text: text)]
    }
}

public struct OpenAIResponsesTool: Sendable, Encodable {
    public let type: String
    public let name: String
    public let description: String
    public let parameters: [String: AnyJSON]
    public let strict: Bool?

    public init(
        name: String,
        description: String,
        parameters: [String: AnyJSON],
        strict: Bool? = nil,
        type: String = "function"
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public struct OpenAIReasoningOptions: Sendable, Encodable {
    public let effort: String?

    public init(effort: String? = nil) {
        self.effort = effort
    }
}

public struct OpenAITextOptions: Sendable, Encodable {
    public let verbosity: String?

    public init(verbosity: String? = nil) {
        self.verbosity = verbosity
    }
}

public struct OpenAIResponsesRequest: Sendable, Encodable {
    public let model: String
    public let instructions: String?
    public let input: [OpenAIResponsesInputMessage]
    public let tools: [OpenAIResponsesTool]?
    public let stream: Bool
    public let store: Bool
    public let parallelToolCalls: Bool?
    public let reasoning: OpenAIReasoningOptions?
    public let text: OpenAITextOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case stream
        case store
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case text
    }

    public init(
        model: String,
        instructions: String?,
        input: [OpenAIResponsesInputMessage],
        tools: [OpenAIResponsesTool]?,
        stream: Bool,
        store: Bool,
        parallelToolCalls: Bool?,
        reasoning: OpenAIReasoningOptions? = nil,
        text: OpenAITextOptions? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.stream = stream
        self.store = store
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.text = text
    }
}

public enum OpenAIStreamEvent: Sendable {
    case textDelta(String)
    case toolCallStart(name: String, callID: String)
    case toolCallDelta(String)
    case toolCallComplete(name: String, callID: String, arguments: String)
    case completed
}

public struct OpenAIResponsesClient: Sendable {
    public static let defaultBaseURL = "https://chatgpt.com/backend-api/codex/responses"
    public static let chatgptAuthClaim = "https://api.openai.com/auth"

    private let endpointURL: String
    private let urlSession: URLSession
    private let originator: String

    public init(
        endpointURL: String = OpenAIResponsesClient.defaultBaseURL,
        originator: String = "colearner",
        urlSession: URLSession = StreamingURLSession.shared
    ) {
        self.endpointURL = endpointURL
        self.originator = originator
        self.urlSession = urlSession
    }

    public func stream(
        request requestBody: OpenAIResponsesRequest,
        accessToken: String
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
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
        request requestBody: OpenAIResponsesRequest,
        accessToken: String,
        continuation: AsyncThrowingStream<OpenAIStreamEvent, Error>.Continuation
    ) async throws {
        guard let endpoint = URL(string: endpointURL) else {
            throw OpenAIResponsesError.invalidURL
        }

        guard let accountID = Self.accountID(fromJWT: accessToken) else {
            throw OpenAIResponsesError.missingAccountID
        }

        let sessionID = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue(originator, forHTTPHeaderField: "originator")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(sessionID, forHTTPHeaderField: "session-id")
        request.setValue(sessionID, forHTTPHeaderField: "x-client-request-id")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIResponsesError.requestFailed(0, "non-http response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var collected = Data()
            for try await byte in bytes {
                collected.append(byte)
                if collected.count > 8192 { break }
            }
            let body = String(data: collected, encoding: .utf8) ?? ""
            throw OpenAIResponsesError.requestFailed(httpResponse.statusCode, body)
        }

        var currentEventName: String?
        var dataBuffer = ""
        var activeToolCalls = [String: (name: String, args: String)]()

        func dispatchPending() throws {
            guard let eventName = currentEventName, !dataBuffer.isEmpty else {
                return
            }
            try handle(
                eventName: eventName,
                payload: dataBuffer,
                activeToolCalls: &activeToolCalls,
                continuation: continuation
            )
        }

        // URLSession.AsyncBytes.lines collapses the blank-line SSE separator, so dispatch
        // on the start of each new `event:` line and once more after the stream ends.
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
        activeToolCalls: inout [String: (name: String, args: String)],
        continuation: AsyncThrowingStream<OpenAIStreamEvent, Error>.Continuation
    ) throws {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch eventName {
        case "response.output_text.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                continuation.yield(.textDelta(delta))
            }

        case "response.output_item.added":
            guard let item = json["item"] as? [String: Any],
                  let type = item["type"] as? String,
                  type == "function_call",
                  let callID = (item["call_id"] as? String) ?? (item["id"] as? String),
                  let name = item["name"] as? String else {
                return
            }
            activeToolCalls[callID] = (name, "")
            continuation.yield(.toolCallStart(name: name, callID: callID))

        case "response.function_call_arguments.delta":
            guard let delta = json["delta"] as? String,
                  let callID = (json["call_id"] as? String) ?? (json["item_id"] as? String) else {
                return
            }
            if var current = activeToolCalls[callID] {
                current.args += delta
                activeToolCalls[callID] = current
            } else {
                activeToolCalls[callID] = (name: "", args: delta)
            }
            if !delta.isEmpty {
                continuation.yield(.toolCallDelta(delta))
            }

        case "response.function_call_arguments.done":
            let callID = (json["call_id"] as? String) ?? (json["item_id"] as? String) ?? ""
            let arguments = (json["arguments"] as? String)
                ?? activeToolCalls[callID]?.args
                ?? ""
            let name = activeToolCalls[callID]?.name ?? ""
            activeToolCalls.removeValue(forKey: callID)
            continuation.yield(.toolCallComplete(name: name, callID: callID, arguments: arguments))

        case "response.completed":
            continuation.yield(.completed)

        case "response.failed", "error":
            let message = (json["error"] as? [String: Any]).flatMap { $0["message"] as? String }
                ?? (json["message"] as? String)
                ?? "OpenAI stream reported an error"
            throw OpenAIResponsesError.malformedStream(message)

        default:
            break
        }
    }

    /// Extract the ChatGPT account ID from the JWT access token without verifying the signature.
    public static func accountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }
        let payloadSegment = String(parts[1])
        guard let payloadData = Data(base64URLEncoded: payloadSegment) else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let authClaim = json[chatgptAuthClaim] as? [String: Any],
              let accountID = authClaim["chatgpt_account_id"] as? String else {
            return nil
        }
        return accountID
    }
}

extension Data {
    init?(base64URLEncoded input: String) {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingNeeded = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingNeeded)
        self.init(base64Encoded: base64)
    }
}
