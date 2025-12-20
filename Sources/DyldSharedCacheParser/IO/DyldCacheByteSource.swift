import Foundation

/// A random-access byte source for dyld shared cache parsing.
///
/// This lets the parser operate on dyld caches that are not available as real files on disk
/// (e.g. read directly from an APFS image), without loading the entire cache into memory.
public protocol DyldCacheByteSource: Sendable {
    /// Total byte size of the underlying source.
    var size: Int { get }

    /// Reads up to `length` bytes at `offset`.
    ///
    /// Implementations should return exactly `length` bytes unless they hit EOF.
    func read(offset: Int, length: Int) throws -> Data
}

/// A byte source backed by a `Data` buffer.
public struct DataByteSource: DyldCacheByteSource, Sendable {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    public var size: Int { data.count }

    public func read(offset: Int, length: Int) throws -> Data {
        if length <= 0 { return Data() }
        guard offset >= 0, offset < data.count else { return Data() }
        let end = min(data.count, offset + length)
        return data[offset..<end]
    }
}

extension DyldCacheByteSource {
    /// Reads a NUL-terminated UTF-8 string starting at `offset`.
    public func readNulTerminatedString(
        offset: Int,
        maxBytes: Int = 256 * 1024,
        chunkSize: Int = 4096
    ) throws -> String {
        if maxBytes <= 0 { return "" }
        if chunkSize <= 0 { return "" }

        var cursor = offset
        var remaining = maxBytes
        var out = Data()
        out.reserveCapacity(min(maxBytes, 1024))

        while remaining > 0 {
            let want = min(remaining, chunkSize)
            let chunk = try read(offset: cursor, length: want)
            if chunk.isEmpty { break }

            if let nul = chunk.firstIndex(of: 0) {
                out.append(chunk[..<nul])
                break
            }

            out.append(chunk)
            cursor += chunk.count
            remaining -= chunk.count

            if chunk.count < want { break }
        }

        return String(decoding: out, as: UTF8.self)
    }
}

