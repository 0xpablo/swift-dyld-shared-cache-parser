import BinaryParsing
import Foundation

/// Represents the CPU architecture of a dyld shared cache.
public enum CacheArchitecture: String, CaseIterable, Sendable {
    case arm64 = "arm64"
    case arm64e = "arm64e"
    case arm64_32 = "arm64_32"
    case x86_64 = "x86_64"
    case x86_64h = "x86_64h"
    case i386 = "i386"

    /// The size of pointers for this architecture in bytes.
    public var pointerSize: Int {
        switch self {
        case .arm64, .arm64e, .x86_64, .x86_64h:
            return 8
        case .arm64_32, .i386:
            return 4
        }
    }

    /// Whether this is a 64-bit architecture.
    public var is64Bit: Bool {
        pointerSize == 8
    }

    /// Whether this architecture uses pointer authentication (PAC).
    public var usesPointerAuthentication: Bool {
        self == .arm64e
    }

    /// Parse architecture from a 16-byte magic string.
    /// Magic format: "dyld_v1   <arch>" padded with spaces or null bytes.
    public init?(magic: String) {
        // Magic string is "dyld_v1" followed by spaces and architecture name
        // Examples: "dyld_v1    i386", "dyld_v1   arm64", "dyld_v1  arm64e"
        guard magic.hasPrefix("dyld_v") else {
            return nil
        }

        // Extract architecture from magic by trimming prefix and spaces
        let archPart = magic
            .dropFirst(7) // Drop "dyld_v1" or similar
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))

        self.init(rawValue: archPart)
    }

    /// Parse architecture from raw 16 bytes.
    public init?(magicBytes: [UInt8]) {
        guard magicBytes.count >= 16 else { return nil }

        // Convert bytes to string, stopping at first null or using all 16 bytes
        var magicString = ""
        for byte in magicBytes.prefix(16) {
            if byte == 0 { break }
            magicString.append(Character(UnicodeScalar(byte)))
        }

        self.init(magic: magicString)
    }
}

/// VM protection flags for memory mappings.
public struct VMProtection: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Read permission.
    public static let read = VMProtection(rawValue: 1)
    /// Write permission.
    public static let write = VMProtection(rawValue: 2)
    /// Execute permission.
    public static let execute = VMProtection(rawValue: 4)

    /// Read + Write.
    public static let readWrite: VMProtection = [.read, .write]
    /// Read + Execute.
    public static let readExecute: VMProtection = [.read, .execute]
    /// Read + Write + Execute.
    public static let all: VMProtection = [.read, .write, .execute]
}

extension VMProtection: CustomStringConvertible {
    public var description: String {
        var result = ""
        result += contains(.read) ? "r" : "-"
        result += contains(.write) ? "w" : "-"
        result += contains(.execute) ? "x" : "-"
        return result
    }
}

/// Cache type indicating development vs production build.
public enum CacheType: UInt64, Sendable {
    case development = 0
    case production = 1
    case multiCache = 2
}

/// Platform identifier for the shared cache.
public enum CachePlatform: UInt32, Sendable {
    case unknown = 0
    case macOS = 1
    case iOS = 2
    case tvOS = 3
    case watchOS = 4
    case bridgeOS = 5
    case macCatalyst = 6
    case iOSSimulator = 7
    case tvOSSimulator = 8
    case watchOSSimulator = 9
    case driverKit = 10
    case visionOS = 11
    case visionOSSimulator = 12
}
