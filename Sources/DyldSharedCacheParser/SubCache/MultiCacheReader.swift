import BinaryParsing
import Foundation

/// A reader for multi-file dyld shared caches.
///
/// Modern dyld caches are split across multiple files:
/// - Main cache file (e.g., `dyld_shared_cache_arm64e`)
/// - Numbered subcaches (e.g., `.01`, `.02`, ... `.XX`)
/// - Special subcaches (`.dylddata`, `.dyldreadonly`, `.dyldlinkedit`)
/// - Symbols file (`.symbols`)
///
/// This reader loads and coordinates access to all cache files.
public struct MultiCacheReader: Sendable {
    /// The path to the main cache file.
    public let mainCachePath: String

    /// The main cache.
    public let mainCache: DyldCache

    /// The main cache byte source.
    public let mainSource: any DyldCacheByteSource

    /// Loaded subcache files, keyed by their UUID.
    public let subCaches: [UUID: (cache: DyldCache, source: any DyldCacheByteSource, path: String)]

    /// The symbols cache (from `.symbols` file), if available.
    public let symbolsCache: DyldCache?

    /// The symbols byte source, if available.
    public let symbolsSource: (any DyldCacheByteSource)?

    /// Initialize a multi-cache reader from the main cache path.
    ///
    /// This will automatically discover and load:
    /// - The main cache file
    /// - The .symbols file (if present)
    ///
    /// - Parameter mainCachePath: Path to the main dyld cache file.
    public init(
        mainCachePath: String,
        requireAllSubCaches: Bool = true,
        requireSymbolsFile: Bool = false
    ) throws {
        func openDataSource(path: String) throws -> any DyldCacheByteSource {
            let url = URL(fileURLWithPath: path)
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw DyldCacheError.fileReadError(path: path, underlying: error)
            }
            return DataByteSource(data)
        }

        try self.init(
            mainCachePath: mainCachePath,
            open: { path in
                if FileManager.default.fileExists(atPath: path) {
                    return try openDataSource(path: path)
                }
                return nil
            },
            requireAllSubCaches: requireAllSubCaches,
            requireSymbolsFile: requireSymbolsFile
        )
    }

    /// Initialize from a byte-source opener.
    ///
    /// The `open` closure is expected to return `nil` if the path does not exist.
    public init(
        mainCachePath: String,
        open: (String) throws -> (any DyldCacheByteSource)?,
        requireAllSubCaches: Bool = true,
        requireSymbolsFile: Bool = false
    ) throws {
        self.mainCachePath = mainCachePath
        guard let mainSource = try open(mainCachePath) else {
            throw DyldCacheError.fileReadError(path: mainCachePath, underlying: CocoaError(.fileNoSuchFile))
        }
        self.mainSource = mainSource
        self.mainCache = try DyldCache(source: mainSource)

        let directory = (mainCachePath as NSString).deletingLastPathComponent
        let baseName = (mainCachePath as NSString).lastPathComponent

        var loadedSubCaches: [UUID: (cache: DyldCache, source: any DyldCacheByteSource, path: String)] = [:]
        for entry in mainCache.subCaches {
            let fileName = entry.fileName(forMainCache: baseName)
            let fullPath = (directory as NSString).appendingPathComponent(fileName)
            guard let scSource = try open(fullPath) else {
                if requireAllSubCaches { throw DyldCacheError.subCacheNotFound(suffix: entry.fileSuffix) }
                continue
            }
            let cache = try DyldCache(source: scSource)
            guard cache.header.uuid == entry.uuid else {
                throw DyldCacheError.subCacheUUIDMismatch(expected: entry.uuid, actual: cache.header.uuid)
            }
            loadedSubCaches[cache.header.uuid] = (cache: cache, source: scSource, path: fullPath)
        }
        self.subCaches = loadedSubCaches

        if !mainCache.header.symbolFileUUID.isNullUUID {
            let symbolsPath = mainCachePath + ".symbols"
            if let symSource = try open(symbolsPath) {
                let symCache = try DyldCache(source: symSource)
                guard symCache.header.uuid == mainCache.header.symbolFileUUID else {
                    throw DyldCacheError.subCacheUUIDMismatch(expected: mainCache.header.symbolFileUUID, actual: symCache.header.uuid)
                }
                self.symbolsSource = symSource
                self.symbolsCache = symCache
            } else {
                if requireSymbolsFile { throw DyldCacheError.symbolsFileNotFound }
                self.symbolsSource = nil
                self.symbolsCache = nil
            }
        } else {
            self.symbolsSource = nil
            self.symbolsCache = nil
        }
    }

    /// Initialize with pre-loaded components.
    public init(
        mainCache: DyldCache,
        mainSource: any DyldCacheByteSource,
        mainCachePath: String,
        subCaches: [UUID: (cache: DyldCache, source: any DyldCacheByteSource, path: String)],
        symbolsCache: DyldCache?,
        symbolsSource: (any DyldCacheByteSource)?
    ) {
        self.mainCache = mainCache
        self.mainSource = mainSource
        self.mainCachePath = mainCachePath
        self.subCaches = subCaches
        self.symbolsCache = symbolsCache
        self.symbolsSource = symbolsSource
    }
}

