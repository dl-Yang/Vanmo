import Foundation

enum PrefetchError: LocalizedError {
    case badRequest
    case badResponse
    case unknownSize
    case listenerFailed
    case connectionClosed
    case sessionNotFound
    case upstream(Int)

    var errorDescription: String? {
        switch self {
        case .badRequest: return "Prefetch: invalid HTTP request"
        case .badResponse: return "Prefetch: invalid upstream response"
        case .unknownSize: return "Prefetch: could not determine content length"
        case .listenerFailed: return "Prefetch: local listener failed"
        case .connectionClosed: return "Prefetch: connection closed"
        case .sessionNotFound: return "Prefetch: session not found"
        case .upstream(let code): return "Prefetch: upstream HTTP \(code)"
        }
    }
}
