import AuthenticationServices
import UIKit
import VanmoCore

@MainActor
final class UIKitOAuthPresentationContextProvider: NSObject, OAuthPresentationContextProvider {
    static let shared = UIKitOAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
