import Foundation
import VanmoCore

extension Int64 {
    var formattedFileSize: String {
        LocalizedFormat.fileSize(self)
    }
}
