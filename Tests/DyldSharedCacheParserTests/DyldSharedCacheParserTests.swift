import Testing
import Foundation
@testable import DyldSharedCacheParser

@Suite("Architecture Tests")
struct ArchitectureTests {
    @Test("Parse arm64 magic")
    func testArm64Magic() {
        let arch = CacheArchitecture(magic: "dyld_v1   arm64")
        #expect(arch == .arm64)
        #expect(arch?.is64Bit == true)
        #expect(arch?.pointerSize == 8)
    }

    @Test("Parse arm64e magic")
    func testArm64eMagic() {
        let arch = CacheArchitecture(magic: "dyld_v1  arm64e")
        #expect(arch == .arm64e)
        #expect(arch?.usesPointerAuthentication == true)
    }

    @Test("Parse x86_64 magic")
    func testX8664Magic() {
        let arch = CacheArchitecture(magic: "dyld_v1  x86_64")
        #expect(arch == .x86_64)
        #expect(arch?.is64Bit == true)
    }

    @Test("Parse i386 magic")
    func testI386Magic() {
        let arch = CacheArchitecture(magic: "dyld_v1    i386")
        #expect(arch == .i386)
        #expect(arch?.is64Bit == false)
        #expect(arch?.pointerSize == 4)
    }

    @Test("Invalid magic returns nil")
    func testInvalidMagic() {
        let arch = CacheArchitecture(magic: "not a valid magic")
        #expect(arch == nil)
    }
}

@Suite("Cache Header Tests")
struct CacheHeaderTests {
    @Test("Header flags decode")
    func testHeaderFlags() throws {
        var raw: UInt32 = 0x7F
        raw |= UInt32(1 << 8)
        raw |= UInt32(1 << 9)
        raw |= UInt32(1 << 10)
        raw |= UInt32(1 << 11)
        raw |= UInt32(1 << 12)
        let data = makeTestHeaderData(flagsRaw: raw)
        let header = try data.withParserSpan { span in
            try DyldCacheHeader(parsing: &span)
        }

        #expect(header.flags.formatVersion == 0x7F)
        #expect(header.flags.dylibsExpectedOnDisk == true)
        #expect(header.flags.simulator == true)
        #expect(header.flags.locallyBuiltCache == true)
        #expect(header.flags.builtFromChainedFixups == true)
        #expect(header.flags.newFormatTLVs == true)
    }

    @Test("Cache type and platform parsing")
    func testCacheTypeAndPlatform() throws {
        let data = makeTestHeaderData(
            platformRaw: CachePlatform.iOS.rawValue,
            cacheTypeRaw: CacheType.production.rawValue
        )
        let header = try data.withParserSpan { span in
            try DyldCacheHeader(parsing: &span)
        }

        #expect(header.cacheType == CacheType.production)
        #expect(header.platform == CachePlatform.iOS)
    }

    @Test("Unknown platform defaults to .unknown")
    func testUnknownPlatform() throws {
        let data = makeTestHeaderData(platformRaw: 99)
        let header = try data.withParserSpan { span in
            try DyldCacheHeader(parsing: &span)
        }

        #expect(header.platform == .unknown)
    }

    @Test("Unknown cache type defaults to .development")
    func testUnknownCacheType() throws {
        let data = makeTestHeaderData(cacheTypeRaw: 99)
        let header = try data.withParserSpan { span in
            try DyldCacheHeader(parsing: &span)
        }

        #expect(header.cacheType == .development)
    }
}

@Suite("VM Protection Tests")
struct VMProtectionTests {
    @Test("Protection flags description")
    func testProtectionDescription() {
        let rwx: VMProtection = [.read, .write, .execute]
        #expect(rwx.description == "rwx")

        let rx: VMProtection = [.read, .execute]
        #expect(rx.description == "r-x")

        let rw: VMProtection = [.read, .write]
        #expect(rw.description == "rw-")

        let none: VMProtection = []
        #expect(none.description == "---")
    }
}

@Suite("Export Flags Tests")
struct ExportFlagsTests {
    @Test("Regular export kind")
    func testRegularKind() {
        let flags = ExportFlags(rawValue: 0)
        #expect(flags.kind == .regular)
        #expect(flags.isWeakDefinition == false)
        #expect(flags.isReExport == false)
    }

    @Test("Thread local export kind")
    func testThreadLocalKind() {
        let flags = ExportFlags(rawValue: 1)
        #expect(flags.kind == .threadLocal)
        #expect(flags.isThreadLocal == true)
    }

    @Test("Absolute export kind")
    func testAbsoluteKind() {
        let flags = ExportFlags(rawValue: 2)
        #expect(flags.kind == .absolute)
        #expect(flags.isAbsolute == true)
    }

    @Test("Weak definition flag")
    func testWeakDefinition() {
        let flags = ExportFlags(rawValue: 0x04)
        #expect(flags.isWeakDefinition == true)
    }

    @Test("Re-export flag")
    func testReExport() {
        let flags = ExportFlags(rawValue: 0x08)
        #expect(flags.isReExport == true)
    }

    @Test("Stub and resolver flag")
    func testStubAndResolver() {
        let flags = ExportFlags(rawValue: 0x10)
        #expect(flags.isStubAndResolver == true)
    }
}

@Suite("NList64 Tests")
struct NList64Tests {
    @Test("Symbol type detection")
    func testSymbolType() {
        // External symbol defined in section
        let externalDefined = SymbolType(rawValue: 0x0F) // N_EXT | N_SECT
        #expect(externalDefined.isExternal == true)
        #expect(externalDefined.isDefinedInSection == true)

        // Local symbol
        let local = SymbolType(rawValue: 0x0E) // N_SECT only
        #expect(local.isExternal == false)
        #expect(local.isDefinedInSection == true)

        // Undefined external
        let undefined = SymbolType(rawValue: 0x01) // N_EXT only
        #expect(undefined.isExternal == true)
        #expect(undefined.isUndefined == true)
    }

    @Test("Symbol description flags")
    func testSymbolDesc() {
        let weak = SymbolDesc(rawValue: 0x0080)
        #expect(weak.isWeakDefinition == true)

        let weakRef = SymbolDesc(rawValue: 0x0040)
        #expect(weakRef.isWeakReference == true)

        // Library ordinal in high byte
        let withOrdinal = SymbolDesc(rawValue: 0x0200)
        #expect(withOrdinal.libraryOrdinal == 2)
    }
}

@Suite("Export Trie Tests")
struct ExportTrieTests {
    @Test("Empty trie")
    func testEmptyTrie() throws {
        let trie = ExportTrie(data: Data())
        #expect(trie.isEmpty == true)

        let symbols = try trie.allSymbols()
        #expect(symbols.isEmpty == true)
    }

    @Test("Simple trie with one symbol")
    func testSimpleTrie() throws {
        // Build a minimal export trie with one symbol "_main"
        // Root node (2 bytes) + edge label "_main\0" (6 bytes) + offset (1 byte) = 9 bytes
        // Child node starts at offset 9

        var trieData = Data()

        // Root node: terminal size = 0 (not terminal), 1 child
        trieData.append(0x00) // terminal size = 0
        trieData.append(0x01) // 1 child

        // Child edge: "_main\0" + offset to child node
        trieData.append(contentsOf: "_main".utf8) // 5 bytes
        trieData.append(0x00) // null terminator
        trieData.append(0x09) // offset to child node (at byte 9)

        // Child node at offset 9: terminal with symbol info
        trieData.append(0x02) // terminal size = 2 bytes
        trieData.append(0x00) // flags = regular export
        trieData.append(0x10) // offset = 0x10
        trieData.append(0x00) // 0 children

        let trie = ExportTrie(data: trieData)
        let symbols = try trie.allSymbols()

        #expect(symbols.count == 1)
        #expect(symbols[0].name == "_main")
        #expect(symbols[0].flags.kind == .regular)
        #expect(symbols[0].offset == 0x10)
    }

    @Test("Lookup symbol")
    func testLookupSymbol() throws {
        var trieData = Data()

        // Root node: not terminal, 1 child
        trieData.append(0x00)
        trieData.append(0x01)

        // Child: "_test\0" + offset (terminal node is at byte 9)
        trieData.append(contentsOf: "_test".utf8)
        trieData.append(0x00)
        trieData.append(0x09)

        // Terminal node
        trieData.append(0x02) // terminal size
        trieData.append(0x00) // flags
        trieData.append(0x20) // offset
        trieData.append(0x00) // no children

        let trie = ExportTrie(data: trieData)

        let found = try trie.lookup("_test")
        #expect(found != nil)
        #expect(found?.name == "_test")
        #expect(found?.offset == 0x20)

        let notFound = try trie.lookup("_missing")
        #expect(notFound == nil)
    }

