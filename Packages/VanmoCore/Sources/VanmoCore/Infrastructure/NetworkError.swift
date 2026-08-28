import Foundation

public enum NetworkError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case authenticationFailed
    case sharePathRequired
    case timeout
    case invalidURL
    case transferFailed(String)
    case unsupportedProtocol

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到服务器"
        case .connectionFailed(let msg): return "连接失败: \(msg)"
        case .authenticationFailed: return "认证失败，请检查用户名和密码"
        case .sharePathRequired:
            return "已登录，但服务器不允许列出共享。请编辑连接并在路径中填写共享名（例如 /Movies）。"
        case .timeout: return "连接超时"
        case .invalidURL: return "无效的 URL"
        case .transferFailed(let msg): return "传输失败: \(msg)"
        case .unsupportedProtocol: return "不支持的协议"
        }
    }
}
