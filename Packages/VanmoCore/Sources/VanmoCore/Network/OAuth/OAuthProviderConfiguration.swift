import Foundation

/// 国际网盘 OAuth 开发者凭据配置中心。
///
/// 凭据不写在源码里：构建者在仓库根目录未跟踪的 `Local.xcconfig` 中填写（模板 `Local.xcconfig.example`），
/// `Config/Secrets.xcconfig` 引入后经 App `Info.plist` 的 `VanmoOAuthCredentials` 注入，运行时从主 Bundle 读取。
/// 未填写的网盘"登录"入口保持禁用并提示未配置。
///
/// | 网盘 | 需要申请的凭据 | 申请入口 |
/// |---|---|---|
/// | Google Drive | Client ID（iOS 类型 OAuth 客户端，无需 Secret，走 PKCE） | https://console.cloud.google.com/apis/credentials |
/// | OneDrive | Application (client) ID（公共客户端，无需 Secret，走 PKCE） | https://portal.azure.com （Microsoft Entra ID → 应用注册） |
/// | Box | Client ID + Client Secret（Box 不支持 PKCE，Secret 只在本机构建时填入，禁止提交） | https://app.box.com/developers/console |
/// | pCloud | Client ID + Client Secret | https://docs.pcloud.com/my_apps/ |
/// | Yandex.Disk | Client ID（iOS 走 YandexLoginSDK，macOS 走 PKCE，均无需 Secret） | https://oauth.yandex.com |
/// | 百度网盘 | AppKey（简化模式，无需 Secret） | https://pan.baidu.com/union/console/applist |
///
/// Redirect URI 按 provider 分流：
/// - Google Drive：iOS OAuth Client ID 派生的反向域名 scheme，`com.googleusercontent.apps.<prefix>:/oauth2redirect`
/// - 其余 OAuth 网盘：`vanmo://oauth/{ConnectionType.rawValue}`，需在对应开发者后台登记
public enum OAuthProviderConfiguration {
    public static let vanmoRedirectScheme = "vanmo"
    public static let vanmoRedirectHost = "oauth"
    public static let googleRedirectPath = "/oauth2redirect"