    @Test("Re-export terminal info")
    func testReExportTerminalInfo() throws {
        var terminal = Data()
        terminal.append(0x08) // re-export flag
        terminal.append(0x02) // ordinal
        terminal.append(contentsOf: "_imported".utf8)
        terminal.append(0x00)

        let trieData = makeSingleSymbolExportTrie(symbol: "_reexp", terminalInfo: terminal)
        let trie = ExportTrie(data: trieData)

        let symbols = try trie.allSymbols()
        #expect(symbols.count == 1)
        let symbol = symbols[0]
        #expect(symbol.isReExport == true)
        #expect(symbol.reExportDylibOrdinal == 2)
        #expect(symbol.importedName == "_imported")
        #expect(symbol.offset == nil)
    }

    @Test("Stub and resolver terminal info")
    func testStubAndResolverTerminalInfo() throws {
        var terminal = Data()
        terminal.append(0x10) // stub and resolver flag
        terminal.append(0x20) // stub offset
        terminal.append(0x30) // resolver offset

        let trieData = makeSingleSymbolExportTrie(symbol: "_stub", terminalInfo: terminal)
        let trie = ExportTrie(data: trieData)

        let symbols = try trie.allSymbols()
        #expect(symbols.count == 1)
        let symbol = symbols[0]
        #expect(symbol.hasResolver == true)
        #expect(symbol.offset == 0x20)
        #expect(symbol.resolverOffset == 0x30)
    }

    @Test("Best-effort enumeration tolerates malformed labels")
    func testBestEffortEnumerationMalformedLabel() throws {
        // Root node: terminal size = 0, 1 child.
        var trieData = Data([0x00, 0x01])

        // Child edge label without NUL terminator, exceeding the maximum allowed length.
        trieData.append(contentsOf: Array(repeating: UInt8(ascii: "a"), count: 4097))

        let trie = ExportTrie(data: trieData)
        #expect(throws: DyldCacheError.self) {
            _ = try trie.allSymbols()
        }

        let bestEffort = trie.allSymbolsBestEffort()
        #expect(bestEffort.isEmpty == true)
    }
}

@Suite("Mach-O Exports Trie Locator Tests")
struct MachOExportsTrieLocatorTests {
    @Test("Locate exports trie via LC_DYLD_EXPORTS_TRIE")
    func testLocateViaExportsTrieCommand() throws {
        var data = Data()

        // mach_header_64
        data.append(contentsOf: u32(0xfeedfacf)) // magic
        data.append(contentsOf: u32(0x0100000c)) // cputype (arm64)
        data.append(contentsOf: u32(0)) // cpusubtype
        data.append(contentsOf: u32(0x2)) // filetype (MH_EXECUTE)
        data.append(contentsOf: u32(2)) // ncmds
        data.append(contentsOf: u32(72 + 16)) // sizeofcmds
        data.append(contentsOf: u32(0)) // flags
        data.append(contentsOf: u32(0)) // reserved

        // LC_SEGMENT_64 (__LINKEDIT)
        data.append(contentsOf: u32(0x19)) // cmd
        data.append(contentsOf: u32(72)) // cmdsize
        data.append(contentsOf: fixedCString16("__LINKEDIT"))
        data.append(contentsOf: u64(0x1000)) // vmaddr
        data.append(contentsOf: u64(0x1000)) // vmsize
        data.append(contentsOf: u64(0x200)) // fileoff
        data.append(contentsOf: u64(0x1000)) // filesize
        data.append(contentsOf: u32(0)) // maxprot
        data.append(contentsOf: u32(0)) // initprot
        data.append(contentsOf: u32(0)) // nsects
        data.append(contentsOf: u32(0)) // flags

        // LC_DYLD_EXPORTS_TRIE
        data.append(contentsOf: u32(0x80000033))
        data.append(contentsOf: u32(16))
        data.append(contentsOf: u32(0x300)) // dataoff
        data.append(contentsOf: u32(0x40)) // datasize

        let loc = try MachOExportTrieLocator.locate(in: data)
        #expect(loc != nil)
        #expect(loc?.vmAddress == 0x1100) // 0x1000 + 0x300 - 0x200
        #expect(loc?.size == 0x40)
    }

    @Test("Locate exports trie via LC_DYLD_INFO_ONLY")
    func testLocateViaDyldInfoOnlyCommand() throws {
        var data = Data()

        // mach_header_64
        data.append(contentsOf: u32(0xfeedfacf))
        data.append(contentsOf: u32(0x01000007)) // cputype (x86_64)
        data.append(contentsOf: u32(0))
        data.append(contentsOf: u32(0x2))
        data.append(contentsOf: u32(2))
        data.append(contentsOf: u32(72 + 48))
        data.append(contentsOf: u32(0))
        data.append(contentsOf: u32(0))

        // LC_SEGMENT_64 (__LINKEDIT)
        data.append(contentsOf: u32(0x19))
        data.append(contentsOf: u32(72))
        data.append(contentsOf: fixedCString16("__LINKEDIT"))
        data.append(contentsOf: u64(0x8000))
        data.append(contentsOf: u64(0x1000))
        data.append(contentsOf: u64(0x1000))
        data.append(contentsOf: u64(0x1000))
        data.append(contentsOf: u32(0))
        data.append(contentsOf: u32(0))
        data.append(contentsOf: u32(0))
        data.append(contentsOf: u32(0))

        // LC_DYLD_INFO_ONLY
        data.append(contentsOf: u32(0x80000022))
        data.append(contentsOf: u32(48))
        // rebase/bind/weak/lazy pairs
        for _ in 0..<8 { data.append(contentsOf: u32(0)) }
        data.append(contentsOf: u32(0x1200)) // export_off
        data.append(contentsOf: u32(0x20)) // export_size

        let loc = try MachOExportTrieLocator.locate(in: data)
        #expect(loc != nil)
        #expect(loc?.vmAddress == 0x8200) // 0x8000 + 0x1200 - 0x1000
        #expect(loc?.size == 0x20)
    }
}

@Suite("MultiCacheReader Export Trie Tests")
struct MultiCacheReaderExportTrieTests {
    @Test("Exported symbols from a minimal export trie")
    func testExportedSymbolsFromTrie() throws {
        let fixture = makeExportTrieFixture()
        let exports = try fixture.reader.exportedSymbols(forImageAt: 0)

        #expect(exports.count == 1)
        #expect(exports[0].name == fixture.symbolName)
        #expect(exports[0].offset == fixture.symbolOffset)
    }

    @Test("Symbolication falls back to export trie")
    func testSymbolicationFallback() throws {
        let fixture = makeExportTrieFixture()
        let imageLoadAddress: UInt64 = 0x2000
        let pc: UInt64 = imageLoadAddress + fixture.symbolOffset + 0x5

        let result = try fixture.reader.lookup(
            pc: pc,
            imageUUID: fixture.imageUUID,
            imageLoadAddress: imageLoadAddress
        )

        #expect(result?.symbol == fixture.symbolName)
        #expect(result?.symbolOffset == fixture.symbolOffset)
        #expect(result?.addend == 0x5)
    }
}

@Suite("MultiCacheReader Subcache Tests")
struct MultiCacheReaderSubcacheTests {
    @Test("Read bytes across cache boundaries")
    func testReadBytesAcrossCaches() throws {
        let fixture = makeSubcacheReadFixture()
        let data = try fixture.reader.readBytes(vmAddress: 0x10F0, size: 0x30)

        #expect(data.count == 0x30)
        #expect(allBytesEqual(data.prefix(0x10), fixture.mainByte))
        #expect(allBytesEqual(data.suffix(0x20), fixture.subByte))
    }

    @Test("Read bytes from unmapped address throws")
    func testReadBytesUnmapped() {
        let fixture = makeSubcacheReadFixture()

        #expect(throws: DyldCacheError.self) {
            _ = try fixture.reader.readBytes(vmAddress: 0x5000, size: 1)
        }
    }
}

