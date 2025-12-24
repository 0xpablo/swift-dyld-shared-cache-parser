import BinaryParsing
import Foundation

// MARK: - Lazy String Pool for Memory-Efficient Symbol Loading

/// Memory-mapped string pool that streams data to a temp file and uses mmap for access.
///
/// This approach provides:
/// - Fast initialization: One sequential read from the source (streaming in chunks)
/// - Low memory: Only ~4MB buffer during streaming, then OS handles paging via mmap
/// - Fast access: Direct memory access to mmap'd data
public final class LazyStringPool: @unchecked Sendable {
    private let mappedData: Data
    private let tempFileURL: URL?

    /// Creates a lazy string pool by streaming from source to a temp file and memory-mapping it.
    ///
    /// - Parameters:
    ///   - source: The byte source to read from.
    ///   - baseOffset: The offset in the source where the string pool starts.
    ///   - totalSize: The total size of the string pool in bytes.
    public init(
        source: any DyldCacheByteSource,
        baseOffset: Int,
        totalSize: Int
    ) throws {
        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("dyld-strings-\(UUID().uuidString)")

        // Create and open the file for writing
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempFile)

        do {
            // Stream from source to temp file in chunks to avoid memory spikes
            let chunkSize = 4 * 1024 * 1024 // 4MB chunks
            var offset = baseOffset
            var remaining = totalSize

            while remaining > 0 {
                let readSize = min(chunkSize, remaining)
                let chunk = try source.read(offset: offset, length: readSize)
                try handle.write(contentsOf: chunk)
                offset += readSize
                remaining -= readSize
            }

            try handle.close()

            // Memory-map the temp file - OS handles paging
            self.mappedData = try Data(contentsOf: tempFile, options: .mappedIfSafe)
            self.tempFileURL = tempFile
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempFile)
            throw error
        }
    }

    deinit {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Read a NUL-terminated string at the given pool offset.
    ///
    /// - Parameter poolOffset: The offset within the string pool.
    /// - Returns: The string at that offset, or empty string if out of bounds.
    public func string(at poolOffset: Int) -> String {
        guard poolOffset >= 0, poolOffset < mappedData.count else { return "" }
        let start = mappedData.startIndex + poolOffset
        var end = start
        while end < mappedData.endIndex, mappedData[end] != 0 { end += 1 }
        return String(decoding: mappedData[start..<end], as: UTF8.self)
    }
}

/// A parsed dyld shared cache.
///
/// This is the main entry point for parsing dyld shared cache files.
/// It provides access to the header, mappings, images, and methods
/// for extracting symbols and other data.
public struct DyldCache: Sendable {
    /// The parsed cache header.
    public let header: DyldCacheHeader

    /// Basic mapping information.
    public let mappings: [MappingInfo]

    /// Extended mapping information with slide info.
    public let mappingsWithSlide: [MappingAndSlideInfo]

    /// Image information for all cached dylibs.
    public let images: [ImageInfo]

    /// TEXT info entries for cached dylibs (includes per-image UUIDs).
    public let imagesText: [ImageTextInfo]

    /// Subcache entries (for multi-file caches).
    public let subCaches: [SubCacheEntry]

    /// VM address resolver for this cache.
    public var addressResolver: VMAddressResolver {
        if !mappingsWithSlide.isEmpty {
            return VMAddressResolver(mappings: mappingsWithSlide)
        } else {
            return VMAddressResolver(basicMappings: mappings)
        }
    }

    /// Initialize with pre-parsed components.
    public init(
        header: DyldCacheHeader,
        mappings: [MappingInfo],
        mappingsWithSlide: [MappingAndSlideInfo],
        images: [ImageInfo],
        imagesText: [ImageTextInfo],
        subCaches: [SubCacheEntry]
    ) {
        self.header = header
        self.mappings = mappings
        self.mappingsWithSlide = mappingsWithSlide
        self.images = images
        self.imagesText = imagesText
        self.subCaches = subCaches
    }
}

// MARK: - Parsing

extension DyldCache {
    /// Parse a DyldCache from raw data.
    public init(data: Data) throws {
        self = try Self.parse(from: data)
    }

    /// Parse a DyldCache from an abstract byte source.
    public init(source: any DyldCacheByteSource) throws {
        self = try Self.parse(from: source)
    }

