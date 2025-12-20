import BinaryParsing
import Foundation

/// Extended information about a cached dylib image.
///
/// This structure contains additional metadata including the address
/// of the exports trie and weak bindings for this dylib.
public struct ImageInfoExtra: Sendable, Hashable {
    /// Unslid address of the exports trie in the cache.
    public let exportsTrieAddr: UInt64

    /// Unslid address of weak bindings data.
    public let weakBindingsAddr: UInt64

    /// Size of the exports trie in bytes.
    public let exportsTrieSize: UInt32

    /// Size of weak bindings data in bytes.
    public let weakBindingsSize: UInt32

    /// Start index in the dependents array.
    public let dependentsStartArrayIndex: UInt32

    /// Start index in the re-exports array.
    public let reExportsStartArrayIndex: UInt32

    public init(
        exportsTrieAddr: UInt64,
        weakBindingsAddr: UInt64,
        exportsTrieSize: UInt32,
        weakBindingsSize: UInt32,
        dependentsStartArrayIndex: UInt32,
        reExportsStartArrayIndex: UInt32
    ) {
        self.exportsTrieAddr = exportsTrieAddr
        self.weakBindingsAddr = weakBindingsAddr
        self.exportsTrieSize = exportsTrieSize
        self.weakBindingsSize = weakBindingsSize
        self.dependentsStartArrayIndex = dependentsStartArrayIndex
        self.reExportsStartArrayIndex = reExportsStartArrayIndex
    }

    /// Whether this image has an exports trie.
    public var hasExportsTrie: Bool {
        exportsTrieSize > 0
    }

    /// Whether this image has weak bindings.
    public var hasWeakBindings: Bool {
        weakBindingsSize > 0
    }
}

extension ImageInfoExtra {
    /// Size of this structure in bytes.
    public static let size = 32

    /// Parse an ImageInfoExtra from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.exportsTrieAddr = try UInt64(parsingLittleEndian: &input)
        self.weakBindingsAddr = try UInt64(parsingLittleEndian: &input)
        self.exportsTrieSize = try UInt32(parsingLittleEndian: &input)
        self.weakBindingsSize = try UInt32(parsingLittleEndian: &input)
        self.dependentsStartArrayIndex = try UInt32(parsingLittleEndian: &input)
        self.reExportsStartArrayIndex = try UInt32(parsingLittleEndian: &input)
    }
}

/// Information about a cached dylib's TEXT segment.
public struct ImageTextInfo: Sendable, Hashable {
    /// UUID of this dylib.
    public let uuid: UUID

    /// Unslid load address of __TEXT segment.
    public let loadAddress: UInt64

    /// Size of the __TEXT segment.
    public let textSegmentSize: UInt32

    /// Offset from start of cache file to the path string.
    public let pathOffset: UInt32

    public init(
        uuid: UUID,
        loadAddress: UInt64,
        textSegmentSize: UInt32,
        pathOffset: UInt32
    ) {
        self.uuid = uuid
        self.loadAddress = loadAddress
        self.textSegmentSize = textSegmentSize
        self.pathOffset = pathOffset
    }
}

extension ImageTextInfo {
    /// Size of this structure in bytes.
    public static let size = 32

    /// Parse an ImageTextInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        // UUID (16 bytes)
        let uuidBytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        self.uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        self.loadAddress = try UInt64(parsingLittleEndian: &input)
        self.textSegmentSize = try UInt32(parsingLittleEndian: &input)
        self.pathOffset = try UInt32(parsingLittleEndian: &input)
    }
}