@Suite("MultiCacheReader Init Tests")
struct MultiCacheReaderInitTests {
    @Test("Missing subcache throws when required")
    func testMissingSubcacheRequired() {
        let mainUUID = UUID()
        let subUUID = UUID()
        let entry = makeSubCacheEntryData(uuid: subUUID, cacheVMOffset: 0, suffix: ".01")
        let mainData = makeCacheData(uuid: mainUUID, mappingOffset: 0x200, subCacheEntries: [entry])
        let mainPath = "/tmp/dyld_shared_cache_main"

        #expect(throws: DyldCacheError.self) {
            _ = try MultiCacheReader(
                mainCachePath: mainPath,
                open: { path in
                    if path == mainPath { return DataByteSource(mainData) }
                    return nil
                },
                requireAllSubCaches: true,
                requireSymbolsFile: false
            )
        }
    }

    @Test("Missing subcache allowed when not required")
    func testMissingSubcacheAllowed() throws {
        let mainUUID = UUID()
        let subUUID = UUID()
        let entry = makeSubCacheEntryData(uuid: subUUID, cacheVMOffset: 0, suffix: ".01")
        let mainData = makeCacheData(uuid: mainUUID, mappingOffset: 0x200, subCacheEntries: [entry])
        let mainPath = "/tmp/dyld_shared_cache_main"

        let reader = try MultiCacheReader(
            mainCachePath: mainPath,
            open: { path in
                if path == mainPath { return DataByteSource(mainData) }
                return nil
            },
            requireAllSubCaches: false,
            requireSymbolsFile: false
        )

        #expect(reader.subCaches.isEmpty == true)
    }

    @Test("Subcache UUID mismatch throws")
    func testSubcacheUUIDMismatch() {
        let mainUUID = UUID()
        let expectedSubUUID = UUID()
        let entry = makeSubCacheEntryData(uuid: expectedSubUUID, cacheVMOffset: 0, suffix: ".01")
        let mainData = makeCacheData(uuid: mainUUID, mappingOffset: 0x200, subCacheEntries: [entry])

        let actualSubUUID = UUID()
        let subData = makeCacheData(uuid: actualSubUUID)

        let mainPath = "/tmp/dyld_shared_cache_main"
        let subPath = mainPath + ".01"

        do {
            _ = try MultiCacheReader(
                mainCachePath: mainPath,
                open: { path in
                    switch path {
                    case mainPath:
                        return DataByteSource(mainData)
                    case subPath:
                        return DataByteSource(subData)
                    default:
                        return nil
                    }
                },
                requireAllSubCaches: true,
                requireSymbolsFile: false
            )
            Issue.record("Expected subcache UUID mismatch")
        } catch DyldCacheError.subCacheUUIDMismatch(let expected, let actual) {
            #expect(expected == expectedSubUUID)
            #expect(actual == actualSubUUID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Missing symbols file throws when required")
    func testMissingSymbolsFileRequired() {
        let mainUUID = UUID()
        let symbolsUUID = UUID()
        let mainData = makeCacheData(uuid: mainUUID, symbolFileUUID: symbolsUUID)
        let mainPath = "/tmp/dyld_shared_cache_main"

        #expect(throws: DyldCacheError.self) {
            _ = try MultiCacheReader(
                mainCachePath: mainPath,
                open: { path in
                    if path == mainPath { return DataByteSource(mainData) }
                    return nil
                },
                requireAllSubCaches: true,
                requireSymbolsFile: true
            )
        }
    }

    @Test("Symbols UUID mismatch throws")
    func testSymbolsUUIDMismatch() {
        let mainUUID = UUID()
        let expectedSymbolsUUID = UUID()
        let mainData = makeCacheData(uuid: mainUUID, symbolFileUUID: expectedSymbolsUUID)

        let actualSymbolsUUID = UUID()
        let symbolsData = makeCacheData(uuid: actualSymbolsUUID)

        let mainPath = "/tmp/dyld_shared_cache_main"
        let symbolsPath = mainPath + ".symbols"

        do {
            _ = try MultiCacheReader(
                mainCachePath: mainPath,
                open: { path in
                    switch path {
                    case mainPath:
                        return DataByteSource(mainData)
                    case symbolsPath:
                        return DataByteSource(symbolsData)
                    default:
                        return nil
                    }
                },
                requireAllSubCaches: true,
                requireSymbolsFile: false
            )
            Issue.record("Expected symbols UUID mismatch")
        } catch DyldCacheError.subCacheUUIDMismatch(let expected, let actual) {
            #expect(expected == expectedSymbolsUUID)
            #expect(actual == actualSymbolsUUID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite("SubCache Entry Tests")
struct SubCacheEntryTests {
    @Test("SubCacheEntryV1 parsing path")
    func testSubCacheEntryV1Parsing() throws {
        let mainUUID = UUID()
        let subUUID = UUID()
        let entry = makeSubCacheEntryV1Data(uuid: subUUID, cacheVMOffset: 0x1234)
        let data = makeCacheData(uuid: mainUUID, mappingOffset: 0x100, subCacheEntries: [entry])

        let cache = try DyldCache(data: data)
        #expect(cache.subCaches.count == 1)
        #expect(cache.subCaches[0].uuid == subUUID)
        #expect(cache.subCaches[0].cacheVMOffset == 0x1234)
        #expect(cache.subCaches[0].fileSuffix == ".1")
    }
}

@Suite("Image Path Tests")
struct ImagePathTests {
    @Test("Image paths from data and byte source")
    func testImagePathsFromDataAndSource() throws {
        let fixture = makeImagePathsFixture()
        let source = DataByteSource(fixture.data)

        #expect(try fixture.cache.imagePath(at: 0, from: fixture.data) == fixture.paths[0])
        #expect(try fixture.cache.imagePath(at: 1, from: source) == fixture.paths[1])
    }

    @Test("All image paths and find image")
    func testAllImagePathsAndFindImage() throws {
        let fixture = makeImagePathsFixture()
        let source = DataByteSource(fixture.data)

        let dataPaths = try fixture.cache.allImagePaths(from: fixture.data)
        let sourcePaths = try fixture.cache.allImagePaths(from: source)
        #expect(dataPaths == fixture.paths)
        #expect(sourcePaths == fixture.paths)

        let foundData = try fixture.cache.findImage(byPath: fixture.paths[1], from: fixture.data)
        let foundSource = try fixture.cache.findImage(byPath: fixture.paths[0], from: source)
        #expect(foundData?.index == 1)
        #expect(foundSource?.index == 0)
    }

    @Test("MultiCacheReader image APIs")
    func testMultiCacheReaderImageAPIs() throws {
        let fixture = makeImagePathsFixture()
        let reader = fixture.reader

        #expect(try reader.imagePath(at: 0) == fixture.paths[0])
        #expect(try reader.allImagePaths() == fixture.paths)

        let found = try reader.findImage(byPath: fixture.paths[1])
        #expect(found?.index == 1)

        #expect(reader.findImageIndex(byUUID: fixture.uuids[0]) == 0)
        #expect(reader.findImageIndex(byUUID: UUID()) == nil)
    }

    @Test("MultiCacheReader string at file offset")
    func testStringAtFileOffset() throws {
        let fixture = makeImagePathsFixture()
        let reader = fixture.reader
        let offset = Int(fixture.cache.images[0].pathFileOffset)

        #expect(try reader.string(atFileOffset: offset) == fixture.paths[0])
        #expect(try reader.string(atFileOffset: -1) == "")
        #expect(try reader.string(atFileOffset: fixture.data.count + 1) == "")
    }
}

@Suite("Local Symbols Tests")
struct LocalSymbolsTests {
    @Test("Resolve local symbols from main cache")
    func testLocalSymbolsFromMainCache() throws {
        let fixture = makeLocalSymbolsFixture()
        let symbols = try fixture.reader.localSymbols(forImageAt: 0)

        #expect(symbols.count == 1)
        guard let first = symbols.first else {
            Issue.record("Expected at least one local symbol")
            return
        }
        #expect(first.name == fixture.symbolName)
        #expect(first.address == fixture.symbolValue)
    }

    @Test("Resolve local symbols from data")
    func testLocalSymbolsFromData() throws {
        let fixture = makeLocalSymbolsFixture()
        let symbols = try fixture.cache.localSymbols(forImageAt: 0, from: fixture.data)

        #expect(symbols.count == 1)
        guard let first = symbols.first else {
            Issue.record("Expected at least one local symbol")
            return
        }
        #expect(first.name == fixture.symbolName)
        #expect(first.address == fixture.symbolValue)
    }

    @Test("Local symbols resolver uses shared context")
    func testLocalSymbolsResolver() throws {
        let fixture = makeLocalSymbolsFixture()
        let resolver = try fixture.reader.makeLocalSymbolsResolver()

        #expect(resolver != nil)
        let symbols = try resolver?.symbols(forImageAt: 0)
        #expect(symbols?.first?.name == fixture.symbolName)
    }

    @Test("Local symbols info and entries round-trip")
    func testLocalSymbolsInfoAndEntries() throws {
        let fixture = makeLocalSymbolsFixture()
        let info = try fixture.reader.localSymbolsInfo()
        let entries = try fixture.reader.allLocalSymbolsEntries()

        #expect(info?.entriesCount == 1)
        #expect(info?.nlistCount == 1)
        #expect(entries.count == 1)
        #expect(entries[0].nlistCount == 1)
    }
}

// MARK: - Helpers

private func u16(_ value: UInt16) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

private func u32(_ value: UInt32) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

private func u64(_ value: UInt64) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian, Array.init)
}

private func fixedCString16(_ string: String) -> [UInt8] {
    var bytes = Array(string.utf8.prefix(16))
    if bytes.count < 16 {
        bytes.append(contentsOf: repeatElement(0, count: 16 - bytes.count))
    }
    return bytes
}

private func appendUUID(_ uuid: UUID, to data: inout Data) {
    var raw = uuid.uuid
    withUnsafeBytes(of: &raw) { data.append(contentsOf: $0) }
}

private let nullUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

private func allBytesEqual(_ data: Data, _ value: UInt8) -> Bool {
    data.allSatisfy { $0 == value }
}

private struct ExportTrieFixture {
    let reader: MultiCacheReader
    let imageUUID: UUID
    let symbolName: String
    let symbolOffset: UInt64
}

private func makeSingleSymbolExportTrie(symbol: String, offset: UInt8) -> Data {
    var data = Data()
    data.append(0x00) // terminal size = 0
    data.append(0x01) // 1 child
    data.append(contentsOf: symbol.utf8)
    data.append(0x00) // null terminator
    let childOffset = 2 + symbol.utf8.count + 2
    data.append(UInt8(childOffset))
    data.append(0x02) // terminal size = 2 bytes
    data.append(0x00) // flags
    data.append(offset) // symbol offset
    data.append(0x00) // 0 children
    return data
}

private func makeSingleSymbolExportTrie(symbol: String, terminalInfo: Data) -> Data {
    var data = Data()
    data.append(0x00) // terminal size = 0
    data.append(0x01) // 1 child
    data.append(contentsOf: symbol.utf8)
    data.append(0x00) // null terminator
    let childOffset = 2 + symbol.utf8.count + 2
    data.append(UInt8(childOffset))
    data.append(UInt8(terminalInfo.count))
    data.append(terminalInfo)
    data.append(0x00) // 0 children
    return data
}

private func makeTestHeaderData(
    uuid: UUID = UUID(),
    localSymbolsOffset: UInt64 = 0,
    localSymbolsSize: UInt64 = 0,
    mappingCount: UInt32 = 0,
    imagesCount: UInt32 = 0,
    imagesTextCount: UInt64 = 0,
    mappingWithSlideCount: UInt32 = 0,
    mappingOffset: UInt32 = 0,
    subCacheArrayOffset: UInt32 = 0,
    subCacheArrayCount: UInt32 = 0,
    symbolFileUUID: UUID? = nil,
    platformRaw: UInt32 = 1,
    flagsRaw: UInt32 = 0,
    cacheTypeRaw: UInt64 = 0
) -> Data {
    var data = Data()
    var magicBytes = Array("dyld_v1   arm64".utf8)
    if magicBytes.count < 16 {
        magicBytes.append(contentsOf: repeatElement(0, count: 16 - magicBytes.count))
    }
    data.append(contentsOf: magicBytes.prefix(16))

    data.append(contentsOf: u32(mappingOffset)) // mappingOffset
    data.append(contentsOf: u32(mappingCount))
    data.append(contentsOf: u32(0)) // imagesOffsetOld
    data.append(contentsOf: u32(0)) // imagesCountOld
    data.append(contentsOf: u64(0)) // dyldBaseAddress
    data.append(contentsOf: u64(0)) // codeSignatureOffset
    data.append(contentsOf: u64(0)) // codeSignatureSize
    data.append(contentsOf: u64(0)) // slideInfoOffsetUnused
    data.append(contentsOf: u64(0)) // slideInfoSizeUnused
    data.append(contentsOf: u64(localSymbolsOffset))
    data.append(contentsOf: u64(localSymbolsSize))
    appendUUID(uuid, to: &data)
    data.append(contentsOf: u64(cacheTypeRaw)) // cacheType
    data.append(contentsOf: u32(0)) // branchPoolsOffset
    data.append(contentsOf: u32(0)) // branchPoolsCount
    data.append(contentsOf: u64(0)) // dyldInCacheMH
    data.append(contentsOf: u64(0)) // dyldInCacheEntry
    data.append(contentsOf: u64(0)) // imagesTextOffset
    data.append(contentsOf: u64(imagesTextCount))
    data.append(contentsOf: u64(0)) // patchInfoAddr
    data.append(contentsOf: u64(0)) // patchInfoSize
    data.append(contentsOf: u64(0)) // otherImageGroupUnused1
    data.append(contentsOf: u64(0)) // otherImageGroupUnused2
    data.append(contentsOf: u64(0)) // progClosuresAddr
    data.append(contentsOf: u64(0)) // progClosuresSize
    data.append(contentsOf: u64(0)) // progClosuresTrieAddr
    data.append(contentsOf: u64(0)) // progClosuresTrieSize
    data.append(contentsOf: u32(platformRaw)) // platformRaw
    data.append(contentsOf: u32(flagsRaw)) // flagsRaw
    data.append(contentsOf: u64(0)) // sharedRegionStart
    data.append(contentsOf: u64(0)) // sharedRegionSize
    data.append(contentsOf: u64(0)) // maxSlide
    data.append(contentsOf: u64(0)) // dylibsImageArrayAddr
    data.append(contentsOf: u64(0)) // dylibsImageArraySize
    data.append(contentsOf: u64(0)) // dylibsTrieAddr
    data.append(contentsOf: u64(0)) // dylibsTrieSize
    data.append(contentsOf: u64(0)) // otherImageArrayAddr
    data.append(contentsOf: u64(0)) // otherImageArraySize
    data.append(contentsOf: u64(0)) // otherTrieAddr
    data.append(contentsOf: u64(0)) // otherTrieSize
    data.append(contentsOf: u32(0)) // mappingWithSlideOffset
    data.append(contentsOf: u32(mappingWithSlideCount))
    data.append(contentsOf: u64(0)) // dylibsPBLStateArrayAddrUnused
    data.append(contentsOf: u64(0)) // dylibsPBLSetAddr
    data.append(contentsOf: u64(0)) // programsPBLSetPoolAddr
    data.append(contentsOf: u64(0)) // programsPBLSetPoolSize
    data.append(contentsOf: u64(0)) // programTrieAddr
    data.append(contentsOf: u32(0)) // programTrieSize
    data.append(contentsOf: u32(0)) // osVersion
    data.append(contentsOf: u32(0)) // altPlatform
    data.append(contentsOf: u32(0)) // altOsVersion
    data.append(contentsOf: u64(0)) // swiftOptsOffset
    data.append(contentsOf: u64(0)) // swiftOptsSize
    data.append(contentsOf: u32(subCacheArrayOffset)) // subCacheArrayOffset
    data.append(contentsOf: u32(subCacheArrayCount)) // subCacheArrayCount
    appendUUID(symbolFileUUID ?? nullUUID, to: &data)
    data.append(contentsOf: u64(0)) // rosettaReadOnlyAddr
    data.append(contentsOf: u64(0)) // rosettaReadOnlySize
    data.append(contentsOf: u64(0)) // rosettaReadWriteAddr
    data.append(contentsOf: u64(0)) // rosettaReadWriteSize
    data.append(contentsOf: u32(0)) // imagesOffset
    data.append(contentsOf: u32(imagesCount))
    data.append(contentsOf: u32(0)) // cacheSubType
    data.append(contentsOf: u64(0)) // objcOptsOffset
    data.append(contentsOf: u64(0)) // objcOptsSize
    data.append(contentsOf: u64(0)) // cacheAtlasOffset
    data.append(contentsOf: u64(0)) // cacheAtlasSize
    data.append(contentsOf: u64(0)) // dynamicDataOffset
    data.append(contentsOf: u64(0)) // dynamicDataMaxSize
    data.append(contentsOf: u32(0)) // tproMappingsOffset
    data.append(contentsOf: u32(0)) // tproMappingsCount

    return data
}

private func makeTestHeader(
    uuid: UUID = UUID(),
    localSymbolsOffset: UInt64 = 0,
    localSymbolsSize: UInt64 = 0,
    mappingCount: UInt32 = 0,
    imagesCount: UInt32 = 0,
    imagesTextCount: UInt64 = 0,
    mappingWithSlideCount: UInt32 = 0,
    mappingOffset: UInt32 = 0,
    subCacheArrayOffset: UInt32 = 0,
    subCacheArrayCount: UInt32 = 0,
    symbolFileUUID: UUID? = nil,
    platformRaw: UInt32 = 1,
    flagsRaw: UInt32 = 0,
    cacheTypeRaw: UInt64 = 0
) -> DyldCacheHeader {
    let data = makeTestHeaderData(
        uuid: uuid,
        localSymbolsOffset: localSymbolsOffset,
        localSymbolsSize: localSymbolsSize,
        mappingCount: mappingCount,
        imagesCount: imagesCount,
        imagesTextCount: imagesTextCount,
        mappingWithSlideCount: mappingWithSlideCount,
        mappingOffset: mappingOffset,
        subCacheArrayOffset: subCacheArrayOffset,
        subCacheArrayCount: subCacheArrayCount,
        symbolFileUUID: symbolFileUUID,
        platformRaw: platformRaw,
        flagsRaw: flagsRaw,
        cacheTypeRaw: cacheTypeRaw
    )
    return try! data.withParserSpan { span in
        try DyldCacheHeader(parsing: &span)
    }
}

private func makeSubCacheEntryData(uuid: UUID, cacheVMOffset: UInt64, suffix: String) -> Data {
    var data = Data()
    appendUUID(uuid, to: &data)
    data.append(contentsOf: u64(cacheVMOffset))
    var bytes = Array(suffix.utf8.prefix(32))
    if bytes.count < 32 {
        bytes.append(contentsOf: repeatElement(0, count: 32 - bytes.count))
    }
    data.append(contentsOf: bytes)
    return data
}

private func makeSubCacheEntryV1Data(uuid: UUID, cacheVMOffset: UInt64) -> Data {
    var data = Data()
    appendUUID(uuid, to: &data)
    data.append(contentsOf: u64(cacheVMOffset))
    return data
}

private func makeCacheData(
    uuid: UUID,
    mappingOffset: UInt32 = 0,
    subCacheEntries: [Data] = [],
    symbolFileUUID: UUID? = nil
) -> Data {
    let headerSize = makeTestHeaderData(
        uuid: uuid,
        mappingOffset: mappingOffset,
        symbolFileUUID: symbolFileUUID
    ).count
    let offset: UInt32 = subCacheEntries.isEmpty ? 0 : UInt32(max(0x200, headerSize))
    var data = makeTestHeaderData(
        uuid: uuid,
        mappingOffset: mappingOffset,
        subCacheArrayOffset: offset,
        subCacheArrayCount: UInt32(subCacheEntries.count),
        symbolFileUUID: symbolFileUUID
    )
    if offset > data.count {
        data.append(Data(repeating: 0, count: Int(offset) - data.count))
    }
    for entry in subCacheEntries {
        data.append(entry)
    }
    return data
}

private struct ImagePathsFixture {
    let cache: DyldCache
    let reader: MultiCacheReader
    let data: Data
    let paths: [String]
    let uuids: [UUID]
}

private func makeImagePathsFixture() -> ImagePathsFixture {
    let paths = ["/usr/lib/libA.dylib", "/usr/lib/libB.dylib"]
    let uuids = [UUID(), UUID()]

    var data = Data(repeating: 0, count: 0x80)
    var offsets: [UInt32] = []
    for path in paths {
        let offset = UInt32(data.count)
        offsets.append(offset)
        data.append(contentsOf: path.utf8)
        data.append(0)
    }

    let images = offsets.map {
        ImageInfo(address: 0, modTime: 0, inode: 0, pathFileOffset: $0)
    }

    let imagesText = zip(uuids, offsets).map { uuid, offset in
        ImageTextInfo(uuid: uuid, loadAddress: 0, textSegmentSize: 0, pathOffset: offset)
    }

    let cache = DyldCache(
        header: makeTestHeader(imagesCount: UInt32(images.count), imagesTextCount: UInt64(imagesText.count)),
        mappings: [],
        mappingsWithSlide: [],
        images: images,
        imagesText: imagesText,
        subCaches: []
    )

    let reader = MultiCacheReader(
        mainCache: cache,
        mainSource: DataByteSource(data),
        mainCachePath: "/tmp/dyld_shared_cache_images",
        subCaches: [:],
        symbolsCache: nil,
        symbolsSource: nil
    )

    return ImagePathsFixture(cache: cache, reader: reader, data: data, paths: paths, uuids: uuids)
}

private func makeMachOHeaderWithExportTrie(exportOff: UInt32, exportSize: UInt32) -> Data {
    var data = Data()

    // mach_header_64
    data.append(contentsOf: u32(0xfeedfacf)) // magic
    data.append(contentsOf: u32(0)) // cputype
    data.append(contentsOf: u32(0)) // cpusubtype
    data.append(contentsOf: u32(0x2)) // filetype (MH_EXECUTE)
    data.append(contentsOf: u32(2)) // ncmds
    data.append(contentsOf: u32(72 + 16)) // sizeofcmds
    data.append(contentsOf: u32(0)) // flags
    data.append(contentsOf: u32(0)) // reserved

    // LC_SEGMENT_64 (__LINKEDIT)
    data.append(contentsOf: u32(0x19)) // cmd
    data.append(contentsOf: u32(72)) // cmdsize
    data.append(contentsOf: fixedCString16("__LINKEDIT"))
    data.append(contentsOf: u64(0x1000)) // vmaddr
    data.append(contentsOf: u64(0x1000)) // vmsize
    data.append(contentsOf: u64(0x0)) // fileoff
    data.append(contentsOf: u64(0x1000)) // filesize
    data.append(contentsOf: u32(0)) // maxprot
    data.append(contentsOf: u32(0)) // initprot
    data.append(contentsOf: u32(0)) // nsects
    data.append(contentsOf: u32(0)) // flags

    // LC_DYLD_EXPORTS_TRIE
    data.append(contentsOf: u32(0x80000033))
    data.append(contentsOf: u32(16))
    data.append(contentsOf: u32(exportOff))
    data.append(contentsOf: u32(exportSize))

    return data
}

private func makeExportTrieFixture() -> ExportTrieFixture {
    let symbolName = "_func"
    let symbolOffset: UInt8 = 0x20
    let exportTrie = makeSingleSymbolExportTrie(symbol: symbolName, offset: symbolOffset)
    let exportOff: UInt32 = 0x200
    let headerBytes = makeMachOHeaderWithExportTrie(exportOff: exportOff, exportSize: UInt32(exportTrie.count))

    var bytes = Data()
    bytes.append(headerBytes)
    if bytes.count < Int(exportOff) {
        bytes.append(Data(repeating: 0, count: Int(exportOff) - bytes.count))
    }
    bytes.append(exportTrie)

    let source = DataByteSource(bytes)

    let mapping = MappingAndSlideInfo(
        address: 0x1000,
        size: 0x2000,
        fileOffset: 0,
        slideInfoFileOffset: 0,
        slideInfoFileSize: 0,
        flags: [],
        maxProt: .read,
        initProt: .read
    )
    let basicMapping = MappingInfo(address: 0x1000, size: 0x2000, fileOffset: 0, maxProt: .read, initProt: .read)
    let imageInfo = ImageInfo(address: 0x1000, modTime: 0, inode: 0, pathFileOffset: 0)

    let imageUUID = UUID()
    let imageText = ImageTextInfo(uuid: imageUUID, loadAddress: 0x1000, textSegmentSize: 0x1000, pathOffset: 0)

    let header = makeTestHeader(imagesCount: 1, imagesTextCount: 1, mappingWithSlideCount: 1)
    let cache = DyldCache(
        header: header,
        mappings: [basicMapping],
        mappingsWithSlide: [mapping],
        images: [imageInfo],
        imagesText: [imageText],
        subCaches: []
    )

    let reader = MultiCacheReader(
        mainCache: cache,
        mainSource: source,
        mainCachePath: "/tmp/dyld_shared_cache_test",
        subCaches: [:],
        symbolsCache: nil,
        symbolsSource: nil
    )

    return ExportTrieFixture(
        reader: reader,
        imageUUID: imageUUID,
        symbolName: symbolName,
        symbolOffset: UInt64(symbolOffset)
    )
}

private struct SubcacheReadFixture {
    let reader: MultiCacheReader
    let mainByte: UInt8
    let subByte: UInt8
}

private func makeSubcacheReadFixture() -> SubcacheReadFixture {
    let mainByte: UInt8 = 0xAA
    let subByte: UInt8 = 0xBB
    let mainData = Data(repeating: mainByte, count: 0x100)
    let subData = Data(repeating: subByte, count: 0x100)

    let mainSource = DataByteSource(mainData)
    let subSource = DataByteSource(subData)

    let mainMapping = MappingAndSlideInfo(
        address: 0x1000,
        size: 0x100,
        fileOffset: 0,
        slideInfoFileOffset: 0,
        slideInfoFileSize: 0,
        flags: [],
        maxProt: .read,
        initProt: .read
    )
    let subMapping = MappingAndSlideInfo(
        address: 0x1100,
        size: 0x100,
        fileOffset: 0,
        slideInfoFileOffset: 0,
        slideInfoFileSize: 0,
        flags: [],
        maxProt: .read,
        initProt: .read
    )

    let mainUUID = UUID()
    let subUUID = UUID()

    let mainCache = DyldCache(
        header: makeTestHeader(uuid: mainUUID, mappingWithSlideCount: 1),
        mappings: [],
        mappingsWithSlide: [mainMapping],
        images: [],
        imagesText: [],
        subCaches: []
    )
    let subCache = DyldCache(
        header: makeTestHeader(uuid: subUUID, mappingWithSlideCount: 1),
        mappings: [],
        mappingsWithSlide: [subMapping],
        images: [],
        imagesText: [],
        subCaches: []
    )

    let reader = MultiCacheReader(
        mainCache: mainCache,
        mainSource: mainSource,
        mainCachePath: "/tmp/dyld_shared_cache_main",
        subCaches: [subUUID: (cache: subCache, source: subSource, path: "/tmp/dyld_shared_cache_sub")],
        symbolsCache: nil,
        symbolsSource: nil
    )

    return SubcacheReadFixture(reader: reader, mainByte: mainByte, subByte: subByte)
}

private struct LocalSymbolsFixture {
    let reader: MultiCacheReader
    let cache: DyldCache
    let data: Data
    let symbolName: String
    let symbolValue: UInt64
}

private func makeLocalSymbolsFixture() -> LocalSymbolsFixture {
    let symbolName = "local_symbol"
    let symbolValue: UInt64 = 0x1234
    let baseOffset = 0x100

    let entriesOffset: UInt32 = UInt32(LocalSymbolsInfo.size)
    let entrySize = UInt32(LocalSymbolsEntry64.size)
    let nlistOffset = entriesOffset + entrySize
    let nlistSize = UInt32(NList64.size)
    let stringsOffset = nlistOffset + nlistSize
    let strings = Data(symbolName.utf8) + Data([0])
    let stringsSize = UInt32(strings.count)

    var region = Data()
    region.append(contentsOf: u32(nlistOffset))
    region.append(contentsOf: u32(1)) // nlistCount
    region.append(contentsOf: u32(stringsOffset))
    region.append(contentsOf: u32(stringsSize))
    region.append(contentsOf: u32(entriesOffset))
    region.append(contentsOf: u32(1)) // entriesCount

    region.append(contentsOf: u64(0)) // dylibOffset
    region.append(contentsOf: u32(0)) // nlistStartIndex
    region.append(contentsOf: u32(1)) // nlistCount

    region.append(contentsOf: u32(0)) // stringIndex
    region.append(0x0e) // N_SECT
    region.append(0x01) // section
    region.append(contentsOf: u16(0)) // desc
    region.append(contentsOf: u64(symbolValue))

    region.append(strings)

    var data = Data(repeating: 0, count: baseOffset)
    data.append(region)

    let source = DataByteSource(data)
    let header = makeTestHeader(
        localSymbolsOffset: UInt64(baseOffset),
        localSymbolsSize: UInt64(region.count),
        imagesCount: 1
    )
    let cache = DyldCache(
        header: header,
        mappings: [],
        mappingsWithSlide: [],
        images: [ImageInfo(address: 0, modTime: 0, inode: 0, pathFileOffset: 0)],
        imagesText: [],
        subCaches: []
    )
    let reader = MultiCacheReader(
        mainCache: cache,
        mainSource: source,
        mainCachePath: "/tmp/dyld_shared_cache_symbols",
        subCaches: [:],
        symbolsCache: nil,
        symbolsSource: nil
    )

    return LocalSymbolsFixture(reader: reader, cache: cache, data: data, symbolName: symbolName, symbolValue: symbolValue)
}

@Suite("Slide Pointer Tests")
struct SlidePointerTests {
    @Test("Plain pointer V3")
    func testPlainPointerV3() {
        // Plain pointer with value and delta
        let raw: UInt64 = 0x0001_FFFF_FFFF_FFFF // 51-bit value, 11-bit delta = 0
        let pointer = SlidePointer3(raw: raw)

        #expect(pointer.isAuthenticated == false)
        #expect(pointer.offsetToNextPointer == 0)
    }

    @Test("Authenticated pointer V3")
    func testAuthPointerV3() {
        // Authenticated pointer (high bit set)
        let raw: UInt64 = 0x8000_0000_0000_1234 // auth=1, various fields
        let pointer = SlidePointer3(raw: raw)

        #expect(pointer.isAuthenticated == true)
    }

    @Test("Rebase plain pointer V3")
    func testPlainPointerV3Rebase() {
        let raw: UInt64 = 0x0000_0000_0000_1234
        let pointer = SlidePointer3(raw: raw)
        let rebased = pointer.rebasedValue(slide: 0x10)
        #expect(rebased == 0x1244)
    }

    @Test("Authenticated pointer V3 has no rebased value")
    func testAuthPointerV3RebaseNil() {
        let raw: UInt64 = 0x8000_0000_0000_0000
        let pointer = SlidePointer3(raw: raw)
        #expect(pointer.rebasedValue(slide: 0x10) == nil)
    }

    @Test("Regular pointer V5 rebasing")
    func testPointerV5RegularRebase() {
        let target: UInt64 = 0x12345
        let high8: UInt8 = 0xAA
        let offsetToNext: UInt16 = 0x5
        let raw = target | (UInt64(high8) << 43) | (UInt64(offsetToNext) << 51)
        let pointer = SlidePointer5(raw: raw)

        #expect(pointer.isAuthenticated == false)
        #expect(pointer.offsetToNextPointer == offsetToNext)

        let value = pointer.rebasedValue(valueAdd: 0, slide: 0)
        let expected = (UInt64(high8) << 56) | target
        #expect(value == expected)
    }

    @Test("Authenticated pointer V5 rebasing")
    func testPointerV5AuthRebase() {
        let raw: UInt64 = 0x8000_0000_0000_1234
        let pointer = SlidePointer5(raw: raw)

        #expect(pointer.isAuthenticated == true)
        let value = pointer.rebasedValue(valueAdd: 0, slide: 0)
        #expect(value == 0x1234)
    }
}

@Suite("Byte Source Tests")
struct ByteSourceTests {
    @Test("Read NUL-terminated string")
    func testReadNulTerminatedString() throws {
        let bytes = Data("hello".utf8) + Data([0]) + Data("world".utf8)
        let src = DataByteSource(bytes)
        let s = try src.readNulTerminatedString(offset: 0)
        #expect(s == "hello")
    }
}

#if canImport(Darwin)
@Suite("Integration Tests")
struct IntegrationTests {
    // Modern macOS (Ventura+) uses Cryptexes path
    static let cryptexesBasePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld"
    // Legacy path for older macOS versions
    static let legacyBasePath = "/System/Library/dyld"

    static var cachePath: String? {
        #if arch(arm64)
        let cacheFileName = "dyld_shared_cache_arm64e"
        #else
        let cacheFileName = "dyld_shared_cache_x86_64"
        #endif

        // Try Cryptexes path first (modern macOS)
        let cryptexesPath = "\(cryptexesBasePath)/\(cacheFileName)"
        if FileManager.default.fileExists(atPath: cryptexesPath) {
            return cryptexesPath
        }

        // Fall back to legacy path
        let legacyPath = "\(legacyBasePath)/\(cacheFileName)"
        if FileManager.default.fileExists(atPath: legacyPath) {
            return legacyPath
        }

        return nil
    }

    @Test("Parse system cache header")
    func testParseSystemCache() throws {
        guard let path = Self.cachePath else {
            // Skip test if no cache found (e.g., in CI environment)
            return
        }

        let cache = try DyldCache(path: path)
        
        #if arch(arm64)
        #expect(cache.header.architecture == .arm64e)
        #else
        #expect(cache.header.architecture == .x86_64)
        #endif
        #expect(cache.images.count > 100)
        #expect(cache.mappings.count >= 1)
    }

    @Test("Read image paths from system cache")
    func testReadImagePaths() throws {
        guard let path = Self.cachePath else { return }

        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        let cache = try DyldCache(data: data)

        // Read first few image paths
        for i in 0..<min(5, cache.images.count) {
            let imagePath = try cache.imagePath(at: i, from: data)
            #expect(!imagePath.isEmpty)
            #expect(imagePath.hasPrefix("/"))
        }
    }

    @Test("Read image paths via DyldCacheByteSource")
    func testReadImagePathsViaByteSource() throws {
        guard let path = Self.cachePath else { return }

        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        let dataCache = try DyldCache(data: data)

        let source = DataByteSource(data)
        let sourceCache = try DyldCache(source: source)

        for i in 0..<min(5, dataCache.images.count) {
            let a = try dataCache.imagePath(at: i, from: data)
            let b = try sourceCache.imagePath(at: i, from: source)
            #expect(a == b)
        }
    }

    @Test("MultiCacheReader(open:) works with DataByteSource")
    func testMultiCacheReaderOpenClosure() throws {
        guard let path = Self.cachePath else { return }

        let direct = try MultiCacheReader(mainCachePath: path, requireAllSubCaches: false, requireSymbolsFile: false)
        let viaOpen = try MultiCacheReader(
            mainCachePath: path,
            open: { p in
                guard FileManager.default.fileExists(atPath: p) else { return nil }
                let data = try Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe)
                return DataByteSource(data)
            },
            requireAllSubCaches: false,
            requireSymbolsFile: false
        )

        #expect(direct.imageCount == viaOpen.imageCount)
        for i in 0..<min(5, direct.imageCount) {
            #expect(try direct.imagePath(at: i) == viaOpen.imagePath(at: i))
        }
    }
}
#endif

