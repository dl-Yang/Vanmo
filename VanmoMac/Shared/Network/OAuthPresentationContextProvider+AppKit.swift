import AppKit
import AuthenticationServices
import VanmoCore

@MainActor
final class AppKitOAuthPresentationContextProvider: NSObject, OAuthPresentationContextProvider {
    static let shared = AppKitOAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