// MARK: - Image Access

extension MultiCacheReader {
    /// Number of images in the cache.
    public var imageCount: Int {
        mainCache.images.count
    }

    /// Get the path for an image at the given index.
    public func imagePath(at index: Int) throws -> String {
        try mainCache.imagePath(at: index, from: mainSource)
    }

    /// Get all image paths.
    public func allImagePaths() throws -> [String] {
        try mainCache.allImagePaths(from: mainSource)
    }

    /// Find an image by path.
    public func findImage(byPath path: String) throws -> (index: Int, info: ImageInfo)? {
        try mainCache.findImage(byPath: path, from: mainSource)
    }

    /// Find the image index for a given image UUID (from `ImageTextInfo`).
    public func findImageIndex(byUUID uuid: UUID) -> Int? {
        mainCache.imagesText.firstIndex { $0.uuid == uuid }
    }

    /// Reads a NUL-terminated UTF-8 string from the main cache file at `fileOffset`.
    public func string(atFileOffset fileOffset: Int) throws -> String {
        guard fileOffset >= 0, fileOffset < mainSource.size else { return "" }
        return try mainSource.readNulTerminatedString(offset: fileOffset)
    }
}

// MARK: - VM Reading

extension MultiCacheReader {
    private struct CacheSource: Sendable {
        let uuid: UUID
        let cache: DyldCache
        let path: String
        let source: any DyldCacheByteSource
    }

    private func vmSources() -> [CacheSource] {
        var sources: [CacheSource] = [
            CacheSource(uuid: mainCache.header.uuid, cache: mainCache, path: mainCachePath, source: mainSource)
        ]
        sources.reserveCapacity(1 + subCaches.count)
        for (uuid, entry) in subCaches {
            sources.append(CacheSource(uuid: uuid, cache: entry.cache, path: entry.path, source: entry.source))
        }
        return sources
    }

    private func resolve(vmAddress: UInt64) -> (source: CacheSource, mapping: MappingAndSlideInfo, fileOffset: UInt64)? {
        for source in vmSources() {
            guard let mapping = source.cache.addressResolver.mapping(forVMAddress: vmAddress) else { continue }
            let fileOffset = mapping.fileOffset + (vmAddress - mapping.address)
            return (source, mapping, fileOffset)
        }
        return nil
    }

    /// Read bytes from the cache at a given unslid VM address.
    ///
    /// This works across dyld4 split caches by consulting mappings in the main cache and all subcaches.
    public func readBytes(vmAddress: UInt64, size: Int) throws -> Data {
        guard size >= 0 else { return Data() }

        var remaining = size
        var current = vmAddress
        var out = Data()
        out.reserveCapacity(size)

        while remaining > 0 {
            guard let resolved = resolve(vmAddress: current) else {
                throw DyldCacheError.vmAddressNotMapped(current)
            }

            let mappingEnd = resolved.mapping.address + resolved.mapping.size
            let availableInMapping = Int(min(UInt64(remaining), mappingEnd - current))
            let start = Int(resolved.fileOffset)
            let end = start + availableInMapping
            if start < 0 || start >= resolved.source.source.size || end > resolved.source.source.size {
                throw DyldCacheError.rangeOutOfBounds(
                    offset: resolved.fileOffset,
                    size: UInt64(availableInMapping),
                    bufferSize: resolved.source.source.size
                )
            }
            let chunk = try resolved.source.source.read(offset: start, length: availableInMapping)
            if chunk.count != availableInMapping {
                throw DyldCacheError.rangeOutOfBounds(
                    offset: resolved.fileOffset,
                    size: UInt64(availableInMapping),
                    bufferSize: resolved.source.source.size
                )
            }
            out.append(chunk)
            remaining -= availableInMapping
            current += UInt64(availableInMapping)
        }

        return out
    }
}

// MARK: - Exports Trie

