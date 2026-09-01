import SwiftUI
import UIKit
import VanmoCore

extension ConnectionType {
    /// iOS catalog names matching the copied `MacConn*` imagesets.
    var iosProviderIconName: String {
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
}

struct ConnectionProviderIcon: View {
    let type: ConnectionType
    var size: CGFloat = 20
    var fallbackTint: Color = .primary

    var body: some View {
        if UIImage(named: type.iosProviderIconName) != nil {
            Image(type.iosProviderIconName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: type.icon)
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(fallbackTint)
                .frame(width: size, height: size)
        }
    }
}