    /// Internal parsing helper.
    private static func parse(from data: Data) throws -> DyldCache {
        try data.withParserSpan { span in
            try DyldCache(parsing: &span, fullData: data)
        }
    }

    /// Internal parsing helper for random-access sources.
    private static func parse(from source: any DyldCacheByteSource) throws -> DyldCache {
        // Read a conservative header window (dyld cache headers are < 4 KiB).
        let headerWindow = min(source.size, 4096)
        let headerData = try source.read(offset: 0, length: headerWindow)

        let header: DyldCacheHeader = try headerData.withParserSpan { span in
            try DyldCacheHeader(parsing: &span)
        }

        func readTable(offset: UInt64, count: UInt64, entrySize: Int) throws -> Data {
            guard entrySize > 0 else { return Data() }
            guard let c = Int(exactly: count) else { throw DyldCacheError.invalidMachO("unreasonable table count") }
            guard c >= 0 else { throw DyldCacheError.invalidMachO("negative table count") }
            let byteCount = c * entrySize
            guard let off = Int(exactly: offset) else { throw DyldCacheError.invalidMachO("unreasonable table offset") }
            if byteCount == 0 { return Data() }
            if off < 0 || off >= source.size { throw DyldCacheError.offsetOutOfBounds(offset: offset, bufferSize: source.size) }
            if off + byteCount > source.size {
                throw DyldCacheError.rangeOutOfBounds(offset: offset, size: UInt64(byteCount), bufferSize: source.size)
            }
            return try source.read(offset: off, length: byteCount)
        }

        // Parse mappings.
        let mappingsData = try readTable(offset: UInt64(header.mappingOffset),
                                         count: UInt64(header.mappingCount),
                                         entrySize: MappingInfo.size)
        let mappings: [MappingInfo] = try mappingsData.withParserSpan { span in
            var out: [MappingInfo] = []
            out.reserveCapacity(Int(header.mappingCount))
            for _ in 0..<header.mappingCount {
                out.append(try MappingInfo(parsing: &span))
            }
            return out
        }

        // Parse mappings with slide info.
        let mappingsWithSlide: [MappingAndSlideInfo]
        if header.mappingWithSlideCount > 0 {
            let slideData = try readTable(offset: UInt64(header.mappingWithSlideOffset),
                                          count: UInt64(header.mappingWithSlideCount),
                                          entrySize: MappingAndSlideInfo.size)
            mappingsWithSlide = try slideData.withParserSpan { span in
                var out: [MappingAndSlideInfo] = []
                out.reserveCapacity(Int(header.mappingWithSlideCount))
                for _ in 0..<header.mappingWithSlideCount {
                    out.append(try MappingAndSlideInfo(parsing: &span))
                }
                return out
            }
        } else {
            mappingsWithSlide = []
        }

        // Parse images.
        let imagesData = try readTable(offset: UInt64(header.imagesOffset),
                                       count: UInt64(header.imagesCount),
                                       entrySize: ImageInfo.size)
        let images: [ImageInfo] = try imagesData.withParserSpan { span in
            var out: [ImageInfo] = []
            out.reserveCapacity(Int(header.imagesCount))
            for _ in 0..<header.imagesCount {
                out.append(try ImageInfo(parsing: &span))
            }
            return out
        }

        // Parse image TEXT info entries.
        let imagesText: [ImageTextInfo]
        if header.imagesTextCount > 0, header.imagesTextOffset > 0 {
            let textData = try readTable(offset: header.imagesTextOffset,
                                         count: header.imagesTextCount,
                                         entrySize: ImageTextInfo.size)
            imagesText = try textData.withParserSpan { span in
                var out: [ImageTextInfo] = []
                out.reserveCapacity(Int(exactly: header.imagesTextCount) ?? 0)
                for _ in 0..<header.imagesTextCount {
                    out.append(try ImageTextInfo(parsing: &span))
                }
                return out
            }
        } else {
            imagesText = []
        }

        // Parse subcache entries.
        let subCaches: [SubCacheEntry]
        if header.subCacheArrayCount > 0, header.subCacheArrayOffset > 0 {
            if header.mappingOffset >= 0x200 {
                let scData = try readTable(offset: UInt64(header.subCacheArrayOffset),
                                           count: UInt64(header.subCacheArrayCount),
                                           entrySize: SubCacheEntry.size)
                subCaches = try scData.withParserSpan { span in
                    var out: [SubCacheEntry] = []
                    out.reserveCapacity(Int(header.subCacheArrayCount))
                    for _ in 0..<header.subCacheArrayCount {
                        out.append(try SubCacheEntry(parsing: &span))
                    }
                    return out
                }
            } else {
                let scData = try readTable(offset: UInt64(header.subCacheArrayOffset),
                                           count: UInt64(header.subCacheArrayCount),
                                           entrySize: SubCacheEntryV1.size)
                subCaches = try scData.withParserSpan { span in
                    var out: [SubCacheEntry] = []
                    out.reserveCapacity(Int(header.subCacheArrayCount))
                    for idx in 0..<header.subCacheArrayCount {
                        let v1 = try SubCacheEntryV1(parsing: &span)
                        out.append(SubCacheEntry(uuid: v1.uuid, cacheVMOffset: v1.cacheVMOffset, fileSuffix: ".\(idx + 1)"))
                    }
                    return out
                }
            }
        } else {
            subCaches = []
        }

        return DyldCache(header: header,
                         mappings: mappings,
                         mappingsWithSlide: mappingsWithSlide,
                         images: images,
                         imagesText: imagesText,
                         subCaches: subCaches)
    }

