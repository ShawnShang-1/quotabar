import Foundation
import XCTest

final class PackageLocalAppScriptTests: XCTestCase {
    func testPackageScriptCreatesLocalAppBundle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root.appendingPathComponent("Scripts/package-local-app.sh").path
        let appBundle = root.appendingPathComponent("dist/QuotaBar.app")
        try? FileManager.default.removeItem(at: appBundle)

        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script, "--configuration", "debug", "--skip-build"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appBundle.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appBundle.appendingPathComponent("Contents/MacOS/QuotaBar").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appBundle.appendingPathComponent("Contents/Resources/AppIcon.placeholder.txt").path))

        let plistData = try Data(contentsOf: appBundle.appendingPathComponent("Contents/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "QuotaBar")
    }
}
