import Foundation

/// Shared URLSession configured for long-lived Server-Sent-Events streams.
///
/// The default `URLSession.shared` has `timeoutIntervalForRequest = 60`, which kills the
/// connection if no bytes arrive for 60 seconds. Reasoning models (Codex `gpt-5.5`, Claude
/// with extended thinking) can spend well over that time on internal reasoning before the
/// first `text_delta` event, so we lift both timeouts well above any realistic model
/// response latency.
public enum StreamingURLSession {
    public static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600   // 10 min per byte-arrival window
        configuration.timeoutIntervalForResource = 1800 // 30 min total
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = nil
        return URLSession(configuration: configuration)
    }()
}
