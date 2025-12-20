import BinaryParsing

/// Basic mapping information for a region in the dyld shared cache.
///
/// This structure describes a memory mapping: its virtual address,
/// size, file offset, and protection flags.
public struct MappingInfo: Sendable, Hashable {
    /// Virtual memory address where this region is mapped.
    public let address: UInt64

    /// Size of the mapping in bytes.
    public let size: UInt64

    /// Offset in the cache file where this region's data starts.
    public let fileOffset: UInt64

    /// Maximum protection flags (r/w/x).
    public let maxProt: VMProtection

    /// Initial protection flags (r/w/x).
    public let initProt: VMProtection

    public init(
        address: UInt64,
        size: UInt64,
        fileOffset: UInt64,
        maxProt: VMProtection,
        initProt: VMProtection
    ) {
        self.address = address
        self.size = size
        self.fileOffset = fileOffset
        self.maxProt = maxProt
        self.initProt = initProt
    }
}

extension MappingInfo {
    /// Size of this structure in bytes.
    public static let size = 32

    /// Parse a MappingInfo from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.address = try UInt64(parsingLittleEndian: &input)
        self.size = try UInt64(parsingLittleEndian: &input)
        self.fileOffset = try UInt64(parsingLittleEndian: &input)
        self.maxProt = VMProtection(rawValue: try UInt32(parsingLittleEndian: &input))
        self.initProt = VMProtection(rawValue: try UInt32(parsingLittleEndian: &input))
    }
}

extension MappingInfo: CustomStringConvertible {
    public var description: String {
        let addrHex = String(format: "0x%016llx", address)
        let sizeHex = String(format: "0x%llx", size)
        let offsetHex = String(format: "0x%llx", fileOffset)
        return "MappingInfo(addr: \(addrHex), size: \(sizeHex), offset: \(offsetHex), prot: \(initProt)/\(maxProt))"
    }
}