    /// Google iOS OAuth Client ID 对应的 URL scheme（由 Client ID 前缀派生）。
    /// 更换 Client ID 时须同步更新 `Info.plist` 中 `CFBundleURLSchemes` 的 Google 条目。
    public static func googleURLScheme(for type: ConnectionType = .googleDrive) -> String? {
        guard type == .googleDrive else { return nil }
        let clientID = clientID(for: .googleDrive)
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    public static func redirectURI(for type: ConnectionType) -> String {
        if let scheme = googleURLScheme(for: type) {
            return "\(scheme):\(googleRedirectPath)"
        }
        return "\(vanmoRedirectScheme)://\(vanmoRedirectHost)/\(type.rawValue)"
    }

    /// `ASWebAuthenticationSession` 回调 scheme，须与 redirect URI 的 scheme 一致。
    public static func callbackURLScheme(for type: ConnectionType) -> String {
        googleURLScheme(for: type) ?? vanmoRedirectScheme
    }

    public static func matchesCallback(_ components: URLComponents, type: ConnectionType) -> Bool {
        if let scheme = googleURLScheme(for: type) {
            return components.scheme == scheme && components.path == googleRedirectPath
        }
        return components.scheme == vanmoRedirectScheme &&
            components.host == vanmoRedirectHost &&
            components.path == "/\(type.rawValue)"
    }

    static let credentialsInfoKey = "VanmoOAuthCredentials"

    /// App `Info.plist` 注入的凭据；单元测试进程没有该字典，全部视为未配置。
    static var bundledCredentials: [String: Any] {
        Bundle.main.object(forInfoDictionaryKey: credentialsInfoKey) as? [String: Any] ?? [:]
    }

    public static func clientID(for type: ConnectionType) -> String {
        clientID(for: type, in: bundledCredentials)
    }

    static func clientID(for type: ConnectionType, in credentials: [String: Any]) -> String {
        let key: String
        switch type {
        case .googleDrive: key = "GoogleDriveClientID"
        case .oneDrive: key = "OneDriveClientID"
        case .box: key = "BoxClientID"
        case .pCloudDrive: key = "PCloudClientID"
        // 同时驱动 iOS `yx{Client ID}` scheme 与 Associated Domain（均由同一个 xcconfig 变量展开）。
        case .yandexDisk: key = "YandexDiskClientID"
        case .baiduNetdisk: key = "BaiduNetdiskAppKey"
        default: return ""
        }
        return credential(key, in: credentials)
    }

    /// Google Drive / OneDrive / Yandex.Disk 走 PKCE、百度走简化模式，均无 Secret。
    /// Box 没有 PKCE（authorize 不接受 `code_challenge`），token 交换必须带 Secret；pCloud 同理。
    public static func clientSecret(for type: ConnectionType) -> String? {
        clientSecret(for: type, in: bundledCredentials)
    }

    static func clientSecret(for type: ConnectionType, in credentials: [String: Any]) -> String? {
        let key: String
        switch type {
        case .box: key = "BoxClientSecret"
        case .pCloudDrive: key = "PCloudClientSecret"
        default: return nil
        }
        let value = credential(key, in: credentials)
        return value.isEmpty ? nil : value
    }

    /// 未定义的构建变量会原样留下 `$(NAME)`，按未配置处理。
    static func credential(_ key: String, in credentials: [String: Any]) -> String {
        let value = (credentials[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.hasPrefix("$(") ? "" : value
    }

    public static func scope(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return "https://www.googleapis.com/auth/drive.readonly"
        case .oneDrive:
            return "Files.Read.All offline_access"
        case .box:
            // Box 的 scope 由 Developer Console 的 Application Scopes 决定。这里不能降权到
            // `root_readonly`: 2026-11-01 iOS Simulator 验收中,只读 token 列表正常但请求
            // `/files/{id}/content` 返回 403 insufficient permission;因此这里请求读写 scope。
            // Vanmo 只调用读取类接口,不会写用户内容;console 侧仍需勾选 Read and write 权限。
            return "root_readwrite"
        case .pCloudDrive:
            return ""
        case .yandexDisk:
            // 须是 oauth.yandex.com 应用已登记权限的子集；YandexDiskService 只调用 resources / download。
            return "cloud_api:disk.read"
        case .baiduNetdisk:
            return "basic,netdisk"
        default:
            return ""
        }
    }

    /// 是否使用 PKCE（code_verifier / code_challenge），公共客户端优先选择，避免在 App 内嵌 Client Secret。
    /// Box 不支持 PKCE，即使启用也会退化为 Secret 模式，因此这里显式返回 false。
    public static func usesPKCE(for type: ConnectionType) -> Bool {
        switch type {
        case .googleDrive, .oneDrive, .yandexDisk:
            return true
        default:
            return false
        }
    }

    /// Yandex 经 Google 等社交账号登录后会落到账号主页而非授权确认页，
    /// 需保留 Cookie，让再次授权直接进入确认页。
    public static func prefersEphemeralWebBrowserSession(for type: ConnectionType) -> Bool {
        type != .yandexDisk
    }

    /// 是否走 OAuth 2.0 简化模式（Implicit Grant）：回调 fragment 直接返回 access_token，无 refresh_token。
    public static func usesImplicitGrant(for type: ConnectionType) -> Bool {
        type.isImplicitOAuthCloudDrive
    }

    public static func authorizationEndpoint(for type: ConnectionType) -> URL? {
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

    public static func tokenEndpoint(for type: ConnectionType) -> URL? {
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

    public static func isConfigured(for type: ConnectionType) -> Bool {
        isConfigured(clientID: clientID(for: type), clientSecret: clientSecret(for: type), type: type)
    }

    /// 纯函数形式，便于在不依赖真实凭据的情况下固定“Secret 模式必须同时有 ID + Secret”的契约。
    static func isConfigured(clientID: String, clientSecret: String?, type: ConnectionType) -> Bool {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // PKCE 公共客户端（Google/OneDrive/Yandex.Disk）与简化模式（百度网盘）不需要 secret；
        // 其余走 client secret 模式的网盘（Box/pCloud）必须同时配置好 secret，否则 token exchange 必然失败。
        if usesPKCE(for: type) || usesImplicitGrant(for: type) {
            return true
        }
        return !(clientSecret ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 未配置时展示给用户的提示，指引去哪里申请。
    public static func missingCredentialHint(for type: ConnectionType) -> String {
        switch type {
        case .googleDrive:
            return "需要先在 Google Cloud Console 创建 iOS 类型 OAuth 客户端并填入 Client ID。"
        case .oneDrive:
            return "需要先在 Microsoft Entra 管理中心注册应用（公共客户端）并填入 Application (client) ID。"
        case .box:
            return "需要先在 Box Developer Console 创建 User Authentication (OAuth 2.0) 应用，回调登记为 vanmo://oauth/box，并在本机填入 Client ID / Client Secret（Secret 不要提交）。"
        case .pCloudDrive:
            return "需要先在 pCloud 开发者后台注册 App 并填入 Client ID / Client Secret。"
        case .yandexDisk:
            return "需要先在 oauth.yandex.com 注册应用（iOS 平台 + Web services 平台）并填入 Client ID。"
        case .baiduNetdisk:
            return "需要先在百度网盘开放平台创建应用并填入 AppKey，回调地址登记为 vanmo://oauth/baiduNetdisk。"
        default:
            return "该网盘尚未配置开发者凭据。"
        }
    }
}
