import os.log

public enum VanmoLogger {
    public static let player = Logger(subsystem: "com.vanmo.app", category: "Player")
    public static let network = Logger(subsystem: "com.vanmo.app", category: "Network")
    public static let library = Logger(subsystem: "com.vanmo.app", category: "Library")
    public static let metadata = Logger(subsystem: "com.vanmo.app", category: "Metadata")
    public static let subtitle = Logger(subsystem: "com.vanmo.app", category: "Subtitle")
    public static let storage = Logger(subsystem: "com.vanmo.app", category: "Storage")
    public static let prefetch = Logger(subsystem: "com.vanmo.app", category: "Prefetch")
}
