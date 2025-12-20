import Foundation

/// A parsed exported symbol from the export trie.
public struct ExportSymbol: Sendable, Hashable {
    /// The full symbol name.
    public let name: String

    /// Export flags indicating the symbol type and attributes.
    public let flags: ExportFlags

    /// The symbol offset/address (for regular exports).
    /// This is an offset from the image base address.
    public let offset: UInt64?

    /// The library ordinal for re-exported symbols.
    public let reExportDylibOrdinal: Int?

    /// The imported name for re-exported symbols (if different from `name`).
    public let importedName: String?

    /// The resolver function offset for stub-and-resolver exports.
    public let resolverOffset: UInt64?

    public init(
        name: String,
        flags: ExportFlags,
        offset: UInt64? = nil,
        reExportDylibOrdinal: Int? = nil,
        importedName: String? = nil,
        resolverOffset: UInt64? = nil
    ) {
        self.name = name
        self.flags = flags
        self.offset = offset
        self.reExportDylibOrdinal = reExportDylibOrdinal
        self.importedName = importedName
        self.resolverOffset = resolverOffset
    }

    /// Whether this symbol is a re-export.
    public var isReExport: Bool {
        flags.isReExport
    }

    /// Whether this symbol is a weak definition.
    public var isWeak: Bool {
        flags.isWeakDefinition
    }

    /// Whether this symbol has a resolver function.
    public var hasResolver: Bool {
        flags.isStubAndResolver
    }

    /// The effective address of this symbol given a base address.
    public func address(withBase baseAddress: UInt64) -> UInt64? {
        guard let offset = offset else { return nil }
        if flags.isAbsolute {
            return offset
        }
        return baseAddress + offset
    }
}

extension ExportSymbol: CustomStringConvertible {
    public var description: String {
        var parts: [String] = [name]

        if let offset = offset {
            parts.append(String(format: "offset: 0x%llx", offset))
        }

        if let ordinal = reExportDylibOrdinal {
            parts.append("re-export from ordinal \(ordinal)")
            if let imported = importedName, imported != name {
                parts.append("as \(imported)")
            }
        }

        if let resolver = resolverOffset {
            parts.append(String(format: "resolver: 0x%llx", resolver))
        }

        if flags.isWeakDefinition {
            parts.append("[weak]")
        }

        return parts.joined(separator: " ")
    }
}
