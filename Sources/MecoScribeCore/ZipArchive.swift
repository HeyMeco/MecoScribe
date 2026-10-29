import Compression
import Foundation

/// Minimal ZIP reader/writer (stored and deflate entries, no ZIP64), enough for
/// `.mscribe` containers and for archives re-zipped by Finder or `zip`.
public enum ZipArchive {
    public struct Entry: Sendable {
        public var name: String
        public var data: Data
        public var modified: Date

        public init(name: String, data: Data, modified: Date = Date()) {
            self.name = name
            self.data = data
            self.modified = modified
        }
    }

    public enum ZipError: LocalizedError {
        case notAZipFile
        case corrupt(String)
        case unsupportedCompression(name: String, method: UInt16)
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .notAZipFile:
                return "The file is not a valid archive."
            case .corrupt(let detail):
                return "The archive is damaged (\(detail))."
            case .unsupportedCompression(let name, let method):
                return "“\(name)” uses an unsupported compression method (\(method))."
            case .tooLarge:
                return "The archive is too large."
            }
        }
    }

    // MARK: Writing

    public static func data(for entries: [Entry]) throws -> Data {
        var archive = Data()
        var central = Data()

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let deflated = deflate(entry.data)
            let method: UInt16 = deflated == nil ? 0 : 8
            let payload = deflated ?? entry.data
            guard archive.count < UInt32.max, payload.count < UInt32.max, entry.data.count < UInt32.max else {
                throw ZipError.tooLarge
            }
            let (dosTime, dosDate) = dosDateTime(entry.modified)
            let offset = UInt32(archive.count)

            // Local file header. Bit 11: names are UTF-8.
            archive.appendUInt32(0x0403_4b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0x0800)
            archive.appendUInt16(method)
            archive.appendUInt16(dosTime)
            archive.appendUInt16(dosDate)
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(payload.count))
            archive.appendUInt32(UInt32(entry.data.count))
            archive.appendUInt16(UInt16(nameBytes.count))
            archive.appendUInt16(0)
            archive.append(nameBytes)
            archive.append(payload)

            // Central directory record.
            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(0x031E) // made by: Unix, spec 3.0
            central.appendUInt16(20)
            central.appendUInt16(0x0800)
            central.appendUInt16(method)
            central.appendUInt16(dosTime)
            central.appendUInt16(dosDate)
            central.appendUInt32(crc)
            central.appendUInt32(UInt32(payload.count))
            central.appendUInt32(UInt32(entry.data.count))
            central.appendUInt16(UInt16(nameBytes.count))
            central.appendUInt16(0) // extra
            central.appendUInt16(0) // comment
            central.appendUInt16(0) // disk
            central.appendUInt16(0) // internal attributes
            central.appendUInt32(0o100644 << 16) // external attributes: regular file, rw-r--r--
            central.appendUInt32(offset)
            central.append(nameBytes)
        }

        guard entries.count < UInt16.max, archive.count < UInt32.max else { throw ZipError.tooLarge }
        let centralOffset = UInt32(archive.count)
        archive.append(central)

        // End of central directory.
        archive.appendUInt32(0x0605_4b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(central.count))
        archive.appendUInt32(centralOffset)
        archive.appendUInt16(0)
        return archive
    }

    public static func write(_ entries: [Entry], to url: URL) throws {
        try data(for: entries).write(to: url, options: .atomic)
    }

    // MARK: Reading

    /// Returns every file entry keyed by its path inside the archive. Directory
    /// entries and macOS resource forks (`__MACOSX/`) are skipped.
    public static func read(_ archive: Data) throws -> [String: Data] {
        let bytes = [UInt8](archive)
        guard let end = findEndOfCentralDirectory(bytes) else { throw ZipError.notAZipFile }
        let count = Int(bytes.uint16(at: end + 10))
        var cursor = Int(bytes.uint32(at: end + 16))
        var files: [String: Data] = [:]

        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes.uint32(at: cursor) == 0x0201_4b50 else {
                throw ZipError.corrupt("central directory")
            }
            let method = bytes.uint16(at: cursor + 10)
            let crc = bytes.uint32(at: cursor + 16)
            let compressedSize = Int(bytes.uint32(at: cursor + 20))
            let size = Int(bytes.uint32(at: cursor + 24))
            let nameLength = Int(bytes.uint16(at: cursor + 28))
            let extraLength = Int(bytes.uint16(at: cursor + 30))
            let commentLength = Int(bytes.uint16(at: cursor + 32))
            let localOffset = Int(bytes.uint32(at: cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.corrupt("entry name") }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") || name.hasPrefix("__MACOSX/") { continue }

            guard localOffset + 30 <= bytes.count, bytes.uint32(at: localOffset) == 0x0403_4b50 else {
                throw ZipError.corrupt("local header for \(name)")
            }
            let start = localOffset + 30
                + Int(bytes.uint16(at: localOffset + 26))
                + Int(bytes.uint16(at: localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.corrupt("data for \(name)") }
            let payload = Data(bytes[start..<(start + compressedSize)])

            let data: Data
            switch method {
            case 0:
                data = payload
            case 8:
                guard let inflated = inflate(payload, expectedSize: size) else {
                    throw ZipError.corrupt("could not decompress \(name)")
                }
                data = inflated
            default:
                throw ZipError.unsupportedCompression(name: name, method: method)
            }
            guard data.count == size, CRC32.checksum(data) == crc else {
                throw ZipError.corrupt("checksum mismatch for \(name)")
            }
            files[name] = data
        }
        return files
    }

    public static func read(contentsOf url: URL) throws -> [String: Data] {
        try read(Data(contentsOf: url))
    }

    private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        // The record is 22 bytes plus a comment of up to 64 KB.
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowest {
            if bytes.uint32(at: index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    // MARK: Compression

    /// Raw DEFLATE (what ZIP stores). Returns nil when compressing does not help.
    private static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        let capacity = data.count
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written
        return output
    }

    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        guard !data.isEmpty else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { return nil }
        return output
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = max(1980, min(2107, parts.year ?? 1980))
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

private extension [UInt8] {
    func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
