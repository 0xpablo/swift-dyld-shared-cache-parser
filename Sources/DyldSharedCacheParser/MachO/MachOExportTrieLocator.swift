import BinaryParsing
import Foundation

/// Minimal Mach-O parsing to locate the exports trie for a cached image.
enum MachOExportTrieLocator {
    private enum Magic: UInt32 {
        case mhMagic = 0xfeedface
        case mhMagic64 = 0xfeedfacf
    }

    private enum LoadCommand: UInt32 {
        case segment = 0x1
        case segment64 = 0x19
        case dyldInfo = 0x22
        case dyldInfoOnly = 0x80000022
        case dyldExportsTrie = 0x80000033
    }

    struct ExportTrieLocation: Sendable, Hashable {
        /// Unslid VM address for the exports trie bytes (in the dyld cache address space).
        let vmAddress: UInt64
        /// Size in bytes of the exports trie.
        let size: UInt32
    }

    static func locate(in machOBytes: Data) throws -> ExportTrieLocation? {
        do {
            return try machOBytes.withParserSpan { span in
                let magic = try UInt32(parsingLittleEndian: &span)
                let is64: Bool
                switch magic {
                case Magic.mhMagic.rawValue:
                    is64 = false
                case Magic.mhMagic64.rawValue:
                    is64 = true
                default:
                    throw DyldCacheError.invalidMachO(String(format: "unknown magic 0x%08x", magic))
                }

                // cputype, cpusubtype, filetype
                _ = try UInt32(parsingLittleEndian: &span)
                _ = try UInt32(parsingLittleEndian: &span)
                _ = try UInt32(parsingLittleEndian: &span)

                let ncmds = try UInt32(parsingLittleEndian: &span)
                let sizeofcmds = try UInt32(parsingLittleEndian: &span)

                // flags (+ reserved for 64-bit)
                _ = try UInt32(parsingLittleEndian: &span)
                if is64 {
                    _ = try UInt32(parsingLittleEndian: &span)
                }

                var loadCommands = try span.sliceSpan(byteCount: sizeofcmds)

                var linkeditVMAddr: UInt64?
                var linkeditFileOff: UInt64?
                var exportOff: UInt32?
                var exportSize: UInt32?

                for _ in 0..<ncmds {
                    if loadCommands.isEmpty { break }

                    let cmd = try UInt32(parsingLittleEndian: &loadCommands)
                    let cmdsize = try UInt32(parsingLittleEndian: &loadCommands)
                    guard cmdsize >= 8 else {
                        throw DyldCacheError.invalidMachO("load command size < 8")
                    }

                    var payload = try loadCommands.sliceSpan(byteCount: UInt64(cmdsize) - 8)

                    if cmd == LoadCommand.segment64.rawValue {
                        let segname = try readFixedCString16(parsing: &payload)
                        let vmaddr = try UInt64(parsingLittleEndian: &payload)
                        _ = try UInt64(parsingLittleEndian: &payload) // vmsize
                        let fileoff = try UInt64(parsingLittleEndian: &payload)
                        _ = try UInt64(parsingLittleEndian: &payload) // filesize
                        _ = try UInt32(parsingLittleEndian: &payload) // maxprot
                        _ = try UInt32(parsingLittleEndian: &payload) // initprot
                        _ = try UInt32(parsingLittleEndian: &payload) // nsects
                        _ = try UInt32(parsingLittleEndian: &payload) // flags

                        if segname == "__LINKEDIT" {
                            linkeditVMAddr = vmaddr
                            linkeditFileOff = fileoff
                        }
                    } else if cmd == LoadCommand.segment.rawValue {
                        let segname = try readFixedCString16(parsing: &payload)
                        let vmaddr = UInt64(try UInt32(parsingLittleEndian: &payload))
                        _ = try UInt32(parsingLittleEndian: &payload) // vmsize
                        let fileoff = UInt64(try UInt32(parsingLittleEndian: &payload))
                        _ = try UInt32(parsingLittleEndian: &payload) // filesize
                        _ = try UInt32(parsingLittleEndian: &payload) // maxprot
                        _ = try UInt32(parsingLittleEndian: &payload) // initprot
                        _ = try UInt32(parsingLittleEndian: &payload) // nsects
                        _ = try UInt32(parsingLittleEndian: &payload) // flags

                        if segname == "__LINKEDIT" {
                            linkeditVMAddr = vmaddr
                            linkeditFileOff = fileoff
                        }
                    } else if cmd == LoadCommand.dyldExportsTrie.rawValue {
                        // linkedit_data_command
                        exportOff = try UInt32(parsingLittleEndian: &payload)
                        exportSize = try UInt32(parsingLittleEndian: &payload)
                    } else if cmd == LoadCommand.dyldInfo.rawValue || cmd == LoadCommand.dyldInfoOnly.rawValue {
                        // dyld_info_command:
                        // rebase_off, rebase_size, bind_off, bind_size, weak_bind_off, weak_bind_size,
                        // lazy_bind_off, lazy_bind_size, export_off, export_size
                        for _ in 0..<8 {
                            _ = try UInt32(parsingLittleEndian: &payload)
                        }
                        let eoff = try UInt32(parsingLittleEndian: &payload)
                        let esize = try UInt32(parsingLittleEndian: &payload)
                        if exportOff == nil || exportSize == nil {
                            exportOff = eoff
                            exportSize = esize
                        }
                    }
                }

                guard let linkeditVMAddr, let linkeditFileOff else { return nil }
                guard let exportOff, let exportSize, exportSize > 0 else { return nil }

                let vmAddress = linkeditVMAddr + UInt64(exportOff) - linkeditFileOff
                return ExportTrieLocation(vmAddress: vmAddress, size: exportSize)
            }
        } catch let error as ParsingError {
            throw DyldCacheError.invalidMachO(error.description)
        }
    }

    private static func readFixedCString16(parsing input: inout ParserSpan) throws -> String {
        let bytes = try Array<UInt8>(parsing: &input, byteCount: 16)
        return String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
    }
}
