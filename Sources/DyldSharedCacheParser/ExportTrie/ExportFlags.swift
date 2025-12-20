import BinaryParsing

/// The kind of exported symbol.
public enum ExportKind: UInt8, Sendable {
    /// Regular exported symbol with an address.
    case regular = 0

    /// Thread-local variable.
    case threadLocal = 1

    /// Absolute symbol (not subject to ASLR).
    case absolute = 2
}

/// Flags for an exported symbol in the export trie.
public struct ExportFlags: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    // MARK: - Flag masks

    /// Mask for the export kind (bits 0-1).
    private static let kindMask: UInt64 = 0x03

    /// Weak definition flag.
    public static let weakDefinition: UInt64 = 0x04

    /// Re-export flag.
    public static let reExport: UInt64 = 0x08

    /// Stub and resolver flag.
    public static let stubAndResolver: UInt64 = 0x10

    /// Static resolver flag (for Swift).
    public static let staticResolver: UInt64 = 0x20

    /// Function variant flag.
    public static let functionVariant: UInt64 = 0x40

    // MARK: - Computed properties

    /// The export kind.
    public var kind: ExportKind {
        ExportKind(rawValue: UInt8(rawValue & Self.kindMask)) ?? .regular
    }

    /// Whether this is a weak definition.
    public var isWeakDefinition: Bool {
        (rawValue & Self.weakDefinition) != 0
    }

    /// Whether this is a re-export from another dylib.
    public var isReExport: Bool {
        (rawValue & Self.reExport) != 0
    }

    /// Whether this has a stub and resolver.
    public var isStubAndResolver: Bool {
        (rawValue & Self.stubAndResolver) != 0
    }

    /// Whether this uses a static resolver.
    public var isStaticResolver: Bool {
        (rawValue & Self.staticResolver) != 0
    }

    /// Whether this is a function variant.
    public var isFunctionVariant: Bool {
        (rawValue & Self.functionVariant) != 0
    }

    /// Whether this is a thread-local variable.
    public var isThreadLocal: Bool {
        kind == .threadLocal
    }

    /// Whether this is an absolute symbol.
    public var isAbsolute: Bool {
        kind == .absolute
    }
}

extension ExportFlags: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        parts.append("kind: \(kind)")
        if isWeakDefinition { parts.append("weak") }
        if isReExport { parts.append("re-export") }
        if isStubAndResolver { parts.append("resolver") }
        if isStaticResolver { parts.append("static-resolver") }
        if isFunctionVariant { parts.append("variant") }
        return "ExportFlags(\(parts.joined(separator: ", ")))"
    }
}
