import XCTest
@testable import Gophy

@MainActor
final class AppDependenciesTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyAppDependenciesTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testDatabaseIsCachedForAppSurfaceReuse() throws {
        let dependencies = AppDependencies(
            storageManager: StorageManager(baseDirectory: tempDirectory)
        )

        let first = try dependencies.database()
        let second = try dependencies.database()

        XCTAssertTrue(first === second)
    }
}