    /// Parse a DyldCache from a file path.
    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DyldCacheError.fileReadError(path: path, underlying: error)
        }
        try self.init(data: data)
    }

    /// Parse a DyldCache from a ParserSpan with access to full data.
    internal init(parsing input: inout ParserSpan, fullData: Data) throws {
        // Parse header first to get offsets
        let header = try DyldCacheHeader(parsing: &input)
        self.header = header

        // Parse basic mappings using seeking
        var mappingSpan = try input.seeking(toAbsoluteOffset: Int(header.mappingOffset))
        var mappings: [MappingInfo] = []
        mappings.reserveCapacity(Int(header.mappingCount))
        for _ in 0..<header.mappingCount {
            mappings.append(try MappingInfo(parsing: &mappingSpan))
        }
        self.mappings = mappings

        // Parse extended mappings with slide info
        if header.mappingWithSlideCount > 0 {
            var slideSpan = try input.seeking(toAbsoluteOffset: Int(header.mappingWithSlideOffset))
            var mappingsWithSlide: [MappingAndSlideInfo] = []
            mappingsWithSlide.reserveCapacity(Int(header.mappingWithSlideCount))
            for _ in 0..<header.mappingWithSlideCount {
                mappingsWithSlide.append(try MappingAndSlideInfo(parsing: &slideSpan))
            }
            self.mappingsWithSlide = mappingsWithSlide
        } else {
            self.mappingsWithSlide = []
        }

        // Parse images
        var imageSpan = try input.seeking(toAbsoluteOffset: Int(header.imagesOffset))
        var images: [ImageInfo] = []
        images.reserveCapacity(Int(header.imagesCount))
        for _ in 0..<header.imagesCount {
            images.append(try ImageInfo(parsing: &imageSpan))
        }
        self.images = images

        // Parse image TEXT info entries (contains per-image UUIDs and unslid load addresses)
        if header.imagesTextCount > 0, header.imagesTextOffset > 0 {
            var textSpan = try input.seeking(toAbsoluteOffset: Int(header.imagesTextOffset))
            var texts: [ImageTextInfo] = []
            texts.reserveCapacity(Int(header.imagesTextCount))
            for _ in 0..<header.imagesTextCount {
                texts.append(try ImageTextInfo(parsing: &textSpan))
            }
            self.imagesText = texts
        } else {
            self.imagesText = []
        }

        // Parse subcache entries
        if header.subCacheArrayCount > 0, header.subCacheArrayOffset > 0 {
            var subCacheSpan = try input.seeking(toAbsoluteOffset: Int(header.subCacheArrayOffset))
            var subCaches: [SubCacheEntry] = []
            subCaches.reserveCapacity(Int(header.subCacheArrayCount))
            if header.mappingOffset >= 0x200 {
                for _ in 0..<header.subCacheArrayCount {
                    subCaches.append(try SubCacheEntry(parsing: &subCacheSpan))
                }
            } else {
                for idx in 0..<header.subCacheArrayCount {
                    let v1 = try SubCacheEntryV1(parsing: &subCacheSpan)
                    subCaches.append(SubCacheEntry(
                        uuid: v1.uuid,
                        cacheVMOffset: v1.cacheVMOffset,
                        fileSuffix: ".\(idx + 1)"
                    ))
                }
            }
            self.subCaches = subCaches
        } else {
            self.subCaches = []
        }
    }
}

