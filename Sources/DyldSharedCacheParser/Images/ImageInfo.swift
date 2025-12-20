import BinaryParsing
import Foundation

/// Basic information about a cached dylib image.
///
/// Each image (dylib) in the cache has an entry describing its
/// load address, modification time, inode, and path.
public struct ImageInfo: Sendable, Hashable {
    /// Unslid load address of this dylib.
    public let address: UInt64

    /// Modification time of the dylib when the cache was built.
    public let modTime: UInt64

    /// File system inode of the dylib when the cache was built.
    public let inode: UInt64

    /// File offset to the null-terminated path string in the cache.
    public let pathFileOffset: UInt32

    public init(
        address: UInt64,
        modTime: UInt64,
        inode: UInt64,
        pathFileOffset: UInt32
    ) {
        self.address = address
        self.modTime = modTime
        self.inode = inode
        self.pathFileOffset = pathFileOffset
    }
}

extension ImageInfo {
    /// Size of this structure in bytes.
    public static let size = 32

    /// Parse an ImageInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.address = try UInt64(parsingLittleEndian: &input)
        self.modTime = try UInt64(parsingLittleEndian: &input)
        self.inode = try UInt64(parsingLittleEndian: &input)
        self.pathFileOffset = try UInt32(parsingLittleEndian: &input)
        _ = try UInt32(parsingLittleEndian: &input) // pad
    }
}

extension ImageInfo: CustomStringConvertible {
    public var description: String {
        let addrHex = String(format: "0x%016llx", address)
        return "ImageInfo(addr: \(addrHex), pathOffset: \(pathFileOffset))"
    }
}
