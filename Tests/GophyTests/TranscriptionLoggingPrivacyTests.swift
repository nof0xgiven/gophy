import XCTest

final class TranscriptionLoggingPrivacyTests: XCTestCase {
    func testTranscriptionLogsDoNotExposeTranscriptTextAsPublicOSLogData() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let files = [
            root.appendingPathComponent("Sources/Gophy/Audio/TranscriptionPipeline.swift"),
            root.appendingPathComponent("Sources/Gophy/Engines/TranscriptionEngine.swift")
        ]

        for file in files {
            let source = try String(contentsOf: file)
            XCTAssertFalse(
                source.contains("\\(segment.text, privacy: .public)"),
                "\(file.path) must not log raw transcript segment text as public OSLog data"
            )
            XCTAssertFalse(
                source.contains("\\(cleanedText, privacy: .public)"),
                "\(file.path) must not log cleaned transcript text as public OSLog data"
            )
        }
    }
}
