import XCTest
@testable import GhostEditCore

final class LocalModelSupportTests: XCTestCase {

    // MARK: - LocalModelStatus

    func testLocalModelStatusRawValues() {
        XCTAssertEqual(LocalModelStatus.notDownloaded.rawValue, "notDownloaded")
        XCTAssertEqual(LocalModelStatus.downloading.rawValue, "downloading")
        XCTAssertEqual(LocalModelStatus.ready.rawValue, "ready")
        XCTAssertEqual(LocalModelStatus.error.rawValue, "error")
    }

    func testLocalModelStatusCodable() throws {
        let statuses: [LocalModelStatus] = [.notDownloaded, .downloading, .ready, .error]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(LocalModelStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - LocalModelEntry

    func testLocalModelEntryDefaults() {
        let entry = LocalModelEntry(
            repoID: "org/model",
            displayName: "Model",
            parameterCount: "100M",
            approxDiskGB: 1.0
        )
        XCTAssertEqual(entry.status, .notDownloaded)
        XCTAssertEqual(entry.localPath, "")
    }

    func testLocalModelEntryCustomValues() {
        let entry = LocalModelEntry(
            repoID: "org/model",
            displayName: "Model",
            parameterCount: "100M",
            approxDiskGB: 1.0,
            status: .ready,
            localPath: "/tmp/model"
        )
        XCTAssertEqual(entry.repoID, "org/model")
        XCTAssertEqual(entry.displayName, "Model")
        XCTAssertEqual(entry.parameterCount, "100M")
        XCTAssertEqual(entry.approxDiskGB, 1.0)
        XCTAssertEqual(entry.status, .ready)
        XCTAssertEqual(entry.localPath, "/tmp/model")
    }

    func testLocalModelEntryCodable() throws {
        let entry = LocalModelEntry(
            repoID: "grammarly/coedit-large",
            displayName: "CoEdIT Large",
            parameterCount: "770M",
            approxDiskGB: 3.0,
            status: .ready,
            localPath: "/path/to/model"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LocalModelEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testLocalModelEntryDecodesWithoutTaskPrefix() throws {
        // Simulate old JSON without taskPrefix field
        let json = """
        {"repoID":"org/model","displayName":"M","parameterCount":"1M","approxDiskGB":0.5,"status":"ready","localPath":"/path"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LocalModelEntry.self, from: data)
        XCTAssertEqual(decoded.repoID, "org/model")
        XCTAssertEqual(decoded.taskPrefix, "Fix grammatical errors in this sentence: ")
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertEqual(decoded.localPath, "/path")
    }

    func testLocalModelEntryDecodesWithTaskPrefix() throws {
        let json = """
        {"repoID":"org/model","displayName":"M","parameterCount":"1M","approxDiskGB":0.5,"taskPrefix":"grammar: "}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LocalModelEntry.self, from: data)
        XCTAssertEqual(decoded.taskPrefix, "grammar: ")
        XCTAssertEqual(decoded.status, .notDownloaded)
        XCTAssertEqual(decoded.localPath, "")
    }

    func testLocalModelEntryDecodesMinimalJSON() throws {
        let json = """
        {"repoID":"a/b","displayName":"X","parameterCount":"10M","approxDiskGB":1.0}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LocalModelEntry.self, from: data)
        XCTAssertEqual(decoded.repoID, "a/b")
        XCTAssertEqual(decoded.status, .notDownloaded)
        XCTAssertEqual(decoded.localPath, "")
        XCTAssertEqual(decoded.taskPrefix, "Fix grammatical errors in this sentence: ")
    }

    func testLocalModelEntryEquality() {
        let a = LocalModelEntry(
            repoID: "org/model", displayName: "M", parameterCount: "1M", approxDiskGB: 0.1
        )
        let b = LocalModelEntry(
            repoID: "org/model", displayName: "M", parameterCount: "1M", approxDiskGB: 0.1
        )
        XCTAssertEqual(a, b)

        let c = LocalModelEntry(
            repoID: "org/other", displayName: "M", parameterCount: "1M", approxDiskGB: 0.1
        )
        XCTAssertNotEqual(a, c)
    }

    // MARK: - recommendedModels

    func testRecommendedModelsHasThreeEntries() {
        XCTAssertEqual(LocalModelSupport.recommendedModels.count, 3)
    }

    func testRecommendedModelsContainsExpectedModels() {
        let repoIDs = LocalModelSupport.recommendedModels.map(\.repoID)
        XCTAssertTrue(repoIDs.contains("vennify/t5-base-grammar-correction"))
        XCTAssertTrue(repoIDs.contains("grammarly/coedit-large"))
        XCTAssertTrue(repoIDs.contains("grammarly/coedit-xl"))
    }

    func testRecommendedModelsAllNotDownloaded() {
        for model in LocalModelSupport.recommendedModels {
            XCTAssertEqual(model.status, .notDownloaded)
            XCTAssertEqual(model.localPath, "")
        }
    }

    func testRecommendedModelsHaveValidRepoIDs() {
        for model in LocalModelSupport.recommendedModels {
            XCTAssertTrue(LocalModelSupport.isValidRepoID(model.repoID), "\(model.repoID) should be valid")
        }
    }

    // MARK: - modelsDirectoryURL

    func testModelsDirectoryURL() {
        let base = URL(fileURLWithPath: "/Users/test/.ghostedit")
        let result = LocalModelSupport.modelsDirectoryURL(baseDirectoryURL: base)
        XCTAssertEqual(result.path, "/Users/test/.ghostedit/models")
    }

    // MARK: - modelDirectoryURL

    func testModelDirectoryURLConvertsSlashToDash() {
        let base = URL(fileURLWithPath: "/Users/test/.ghostedit")
        let result = LocalModelSupport.modelDirectoryURL(baseDirectoryURL: base, repoID: "grammarly/coedit-large")
        XCTAssertEqual(result.path, "/Users/test/.ghostedit/models/grammarly--coedit-large")
    }

    func testModelDirectoryURLWithNestedSlashes() {
        let base = URL(fileURLWithPath: "/home/.ghostedit")
        let result = LocalModelSupport.modelDirectoryURL(baseDirectoryURL: base, repoID: "org/sub/model")
        XCTAssertEqual(result.path, "/home/.ghostedit/models/org--sub--model")
    }

    // MARK: - taskPrefix

    func testTaskPrefixForCoEdit() {
        let prefix = LocalModelSupport.taskPrefix(for: "grammarly/coedit-large")
        XCTAssertEqual(prefix, "Fix grammatical errors in this sentence: ")
    }

    func testTaskPrefixForT5Grammar() {
        let prefix = LocalModelSupport.taskPrefix(for: "vennify/t5-base-grammar-correction")
        XCTAssertEqual(prefix, "grammar: ")
    }

    func testTaskPrefixForUnknownModelUsesDefault() {
        let prefix = LocalModelSupport.taskPrefix(for: "unknown/model")
        XCTAssertEqual(prefix, "Fix grammatical errors in this sentence: ")
    }

    // MARK: - isValidRepoID

    func testIsValidRepoIDAcceptsOrgSlashModel() {
        XCTAssertTrue(LocalModelSupport.isValidRepoID("grammarly/coedit-large"))
        XCTAssertTrue(LocalModelSupport.isValidRepoID("facebook/bart-large"))
        XCTAssertTrue(LocalModelSupport.isValidRepoID("org_name/model.v2"))
    }

    func testIsValidRepoIDRejectsInvalid() {
        XCTAssertFalse(LocalModelSupport.isValidRepoID(""))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("noslash"))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("/model"))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("org/"))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("a/b/c"))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("org/model name"))
        XCTAssertFalse(LocalModelSupport.isValidRepoID("org/model@1"))
    }

    func testIsValidRepoIDTrimsWhitespace() {
        XCTAssertTrue(LocalModelSupport.isValidRepoID("  grammarly/coedit-large  "))
    }

    // MARK: - extractRepoID

    func testExtractRepoIDFromDirectRepoID() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "grammarly/coedit-large"),
            "grammarly/coedit-large"
        )
    }

    func testExtractRepoIDFromHuggingFaceURL() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "https://huggingface.co/grammarly/coedit-large"),
            "grammarly/coedit-large"
        )
    }

    func testExtractRepoIDFromHuggingFaceURLWithTrailingSlash() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "https://huggingface.co/grammarly/coedit-large/"),
            "grammarly/coedit-large"
        )
    }

    func testExtractRepoIDFromWWWHuggingFaceURL() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "https://www.huggingface.co/facebook/bart-large"),
            "facebook/bart-large"
        )
    }

    func testExtractRepoIDFromHuggingFaceURLWithExtraPaths() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "https://huggingface.co/grammarly/coedit-large/tree/main"),
            "grammarly/coedit-large"
        )
    }

    func testExtractRepoIDReturnsNilForInvalidURL() {
        XCTAssertNil(LocalModelSupport.extractRepoID(from: "https://github.com/grammarly/coedit-large"))
        XCTAssertNil(LocalModelSupport.extractRepoID(from: "https://huggingface.co/onlyorg"))
        XCTAssertNil(LocalModelSupport.extractRepoID(from: "not a url at all"))
        XCTAssertNil(LocalModelSupport.extractRepoID(from: ""))
    }

    func testExtractRepoIDTrimsWhitespace() {
        XCTAssertEqual(
            LocalModelSupport.extractRepoID(from: "  grammarly/coedit-large  "),
            "grammarly/coedit-large"
        )
    }

    // MARK: - mergedModelList

    func testMergedModelListWithNoSavedModels() {
        let result = LocalModelSupport.mergedModelList(saved: [], downloaded: [])
        XCTAssertEqual(result.count, 3)
        for entry in result {
            XCTAssertEqual(entry.status, .notDownloaded)
        }
    }

    func testMergedModelListMarksDownloadedAsReady() {
        let result = LocalModelSupport.mergedModelList(
            saved: [],
            downloaded: ["grammarly/coedit-large"]
        )
        let large = result.first(where: { $0.repoID == "grammarly/coedit-large" })
        XCTAssertEqual(large?.status, .ready)

        let t5base = result.first(where: { $0.repoID == "vennify/t5-base-grammar-correction" })
        XCTAssertEqual(t5base?.status, .notDownloaded)
    }

    func testMergedModelListIncludesCustomModels() {
        let custom = LocalModelEntry(
            repoID: "custom/model",
            displayName: "Custom",
            parameterCount: "500M",
            approxDiskGB: 2.0
        )
        let result = LocalModelSupport.mergedModelList(
            saved: [custom],
            downloaded: ["custom/model"]
        )
        XCTAssertEqual(result.count, 4)
        let customResult = result.first(where: { $0.repoID == "custom/model" })
        XCTAssertEqual(customResult?.status, .ready)
        XCTAssertEqual(customResult?.displayName, "Custom")
    }

    func testMergedModelListUpdatesLocalPathFromSaved() {
        let savedLarge = LocalModelEntry(
            repoID: "grammarly/coedit-large",
            displayName: "CoEdIT Large",
            parameterCount: "770M",
            approxDiskGB: 3.0,
            localPath: "/models/coedit-large"
        )
        let result = LocalModelSupport.mergedModelList(
            saved: [savedLarge],
            downloaded: ["grammarly/coedit-large"]
        )
        let large = result.first(where: { $0.repoID == "grammarly/coedit-large" })
        XCTAssertEqual(large?.localPath, "/models/coedit-large")
        XCTAssertEqual(large?.status, .ready)
    }

    func testMergedModelListDoesNotDuplicateRecommended() {
        let savedDuplicate = LocalModelEntry(
            repoID: "vennify/t5-base-grammar-correction",
            displayName: "T5 Base Custom",
            parameterCount: "220M",
            approxDiskGB: 0.9
        )
        let result = LocalModelSupport.mergedModelList(
            saved: [savedDuplicate],
            downloaded: []
        )
        let t5Entries = result.filter { $0.repoID == "vennify/t5-base-grammar-correction" }
        XCTAssertEqual(t5Entries.count, 1)
    }

    func testMergedModelListCustomNotDownloaded() {
        let custom = LocalModelEntry(
            repoID: "custom/model",
            displayName: "Custom",
            parameterCount: "500M",
            approxDiskGB: 2.0,
            status: .ready
        )
        let result = LocalModelSupport.mergedModelList(
            saved: [custom],
            downloaded: []
        )
        let customResult = result.first(where: { $0.repoID == "custom/model" })
        XCTAssertEqual(customResult?.status, .notDownloaded)
    }
}
