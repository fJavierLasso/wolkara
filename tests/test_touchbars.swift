import Foundation
import ZIPFoundation

@_silgen_name("TestTouchbars")
func testTouchbars(_ directory: UnsafePointer<CChar>)

@main
struct TouchbarsTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ name: String, folders: [String]) throws {
            let archive = try Archive(url: root.appendingPathComponent(name), accessMode: .create)
            for folder in folders {
                let bytes = Data("## Interface: 16001\n## Title: Synthetic \(folder)\n## Version: fixture\n".utf8)
                try archive.addEntry(with: folder + "/" + folder + ".toc", type: .file,
                                     uncompressedSize: Int64(bytes.count)) { position, count in
                    let start = Int(position)
                    return bytes.subdata(in: start..<min(start + count, bytes.count))
                }
            }
        }
        try fixture("fixture.zip", folders: ["SPTouchBars"])
        try fixture("bundle.zip", folders: ["SPTouchBars", "KeepOtherAddon"])
        root.path.withCString { testTouchbars($0) }
        var error: NSError?
        let output = root.appendingPathComponent("rejected.zip")
        assert(!TKTouchbarsArchive.write(files: [:], to: output, error: &error) && error != nil)
        var files = Dictionary(uniqueKeysWithValues: ["SPTouchBars.lua", "SPTouchBars.toc", "SPTouchBars.tga", "LICENSE"].map { ($0, Data("untrusted".utf8)) })
        assert(!TKTouchbarsArchive.write(files: files, to: output, error: &error))
        assert(!FileManager.default.fileExists(atPath: output.path))
        // Optional integration evidence with separately downloaded upstream bytes.
        // Never vendor or execute third-party game Lua in the regression fixture.
        if CommandLine.arguments.count > 1 {
            let source = URL(fileURLWithPath: CommandLine.arguments[1])
            for name in files.keys { files[name] = try Data(contentsOf: source.appendingPathComponent(name)) }
            let zip = root.appendingPathComponent("upstream.zip")
            assert(TKTouchbarsArchive.write(files: files, to: zip, error: &error), error?.localizedDescription ?? "packaging")
            let unpacked = root.appendingPathComponent("unpacked")
            assert(TKAddonArchive.extract(archiveURL: zip, to: unpacked, error: &error))
            let names = try FileManager.default.contentsOfDirectory(atPath: unpacked.appendingPathComponent("SPTouchBars").path)
            assert(Set(names) == Set(files.keys))
            for (name, data) in files {
                let installed = try Data(contentsOf: unpacked.appendingPathComponent("SPTouchBars/" + name))
                assert(installed == data)
            }
            let original = try Data(contentsOf: zip)
            assert(!TKTouchbarsArchive.write(files: files, to: zip, error: &error))
            let unchanged = try Data(contentsOf: zip); assert(unchanged == original)
            files["SPTouchBars.lua"]!.append(0)
            assert(!TKTouchbarsArchive.write(files: files, to: output, error: &error))
            assert(!FileManager.default.fileExists(atPath: output.path))
            print("TOUCHBARS UPSTREAM PASS: pinned hashes, exact four-file package including MIT license, unchanged bytes and tamper rejection")
        }
        print("TOUCHBARS ARCHIVE PASS: missing files and wrong hashes refused before installation")
    }
}
