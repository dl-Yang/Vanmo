import Foundation

extension Notification.Name {
    static let macPlayerTogglePlayPause = Notification.Name("macPlayerTogglePlayPause")
    static let macPlayerSkipBackward = Notification.Name("macPlayerSkipBackward")
    static let macPlayerSkipForward = Notification.Name("macPlayerSkipForward")
    static let macPlayerVolumeUp = Notification.Name("macPlayerVolumeUp")
    static let macPlayerVolumeDown = Notification.Name("macPlayerVolumeDown")
    static let macPlayerToggleFullScreen = Notification.Name("macPlayerToggleFullScreen")
    static let macPlayerClose = Notification.Name("macPlayerClose")
}

enum MacPlayerCommandRouter {
    static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