// MARK: - High-Level API

extension DyldCache {
    /// Get the path string for an image at the given index.
    ///
    /// - Parameters:
    ///   - index: The image index.
    ///   - data: The cache data to read from.
    /// - Returns: The dylib path.
    public func imagePath(at index: Int, from data: Data) throws -> String {
        guard index >= 0 && index < images.count else {
            throw DyldCacheError.imageIndexOutOfBounds(index: index, max: images.count)
        }

        let image = images[index]
        let offset = Int(image.pathFileOffset)

        guard offset < data.count else {
            throw DyldCacheError.offsetOutOfBounds(offset: UInt64(offset), bufferSize: data.count)
        }

        return try data.withParserSpan { span in
            var pathSpan = try span.seeking(toAbsoluteOffset: offset)
            return try String(parsingNulTerminated: &pathSpan)
        }
    }

    /// Get the path string for an image at the given index from a byte source.
    public func imagePath(at index: Int, from source: any DyldCacheByteSource) throws -> String {
        guard index >= 0 && index < images.count else {
            throw DyldCacheError.imageIndexOutOfBounds(index: index, max: images.count)
        }

        let image = images[index]
        let offset = Int(image.pathFileOffset)
        guard offset >= 0, offset < source.size else {
            throw DyldCacheError.offsetOutOfBounds(offset: UInt64(offset), bufferSize: source.size)
        }
        return try source.readNulTerminatedString(offset: offset)
    }

    /// Get all image paths.
    ///
    /// - Parameter data: The cache data to read from.
    /// - Returns: Array of dylib paths.
    public func allImagePaths(from data: Data) throws -> [String] {
        var paths: [String] = []
        paths.reserveCapacity(images.count)
        for i in 0..<images.count {
            paths.append(try imagePath(at: i, from: data))
        }
        return paths
    }

    /// Get all image paths from a byte source.
    public func allImagePaths(from source: any DyldCacheByteSource) throws -> [String] {
        var paths: [String] = []
        paths.reserveCapacity(images.count)
        for i in 0..<images.count {
            paths.append(try imagePath(at: i, from: source))
        }
        return paths
    }

    /// Find an image by path.
    ///
    /// - Parameters:
    ///   - path: The dylib path to search for.
    ///   - data: The cache data to read from.
    /// - Returns: The image index and info, or nil if not found.
    public func findImage(byPath path: String, from data: Data) throws -> (index: Int, info: ImageInfo)? {
        for (index, image) in images.enumerated() {
            let imagePath = try self.imagePath(at: index, from: data)
            if imagePath == path {
                return (index, image)
            }
        }
        return nil
    }

    /// Find an image by path using a byte source.
    public func findImage(byPath path: String, from source: any DyldCacheByteSource) throws -> (index: Int, info: ImageInfo)? {
        for (index, image) in images.enumerated() {
            let imagePath = try self.imagePath(at: index, from: source)
            if imagePath == path {
                return (index, image)
            }
        }
        return nil
    }

    /// Read local symbols info from the cache.
    ///
    /// - Parameter data: The cache data (or separate .symbols file data).
    /// - Returns: The local symbols info, or nil if not present.
    public func localSymbolsInfo(from data: Data) throws -> LocalSymbolsInfo? {
        guard header.localSymbolsSize > 0 else { return nil }

        let offset = Int(header.localSymbolsOffset)
        guard offset < data.count else {
            throw DyldCacheError.offsetOutOfBounds(offset: UInt64(offset), bufferSize: data.count)
        }

        return try data.withParserSpan { span in
            var infoSpan = try span.seeking(toAbsoluteOffset: offset)
            return try LocalSymbolsInfo(parsing: &infoSpan)
        }
    }

