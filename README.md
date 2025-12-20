# swift-dyld-shared-cache-parser

A Swift package for parsing the dyld shared cache and extracting metadata, images, and symbols.

[![CI](https://github.com/0xpablo/swift-dyld-shared-cache-parser/actions/workflows/ci.yml/badge.svg)](https://github.com/0xpablo/swift-dyld-shared-cache-parser/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xpablo%2Fswift-dyld-shared-cache-parser%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/0xpablo/swift-dyld-shared-cache-parser)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2F0xpablo%2Fswift-dyld-shared-cache-parser%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/0xpablo/swift-dyld-shared-cache-parser)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Overview

This library parses dyld shared cache files, including split-cache layouts, and provides APIs to:

- Read headers, mappings, images, and subcache metadata
- Resolve VM addresses and slide info
- Enumerate local symbols (from a .symbols file when present)
- Parse export tries as a fallback
- Perform lightweight symbolication (name + offset)

## Usage

### Open a cache and list images

```swift
import DyldSharedCacheParser

let reader = try MultiCacheReader(
    mainCachePath: "/System/Library/dyld/dyld_shared_cache_arm64e",
    requireAllSubCaches: false,
    requireSymbolsFile: false
)

print("Images: \(reader.imageCount)")
print(try reader.imagePath(at: 0))
```

### Parse a cache header directly

```swift
import DyldSharedCacheParser
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/dyld/dyld_shared_cache_arm64e"))
let cache = try DyldCache(data: data)
print(cache.header)
```

### Resolve local symbols (when available)

```swift
if reader.hasLocalSymbols {
    let symbols = try reader.localSymbols(forImageAt: 0)
    print(symbols.prefix(5).map(\.name))
}
```

### Export trie fallback

```swift
let exports = try reader.exportedSymbols(forImageAt: 0)
print("Exported symbols: \(exports.count)")
```

### Symbolication

```swift
let result = try reader.lookup(
    pc: 0x12345678,
    imageUUID: someUUID,
    imageLoadAddress: 0x100000000
)
if let result {
    print("\(result.symbol) + \(result.addend)")
}
```

### Byte sources and Data slices

`DyldCacheByteSource.read(offset:length:)` may return a `Data` slice (for example,
`data[offset..<end]`), which preserves the original `Data` indices. If you index
into returned `Data` directly, offset from `data.startIndex` or normalize with
`data.subdata(in:)` first.

## Building

```bash
swift build
swift test
```

## Requirements

- Swift 6.2+
- macOS 15+, iOS 18+, watchOS 11+, tvOS 18+, visionOS 2+

## License

This package is available under the MIT license. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please ensure tests pass before submitting PRs.