@Suite("Bounds Validation Tests")
struct BoundsValidationTests {
    @Test("SlideInfoV3 rejects excessive pageStartsCount")
    func testSlideInfoV3BoundsCheck() throws {
        // Build SlideInfoV3 header with excessive pageStartsCount
        var data = Data()

        // version = 3
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: 4))

        // pageSize = 16384
        var pageSize: UInt32 = 16384
        data.append(Data(bytes: &pageSize, count: 4))

        // pageStartsCount = 2_000_000 (exceeds max of 1_000_000)
        var pageStartsCount: UInt32 = 2_000_000
        data.append(Data(bytes: &pageStartsCount, count: 4))

        // authValueAdd = 0
        var authValueAdd: UInt64 = 0
        data.append(Data(bytes: &authValueAdd, count: 8))

        #expect(throws: DyldCacheError.self) {
            _ = try parseSlideInfo(from: data)
        }
    }

    @Test("SlideInfoV5 rejects excessive pageStartsCount")
    func testSlideInfoV5BoundsCheck() throws {
        var data = Data()

        // version = 5
        var version: UInt32 = 5
        data.append(Data(bytes: &version, count: 4))

        // pageSize = 16384
        var pageSize: UInt32 = 16384
        data.append(Data(bytes: &pageSize, count: 4))

        // pageStartsCount = 2_000_000 (exceeds max)
        var pageStartsCount: UInt32 = 2_000_000
        data.append(Data(bytes: &pageStartsCount, count: 4))

        // valueAdd = 0
        var valueAdd: UInt64 = 0
        data.append(Data(bytes: &valueAdd, count: 8))

        #expect(throws: DyldCacheError.self) {
            _ = try parseSlideInfo(from: data)
        }
    }

    @Test("Valid SlideInfoV3 parses successfully")
    func testValidSlideInfoV3() throws {
        var data = Data()

        // version = 3
        var version: UInt32 = 3
        data.append(Data(bytes: &version, count: 4))

        // pageSize = 16384
        var pageSize: UInt32 = 16384
        data.append(Data(bytes: &pageSize, count: 4))

        // pageStartsCount = 2 (small, valid)
        var pageStartsCount: UInt32 = 2
        data.append(Data(bytes: &pageStartsCount, count: 4))

        // authValueAdd = 0x180000000
        var authValueAdd: UInt64 = 0x180000000
        data.append(Data(bytes: &authValueAdd, count: 8))

        // Two page starts
        var pageStart1: UInt16 = 0xFFFF // no rebase
        var pageStart2: UInt16 = 0x0010
        data.append(Data(bytes: &pageStart1, count: 2))
        data.append(Data(bytes: &pageStart2, count: 2))

        let slideInfo = try parseSlideInfo(from: data)
        #expect(slideInfo.version == 3)
        #expect(slideInfo.pageSize == 16384)

        if let v3 = slideInfo as? SlideInfoV3 {
            #expect(v3.pageStarts.count == 2)
            #expect(v3.pageStarts[0] == SlideInfoV3.pageAttrNoRebase)
            #expect(v3.authValueAdd == 0x180000000)
        } else {
            Issue.record("Expected SlideInfoV3")
        }
    }

    @Test("SlideInfoV1 parses fields")
    func testSlideInfoV1Parsing() throws {
        var data = Data()
        data.append(contentsOf: u32(1)) // version
        data.append(contentsOf: u32(0x20)) // tocOffset
        data.append(contentsOf: u32(2)) // tocCount
        data.append(contentsOf: u32(0x40)) // entriesOffset
        data.append(contentsOf: u32(4)) // entriesCount
        data.append(contentsOf: u32(8)) // entriesSize

        let slideInfo = try parseSlideInfo(from: data)
        guard let v1 = slideInfo as? SlideInfoV1 else {
            Issue.record("Expected SlideInfoV1")
            return
        }
        #expect(v1.tocOffset == 0x20)
        #expect(v1.tocCount == 2)
        #expect(v1.entriesOffset == 0x40)
        #expect(v1.entriesCount == 4)
        #expect(v1.entriesSize == 8)
    }

    @Test("SlideInfoV2 parses fields")
    func testSlideInfoV2Parsing() throws {
        var data = Data()
        data.append(contentsOf: u32(2)) // version
        data.append(contentsOf: u32(4096)) // pageSize
        data.append(contentsOf: u32(0x100)) // pageStartsOffset
        data.append(contentsOf: u32(3)) // pageStartsCount
        data.append(contentsOf: u32(0x200)) // pageExtrasOffset
        data.append(contentsOf: u32(1)) // pageExtrasCount
        data.append(contentsOf: u64(0xFF00FF00)) // deltaMask
        data.append(contentsOf: u64(0x12345678)) // valueAdd

        let slideInfo = try parseSlideInfo(from: data)
        guard let v2 = slideInfo as? SlideInfoV2 else {
            Issue.record("Expected SlideInfoV2")
            return
        }
        #expect(v2.pageSize == 4096)
        #expect(v2.pageStartsOffset == 0x100)
        #expect(v2.pageStartsCount == 3)
        #expect(v2.pageExtrasOffset == 0x200)
        #expect(v2.pageExtrasCount == 1)
        #expect(v2.deltaMask == 0xFF00FF00)
        #expect(v2.valueAdd == 0x12345678)
    }

    @Test("SlideInfoV4 parses fields")
    func testSlideInfoV4Parsing() throws {
        var data = Data()
        data.append(contentsOf: u32(4)) // version
        data.append(contentsOf: u32(16384)) // pageSize
        data.append(contentsOf: u32(0x80)) // pageStartsOffset
        data.append(contentsOf: u32(2)) // pageStartsCount
        data.append(contentsOf: u32(0xA0)) // pageExtrasOffset
        data.append(contentsOf: u32(1)) // pageExtrasCount
        data.append(contentsOf: u64(0x0FFF0FFF)) // deltaMask
        data.append(contentsOf: u64(0x2000)) // valueAdd

        let slideInfo = try parseSlideInfo(from: data)
        guard let v4 = slideInfo as? SlideInfoV4 else {
            Issue.record("Expected SlideInfoV4")
            return
        }
        #expect(v4.pageSize == 16384)
        #expect(v4.pageStartsOffset == 0x80)
        #expect(v4.pageStartsCount == 2)
        #expect(v4.pageExtrasOffset == 0xA0)
        #expect(v4.pageExtrasCount == 1)
        #expect(v4.deltaMask == 0x0FFF0FFF)
        #expect(v4.valueAdd == 0x2000)
    }

    @Test("parseSlideInfoFromOffset reads from offset")
    func testSlideInfoFromOffset() throws {
        var slide = Data()
        slide.append(contentsOf: u32(2)) // version
        slide.append(contentsOf: u32(4096)) // pageSize
        slide.append(contentsOf: u32(0x10)) // pageStartsOffset
        slide.append(contentsOf: u32(1)) // pageStartsCount
        slide.append(contentsOf: u32(0x20)) // pageExtrasOffset
        slide.append(contentsOf: u32(0)) // pageExtrasCount
        slide.append(contentsOf: u64(0xAA00AA00)) // deltaMask
        slide.append(contentsOf: u64(0x1000)) // valueAdd

        var data = Data(repeating: 0xAA, count: 16)
        let offset = data.count
        data.append(slide)

        let parsed = try parseSlideInfoFromOffset(data, at: offset)
        guard let v2 = parsed as? SlideInfoV2 else {
            Issue.record("Expected SlideInfoV2")
            return
        }
        #expect(v2.pageStartsOffset == 0x10)
        #expect(v2.valueAdd == 0x1000)
    }
}

