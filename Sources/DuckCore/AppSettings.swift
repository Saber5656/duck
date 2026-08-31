import Foundation

public enum DuckPosition: String, CaseIterable, Equatable {
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
    case topRight = "topRight"
    case topLeft = "topLeft"

    public var displayName: String {
        switch self {
        case .bottomRight:
            return "Bottom Right"
        case .bottomLeft:
            return "Bottom Left"
        case .topRight:
            return "Top Right"
        case .topLeft:
            return "Top Left"
        }
    }
}

public enum DuckSensitivity: String, CaseIterable, Equatable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

public final class DuckSettingsStore {
    public enum Key {
        public static let isListening = "duck.isListening"
        public static let position = "duck.position"
        public static let sensitivity = "duck.sensitivity"
        public static let launchAtLogin = "duck.launchAtLogin"
        public static let hasCompletedOnboarding = "duck.hasCompletedOnboarding"
    }

    private let defaults: UserDefaults
    private let hasPersistedLegacySettingsValue: Bool

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Capture this before register(defaults:) adds fallback values to the lookup chain.
        self.hasPersistedLegacySettingsValue = [
            Key.isListening,
            Key.position,
            Key.sensitivity,
            Key.launchAtLogin
        ].contains { defaults.object(forKey: $0) != nil }
    }

    public var isListening: Bool {
        get { defaults.bool(forKey: Key.isListening) }
        set { defaults.set(newValue, forKey: Key.isListening) }
    }

    public var position: DuckPosition {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.position),
                let position = DuckPosition(rawValue: rawValue)
            else {
                return .bottomRight
            }
            return position
        }
        set { defaults.set(newValue.rawValue, forKey: Key.position) }
    }

    public var sensitivity: DuckSensitivity {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.sensitivity),
                let sensitivity = DuckSensitivity(rawValue: rawValue)
            else {
                return .medium
            }
            return sensitivity
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sensitivity) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var hasPersistedLegacySettings: Bool {
        hasPersistedLegacySettingsValue
    }
}