    /// Get slide info for a mapping.
    ///
    /// - Parameters:
    ///   - mapping: The mapping to get slide info for.
    ///   - data: The cache data to read from.
    /// - Returns: The parsed slide info, or nil if the mapping has no slide info.
    public func slideInfo(for mapping: MappingAndSlideInfo, from data: Data) throws -> (any SlideInfo)? {
        guard mapping.hasSlideInfo else { return nil }

        let offset = Int(mapping.slideInfoFileOffset)
        let size = Int(mapping.slideInfoFileSize)

        guard offset + size <= data.count else {
            throw DyldCacheError.rangeOutOfBounds(
                offset: UInt64(offset),
                size: UInt64(size),
                bufferSize: data.count
            )
        }

        // Zero-copy: parse directly via seeking without subdata() copy
        return try parseSlideInfoFromOffset(data, at: offset)
    }

    /// Get TEXT info for an image index, if available.
    public func imageTextInfo(at index: Int) -> ImageTextInfo? {
        guard index >= 0, index < imagesText.count else { return nil }
        return imagesText[index]
    }

    /// Get the UUID for an image index, if available.
    public func imageUUID(at index: Int) -> UUID? {
        imageTextInfo(at: index)?.uuid
    }

    /// Read local symbols info from the cache using a byte source.
    public func localSymbolsInfo(from source: any DyldCacheByteSource) throws -> LocalSymbolsInfo? {
        guard header.localSymbolsSize > 0 else { return nil }
        let offset = Int(header.localSymbolsOffset)
        guard offset >= 0, offset < source.size else {
            throw DyldCacheError.offsetOutOfBounds(offset: header.localSymbolsOffset, bufferSize: source.size)
        }
        if offset + LocalSymbolsInfo.size > source.size {
            throw DyldCacheError.rangeOutOfBounds(offset: header.localSymbolsOffset, size: UInt64(LocalSymbolsInfo.size), bufferSize: source.size)
        }
        let bytes = try source.read(offset: offset, length: LocalSymbolsInfo.size)
        return try bytes.withParserSpan { span in
            try LocalSymbolsInfo(parsing: &span)
        }
    }
}

// MARK: - Symbol Access

extension DyldCache {
    /// A resolved symbol with its name and nlist entry.
    public struct ResolvedSymbol: Sendable {
        public let name: String
        public let nlist: NList64
        public let imageIndex: Int

        public init(name: String, nlist: NList64, imageIndex: Int) {
            self.name = name
            self.nlist = nlist
            self.imageIndex = imageIndex
        }

        /// The symbol address.
        public var address: UInt64 { nlist.value }

        /// Whether this is a local (non-external) symbol.
        public var isLocal: Bool { nlist.isLocal }

        /// Whether this is a global export.
        public var isGlobal: Bool { nlist.isGlobalExport }
    }

    /// Shared local-symbols data that can be reused across many image lookups.
    ///
    /// The dyld local symbols format uses a single, global strings pool for all images in the cache.
    /// When the backing storage is compressed (e.g. APFS restore images), repeatedly reading and
    /// decompressing that pool per-image is extremely expensive.
    public struct LocalSymbolsSharedContext: @unchecked Sendable {
        public let info: LocalSymbolsInfo
        public let baseOffset: Int
        public let entriesOffset: Int
        public let nlistOffset: Int
        public let stringPool: LazyStringPool

        public init(info: LocalSymbolsInfo, baseOffset: Int, entriesOffset: Int, nlistOffset: Int, stringPool: LazyStringPool) {
            self.info = info
            self.baseOffset = baseOffset
            self.entriesOffset = entriesOffset
            self.nlistOffset = nlistOffset
            self.stringPool = stringPool
        }
    }

