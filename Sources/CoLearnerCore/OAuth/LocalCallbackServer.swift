import Foundation
import Network

public struct LocalCallbackResult: Sendable, Equatable {
    public let code: String?
    public let state: String?
    public let error: String?

    public init(code: String?, state: String?, error: String?) {
        self.code = code
        self.state = state
        self.error = error
    }
}

public enum LocalCallbackServerError: Error, LocalizedError {
    case alreadyRunning
    case failedToStart(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Callback server is already running"
        case let .failedToStart(reason):
            "Could not start callback server: \(reason)"
        case .cancelled:
            "Callback was cancelled"
        }
    }
}

/// Minimal one-shot HTTP listener bound to 127.0.0.1 used to receive an OAuth
/// authorization-code callback. Stops after the first successful request.
public actor LocalCallbackServer {
    public let port: UInt16
    public let path: String

    private var listener: NWListener?
    private var connections = [ObjectIdentifier: NWConnection]()
    private var continuation: CheckedContinuation<LocalCallbackResult, Error>?

    public init(port: UInt16, path: String = "/callback") {
        self.port = port
        self.path = path
    }

    public var redirectURI: String {
        "http://localhost:\(port)\(path)"
    }

    public func waitForCallback(successHTML: String, errorHTML: String) async throws -> LocalCallbackResult {
        guard listener == nil else {
            throw LocalCallbackServerError.alreadyRunning
        }

        let listener: NWListener
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            throw LocalCallbackServerError.failedToStart(error.localizedDescription)
        }
        self.listener = listener

        let successData = httpResponse(status: "200 OK", body: successHTML)
        let errorData = httpResponse(status: "400 Bad Request", body: errorHTML)
        let notFoundData = httpResponse(status: "404 Not Found", body: errorHTML)

        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handle(
                    connection: connection,
                    successData: successData,
                    errorData: errorData,
                    notFoundData: notFoundData
                )
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    public func cancel() {
        finish(with: .failure(LocalCallbackServerError.cancelled))
    }

    private func handle(
        connection: NWConnection,
        successData: Data,
        errorData: Data,
        notFoundData: Data
    ) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { [weak self] in
                await self?.processRequest(
                    connection: connection,
                    id: id,
                    data: data,
                    successData: successData,
                    errorData: errorData,
                    notFoundData: notFoundData
                )
            }
        }
    }

    private func processRequest(
        connection: NWConnection,
        id: ObjectIdentifier,
        data: Data?,
        successData: Data,
        errorData: Data,
        notFoundData: Data
    ) {
        defer {
            connections.removeValue(forKey: id)
        }

        guard let data, let requestString = String(data: data, encoding: .utf8) else {
            send(errorData, on: connection)
            return
        }

        let firstLine = requestString.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let components = firstLine.split(separator: " ")
        guard components.count >= 2 else {
            send(errorData, on: connection)
            return
        }

        let target = String(components[1])
        guard let url = URL(string: "http://localhost\(target)"),
              url.path == path,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            send(notFoundData, on: connection)
            return
        }

        let code = queryItems.first(where: { $0.name == "code" })?.value
        let state = queryItems.first(where: { $0.name == "state" })?.value
        let error = queryItems.first(where: { $0.name == "error" })?.value
        let result = LocalCallbackResult(code: code, state: state, error: error)

        send(error == nil ? successData : errorData, on: connection) { [weak self] in
            Task { [weak self] in
                await self?.finish(with: .success(result))
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection, completion: (@Sendable () -> Void)? = nil) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
            completion?()
        })
    }

    private func finish(with result: Result<LocalCallbackResult, Error>) {
        guard let continuation else {
            return
        }
        self.continuation = nil

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()

        listener?.cancel()
        listener = nil

        continuation.resume(with: result)
    }

    private func httpResponse(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        return Data(header.utf8) + bodyData
    }
}

public enum OAuthCallbackPage {
    public static func success(_ message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>CoLearner</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f6f5f0;color:#1c1b18}
        .card{background:#fff;padding:32px 40px;border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,.06);max-width:420px;text-align:center}
        h1{font-size:18px;margin:0 0 8px}p{font-size:14px;color:#666;margin:0}</style></head>
        <body><div class="card"><h1>You're signed in</h1><p>\(message)</p></div></body></html>
        """
    }

    public static func failure(_ message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>CoLearner</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f6f5f0;color:#1c1b18}
        .card{background:#fff;padding:32px 40px;border-radius:12px;box-shadow:0 8px 32px rgba(0,0,0,.06);max-width:420px;text-align:center}
        h1{font-size:18px;margin:0 0 8px;color:#b00020}p{font-size:14px;color:#666;margin:0}</style></head>
        <body><div class="card"><h1>Sign in failed</h1><p>\(message)</p></div></body></html>
        """
    }
}
