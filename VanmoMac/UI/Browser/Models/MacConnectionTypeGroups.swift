import AppKit
import SwiftUI
import VanmoCore

enum MacConnectionTypeGroup: String, CaseIterable, Identifiable {
    case localAndProtocol
    case mediaServer
    case cloudDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localAndProtocol: "本地与协议"
        case .mediaServer: "媒体服务器"
        case .cloudDrive: "账号云盘"
        }
    }

    var types: [ConnectionType] {
        switch self {
        case .localAndProtocol:
            [.localFolder, .smb, .ftp, .sftp, .webdav, .alist, .fnos, .nfs, .iptv, .dlna]
        case .mediaServer:
            [.emby, .plex, .jellyfin]
        case .cloudDrive:
            [
                .googleDrive, .oneDrive, .baiduNetdisk, .removedOfficialCloudDrive,
                .drive115, .quarkDrive, .box, .pCloudDrive, .yandexDisk, .mega
            ]
        }
    }
}

extension ConnectionType {
    var macProviderIconName: String {
        switch self {
        case .localFolder: "MacConnLocalFolder"
        case .smb: "MacConnSMB"
        case .ftp: "MacConnFTP"
        case .sftp: "MacConnSFTP"
        case .webdav: "MacConnWebDAV"
        case .nfs: "MacConnNFS"
        case .alist: "MacConnAList"
        case .fnos: "MacConnFnOS"
        case .iptv: "MacConnIPTV"
        case .dlna: "MacConnDLNA"
        case .emby: "MacConnEmby"
        case .plex: "MacConnPlex"
        case .jellyfin: "MacConnJellyfin"
        case .googleDrive: "MacConnGoogleDrive"
        case .oneDrive: "MacConnOneDrive"
        case .baiduNetdisk: "MacConnBaiduNetdisk"
        case .removedOfficialCloudDrive: "MacConnAliyunDrive"
        case .drive115: "MacConnDrive115"
        case .quarkDrive: "MacConnQuarkDrive"
        case .box: "MacConnBox"
        case .pCloudDrive: "MacConnPCloud"
        case .yandexDisk: "MacConnYandexDisk"
        case .mega: "MacConnMEGA"
        }
    }

    var macSidebarLabel: String {
        switch self {
        case .alist: "AList"
        case .removedOfficialCloudDrive: "阿里云盘"
        case .drive115: "115 网盘"
        case .quarkDrive: "夸克网盘"
        case .pCloudDrive: "pCloud"
        case .yandexDisk: "Yandex.Disk"
        default: displayName
        }
    }

    var macAddConnectionTitle: String {
        "添加 \(displayName)"
    }

    var macAddConnectionDescription: String? {
        switch self {
        case .webdav:
            return "通用连接。主机可填写域名或 IP，不确定路径时可留空。"
        case .alist:
            return "AList 默认端口 5244、WebDAV 路径为 /dav，是否启用 HTTPS 取决于实例配置。"
        case .smb:
            return "SMB 适用于 fnOS、NAS 或 Mac「文件共享」。Mac 需打开 SMB 并为该用户勾选 Windows 文件共享；路径填写共享名。"
        case .fnos:
            return "fnOS 按 WebDAV 兼容方式连接：局域网 HTTP 通常为 5005，HTTPS 通常为 5006。"
        case .iptv:
            return "可在主机地址或路径中填写完整 M3U/M3U8 播放列表 URL。"
        case .localFolder:
            return "选择本机文件夹作为媒体来源，Vanmo 会扫描其中的视频文件。"
        case .baiduNetdisk:
            return "通过百度网盘开放平台 OAuth 简化模式登录。"
        case .googleDrive:
            return "通过 Google 官方 OAuth 2.0 登录，仅请求只读权限。"
        case .oneDrive:
            return "通过 Microsoft 官方 OAuth 2.0 登录。"
        case .box:
            return "通过 Box 官方 OAuth 2.0 登录。"
        case .pCloudDrive:
            return "通过 pCloud 官方 OAuth 2.0 登录。"
        case .yandexDisk:
            return "通过 Yandex 官方 OAuth 2.0 登录。"
        case .drive115:
            return "115 网盘需通过开放平台入驻和应用审核；当前仅保留合规接入提示。"
        case .quarkDrive:
            return "夸克网盘官方开放能力仍需调研确认；当前仅保留合规接入提示。"
        case .mega:
            return "MEGA 完整支持需要官方 SDK 深度集成；当前仅保留入口。"
        case .removedOfficialCloudDrive:
            return "该历史连接类型已移除，不再提供授权、浏览或取流能力。"
        case .emby, .plex, .jellyfin:
            return "填写媒体服务器地址（如 https://emby.example.com）。"
        default:
            return nil
        }
    }
}

struct MacConnectionProviderIcon: View {
    let type: ConnectionType
    var size: CGFloat = 18

    var body: some View {
        if let _ = NSImage(named: type.macProviderIconName) {
            Image(type.macProviderIconName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: type.icon)
                .font(.system(size: size * 0.78, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}
