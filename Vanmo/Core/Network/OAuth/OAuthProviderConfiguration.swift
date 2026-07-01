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
///
/// 所有网盘的 Redirect URI 统一为 `vanmo://oauth/{ConnectionType.rawValue}`，
/// 需要在对应开发者后台的应用配置里登记同样的值。
enum OAuthProviderConfiguration {
    static let redirectScheme = "vanmo"
    static let redirectHost = "oauth"

    static func redirectURI(for type: ConnectionType) -> String {
        "\(redirectScheme)://\(redirectHost)/\(type.rawValue)"
    }

    /// TODO(User)：在下方对应 case 中填入开发者后台申请到的 Client ID。
    static func clientID(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return ""
        case .oneDrive:
            return ""
        case .box:
            return ""
        case .pCloudDrive:
            return ""
        case .yandexDisk:
            return ""
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
        !clientID(for: type).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        default:
            return "该网盘尚未配置开发者凭据。"
        }
    }
}
