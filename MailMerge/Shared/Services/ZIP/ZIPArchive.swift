import Compression
import Foundation

/// Reads entries from a ZIP archive, such as the parts of a .docx or .xlsx package.
///
/// Handles stored and deflated entries, ZIP64 archives, and entries written with data
/// descriptors (sizes come from the central directory). Encrypted entries and other
/// compression methods aren't supported; Office documents don't use them.
///
/// The app reads ZIP files itself rather than through a package: a Swift package that
/// ships a resource bundle puts that bundle in Contents/Resources, where the App Store
/// export leaves Xcode's development signature on it and App Store Connect rejects the
/// build (ITMS-90284).
nonisolated struct ZIPArchive: Sendable {
    nonisolated struct Entry: Sendable {
        var path: String
        var compressionMethod: UInt16
        var isEncrypted: Bool
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var localHeaderOffset: UInt64
    }

    /// The archive's entries, in central directory order.
    let entries: [Entry]
    private let contents: Data

    /// The largest entry this reads, as a guard against archives that claim enormous sizes.
    private static let maximumEntrySize: UInt64 = 1 << 30

    init(url: URL) throws {
        let contents: Data
        do {
            contents = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw ZIPArchiveError.unreadable
        }
        self.contents = contents
        entries = try Self.centralDirectory(of: contents)
    }

    /// The entry at `path`, matching exactly or, failing that, ignoring case.
    func entry(at path: String) -> Entry? {
        entries.first { $0.path == path }
            ?? entries.first { $0.path.caseInsensitiveCompare(path) == .orderedSame }
    }

    /// The uncompressed contents of the entry at `path`, or nil when there's no such entry.
    func data(at path: String) throws -> Data? {
        guard let entry = entry(at: path) else { return nil }
        return try data(for: entry)
    }

    /// The uncompressed contents of `entry`.
    func data(for entry: Entry) throws -> Data {
        guard !entry.isEncrypted else { throw ZIPArchiveError.unsupportedEntry }
        guard entry.uncompressedSize <= Self.maximumEntrySize,
              entry.compressedSize <= Self.maximumEntrySize else {
            throw ZIPArchiveError.tooLarge
        }
        let bytes = ByteReader(contents)
        let headerOffset = try Self.offset(entry.localHeaderOffset)
        guard try bytes.uint32(at: headerOffset) == ZIPSignature.localFileHeader else {
            throw ZIPArchiveError.corrupt
        }
        // The local header's name and extra field can differ in length from the central
        // directory's copies, so the data starts after the local ones.
        let nameLength = Int(try bytes.uint16(at: headerOffset + 26))
        let extraLength = Int(try bytes.uint16(at: headerOffset + 28))
        let compressed = try bytes.data(at: headerOffset + 30 + nameLength + extraLength, count: Int(entry.compressedSize))

        switch entry.compressionMethod {
        case ZIPCompressionMethod.stored.rawValue:
            return Data(compressed)
        case ZIPCompressionMethod.deflated.rawValue:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZIPArchiveError.unsupportedEntry
        }
    }

    // MARK: - Central Directory

    private static func centralDirectory(of contents: Data) throws -> [Entry] {
        let bytes = ByteReader(contents)
        let endRecordSize = 22
        guard contents.count >= endRecordSize else { throw ZIPArchiveError.notAnArchive }

        // The end record is the last 22 bytes, unless an archive comment of up to 65,535
        // bytes follows it.
        let earliestEndRecord = max(0, contents.count - endRecordSize - Int(UInt16.max))
        var endRecord = contents.count - endRecordSize
        while try bytes.uint32(at: endRecord) != ZIPSignature.endOfCentralDirectory {
            endRecord -= 1
            guard endRecord >= earliestEndRecord else { throw ZIPArchiveError.notAnArchive }
        }

        var entryCount = UInt64(try bytes.uint16(at: endRecord + 10))
        var directoryOffset = UInt64(try bytes.uint32(at: endRecord + 16))
        let usesZIP64 = entryCount == UInt64(UInt16.max) || directoryOffset == UInt64(UInt32.max)
        if usesZIP64, endRecord >= 20, try bytes.uint32(at: endRecord - 20) == ZIPSignature.zip64EndOfCentralDirectoryLocator {
            let zip64EndRecord = try offset(try bytes.uint64(at: endRecord - 20 + 8))
            guard try bytes.uint32(at: zip64EndRecord) == ZIPSignature.zip64EndOfCentralDirectory else {
                throw ZIPArchiveError.corrupt
            }
            entryCount = try bytes.uint64(at: zip64EndRecord + 32)
            directoryOffset = try bytes.uint64(at: zip64EndRecord + 48)
        }

        var entries: [Entry] = []
        var cursor = try offset(directoryOffset)
        while UInt64(entries.count) < entryCount {
            guard try bytes.uint32(at: cursor) == ZIPSignature.centralDirectoryHeader else {
                throw ZIPArchiveError.corrupt
            }
            let flags = try bytes.uint16(at: cursor + 8)
            let method = try bytes.uint16(at: cursor + 10)
            var compressedSize = UInt64(try bytes.uint32(at: cursor + 20))
            var uncompressedSize = UInt64(try bytes.uint32(at: cursor + 24))
            let nameLength = Int(try bytes.uint16(at: cursor + 28))
            let extraLength = Int(try bytes.uint16(at: cursor + 30))
            let commentLength = Int(try bytes.uint16(at: cursor + 32))
            var localHeaderOffset = UInt64(try bytes.uint32(at: cursor + 42))
            let name = try bytes.data(at: cursor + 46, count: nameLength)
            let extra = try bytes.data(at: cursor + 46 + nameLength, count: extraLength)

            // ZIP64 stores sizes and offsets that don't fit in 32 bits in an extra field,
            // in this order, for just the values marked 0xFFFFFFFF.
            if let zip64 = try zip64Field(in: extra) {
                let field = ByteReader(zip64)
                var position = 0
                if uncompressedSize == UInt64(UInt32.max) {
                    uncompressedSize = try field.uint64(at: position)
                    position += 8
                }
                if compressedSize == UInt64(UInt32.max) {
                    compressedSize = try field.uint64(at: position)
                    position += 8
                }
                if localHeaderOffset == UInt64(UInt32.max) {
                    localHeaderOffset = try field.uint64(at: position)
                }
            }

            entries.append(Entry(
                path: entryPath(from: name),
                compressionMethod: method,
                isEncrypted: flags & 0x0001 != 0,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The data of the ZIP64 extended information field, if `extra` has one.
    private static func zip64Field(in extra: Data) throws -> Data? {
        let bytes = ByteReader(extra)
        var position = 0
        while position + 4 <= extra.count {
            let id = try bytes.uint16(at: position)
            let size = Int(try bytes.uint16(at: position + 2))
            if id == 0x0001 {
                return try bytes.data(at: position + 4, count: size)
            }
            position += 4 + size
        }
        return nil
    }

    /// Names are UTF-8 when flagged as such and in practice; anything else is read as
    /// Latin-1 so a name always decodes.
    private static func entryPath(from name: Data) -> String {
        String(data: name, encoding: .utf8) ?? String(decoding: name.map { UInt16($0) }, as: UTF16.self)
    }

    private static func offset(_ value: UInt64) throws -> Int {
        guard let offset = Int(exactly: value) else { throw ZIPArchiveError.corrupt }
        return offset
    }

    private static func inflate(_ compressed: Data, expectedSize: UInt64) throws -> Data {
        var output = Data()
        output.reserveCapacity(Int(min(expectedSize, 64 << 20)))
        do {
            // Compression's zlib algorithm reads raw DEFLATE data, which is what ZIP stores.
            let filter = try OutputFilter(.decompress, using: .zlib) { chunk in
                if let chunk { output.append(chunk) }
            }
            let chunkSize = 1 << 16
            var start = compressed.startIndex
            while start < compressed.endIndex {
                let end = min(start + chunkSize, compressed.endIndex)
                try filter.write(compressed[start..<end])
                start = end
            }
            try filter.finalize()
        } catch {
            throw ZIPArchiveError.corrupt
        }
        // Like the CRC, the recorded size isn't checked: some generators write it wrong,
        // and the XML parsers report content that's actually damaged.
        return output
    }
}

// MARK: - Supporting Types

nonisolated enum ZIPArchiveError: LocalizedError {
    case unreadable
    case notAnArchive
    case corrupt
    case unsupportedEntry
    case tooLarge
    case unwritable

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file couldn’t be read."
        case .notAnArchive: "The file isn’t a ZIP archive."
        case .corrupt: "The file is damaged."
        case .unsupportedEntry: "The file uses encryption or compression that isn’t supported."
        case .tooLarge: "The file is too large."
        case .unwritable: "The archive couldn’t be created."
        }
    }
}

nonisolated enum ZIPCompressionMethod: UInt16, Sendable {
    case stored = 0
    case deflated = 8
}

nonisolated enum ZIPSignature {
    static let localFileHeader: UInt32 = 0x0403_4B50
    static let centralDirectoryHeader: UInt32 = 0x0201_4B50
    static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    static let zip64EndOfCentralDirectory: UInt32 = 0x0606_4B50
    static let zip64EndOfCentralDirectoryLocator: UInt32 = 0x0706_4B50
}

/// Bounds-checked little-endian reads from data.
private nonisolated struct ByteReader {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    func uint16(at offset: Int) throws -> UInt16 {
        UInt16(littleEndian: try load(at: offset))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        UInt32(littleEndian: try load(at: offset))
    }

    func uint64(at offset: Int) throws -> UInt64 {
        UInt64(littleEndian: try load(at: offset))
    }

    /// `count` bytes starting at `offset`, sharing storage with the data.
    func data(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count - count else { throw ZIPArchiveError.corrupt }
        let start = data.startIndex + offset
        return data[start..<start + count]
    }

    private func load<Value: FixedWidthInteger>(at offset: Int) throws -> Value {
        let size = MemoryLayout<Value>.size
        guard offset >= 0, offset <= data.count - size else { throw ZIPArchiveError.corrupt }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Value.self) }
    }
}
