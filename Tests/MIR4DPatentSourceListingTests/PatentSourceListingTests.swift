import XCTest
@testable import MIR4DPatentSourceListing

final class PatentSourceListingTests: XCTestCase {
    func testCommentCleanerPreservesStringURLs() {
        let source = "let url = \"https://example.com/a//b\" // comment\n/* block */\nlet value = 42\n"
        let result = CommentCleaner().clean(source, language: "Swift")
        XCTAssertTrue(result.content.contains("https://example.com/a//b"))
        XCTAssertFalse(result.content.contains("// comment"))
        XCTAssertFalse(result.content.contains("block"))
        XCTAssertTrue(result.removedCommentCount >= 2)
    }

    func testCommentCleanerPreservesTripleQuotedText() {
        let source = """
        let text = \"\"\"
        https://example.com // not a comment
        # still text
        \"\"\"
        // real comment
        """
        let result = CommentCleaner().clean(source, language: "Swift")
        XCTAssertTrue(result.content.contains("// not a comment"))
        XCTAssertTrue(result.content.contains("# still text"))
        XCTAssertFalse(result.content.contains("// real comment"))
    }

    func testDiffAnalyzerFindsAddedFileAndDirectories() throws {
        let diff = """
        diff --git a/Sources/Core/Test.swift b/Sources/Core/Test.swift
        new file mode 100644
        --- /dev/null
        +++ b/Sources/Core/Test.swift
        @@ -0,0 +1,2 @@
        +import Foundation
        +let value = 1
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".diff")
        try Data(diff.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try DiffProjectAnalyzer().analyze(url: url)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.files[0].operation, .added)
        XCTAssertEqual(plan.files[0].path, "Sources/Core/Test.swift")
        XCTAssertTrue(plan.directories.contains("Sources/Core"))
        XCTAssertEqual(plan.files[0].additions, 2)
    }

    func testDiffAnalyzerCountsSourceLinesBeginningWithMarkers() throws {
        let diff = """
        diff --git a/Test.swift b/Test.swift
        --- a/Test.swift
        +++ b/Test.swift
        @@ -1,2 +1,2 @@
        ----old
        ++++new
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".diff")
        try Data(diff.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try DiffProjectAnalyzer().analyze(url: url)
        XCTAssertEqual(plan.files[0].additions, 1)
        XCTAssertEqual(plan.files[0].deletions, 1)
    }

    func testUnsafeDiffPathIsRejected() throws {
        let diff = """
        diff --git a/../../evil.swift b/../../evil.swift
        --- a/../../evil.swift
        +++ b/../../evil.swift
        @@ -1 +1 @@
        -old
        +new
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".diff")
        try Data(diff.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try DiffProjectAnalyzer().analyze(url: url))
    }
}
