import BinaryParsing
import Foundation

/// Maximum symbol name length to prevent excessive memory allocation.
/// Most symbol names are under 1KB; 4KB is a very generous limit.
private let maxSymbolNameLength = 4096

/// Parser for the export trie structure in Mach-O binaries.
///
/// The export trie is a compact prefix tree that stores exported symbols.
/// Each node can be terminal (contains export info) and may have children
/// (edges to other nodes with label strings).
public struct ExportTrie: Sendable {
    /// The raw trie data.
    private let data: Data

    /// Initialize with raw trie data.
    public init(data: Data) {
        self.data = data
    }

    /// Initialize with a byte array.
    public init(bytes: [UInt8]) {
        self.data = Data(bytes)
    }

    /// Whether the trie is empty.
    public var isEmpty: Bool {
        data.isEmpty
    }

    /// Look up a specific symbol by name.
    public func lookup(_ symbolName: String) throws -> ExportSymbol? {
        guard !data.isEmpty else { return nil }
        return try data.withParserSpan { root in
            try lookupSymbol(symbolName, root: root, at: 0, prefix: "")
        }
    }

    /// Enumerate all symbols in the trie.
    public func allSymbols() throws -> [ExportSymbol] {
        guard !data.isEmpty else { return [] }

        var symbols: [ExportSymbol] = []
        try data.withParserSpan { root in
            try enumerateNode(root: root, at: 0, prefix: "", symbols: &symbols)
        }
        return symbols
    }

    /// Enumerate all symbols in the trie, returning partial results when the trie is malformed.
    public func allSymbolsBestEffort() -> [ExportSymbol] {
        guard !data.isEmpty else { return [] }
        var symbols: [ExportSymbol] = []
        do {
            try data.withParserSpan { root in
                try enumerateNode(root: root, at: 0, prefix: "", symbols: &symbols)
            }
        } catch {
            // Best-effort: return whatever was collected before hitting invalid data.
        }
        return symbols
    }

    /// Create an iterator for lazy symbol enumeration.
    public func makeIterator() -> ExportTrieIterator {
        ExportTrieIterator(data: data)
    }
}

extension ExportTrie {
    /// Look up a symbol by walking the trie.
    private func lookupSymbol(
        _ symbolName: String,
        root: borrowing ParserSpan,
        at offset: Int,
        prefix: String
    ) throws -> ExportSymbol? {
        var position: ParserSpan
        do {
            position = try root.seeking(toAbsoluteOffset: offset)
        } catch {
            throw DyldCacheError.unexpectedEndOfTrie
        }

        // Read terminal info size.
        let terminalSize = try Self.readULEB128(from: &position)

        // Check if this node is terminal and matches our symbol.
        if terminalSize > 0 && prefix == symbolName {
            var terminalPosition = try root.seeking(toAbsoluteOffset: position.startPosition)
            return try Self.parseTerminalInfo(from: &terminalPosition, name: symbolName)
        }

        // Skip terminal info if present.
        if terminalSize > 0 {
            try Self.skipBytes(from: &position, count: Int(terminalSize))
        }

        // Read child count.
        let childCount: UInt8
        do {
            childCount = try UInt8(parsing: &position)
        } catch {
            throw DyldCacheError.unexpectedEndOfTrie
        }

        // Look for matching edge.
        for _ in 0..<childCount {
            // Read edge label (NUL-terminated string).
            let edgeLabel = try Self.readNullTerminatedString(from: &position)

            // Read child offset.
            let childOffset = try Self.readULEB128(from: &position)

            // Check if symbol name starts with this edge.
            let newPrefix = prefix + edgeLabel
            if symbolName.hasPrefix(newPrefix) {
                return try lookupSymbol(symbolName, root: root, at: Int(childOffset), prefix: newPrefix)
            }
        }

        return nil
    }

    /// Enumerate all symbols starting from a node.
    private func enumerateNode(
        root: borrowing ParserSpan,
        at offset: Int,
        prefix: String,
        symbols: inout [ExportSymbol]
    ) throws {
        var position: ParserSpan
        do {
            position = try root.seeking(toAbsoluteOffset: offset)
        } catch {
            throw DyldCacheError.unexpectedEndOfTrie
        }

        // Read terminal info size.
        let terminalSize = try Self.readULEB128(from: &position)

        // If terminal, parse the symbol.
        if terminalSize > 0 {
            var terminalPosition = try root.seeking(toAbsoluteOffset: position.startPosition)
            let symbol = try Self.parseTerminalInfo(from: &terminalPosition, name: prefix)
            symbols.append(symbol)
            try Self.skipBytes(from: &position, count: Int(terminalSize))
        }

        // Read child count.
        let childCount: UInt8
        do {
            childCount = try UInt8(parsing: &position)
        } catch {
            return // End of data, no children.
        }

        // Process each child edge.
        for _ in 0..<childCount {
            let edgeLabel = try Self.readNullTerminatedString(from: &position)
            let childOffset = try Self.readULEB128(from: &position)
            let newPrefix = prefix + edgeLabel
            try enumerateNode(root: root, at: Int(childOffset), prefix: newPrefix, symbols: &symbols)
        }
    }

