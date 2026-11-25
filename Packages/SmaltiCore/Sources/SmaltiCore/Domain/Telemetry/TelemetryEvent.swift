import Foundation

/// One Claude Code request to its API, as its OpenTelemetry log event `api_request` reports it (spec F7).
public struct APIRequest: Equatable, Sendable {
    public let sessionID: String
    /// `event.sequence`: tells a repeated delivery from a new event. Nil when the exporter left it out.
    public let sequence: Int?
    public let at: Date
    public let model: String?
    public let durationMilliseconds: Int
    public let costMicroUSD: Int

    public init(
        sessionID: String, sequence: Int?, at: Date, model: String?, durationMilliseconds: Int, costMicroUSD: Int
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.at = at
        self.model = model
        self.durationMilliseconds = durationMilliseconds
        self.costMicroUSD = costMicroUSD
    }
}

/// A request that failed after Claude Code's retries (`api_error`).
public struct APIError: Equatable, Sendable {
    public let sessionID: String
    public let sequence: Int?
    public let at: Date
    public let model: String?
    /// Nil for a network error with no HTTP status.
    public let statusCode: Int?

    public init(sessionID: String, sequence: Int?, at: Date, model: String?, statusCode: Int?) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.at = at
        self.model = model
        self.statusCode = statusCode
    }
}

/// The Claude Code telemetry events the Observatory uses; the receiver drops every other one.
public enum TelemetryEvent: Equatable, Sendable {
    case apiRequest(APIRequest)
    case apiError(APIError)

    var sessionID: String {
        switch self {
        case .apiRequest(let request): request.sessionID
        case .apiError(let error): error.sessionID
        }
    }

    var sequence: Int? {
        switch self {
        case .apiRequest(let request): request.sequence
        case .apiError(let error): error.sequence
        }
    }

    var at: Date {
        switch self {
        case .apiRequest(let request): request.at
        case .apiError(let error): error.at
        }
    }
}
