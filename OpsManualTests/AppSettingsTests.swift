import XCTest
@testable import OpsManual

final class AppSettingsTests: XCTestCase {
    func testDefaultDocumentsPathIsUnderDocuments() {
        XCTAssertTrue(AppSettings.defaultDocumentsPath.hasSuffix("/Documents/Personal Ops Manual"))
    }

    func testDocumentsURLFallsBackToDefaultWhenUnset() {
        let path = UserDefaults.standard.string(forKey: AppSettings.documentsPathKey) ?? ""
        if path.isEmpty {
            XCTAssertEqual(AppSettings.documentsURL.path, AppSettings.defaultDocumentsPath)
        } else {
            XCTAssertEqual(AppSettings.documentsURL.path, path)
        }
    }
}
