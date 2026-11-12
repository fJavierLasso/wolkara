import Foundation
import CryptoKit
import ZIPFoundation

// Matches upstream scripts/package.py for Touchbars 0.7.0 at
// 6ac5bf2e02dba2e2160cf444eef533a4e0118b91. Only the addon and its MIT license
// are downloaded on opt-in; no third-party code or art is bundled in Wolkara.
@objc(TKTouchbarsArchive)
final class TKTouchbarsArchive: NSObject {
    private static let fingerprints = [
        "SPTouchBars.toc": "5edd599b282f559633d38253f5574d82809d13ff7ef59019fba76c663fdc455b",
        "SPTouchBars.lua": "389f8f460524841c1527bc59b399392ab9659abb82c1d927cbab08ab7f858618",
        "SPTouchBars.tga": "c1ff43928d13e89412027a738cae50e62cf91abf33e9f90d9b3ace1435aa0558",
        "LICENSE": "73d0323583395c7049acf60008498f70abb62d4ce273ba8e43805f0222785afe",
    ]

    @objc(writeFiles:toURL:error:)
    static func write(files: [String: Data], to url: URL, error output: NSErrorPointer) -> Bool {
        func fail(_ message: String) -> Bool {
            output?.pointee = NSError(domain: "Wolkara.Touchbars", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: message])
            return false
        }
        guard Set(files.keys) == Set(fingerprints.keys) else {
            return fail("The Touchbars download is incomplete. Nothing was installed.")
        }
        for (name, expected) in fingerprints {
            guard let data = files[name], data.count <= 2 * 1024 * 1024,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else {
                return fail("Touchbars failed its integrity check. Nothing was installed.")
            }
        }
        guard url.isFileURL, !FileManager.default.fileExists(atPath: url.path) else {
            return fail("The Touchbars staging destination already exists.")
        }
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for name in files.keys.sorted() {
                let data = files[name]!
                try archive.addEntry(with: "SPTouchBars/" + name, type: .file,
                                     uncompressedSize: Int64(data.count), permissions: 0o644,
                                     compressionMethod: .deflate) { position, count in
                    let start = Int(position)
                    return data.subdata(in: start..<min(start + count, data.count))
                }
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            output?.pointee = error as NSError
            return false
        }
    }
}
