import BinaryParsing

/// Symbol type parsed from the n_type field of nlist_64.
public struct SymbolType: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    // MARK: - Masks

    /// Mask for STAB (debugging) symbols.
    public static let stabMask: UInt8 = 0xE0

    /// Mask for private external bit.
    public static let pextMask: UInt8 = 0x10

    /// Mask for symbol type.
    public static let typeMask: UInt8 = 0x0E

    /// Mask for external bit.
    public static let extMask: UInt8 = 0x01

    // MARK: - Type values (for typeMask)

    /// Undefined symbol.
    public static let undefined: UInt8 = 0x0

    /// Absolute symbol.
    public static let absolute: UInt8 = 0x2

    /// Indirect symbol.
    public static let indirect: UInt8 = 0xA

    /// Prebound undefined symbol.
    public static let prebound: UInt8 = 0xC

    /// Defined in section.
    public static let section: UInt8 = 0xE

    // MARK: - Computed properties

    /// Whether this is a STAB (debugging) symbol.
    public var isStab: Bool {
        (rawValue & Self.stabMask) != 0
    }

    /// Whether this is a private external symbol.
    public var isPrivateExternal: Bool {
        (rawValue & Self.pextMask) != 0
    }

    /// The type field value (after masking).
    public var typeField: UInt8 {
        rawValue & Self.typeMask
    }

    /// Whether this symbol is external.
    public var isExternal: Bool {
        (rawValue & Self.extMask) != 0
    }

    /// Whether this is an undefined symbol.
    public var isUndefined: Bool {
        !isStab && typeField == Self.undefined
    }

    /// Whether this is an absolute symbol.
    public var isAbsolute: Bool {
        !isStab && typeField == Self.absolute
    }

    /// Whether this symbol is defined in a section.
    public var isDefinedInSection: Bool {
        !isStab && typeField == Self.section
    }

    /// Whether this is an indirect symbol.
    public var isIndirect: Bool {
        !isStab && typeField == Self.indirect
    }

    /// Whether this is a prebound symbol.
    public var isPrebound: Bool {
        !isStab && typeField == Self.prebound
    }
}

/// Symbol description parsed from the n_desc field of nlist_64.
public struct SymbolDesc: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    // MARK: - Library ordinal

    /// The library ordinal for two-level namespace symbols.
    /// Stored in the high 8 bits.
    public var libraryOrdinal: Int {
        Int(Int8(bitPattern: UInt8(rawValue >> 8)))
    }

    // MARK: - Reference type (for undefined symbols)

    /// The reference type (low 4 bits).
    public var referenceType: UInt8 {
        UInt8(rawValue & 0xF)
    }

    // MARK: - Flags

    /// Whether this symbol is referenced dynamically.
    public var isReferencedDynamically: Bool {
        (rawValue & 0x0010) != 0
    }

    /// Whether this symbol should not be dead-stripped.
    public var isNoDeadStrip: Bool {
        (rawValue & 0x0020) != 0
    }

    /// Whether this is a weak reference.
    public var isWeakReference: Bool {
        (rawValue & 0x0040) != 0
    }

    /// Whether this is a weak definition.
    public var isWeakDefinition: Bool {
        (rawValue & 0x0080) != 0
    }

    /// Whether this symbol has a resolver function.
    public var hasResolver: Bool {
        (rawValue & 0x0100) != 0
    }

    /// Whether this is an alternate entry point.
    public var isAltEntry: Bool {
        (rawValue & 0x0200) != 0
    }

    /// Whether this is a cold function (less likely to be called).
    public var isColdFunc: Bool {
        (rawValue & 0x0400) != 0
    }
}

/// A 64-bit symbol table entry (nlist_64).
///
/// This structure represents a symbol in the Mach-O symbol table,
/// containing the symbol name index, type, section, description flags,
/// and value (address).
public struct NList64: Sendable, Hashable {
    /// Index into the string table for the symbol name.
    public let stringIndex: UInt32

    /// Symbol type and attributes.
    public let type: SymbolType

    /// Section number (1-based, 0 means no section).
    public let section: UInt8

    /// Symbol description and flags.
    public let desc: SymbolDesc

    /// Symbol value (typically an address).
    public let value: UInt64

    public init(
        stringIndex: UInt32,
        type: SymbolType,
        section: UInt8,
        desc: SymbolDesc,
        value: UInt64
    ) {
        self.stringIndex = stringIndex
        self.type = type
        self.section = section
        self.desc = desc
        self.value = value
    }

    /// Whether this symbol is defined (not undefined).
    public var isDefined: Bool {
        !type.isUndefined
    }

    /// Whether this symbol is local (not external).
    public var isLocal: Bool {
        !type.isExternal && !type.isPrivateExternal
    }

    /// Whether this symbol is a global export.
    public var isGlobalExport: Bool {
        type.isExternal && !type.isUndefined
    }
}

extension NList64 {
    /// Size of this structure in bytes.
    public static let size = 16

    /// Parse an NList64 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.stringIndex = try UInt32(parsingLittleEndian: &input)
        self.type = SymbolType(rawValue: try UInt8(parsing: &input))
        self.section = try UInt8(parsing: &input)
        self.desc = SymbolDesc(rawValue: try UInt16(parsingLittleEndian: &input))
        self.value = try UInt64(parsingLittleEndian: &input)
    }
}

/// A 32-bit symbol table entry (nlist).
public struct NList32: Sendable, Hashable {
    /// Index into the string table for the symbol name.
    public let stringIndex: UInt32

    /// Symbol type and attributes.
    public let type: SymbolType

    /// Section number (1-based, 0 means no section).
    public let section: UInt8

    /// Symbol description and flags.
    public let desc: SymbolDesc

    /// Symbol value (typically an address).
    public let value: UInt32

    public init(
        stringIndex: UInt32,
        type: SymbolType,
        section: UInt8,
        desc: SymbolDesc,
        value: UInt32
    ) {
        self.stringIndex = stringIndex
        self.type = type
        self.section = section
        self.desc = desc
        self.value = value
    }
}

extension NList32 {
    /// Size of this structure in bytes.
    public static let size = 12

    /// Parse an NList32 from a ParserSpan.
    public init(parsing input: inout ParserSpan) throws {
        self.stringIndex = try UInt32(parsingLittleEndian: &input)
        self.type = SymbolType(rawValue: try UInt8(parsing: &input))
        self.section = try UInt8(parsing: &input)
        self.desc = SymbolDesc(rawValue: try UInt16(parsingLittleEndian: &input))
        self.value = try UInt32(parsingLittleEndian: &input)
    }
}
