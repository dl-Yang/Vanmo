import os.log

enum VanmoLogger {
    static let player = Logger(subsystem: "com.vanmo.app", category: "Player")
    static let network = Logger(subsystem: "com.vanmo.app", category: "Network")
    static let library = Logger(subsystem: "com.vanmo.app", category: "Library")
    static let metadata = Logger(subsystem: "com.vanmo.app", category: "Metadata")
    static let subtitle = Logger(subsystem: "com.vanmo.app", category: "Subtitle")
    static let storage = Logger(subsystem: "com.vanmo.app", category: "Storage")
}