@Suite("VMAddressResolver Tests")
struct VMAddressResolverTests {
    @Test("Basic address resolution")
    func testBasicResolution() {
        let mappings = [
            ResolverMapping(address: 0x180000000, size: 0x1000000, fileOffset: 0),
            ResolverMapping(address: 0x190000000, size: 0x2000000, fileOffset: 0x1000000)
        ]
        let resolver = VMAddressResolver(basicMappings: mappings.map {
            MappingInfo(address: $0.address, size: $0.size, fileOffset: $0.fileOffset, maxProt: .read, initProt: .read)
        })

        // Address in first mapping
        let offset1 = resolver.fileOffset(forVMAddress: 0x180000100)
        #expect(offset1 == 0x100)

        // Address in second mapping
        let offset2 = resolver.fileOffset(forVMAddress: 0x190000200)
        #expect(offset2 == 0x1000200)

        // Address outside all mappings
        let offset3 = resolver.fileOffset(forVMAddress: 0x100000000)
        #expect(offset3 == nil)
    }

    @Test("Overflow-safe arithmetic")
    func testOverflowSafety() {
        // Create a mapping where address + size would overflow
        let mappings = [
            MappingInfo(
                address: 0xFFFFFFFFFFFF0000,
                size: 0x20000, // Would overflow if added naively
                fileOffset: 0,
                maxProt: .read,
                initProt: .read
            )
        ]
        let resolver = VMAddressResolver(basicMappings: mappings)

        // Should not crash due to overflow
        let offset = resolver.fileOffset(forVMAddress: 0x180000000)
        #expect(offset == nil)
    }

