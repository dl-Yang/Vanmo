import Foundation

enum NetworkError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case authenticationFailed
    case timeout
    case invalidURL
    case transferFailed(String)
    case unsupportedProtocol

    var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到服务器"
        case .connectionFailed(let msg): return "连接失败: \(msg)"
        case .authenticationFailed: return "认证失败，请检查用户名和密码"
        case .timeout: return "连接超时"
        case .invalidURL: return "无效的 URL"
        case .transferFailed(let msg): return "传输失败: \(msg)"
        case .unsupportedProtocol: return "不支持的协议"
        }
    }
}