    /// Creates a shared context for accessing local symbols with lazy string pool loading.
    public func makeLocalSymbolsSharedContext(from symbolsSource: any DyldCacheByteSource) throws -> LocalSymbolsSharedContext? {
        guard let info = try localSymbolsInfo(from: symbolsSource) else { return nil }

        let baseOffset = Int(header.localSymbolsOffset)
        let entriesOffset = baseOffset + Int(info.entriesOffset)
        let nlistOffset = baseOffset + Int(info.nlistOffset)

        let stringsOffset = baseOffset + Int(info.stringsOffset)
        let stringsByteCount = Int(info.stringsSize)
        if stringsOffset < 0 || stringsOffset + stringsByteCount > symbolsSource.size {
            throw DyldCacheError.rangeOutOfBounds(
                offset: UInt64(stringsOffset),
                size: UInt64(stringsByteCount),
                bufferSize: symbolsSource.size
            )
        }

        let stringPool = try LazyStringPool(
            source: symbolsSource,
            baseOffset: stringsOffset,
            totalSize: stringsByteCount
        )

        return LocalSymbolsSharedContext(
            info: info,
            baseOffset: baseOffset,
            entriesOffset: entriesOffset,
            nlistOffset: nlistOffset,
            stringPool: stringPool
        )
    }

    /// Get local symbols for a specific image by index.
    ///
    /// The local symbols entries are parallel to the main cache's images array,
    /// meaning entry 0 corresponds to image 0, entry 1 to image 1, etc.
    ///
    /// - Parameters:
    ///   - index: The image index (0-based).
    ///   - symbolsData: The symbols data (either from .symbols file or main cache).
    ///   - is64BitEntries: Whether to use 64-bit local symbol entries.
    /// - Returns: Array of resolved symbols for the image.
    public func localSymbols(
        forImageAt index: Int,
        from symbolsData: Data,
        is64BitEntries: Bool = true
    ) throws -> [ResolvedSymbol] {
        guard let info = try localSymbolsInfo(from: symbolsData) else {
            return []
        }

        guard index >= 0 && index < Int(info.entriesCount) else {
            throw DyldCacheError.imageIndexOutOfBounds(index: index, max: Int(info.entriesCount))
        }

        let baseOffset = Int(header.localSymbolsOffset)
        let entriesOffset = baseOffset + Int(info.entriesOffset)

        // Read the entry at the specified index
        let entrySize = is64BitEntries ? LocalSymbolsEntry64.size : LocalSymbolsEntry32.size
        let entryOffset = entriesOffset + index * entrySize

        let entry: LocalSymbolsEntry = try symbolsData.withParserSpan { span in
            var entrySpan = try span.seeking(toAbsoluteOffset: entryOffset)
            if is64BitEntries {
                return LocalSymbolsEntry(try LocalSymbolsEntry64(parsing: &entrySpan))
            } else {
                return LocalSymbolsEntry(try LocalSymbolsEntry32(parsing: &entrySpan))
            }
        }

        // Read the nlist entries and resolve names
        let nlistOffset = baseOffset + Int(info.nlistOffset) + Int(entry.nlistStartIndex) * NList64.size
        let stringsOffset = baseOffset + Int(info.stringsOffset)

        var symbols: [ResolvedSymbol] = []
        symbols.reserveCapacity(Int(entry.nlistCount))

        try symbolsData.withParserSpan { span in
            var nlistSpan = try span.seeking(toAbsoluteOffset: nlistOffset)

            for _ in 0..<entry.nlistCount {
                let nlist = try NList64(parsing: &nlistSpan)

                // Read symbol name
                let nameOffset = stringsOffset + Int(nlist.stringIndex)
                guard nameOffset < symbolsData.count else { continue }

                var nameSpan = try span.seeking(toAbsoluteOffset: nameOffset)
                let name = (try? String(parsingNulTerminated: &nameSpan)) ?? ""

                symbols.append(ResolvedSymbol(
                    name: name,
                    nlist: nlist,
                    imageIndex: index
                ))
            }
        }

        return symbols
    }

    /// Get local symbols for a specific image by index from a byte source.
    public func localSymbols(
        forImageAt index: Int,
        from symbolsSource: any DyldCacheByteSource,
        is64BitEntries: Bool = true
    ) throws -> [ResolvedSymbol] {
        guard let shared = try makeLocalSymbolsSharedContext(from: symbolsSource) else { return [] }
        return try localSymbols(forImageAt: index, from: symbolsSource, sharedContext: shared, is64BitEntries: is64BitEntries)
    }

