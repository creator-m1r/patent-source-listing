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

    func testRTFExportRoundTripPreservesCyrillicAndRTFSpecialCharacters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = """\n        import Foundation
        
        namespace mir {
            let text = \"{привет} \\\\ путь\"
            // комментарий
            enum class Test : UInt8 { one = 0 }
        }
        """
        let sourceURL = root.appendingPathComponent("Core/Test.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: sourceURL)

        let scanner = ProjectScanner()
        let configuration = ListingConfiguration(
            includeExtensions: [],
            excludedDirectories: [],
            excludedFileNames: [],
            includeDocumentation: false,
            includeConfigurationFiles: false,
            includeEmptyFiles: true,
            removeComments: false,
            fontName: "Courier New",
            fontSize: 10,
            separatorWidth: 80,
            logicalOrder: true,
            pageNumbers: true,
            outputSizeLimitBytes: 4_900_000
        )
        let report = try scanner.scan(root: root, configuration: configuration)
        XCTAssertEqual(report.files.count, 1)
        XCTAssertEqual(report.files[0].content, source)
        XCTAssertFalse(report.files[0].sha256.isEmpty)

        let metadata = ProgramMetadata(
            programName: "МИР 4D",
            projectName: "Тест",
            version: "1.0",
            author: "Автор",
            copyrightHolder: "Правообладатель",
            organization: "Организация",
            organizationAddress: "Адрес",
            contact: "Контакт",
            programmingLanguages: "Swift",
            creationDate: "22.08.2026",
            registrationDate: "",
            notes: ""
        )

        let output = root.appendingPathComponent("listing.rtf")
        try RTFExporter().export(metadata: metadata, report: report, configuration: configuration, to: output)
        let rtfData = try Data(contentsOf: output)
        XCTAssertFalse(rtfData.isEmpty)
        XCTAssertLessThanOrEqual(rtfData.count, 4_900_000)
    }

    func testRTFSizeLimitIsEnforced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Test.swift")
        try Data(String(repeating: "let value = \"МИР 4D\"\n", count: 500).utf8).write(to: sourceURL)
        let scanner = ProjectScanner()
        var configuration = ListingConfiguration.default
        configuration.excludedDirectories = []
        configuration.outputSizeLimitBytes = 100
        let report = try scanner.scan(root: root, configuration: configuration)
        XCTAssertThrowsError(try RTFExporter().export(metadata: ProgramMetadata(), report: report, configuration: configuration, to: root.appendingPathComponent("too-large.rtf"))) { error in
            guard case RTFExportError.sizeLimitExceeded = error else {
                XCTFail("Ожидалась ошибка превышения лимита")
                return
            }
        }
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
