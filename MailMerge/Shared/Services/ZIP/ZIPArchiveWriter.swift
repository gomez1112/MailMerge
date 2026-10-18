import Compression
import Foundation

/// Writes a ZIP archive one entry at a time, such as the merged PDFs attached to an email.
///
/// Call `finish()` after the last entry; until then the file has no central directory
/// and isn't a valid archive. Archives are limited to 65,535 entries and 4 GB.
nonisolated final class ZIPArchiveWriter {
    private let handle: FileHandle
    private var centralDirectory = Data()
    private var entryCount = 0
    private var offset: UInt64 = 0

    /// Creates an empty archive at `url`, replacing any file already there.
    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ZIPArchiveError.unwritable
        }
        handle = try FileHandle(forWritingTo: url)
    }

    /// Adds a file named `path` with `contents`.
    func addEntry(
        path: String,
        contents: Data,
        method: ZIPCompressionMethod = .stored,
        modified: Date = .now
    ) throws {
        let payload = method == .deflated ? try Self.deflate(contents) : contents
        let name = Data(path.utf8)
        guard entryCount < Int(UInt16.max),
              name.count <= Int(UInt16.max),
              contents.count < Int(UInt32.max),
              payload.count < Int(UInt32.max),
              offset < UInt64(UInt32.max) else {
            throw ZIPArchiveError.tooLarge
        }
        let checksum = CRC32.checksum(of: contents)
        let timestamp = Self.dosTimestamp(for: modified)
        // Bit 11 marks the name as UTF-8.
        let flags: UInt16 = 0x0800
        let versionNeeded: UInt16 = 20

        var localHeader = Data()
        localHeader.appendLittleEndian(ZIPSignature.localFileHeader)
        localHeader.appendLittleEndian(versionNeeded)
        localHeader.appendLittleEndian(flags)
        localHeader.appendLittleEndian(method.rawValue)
        localHeader.appendLittleEndian(timestamp.time)
        localHeader.appendLittleEndian(timestamp.date)
        localHeader.appendLittleEndian(checksum)
        localHeader.appendLittleEndian(UInt32(payload.count))
        localHeader.appendLittleEndian(UInt32(contents.count))
        localHeader.appendLittleEndian(UInt16(name.count))
        localHeader.appendLittleEndian(UInt16(0))
        localHeader.append(name)
        try handle.write(contentsOf: localHeader)
        try handle.write(contentsOf: payload)

        var header = Data()
        header.appendLittleEndian(ZIPSignature.centralDirectoryHeader)
        // Made by Unix (3), ZIP 2.0, so the permissions below apply when unzipped.
        header.appendLittleEndian(UInt16(3 << 8 | 20))
        header.appendLittleEndian(versionNeeded)
        header.appendLittleEndian(flags)
        header.appendLittleEndian(method.rawValue)
        header.appendLittleEndian(timestamp.time)
        header.appendLittleEndian(timestamp.date)
        header.appendLittleEndian(checksum)
        header.appendLittleEndian(UInt32(payload.count))
        header.appendLittleEndian(UInt32(contents.count))
        header.appendLittleEndian(UInt16(name.count))
        header.appendLittleEndian(UInt16(0)) // Extra field length
        header.appendLittleEndian(UInt16(0)) // Comment length
        header.appendLittleEndian(UInt16(0)) // Starting disk
        header.appendLittleEndian(UInt16(0)) // Internal attributes
        header.appendLittleEndian(UInt32(0o100644) << 16) // A regular file, rw-r--r--
        header.appendLittleEndian(UInt32(offset))
        header.append(name)
        centralDirectory.append(header)

        offset += UInt64(localHeader.count + payload.count)
        entryCount += 1
    }

    /// Writes the central directory and closes the file.
    func finish() throws {
        guard offset + UInt64(centralDirectory.count) < UInt64(UInt32.max) else {
            throw ZIPArchiveError.tooLarge
        }
        var endRecord = Data()
        endRecord.appendLittleEndian(ZIPSignature.endOfCentralDirectory)
        endRecord.appendLittleEndian(UInt16(0)) // This disk
        endRecord.appendLittleEndian(UInt16(0)) // Disk with the central directory
        endRecord.appendLittleEndian(UInt16(entryCount))
        endRecord.appendLittleEndian(UInt16(entryCount))
        endRecord.appendLittleEndian(UInt32(centralDirectory.count))
        endRecord.appendLittleEndian(UInt32(offset))
        endRecord.appendLittleEndian(UInt16(0)) // Comment length
        try handle.write(contentsOf: centralDirectory)
        try handle.write(contentsOf: endRecord)
        try handle.close()
    }

    private static func deflate(_ data: Data) throws -> Data {
        var output = Data()
        // Compression's zlib algorithm writes raw DEFLATE data, which is what ZIP stores.
        let filter = try OutputFilter(.compress, using: .zlib) { chunk in
            if let chunk { output.append(chunk) }
        }
        try filter.write(data)
        try filter.finalize()
        return output
    }

    /// The MS-DOS time and date ZIP headers use, in local time with 2-second precision.
    private static func dosTimestamp(for date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let year = min(max((components.year ?? 1980) - 1980, 0), 127)
        let time = (components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | (components.second ?? 0) / 2
        let day = year << 9 | (components.month ?? 1) << 5 | (components.day ?? 1)
        return (UInt16(time), UInt16(day))
    }
}

/// The CRC-32 checksum ZIP records for each entry.
nonisolated enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return ~crc
    }
}

private extension Data {
    nonisolated mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