    @Test("Convenience fileOffset method")
    func testConvenienceMethod() {
        let mappings = [
            MappingInfo(address: 0x180000000, size: 0x1000000, fileOffset: 0, maxProt: .read, initProt: .read)
        ]
        let resolver = VMAddressResolver(basicMappings: mappings)

        // Test alias method
        let offset = resolver.fileOffset(for: 0x180000500)
        #expect(offset == 0x500)
    }
}

@Suite("Export Trie Security Tests")
struct ExportTrieSecurityTests {
    @Test("Trie iterator is Sendable")
    func testIteratorSendable() {
        let trie = ExportTrie(data: Data())
        let iterator = trie.makeIterator()

        // Verify iterator can be passed to sendable context
        func takeSendable<T: Sendable>(_ value: T) {}
        takeSendable(iterator)
    }

    @Test("Iterator enumerates symbols")
    func testIteratorEnumeratesSymbols() {
        var data = Data()

        // Root node: not terminal, 2 children
        data.append(0x00)
        data.append(0x02)

        // Edge "_a\0" -> offset 14
        data.append(contentsOf: "_a".utf8)
        data.append(0x00)
        data.append(0x0E)

        // Edge "_b\0" -> offset 18
        data.append(contentsOf: "_b".utf8)
        data.append(0x00)
        data.append(0x12)

        // Padding to reach offset 14
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Node for "_a"
        data.append(0x02)
        data.append(0x00)
        data.append(0x10)
        data.append(0x00)

        // Node for "_b"
        data.append(0x02)
        data.append(0x00)
        data.append(0x20)
        data.append(0x00)

        var iterator = ExportTrie(data: data).makeIterator()
        var names: [String] = []
        while let symbol = iterator.next() {
            names.append(symbol.name)
        }

        #expect(Set(names) == Set(["_a", "_b"]))
    }