    /// Get local symbols for a specific image by index using a shared context.
    public func localSymbols(
        forImageAt index: Int,
        from symbolsSource: any DyldCacheByteSource,
        sharedContext: LocalSymbolsSharedContext,
        is64BitEntries: Bool = true
    ) throws -> [ResolvedSymbol] {
        let info = sharedContext.info
        guard index >= 0 && index < Int(info.entriesCount) else {
            throw DyldCacheError.imageIndexOutOfBounds(index: index, max: Int(info.entriesCount))
        }

        let entrySize = is64BitEntries ? LocalSymbolsEntry64.size : LocalSymbolsEntry32.size
        let entryOffset = sharedContext.entriesOffset + index * entrySize

        if entryOffset < 0 || entryOffset + entrySize > symbolsSource.size {
            throw DyldCacheError.rangeOutOfBounds(offset: UInt64(entryOffset), size: UInt64(entrySize), bufferSize: symbolsSource.size)
        }

        let entryBytes = try symbolsSource.read(offset: entryOffset, length: entrySize)
        let entry: LocalSymbolsEntry = try entryBytes.withParserSpan { span in
            if is64BitEntries {
                return LocalSymbolsEntry(try LocalSymbolsEntry64(parsing: &span))
            } else {
                return LocalSymbolsEntry(try LocalSymbolsEntry32(parsing: &span))
            }
        }

        let nlistOffset = sharedContext.nlistOffset + Int(entry.nlistStartIndex) * NList64.size
        let nlistByteCount = Int(entry.nlistCount) * NList64.size
        if nlistOffset < 0 || nlistOffset + nlistByteCount > symbolsSource.size {
            throw DyldCacheError.rangeOutOfBounds(offset: UInt64(nlistOffset), size: UInt64(nlistByteCount), bufferSize: symbolsSource.size)
        }

        let nlistBytes = try symbolsSource.read(offset: nlistOffset, length: nlistByteCount)
        let stringPool = sharedContext.stringPool

        return try nlistBytes.withParserSpan { span in
            var symbols: [ResolvedSymbol] = []
            symbols.reserveCapacity(Int(entry.nlistCount))

            for _ in 0..<entry.nlistCount {
                let nlist = try NList64(parsing: &span)
                let name = stringPool.string(at: Int(nlist.stringIndex))
                if name.isEmpty { continue }
                symbols.append(ResolvedSymbol(name: name, nlist: nlist, imageIndex: index))
            }

            return symbols
        }
    }

    /// Get all local symbols entries from the symbols data.
    ///
    /// - Parameters:
    ///   - symbolsData: The symbols data (either from .symbols file or main cache).
    ///   - is64BitEntries: Whether to use 64-bit local symbol entries.
    /// - Returns: Array of all local symbols entries.
    public func allLocalSymbolsEntries(
        from symbolsData: Data,
        is64BitEntries: Bool = true
    ) throws -> [LocalSymbolsEntry] {
        guard let info = try localSymbolsInfo(from: symbolsData) else {
            return []
        }

        let baseOffset = Int(header.localSymbolsOffset)
        let entriesOffset = baseOffset + Int(info.entriesOffset)

        var entries: [LocalSymbolsEntry] = []
        entries.reserveCapacity(Int(info.entriesCount))

        try symbolsData.withParserSpan { span in
            var entriesSpan = try span.seeking(toAbsoluteOffset: entriesOffset)

            for _ in 0..<info.entriesCount {
                if is64BitEntries {
                    entries.append(LocalSymbolsEntry(try LocalSymbolsEntry64(parsing: &entriesSpan)))
                } else {
                    entries.append(LocalSymbolsEntry(try LocalSymbolsEntry32(parsing: &entriesSpan)))
                }
            }
        }

        return entries
    }

