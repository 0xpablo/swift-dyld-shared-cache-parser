import Foundation

/// Errors that can occur while parsing a dyld shared cache.
public enum DyldCacheError: Error, CustomStringConvertible, Sendable {
    // MARK: - Header Errors

    /// The magic string is invalid or unrecognized.
    case invalidMagic(String)

    /// The architecture in the magic string is not supported.
    case unsupportedArchitecture(String)

    /// The header is too small to be valid.
    case headerTooSmall(expected: Int, actual: Int)

    /// The format version is not supported.
    case unsupportedFormatVersion(UInt8)

    // MARK: - Offset/Range Errors

    /// An offset points outside the buffer.
    case offsetOutOfBounds(offset: UInt64, bufferSize: Int)

    /// A range extends beyond the buffer.
    case rangeOutOfBounds(offset: UInt64, size: UInt64, bufferSize: Int)

    /// An image index is out of bounds.
    case imageIndexOutOfBounds(index: Int, max: Int)

    /// A string offset is invalid.
    case invalidStringOffset(UInt32)

    /// A VM address is not mapped by any cache mapping.
    case vmAddressNotMapped(UInt64)

    // MARK: - Structure Parsing Errors

    /// Failed to parse a mapping structure.
    case invalidMappingInfo(String)

    /// Failed to parse an image info structure.
    case invalidImageInfo(String)

    /// Failed to parse local symbols info.
    case invalidLocalSymbolsInfo(String)

    // MARK: - Export Trie Errors

    /// The export trie format is invalid.
    case invalidExportTrieFormat(String)

    /// Unexpected end of trie data.
    case unexpectedEndOfTrie

    /// Invalid ULEB128 encoding.
    case invalidULEB128

    // MARK: - Mach-O Errors

    /// Failed to parse an embedded Mach-O header/load commands.
    case invalidMachO(String)

    // MARK: - Slide Info Errors

    /// Unknown slide info version.
    case unknownSlideInfoVersion(UInt32)

    /// Failed to parse slide info.
    case slideInfoParseError(version: UInt32, detail: String)

    // MARK: - Multi-Cache Errors

    /// A subcache file was not found.
    case subCacheNotFound(suffix: String)

    /// The symbols file was not found.
    case symbolsFileNotFound

    /// A subcache UUID doesn't match.
    case subCacheUUIDMismatch(expected: UUID, actual: UUID)

    // MARK: - Symbol Errors

    /// The symbol was not found.
    case symbolNotFound(String)

    /// Invalid symbol type.
    case invalidSymbolType(UInt8)

    /// Invalid export flags.
    case invalidExportFlags(UInt64)

    // MARK: - File I/O Errors

    /// Failed to read file.
    case fileReadError(path: String, underlying: Error)

    /// File is too small.
    case fileTooSmall(path: String, size: Int)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .invalidMagic(let magic):
            return "Invalid dyld cache magic: '\(magic)'"
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: '\(arch)'"
        case .headerTooSmall(let expected, let actual):
            return "Header too small: expected at least \(expected) bytes, got \(actual)"
        case .unsupportedFormatVersion(let version):
            return "Unsupported format version: \(version)"
        case .offsetOutOfBounds(let offset, let bufferSize):
            return "Offset \(offset) is out of bounds (buffer size: \(bufferSize))"
        case .rangeOutOfBounds(let offset, let size, let bufferSize):
            return "Range [\(offset), \(offset + size)) is out of bounds (buffer size: \(bufferSize))"
        case .imageIndexOutOfBounds(let index, let max):
            return "Image index \(index) is out of bounds (max: \(max))"
        case .invalidStringOffset(let offset):
            return "Invalid string offset: \(offset)"
        case .vmAddressNotMapped(let addr):
            return String(format: "VM address 0x%llx is not mapped by any cache mapping", addr)
        case .invalidMappingInfo(let detail):
            return "Invalid mapping info: \(detail)"
        case .invalidImageInfo(let detail):
            return "Invalid image info: \(detail)"
        case .invalidLocalSymbolsInfo(let detail):
            return "Invalid local symbols info: \(detail)"
        case .invalidExportTrieFormat(let detail):
            return "Invalid export trie format: \(detail)"
        case .unexpectedEndOfTrie:
            return "Unexpected end of export trie data"
        case .invalidULEB128:
            return "Invalid ULEB128 encoding"
        case .invalidMachO(let detail):
            return "Invalid Mach-O: \(detail)"
        case .unknownSlideInfoVersion(let version):
            return "Unknown slide info version: \(version)"
        case .slideInfoParseError(let version, let detail):
            return "Slide info v\(version) parse error: \(detail)"
        case .subCacheNotFound(let suffix):
            return "Subcache not found: \(suffix)"
        case .symbolsFileNotFound:
            return "Symbols file not found"
        case .subCacheUUIDMismatch(let expected, let actual):
            return "Subcache UUID mismatch: expected \(expected), got \(actual)"
        case .symbolNotFound(let name):
            return "Symbol not found: \(name)"
        case .invalidSymbolType(let type):
            return "Invalid symbol type: 0x\(String(type, radix: 16))"
        case .invalidExportFlags(let flags):
            return "Invalid export flags: 0x\(String(flags, radix: 16))"
        case .fileReadError(let path, let underlying):
            return "Failed to read file '\(path)': \(underlying)"
        case .fileTooSmall(let path, let size):
            return "File '\(path)' is too small (\(size) bytes)"
        }
    }
}