extension MultiCacheReader {
    private func machOHeaderLoadCommandsSize(vmAddress: UInt64) throws -> Int {
        let headerProbe = try readBytes(vmAddress: vmAddress, size: 32)
        do {
            return try headerProbe.withParserSpan { span in
                let magic = try UInt32(parsingLittleEndian: &span)
                let is64: Bool
                switch magic {
                case 0xfeedface:
                    is64 = false
                case 0xfeedfacf:
                    is64 = true
                default:
                    throw DyldCacheError.invalidMachO(String(format: "unknown magic 0x%08x", magic))
                }

                _ = try UInt32(parsingLittleEndian: &span) // cputype
                _ = try UInt32(parsingLittleEndian: &span) // cpusubtype
                _ = try UInt32(parsingLittleEndian: &span) // filetype
                _ = try UInt32(parsingLittleEndian: &span) // ncmds
                let sizeofcmds = try UInt32(parsingLittleEndian: &span)

                let headerSize = is64 ? 32 : 28
                let total = headerSize + Int(sizeofcmds)
                if total <= 0 || total > 16 * 1024 * 1024 {
                    throw DyldCacheError.invalidMachO("unreasonable load commands size: \(total)")
                }
                return total
            }
        } catch let error as ParsingError {
            throw DyldCacheError.invalidMachO(error.description)
        }
    }

    /// Enumerate exported symbols for an image by parsing its exports trie.
    ///
    /// This is a fallback when local symbols are unavailable.
    public func exportedSymbols(forImageAt index: Int) throws -> [ExportSymbol] {
        guard let textInfo = mainCache.imageTextInfo(at: index) else { return [] }

        let machOSize = try machOHeaderLoadCommandsSize(vmAddress: textInfo.loadAddress)
        let machOBytes = try readBytes(vmAddress: textInfo.loadAddress, size: machOSize)

        guard let location = try MachOExportTrieLocator.locate(in: machOBytes) else { return [] }
        let trieData = try readBytes(vmAddress: location.vmAddress, size: Int(location.size))

        let trie = ExportTrie(data: trieData)
        return trie.allSymbolsBestEffort()
    }
}

// MARK: - Symbolication

extension MultiCacheReader {
    /// A simple symbolication result.
    public struct SymbolicationResult: Sendable, Hashable {
        /// Best-matching symbol name.
        public let symbol: String
        /// The `pc - imageLoadAddress` offset.
        public let pcOffset: UInt64
        /// The offset of the resolved symbol within the image.
        public let symbolOffset: UInt64

        /// The `pcOffset - symbolOffset` addend.
        public var addend: UInt64 { pcOffset - symbolOffset }
    }

    private struct SymbolEntry: Sendable {
        let offset: UInt64
        let name: String
    }

    /// Symbolicate a PC given the image UUID and its runtime load address.
    ///
    /// - Note: This returns function names + offsets, not file/line info.
    public func lookup(
        pc: UInt64,
        imageUUID: UUID,
        imageLoadAddress: UInt64,
        preferLocalSymbols: Bool = true
    ) throws -> SymbolicationResult? {
        guard let imageIndex = findImageIndex(byUUID: imageUUID) else { return nil }
        guard let textInfo = mainCache.imageTextInfo(at: imageIndex) else { return nil }
        guard pc >= imageLoadAddress else { return nil }

        let pcOffset = pc - imageLoadAddress
        let unslidBase = textInfo.loadAddress

        var entries: [SymbolEntry] = []

        if preferLocalSymbols, hasLocalSymbols {
            if let locals = try? localSymbols(forImageAt: imageIndex) {
                entries.reserveCapacity(locals.count)
                for sym in locals {
                    guard !sym.name.isEmpty else { continue }
                    let addr = sym.address
                    guard addr >= unslidBase else { continue }
                    entries.append(SymbolEntry(offset: addr - unslidBase, name: sym.name))
                }
            }
        }

        if entries.isEmpty {
            let exports = try exportedSymbols(forImageAt: imageIndex)
            entries.reserveCapacity(exports.count)
            for sym in exports {
                guard !sym.name.isEmpty else { continue }
                if sym.flags.isAbsolute {
                    guard let absAddr = sym.offset, absAddr >= unslidBase else { continue }
                    entries.append(SymbolEntry(offset: absAddr - unslidBase, name: sym.name))
                } else if let off = sym.offset {
                    entries.append(SymbolEntry(offset: off, name: sym.name))
                }
            }
        }

        guard !entries.isEmpty else { return nil }
        entries.sort { $0.offset < $1.offset }

        // Binary search for the last entry with offset <= pcOffset.
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].offset <= pcOffset {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let idx = lo - 1
        guard idx >= 0 else { return nil }

        let hit = entries[idx]
        return SymbolicationResult(symbol: hit.name, pcOffset: pcOffset, symbolOffset: hit.offset)
    }
}

