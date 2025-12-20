import Foundation

extension UUID {
    /// Returns `true` iff this UUID is all-zeroes.
    public var isNullUUID: Bool {
        var raw = self.uuid
        return withUnsafeBytes(of: &raw) { bytes in
            bytes.allSatisfy { $0 == 0 }
        }
    }
}