    fileprivate static func parseTerminalInfo(
        from input: inout ParserSpan,
        name: String
    ) throws -> ExportSymbol {
        // Read flags.
        let flagsValue = try readULEB128(from: &input)
        let flags = ExportFlags(rawValue: flagsValue)

        if flags.isReExport {
            // Re-export: ordinal + optional imported name.
            let ordinal = try readULEB128(from: &input)
            let importedName = try readNullTerminatedString(from: &input)
            let actualImportedName = importedName.isEmpty ? nil : importedName

            return ExportSymbol(
                name: name,
                flags: flags,
                reExportDylibOrdinal: Int(ordinal),
                importedName: actualImportedName
            )
        }

        if flags.isStubAndResolver {
            // Stub and resolver: stub offset + resolver offset.
            let stubOffset = try readULEB128(from: &input)
            let resolverOffset = try readULEB128(from: &input)

            return ExportSymbol(
                name: name,
                flags: flags,
                offset: stubOffset,
                resolverOffset: resolverOffset
            )
        }

        // Regular export: just an offset.
        let symbolOffset = try readULEB128(from: &input)
        return ExportSymbol(
            name: name,
            flags: flags,
            offset: symbolOffset
        )
    }

    /// Read a ULEB128-encoded value.
    fileprivate static func readULEB128(from input: inout ParserSpan) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            let byte: UInt8
            do {
                byte = try UInt8(parsing: &input)
            } catch {
                throw DyldCacheError.unexpectedEndOfTrie
            }

            result |= UInt64(byte & 0x7F) << shift
            shift += 7

            if (byte & 0x80) == 0 {
                return result
            }
            if shift >= 64 {
                throw DyldCacheError.invalidULEB128
            }
        }
    }

    /// Read a NUL-terminated UTF-8 string with a length limit.
    fileprivate static func readNullTerminatedString(from input: inout ParserSpan) throws -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(256)

        while true {
            let byte: UInt8
            do {
                byte = try UInt8(parsing: &input)
            } catch {
                throw DyldCacheError.unexpectedEndOfTrie
            }

            if byte == 0 {
                return String(decoding: bytes, as: UTF8.self)
            }

            bytes.append(byte)
            if bytes.count > maxSymbolNameLength {
                throw DyldCacheError.invalidExportTrieFormat("Symbol name exceeds maximum length (\(maxSymbolNameLength))")
            }
        }
    }

    fileprivate static func skipBytes(from input: inout ParserSpan, count: Int) throws {
        if count <= 0 { return }
        for _ in 0..<count {
            _ = try UInt8(parsing: &input)
        }
    }
}

/// Iterator for lazy enumeration of export trie symbols.
///
/// - Note: This iterator has mutable state and is marked `@unchecked Sendable`.
///   Individual iterator instances should not be shared across threads.
///   Create separate iterators for each thread if needed.
public struct ExportTrieIterator: IteratorProtocol, Sequence, @unchecked Sendable {
    private let data: Data
    private var stack: [(offset: Int, prefix: String, childIndex: Int, childCount: Int, childOffsets: [(label: String, offset: Int)])]
    private var finished = false

    init(data: Data) {
        self.data = data
        if data.isEmpty {
            self.stack = []
            self.finished = true
        } else {
            self.stack = [(offset: 0, prefix: "", childIndex: 0, childCount: -1, childOffsets: [])]
        }
    }

    public mutating func next() -> ExportSymbol? {
        guard !finished else { return nil }

        while !stack.isEmpty {
            if let symbol = processCurrentNode() {
                return symbol
            }
        }

        finished = true
        return nil
    }

    private mutating func processCurrentNode() -> ExportSymbol? {
        guard var current = stack.popLast() else { return nil }

        return data.withParserSpan { root in
            if current.childCount == -1 {
                do {
                    var position = try root.seeking(toAbsoluteOffset: current.offset)
                    let terminalSize = try ExportTrie.readULEB128(from: &position)

                    var result: ExportSymbol? = nil
                    if terminalSize > 0 {
                        var terminalPosition = try root.seeking(toAbsoluteOffset: position.startPosition)
                        result = try? ExportTrie.parseTerminalInfo(from: &terminalPosition, name: current.prefix)
                        try ExportTrie.skipBytes(from: &position, count: Int(terminalSize))
                    }

                    let childCount: Int
                    do {
                        childCount = Int(try UInt8(parsing: &position))
                    } catch {
                        return result
                    }

                    var childOffsets: [(label: String, offset: Int)] = []
                    childOffsets.reserveCapacity(childCount)
                    for _ in 0..<childCount {
                        guard let label = try? ExportTrie.readNullTerminatedString(from: &position) else { break }
                        guard let off = try? ExportTrie.readULEB128(from: &position) else { break }
                        childOffsets.append((label: label, offset: Int(off)))
                    }

                    current.childCount = childCount
                    current.childOffsets = childOffsets
                    current.childIndex = 0

                    if !childOffsets.isEmpty {
                        stack.append(current)
                    }

                    return result
                } catch {
                    return nil
                }
            }

            if current.childIndex < current.childOffsets.count {
                let child = current.childOffsets[current.childIndex]
                current.childIndex += 1

                if current.childIndex < current.childOffsets.count {
                    stack.append(current)
                }

                let newPrefix = current.prefix + child.label
                stack.append((offset: child.offset, prefix: newPrefix, childIndex: 0, childCount: -1, childOffsets: []))
            }

            return nil
        }
    }
}