    @Test("ULEB128 overflow throws")
    func testULEB128Overflow() {
        let data = Data(repeating: 0x80, count: 12)
        let trie = ExportTrie(data: data)

        #expect(throws: DyldCacheError.self) {
            _ = try trie.allSymbols()
        }
    }

    @Test("Trie with branching paths")
    func testBranchingTrie() throws {
        var data = Data()

        // Root node at offset 0: not terminal, 2 children
        data.append(0x00) // terminal size = 0
        data.append(0x02) // 2 children

        // First child edge: "_a\0" (3 bytes) + offset ULEB128 (1 byte) = 4 bytes
        data.append(contentsOf: "_a".utf8)  // bytes 2-3
        data.append(0x00)                    // byte 4 (null terminator)
        data.append(0x0E)                    // byte 5: offset to node at 14

        // Second child edge: "_b\0" (3 bytes) + offset ULEB128 (1 byte) = 4 bytes
        data.append(contentsOf: "_b".utf8)  // bytes 6-7
        data.append(0x00)                    // byte 8 (null terminator)
        data.append(0x12)                    // byte 9: offset to node at 18

        // Padding to reach offset 14
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // bytes 10-13

        // Node for "_a" at offset 14
        data.append(0x02) // terminal size = 2
        data.append(0x00) // flags = regular
        data.append(0x10) // offset = 0x10
        data.append(0x00) // 0 children

        // Node for "_b" at offset 18
        data.append(0x02) // terminal size = 2
        data.append(0x00) // flags = regular
        data.append(0x20) // offset = 0x20
        data.append(0x00) // 0 children

        let trie = ExportTrie(data: data)
        let symbols = try trie.allSymbols()

        #expect(symbols.count == 2)

        let names = Set(symbols.map { $0.name })
        #expect(names.contains("_a"))
        #expect(names.contains("_b"))
    }
}

