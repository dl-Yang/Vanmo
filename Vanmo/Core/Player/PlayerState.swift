import UIKit
import VanmoCore

extension VideoScaleMode {
    var uiViewContentMode: UIView.ContentMode {
        switch self {
        case .fit: return .scaleAspectFit
        case .fill: return .scaleAspectFill
        case .stretch: return .scaleToFill
        }
    }
}