// MARK: - Symbol Access

extension MultiCacheReader {
    /// Whether local symbols are available.
    public var hasLocalSymbols: Bool {
        localSymbolsSourcePair() != nil
    }

    /// A reusable local-symbols resolver that avoids repeatedly reading the shared strings pool.
    ///
    /// Use this when building indices for many images from a single cache.
    public struct LocalSymbolsResolver: Sendable {
        public let cache: DyldCache
        public let source: any DyldCacheByteSource
        public let sharedContext: DyldCache.LocalSymbolsSharedContext

        public init(cache: DyldCache, source: any DyldCacheByteSource, sharedContext: DyldCache.LocalSymbolsSharedContext) {
            self.cache = cache
            self.source = source
            self.sharedContext = sharedContext
        }

        public func symbols(forImageAt index: Int, is64BitEntries: Bool = true) throws -> [DyldCache.ResolvedSymbol] {
            try cache.localSymbols(forImageAt: index, from: source, sharedContext: sharedContext, is64BitEntries: is64BitEntries)
        }
    }

    /// Creates a local-symbols resolver that preloads the shared strings pool once.
    public func makeLocalSymbolsResolver() throws -> LocalSymbolsResolver? {
        guard let pair = localSymbolsSourcePair() else { return nil }
        guard let ctx = try pair.cache.makeLocalSymbolsSharedContext(from: pair.source) else { return nil }
        return LocalSymbolsResolver(cache: pair.cache, source: pair.source, sharedContext: ctx)
    }

    /// Get local symbols for an image by index.
    ///
    /// - Parameters:
    ///   - index: The image index.
    ///   - is64BitEntries: Whether to use 64-bit local symbol entries.
    /// - Returns: Array of resolved symbols.
    public func localSymbols(
        forImageAt index: Int,
        is64BitEntries: Bool = true
    ) throws -> [DyldCache.ResolvedSymbol] {
        guard let source = localSymbolsSourcePair() else { throw DyldCacheError.symbolsFileNotFound }
        do {
            return try source.cache.localSymbols(forImageAt: index, from: source.source, is64BitEntries: is64BitEntries)
        } catch DyldCacheError.imageIndexOutOfBounds {
            return []
        }
    }

    /// Get local symbols info from the symbols file.
    public func localSymbolsInfo() throws -> LocalSymbolsInfo? {
        guard let source = localSymbolsSourcePair() else { return nil }
        return try source.cache.localSymbolsInfo(from: source.source)
    }

    /// Get all local symbols entries.
    public func allLocalSymbolsEntries(is64BitEntries: Bool = true) throws -> [LocalSymbolsEntry] {
        guard let source = localSymbolsSourcePair() else { return [] }
        return try source.cache.allLocalSymbolsEntries(from: source.source, is64BitEntries: is64BitEntries)
    }
}

private extension MultiCacheReader {
    func localSymbolsSourcePair() -> (cache: DyldCache, source: any DyldCacheByteSource)? {
        if let symbolsCache, let symbolsSource, symbolsCache.header.localSymbolsSize > 0 {
            return (symbolsCache, symbolsSource)
        }
        if mainCache.header.localSymbolsSize > 0 {
            return (mainCache, mainSource)
        }
        return nil
    }
}

// MARK: - SubCache Info

extension MultiCacheReader {
    /// The subcache entries from the main cache.
    public var subCacheEntries: [SubCacheEntry] {
        mainCache.subCaches
    }

    /// Get the expected file names for all subcaches.
    public func subCacheFileNames() -> [String] {
        let baseName = (mainCachePath as NSString).lastPathComponent
        return mainCache.subCaches.map { $0.fileName(forMainCache: baseName) }
    }

    /// Check which subcache files exist on disk.
    public func existingSubCacheFiles() -> [(entry: SubCacheEntry, path: String)] {
        let directory = (mainCachePath as NSString).deletingLastPathComponent
        let baseName = (mainCachePath as NSString).lastPathComponent

        return mainCache.subCaches.compactMap { entry in
            let fileName = entry.fileName(forMainCache: baseName)
            let fullPath = (directory as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fullPath) {
                return (entry, fullPath)
            }
            return nil
        }
    }
}

// MARK: - Description

extension MultiCacheReader: CustomStringConvertible {
    public var description: String {
        """
        MultiCacheReader(
            path: \(mainCachePath),
            architecture: \(mainCache.header.architecture),
            images: \(mainCache.images.count),
            subCaches: \(mainCache.subCaches.count),
            loadedSubCaches: \(subCaches.count),
            hasLocalSymbols: \(hasLocalSymbols)
        )
        """
    }
}