@Suite("LocalSymbols Entry Tests")
struct LocalSymbolsEntryTests {
    @Test("LocalSymbolsEntry32 initialization")
    func testEntry32() {
        let entry32 = LocalSymbolsEntry32(
            dylibOffset: 0x1000,
            nlistStartIndex: 5,
            nlistCount: 10
        )

        let entry = LocalSymbolsEntry(entry32)
        #expect(entry.dylibOffset == 0x1000)
        #expect(entry.nlistStartIndex == 5)
        #expect(entry.nlistCount == 10)
    }

    @Test("LocalSymbolsEntry64 initialization")
    func testEntry64() {
        let entry64 = LocalSymbolsEntry64(
            dylibOffset: 0x100000000,
            nlistStartIndex: 100,
            nlistCount: 50
        )

        let entry = LocalSymbolsEntry(entry64)
        #expect(entry.dylibOffset == 0x100000000)
        #expect(entry.nlistStartIndex == 100)
        #expect(entry.nlistCount == 50)
    }
}

@Suite("DyldCache Error Tests")
struct DyldCacheErrorTests {
    @Test("Error cases can be constructed")
    func testErrorConstruction() {
        // Verify errors can be constructed with associated values
        let offsetError = DyldCacheError.offsetOutOfBounds(offset: 0x1000, bufferSize: 0x800)
        let rangeError = DyldCacheError.rangeOutOfBounds(offset: 0x500, size: 0x1000, bufferSize: 0x800)
        let slideError = DyldCacheError.unknownSlideInfoVersion(99)

        if case .offsetOutOfBounds(let offset, let bufferSize) = offsetError {
            #expect(offset == 0x1000)
            #expect(bufferSize == 0x800)
        } else {
            Issue.record("Error should be offsetOutOfBounds")
        }

        if case .rangeOutOfBounds(let offset, let size, let bufferSize) = rangeError {
            #expect(offset == 0x500)
            #expect(size == 0x1000)
            #expect(bufferSize == 0x800)
        } else {
            Issue.record("Error should be rangeOutOfBounds")
        }

        if case .unknownSlideInfoVersion(let version) = slideError {
            #expect(version == 99)
        } else {
            Issue.record("Error should be unknownSlideInfoVersion")
        }
    }

    @Test("Image index out of bounds error")
    func testImageIndexError() {
        let error = DyldCacheError.imageIndexOutOfBounds(index: 100, max: 50)

        // Verify it matches the specific case
        if case .imageIndexOutOfBounds(let index, let max) = error {
            #expect(index == 100)
            #expect(max == 50)
        } else {
            Issue.record("Error should be imageIndexOutOfBounds")
        }
    }

    @Test("Slide info parse error")
    func testSlideInfoParseError() {
        let error = DyldCacheError.slideInfoParseError(version: 3, detail: "test detail")

        if case .slideInfoParseError(let version, let detail) = error {
            #expect(version == 3)
            #expect(detail == "test detail")
        } else {
            Issue.record("Error should be slideInfoParseError")
        }
    }
}

// Helper struct for tests
private struct ResolverMapping {
    let address: UInt64
    let size: UInt64
    let fileOffset: UInt64
}
