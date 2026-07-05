import Foundation

/// 国际网盘 OAuth 开发者凭据配置中心。
///
/// **重要：以下 clientID / clientSecret 全部留空占位，需要用户在对应开发者后台手动申请后填入，**
/// **否则对应网盘的"登录"入口会保持禁用状态并提示未配置。**
///
/// | 网盘 | 需要申请的凭据 | 申请入口 |
/// |---|---|---|
/// | Google Drive | Client ID（iOS 类型 OAuth 客户端，无需 Secret，走 PKCE） | https://console.cloud.google.com/apis/credentials |
/// | OneDrive | Application (client) ID（公共客户端，无需 Secret，走 PKCE） | https://portal.azure.com （Microsoft Entra ID → 应用注册） |
/// | Box | Client ID + Client Secret | https://app.box.com/developers/console |
/// | pCloud | Client ID + Client Secret | https://docs.pcloud.com/my_apps/ |
/// | Yandex.Disk | Client ID + Client Secret | https://oauth.yandex.com |
/// | 百度网盘 | AppKey（简化模式，无需 Secret） | https://pan.baidu.com/union/console/applist |
///
/// Redirect URI 按 provider 分流：
/// - Google Drive：iOS OAuth Client ID 派生的反向域名 scheme，`com.googleusercontent.apps.<prefix>:/oauth2redirect`
/// - 其余 OAuth 网盘：`vanmo://oauth/{ConnectionType.rawValue}`，需在对应开发者后台登记
enum OAuthProviderConfiguration {
    static let vanmoRedirectScheme = "vanmo"
    static let vanmoRedirectHost = "oauth"
    static let googleRedirectPath = "/oauth2redirect"

    /// Google iOS OAuth Client ID 对应的 URL scheme（由 Client ID 前缀派生）。
    /// 更换 Client ID 时须同步更新 `Info.plist` 中 `CFBundleURLSchemes` 的 Google 条目。
    static func googleURLScheme(for type: ConnectionType = .googleDrive) -> String? {
        guard type == .googleDrive else { return nil }
        let clientID = clientID(for: .googleDrive)
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    static func redirectURI(for type: ConnectionType) -> String {
        if let scheme = googleURLScheme(for: type) {
            return "\(scheme):\(googleRedirectPath)"
        }
        return "\(vanmoRedirectScheme)://\(vanmoRedirectHost)/\(type.rawValue)"
    }

    /// `ASWebAuthenticationSession` 回调 scheme，须与 redirect URI 的 scheme 一致。
    static func callbackURLScheme(for type: ConnectionType) -> String {
        googleURLScheme(for: type) ?? vanmoRedirectScheme
    }

    static func matchesCallback(_ components: URLComponents, type: ConnectionType) -> Bool {
        if let scheme = googleURLScheme(for: type) {
            return components.scheme == scheme && components.path == googleRedirectPath
        }
        return components.scheme == vanmoRedirectScheme &&
            components.host == vanmoRedirectHost &&
            components.path == "/\(type.rawValue)"
    }

    /// TODO(User)：在下方对应 case 中填入开发者后台申请到的 Client ID。
    static func clientID(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return "311522710381-42mtgv9v8kbjm6dqtta9e2ntmane387g.apps.googleusercontent.com"
        case .oneDrive:
            return ""
        case .box:
            return ""
        case .pCloudDrive:
            return ""
        case .yandexDisk:
            return ""
        case .baiduNetdisk:
            return "j5nV46HZKiRzYq5TuHdsYN9DYfvk76AL"
        default:
            return ""
        }
    }

    /// TODO(User)：Google Drive / OneDrive 走 PKCE 公共客户端，不需要 Secret；
    /// Box / pCloud / Yandex.Disk 需要在下方填入开发者后台申请到的 Client Secret。
    static func clientSecret(for type: ConnectionType) -> String? {
        switch type {
        case .box:
            return nil
        case .pCloudDrive:
            return nil
        case .yandexDisk:
            return nil
        default:
            return nil
        }
    }

    static func scope(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return "https://www.googleapis.com/auth/drive.readonly"
        case .oneDrive:
            return "Files.Read.All offline_access"
        case .box:
            return ""
        case .pCloudDrive:
            return ""
        case .yandexDisk:
            return "cloud_api:disk.read cloud_api:disk.info"
        case .baiduNetdisk:
            return "basic,netdisk"
        default:
            return ""
        }
    }

    /// 是否使用 PKCE（code_verifier / code_challenge），公共客户端优先选择，避免在 App 内嵌 Client Secret。
    static func usesPKCE(for type: ConnectionType) -> Bool {
        switch type {
        case .googleDrive, .oneDrive:
            return true
        default:
            return false
        }
    }

    /// 是否走 OAuth 2.0 简化模式（Implicit Grant）：回调 fragment 直接返回 access_token，无 refresh_token。
    static func usesImplicitGrant(for type: ConnectionType) -> Bool {
        type.isImplicitOAuthCloudDrive
    }

    static func authorizationEndpoint(for type: ConnectionType) -> URL? {
        switch type {
        case .googleDrive:
            return URL(string: "https://accounts.google.com/o/oauth2/v2/auth")
        case .oneDrive:
            return URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")
        case .box:
            return URL(string: "https://account.box.com/api/oauth2/authorize")
        case .pCloudDrive:
            return URL(string: "https://my.pcloud.com/oauth2/authorize")
        case .yandexDisk:
            return URL(string: "https://oauth.yandex.com/authorize")
        case .baiduNetdisk:
            return URL(string: "https://openapi.baidu.com/oauth/2.0/authorize")
        default:
            return nil
        }
    }

    static func tokenEndpoint(for type: ConnectionType) -> URL? {
        switch type {
        case .googleDrive:
            return URL(string: "https://oauth2.googleapis.com/token")
        case .oneDrive:
            return URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")
        case .box:
            return URL(string: "https://api.box.com/oauth2/token")
        case .pCloudDrive:
            return URL(string: "https://api.pcloud.com/oauth2_token")
        case .yandexDisk:
            return URL(string: "https://oauth.yandex.com/token")
        default:
            return nil
        }
    }

    static func isConfigured(for type: ConnectionType) -> Bool {
        guard !clientID(for: type).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // PKCE 公共客户端（Google/OneDrive）与简化模式（百度网盘）不需要 secret；
        // 其余走 client secret 模式的网盘必须同时配置好 secret，否则 token exchange 必然失败。
        if usesPKCE(for: type) || usesImplicitGrant(for: type) {
            return true
        }
        return !(clientSecret(for: type) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 未配置时展示给用户的提示，指引去哪里申请。
    static func missingCredentialHint(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return "需要先在 Google Cloud Console 创建 iOS 类型 OAuth 客户端并填入 Client ID。"
        case .oneDrive:
            return "需要先在 Microsoft Entra 管理中心注册应用（公共客户端）并填入 Application (client) ID。"
        case .box:
            return "需要先在 Box Developer Console 创建自定义 App 并填入 Client ID / Client Secret。"
        case .pCloudDrive:
            return "需要先在 pCloud 开发者后台注册 App 并填入 Client ID / Client Secret。"
        case .yandexDisk:
            return "需要先在 oauth.yandex.com 注册应用并填入 Client ID / Client Secret。"
        case .baiduNetdisk:
            return "需要先在百度网盘开放平台创建应用并填入 AppKey，回调地址登记为 vanmo://oauth/baiduNetdisk。"
        default:
            return "该网盘尚未配置开发者凭据。"
        }
    }
}
