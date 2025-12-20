import Foundation

/// Resolves virtual memory addresses to file offsets and vice versa.
public struct VMAddressResolver: Sendable {
    private let mappings: [MappingAndSlideInfo]

    /// Initialize with mappings from a dyld cache.
    public init(mappings: [MappingAndSlideInfo]) {
        self.mappings = mappings
    }

    /// Initialize with basic mappings (converted to MappingAndSlideInfo).
    public init(basicMappings: [MappingInfo]) {
        self.mappings = basicMappings.map { mapping in
            MappingAndSlideInfo(
                address: mapping.address,
                size: mapping.size,
                fileOffset: mapping.fileOffset,
                slideInfoFileOffset: 0,
                slideInfoFileSize: 0,
                flags: [],
                maxProt: mapping.maxProt,
                initProt: mapping.initProt
            )
        }
    }

    /// Convert a virtual memory address to a file offset.
    ///
    /// - Parameter vmAddress: The virtual memory address to resolve.
    /// - Returns: The file offset, or nil if the address is not in any mapping.
    public func fileOffset(forVMAddress vmAddress: UInt64) -> UInt64? {
        for mapping in mappings {
            // Use overflow-safe arithmetic
            let (endAddress, overflow) = mapping.address.addingReportingOverflow(mapping.size)
            guard !overflow else { continue }

            if vmAddress >= mapping.address && vmAddress < endAddress {
                return mapping.fileOffset + (vmAddress - mapping.address)
            }
        }
        return nil
    }

    /// Convenience alias for `fileOffset(forVMAddress:)`.
    public func fileOffset(for vmAddress: UInt64) -> UInt64? {
        fileOffset(forVMAddress: vmAddress)
    }

    /// Convert a file offset to a virtual memory address.
    ///
    /// - Parameter fileOffset: The file offset to resolve.
    /// - Returns: The virtual memory address, or nil if the offset is not in any mapping.
    public func vmAddress(forFileOffset fileOffset: UInt64) -> UInt64? {
        for mapping in mappings {
            // Use overflow-safe arithmetic
            let (endOffset, overflow) = mapping.fileOffset.addingReportingOverflow(mapping.size)
            guard !overflow else { continue }

            if fileOffset >= mapping.fileOffset && fileOffset < endOffset {
                return mapping.address + (fileOffset - mapping.fileOffset)
            }
        }
        return nil
    }

    /// Find the mapping that contains a virtual memory address.
    ///
    /// - Parameter vmAddress: The virtual memory address to look up.
    /// - Returns: The mapping containing the address, or nil if not found.
    public func mapping(forVMAddress vmAddress: UInt64) -> MappingAndSlideInfo? {
        for mapping in mappings {
            // Use overflow-safe arithmetic
            let (endAddress, overflow) = mapping.address.addingReportingOverflow(mapping.size)
            guard !overflow else { continue }

            if vmAddress >= mapping.address && vmAddress < endAddress {
                return mapping
            }
        }
        return nil
    }

    /// Find the mapping that contains a file offset.
    ///
    /// - Parameter fileOffset: The file offset to look up.
    /// - Returns: The mapping containing the offset, or nil if not found.
    public func mapping(forFileOffset fileOffset: UInt64) -> MappingAndSlideInfo? {
        for mapping in mappings {
            // Use overflow-safe arithmetic
            let (endOffset, overflow) = mapping.fileOffset.addingReportingOverflow(mapping.size)
            guard !overflow else { continue }

            if fileOffset >= mapping.fileOffset && fileOffset < endOffset {
                return mapping
            }
        }
        return nil
    }

    /// Check if a virtual memory address is valid (within some mapping).
    public func isValidVMAddress(_ vmAddress: UInt64) -> Bool {
        mapping(forVMAddress: vmAddress) != nil
    }

    /// Check if a file offset is valid (within some mapping).
    public func isValidFileOffset(_ fileOffset: UInt64) -> Bool {
        mapping(forFileOffset: fileOffset) != nil
    }
}