    /// Get all local symbols entries from a byte source.
    public func allLocalSymbolsEntries(
        from symbolsSource: any DyldCacheByteSource,
        is64BitEntries: Bool = true
    ) throws -> [LocalSymbolsEntry] {
        guard let info = try localSymbolsInfo(from: symbolsSource) else {
            return []
        }

        let baseOffset = Int(header.localSymbolsOffset)
        let entriesOffset = baseOffset + Int(info.entriesOffset)

        let entrySize = is64BitEntries ? LocalSymbolsEntry64.size : LocalSymbolsEntry32.size
        guard let count = Int(exactly: info.entriesCount) else { return [] }
        let byteCount = count * entrySize

        if entriesOffset < 0 || entriesOffset + byteCount > symbolsSource.size {
            throw DyldCacheError.rangeOutOfBounds(offset: UInt64(entriesOffset), size: UInt64(byteCount), bufferSize: symbolsSource.size)
        }

        let bytes = try symbolsSource.read(offset: entriesOffset, length: byteCount)
        return try bytes.withParserSpan { span in
            var out: [LocalSymbolsEntry] = []
            out.reserveCapacity(count)
            for _ in 0..<info.entriesCount {
                if is64BitEntries {
                    out.append(LocalSymbolsEntry(try LocalSymbolsEntry64(parsing: &span)))
                } else {
                    out.append(LocalSymbolsEntry(try LocalSymbolsEntry32(parsing: &span)))
                }
            }
            return out
        }
    }

    /// Enumerate local symbols for a specific dylib by file offset.
    ///
    /// - Note: Consider using `localSymbols(forImageAt:from:)` instead, which
    ///   uses the image index directly and is more reliable.
    ///
    /// - Parameters:
    ///   - dylibOffset: The file offset of the dylib in the cache.
    ///   - data: The cache data (or separate .symbols file data).
    ///   - is64BitEntries: Whether to use 64-bit local symbol entries.
    /// - Returns: Array of resolved symbols.
    @available(*, deprecated, message: "Use localSymbols(forImageAt:from:) instead")
    public func localSymbols(
        forDylibOffset dylibOffset: UInt64,
        from data: Data,
        is64BitEntries: Bool = true
    ) throws -> [ResolvedSymbol] {
        guard let info = try localSymbolsInfo(from: data) else {
            return []
        }

        let baseOffset = Int(header.localSymbolsOffset)

        // Find the entry for this dylib
        let entriesOffset = baseOffset + Int(info.entriesOffset)
        var entry: LocalSymbolsEntry?
        var foundIndex = 0

        try data.withParserSpan { span in
            var entriesSpan = try span.seeking(toAbsoluteOffset: entriesOffset)

            for i in 0..<info.entriesCount {
                if is64BitEntries {
                    let e64 = try LocalSymbolsEntry64(parsing: &entriesSpan)
                    if e64.dylibOffset == dylibOffset {
                        entry = LocalSymbolsEntry(e64)
                        foundIndex = Int(i)
                        break
                    }
                } else {
                    let e32 = try LocalSymbolsEntry32(parsing: &entriesSpan)
                    if UInt64(e32.dylibOffset) == dylibOffset {
                        entry = LocalSymbolsEntry(e32)
                        foundIndex = Int(i)
                        break
                    }
                }
            }
        }

        guard let foundEntry = entry else {
            return []
        }

        // Read the nlist entries and resolve names
        let nlistOffset = baseOffset + Int(info.nlistOffset) + Int(foundEntry.nlistStartIndex) * NList64.size
        let stringsOffset = baseOffset + Int(info.stringsOffset)

        var symbols: [ResolvedSymbol] = []
        symbols.reserveCapacity(Int(foundEntry.nlistCount))

        try data.withParserSpan { span in
            var nlistSpan = try span.seeking(toAbsoluteOffset: nlistOffset)

            for _ in 0..<foundEntry.nlistCount {
                let nlist = try NList64(parsing: &nlistSpan)

                // Read symbol name
                let nameOffset = stringsOffset + Int(nlist.stringIndex)
                guard nameOffset < data.count else { continue }

                var nameSpan = try span.seeking(toAbsoluteOffset: nameOffset)
                let name = (try? String(parsingNulTerminated: &nameSpan)) ?? ""

                symbols.append(ResolvedSymbol(
                    name: name,
                    nlist: nlist,
                    imageIndex: foundIndex
                ))
            }
        }

        return symbols
    }
}

// MARK: - Description

extension DyldCache: CustomStringConvertible {
    public var description: String {
        """
        DyldCache(
            architecture: \(header.architecture),
            uuid: \(header.uuid),
            platform: \(header.platform),
            mappings: \(mappings.count),
            images: \(images.count),
            imagesText: \(imagesText.count),
            subCaches: \(subCaches.count)
        )
        """
    }
}
