import XCTest
@testable import GhostEditCore

final class PythonEnvironmentSupportTests: XCTestCase {

    // MARK: - PythonEnvironmentStatus

    func testPythonEnvironmentStatusEquality() {
        XCTAssertEqual(PythonEnvironmentStatus.ready, PythonEnvironmentStatus.ready)
        XCTAssertEqual(PythonEnvironmentStatus.pythonNotFound, PythonEnvironmentStatus.pythonNotFound)
        XCTAssertEqual(
            PythonEnvironmentStatus.pythonTooOld(version: "3.7.0"),
            PythonEnvironmentStatus.pythonTooOld(version: "3.7.0")
        )
        XCTAssertEqual(
            PythonEnvironmentStatus.packagesNotInstalled(missing: ["torch"]),
            PythonEnvironmentStatus.packagesNotInstalled(missing: ["torch"])
        )
        XCTAssertNotEqual(PythonEnvironmentStatus.ready, PythonEnvironmentStatus.pythonNotFound)
    }

    // MARK: - requiredPackages

    func testRequiredPackagesContainsExpected() {
        XCTAssertEqual(PythonEnvironmentSupport.requiredPackages, ["transformers", "torch"])
    }

    // MARK: - parsePythonVersion

    func testParsePythonVersionStandard() {
        let result = PythonEnvironmentSupport.parsePythonVersion("Python 3.11.2")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 11)
        XCTAssertEqual(result?.2, 2)
    }

    func testParsePythonVersionBareNumber() {
        let result = PythonEnvironmentSupport.parsePythonVersion("3.9.7")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 9)
        XCTAssertEqual(result?.2, 7)
    }

    func testParsePythonVersionMajorMinorOnly() {
        let result = PythonEnvironmentSupport.parsePythonVersion("Python 3.10")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 10)
        XCTAssertEqual(result?.2, 0)
    }

    func testParsePythonVersionWithWhitespace() {
        let result = PythonEnvironmentSupport.parsePythonVersion("  Python 3.12.0  \n")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 12)
        XCTAssertEqual(result?.2, 0)
    }

    func testParsePythonVersionInvalid() {
        XCTAssertNil(PythonEnvironmentSupport.parsePythonVersion(""))
        XCTAssertNil(PythonEnvironmentSupport.parsePythonVersion("Python"))
        XCTAssertNil(PythonEnvironmentSupport.parsePythonVersion("not a version"))
        XCTAssertNil(PythonEnvironmentSupport.parsePythonVersion("Python abc.def"))
    }

    func testParsePythonVersionCaseInsensitivePrefix() {
        let result = PythonEnvironmentSupport.parsePythonVersion("python 3.11.5")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 11)
        XCTAssertEqual(result?.2, 5)
    }

    func testParsePythonVersionNonNumericPatch() {
        // Covers the ?? 0 fallback when patch is non-numeric (e.g., "3.10.rc1")
        let result = PythonEnvironmentSupport.parsePythonVersion("Python 3.10.rc1")
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result?.1, 10)
        XCTAssertEqual(result?.2, 0)
    }

    // MARK: - meetsMinimumVersion

    func testMeetsMinimumVersionPython39() {
        XCTAssertTrue(PythonEnvironmentSupport.meetsMinimumVersion(major: 3, minor: 9))
    }

    func testMeetsMinimumVersionPython311() {
        XCTAssertTrue(PythonEnvironmentSupport.meetsMinimumVersion(major: 3, minor: 11))
    }

    func testMeetsMinimumVersionPython4() {
        XCTAssertTrue(PythonEnvironmentSupport.meetsMinimumVersion(major: 4, minor: 0))
    }

    func testMeetsMinimumVersionPython38TooOld() {
        XCTAssertFalse(PythonEnvironmentSupport.meetsMinimumVersion(major: 3, minor: 8))
    }

    func testMeetsMinimumVersionPython2() {
        XCTAssertFalse(PythonEnvironmentSupport.meetsMinimumVersion(major: 2, minor: 7))
    }

    // MARK: - pipInstallCommand

    func testPipInstallCommand() {
        let cmd = PythonEnvironmentSupport.pipInstallCommand(pythonPath: "/usr/bin/python3")
        XCTAssertTrue(cmd.contains("--index-url https://pypi.org/simple/"))
        XCTAssertTrue(cmd.contains("transformers"))
        XCTAssertTrue(cmd.contains("torch"))
        XCTAssertTrue(cmd.contains("--upgrade"))
        XCTAssertTrue(cmd.hasPrefix("/usr/bin/python3"))
    }

    func testPipInstallCommandCustomPath() {
        let cmd = PythonEnvironmentSupport.pipInstallCommand(pythonPath: "/opt/homebrew/bin/python3")
        XCTAssertTrue(cmd.hasPrefix("/opt/homebrew/bin/python3"))
        XCTAssertTrue(cmd.contains("transformers"))
    }

    // MARK: - parseInstalledPackages

    func testParseInstalledPackagesStandardOutput() {
        let output = """
            Package         Version
            --------------- -------
            transformers    4.35.0
            torch           2.1.0
            numpy           1.26.0
            """
        let packages = PythonEnvironmentSupport.parseInstalledPackages(output)
        XCTAssertTrue(packages.contains("transformers"))
        XCTAssertTrue(packages.contains("torch"))
        XCTAssertTrue(packages.contains("numpy"))
        XCTAssertEqual(packages.count, 3)
    }

    func testParseInstalledPackagesEmptyOutput() {
        let packages = PythonEnvironmentSupport.parseInstalledPackages("")
        XCTAssertTrue(packages.isEmpty)
    }

    func testParseInstalledPackagesHeaderOnly() {
        let output = """
            Package    Version
            ---------- -------
            """
        let packages = PythonEnvironmentSupport.parseInstalledPackages(output)
        XCTAssertTrue(packages.isEmpty)
    }

    func testParseInstalledPackagesNormalizesCase() {
        let output = """
            Package    Version
            ---------- -------
            Torch      2.1.0
            """
        let packages = PythonEnvironmentSupport.parseInstalledPackages(output)
        XCTAssertTrue(packages.contains("torch"))
    }

    // MARK: - missingPackages

    func testMissingPackagesAllInstalled() {
        let installed: Set<String> = ["transformers", "torch"]
        let missing = PythonEnvironmentSupport.missingPackages(installed: installed)
        XCTAssertTrue(missing.isEmpty)
    }

    func testMissingPackagesNoneInstalled() {
        let missing = PythonEnvironmentSupport.missingPackages(installed: [])
        XCTAssertEqual(Set(missing), Set(["transformers", "torch"]))
    }

    func testMissingPackagesPartiallyInstalled() {
        let installed: Set<String> = ["torch"]
        let missing = PythonEnvironmentSupport.missingPackages(installed: installed)
        XCTAssertEqual(missing, ["transformers"])
    }

    func testMissingPackagesCaseInsensitive() {
        let installed: Set<String> = ["Transformers", "TORCH"]
        let missing = PythonEnvironmentSupport.missingPackages(installed: installed)
        XCTAssertTrue(missing.isEmpty)
    }

    // MARK: - pythonSearchPaths

    func testPythonSearchPathsContainsExpectedPaths() {
        let paths = PythonEnvironmentSupport.pythonSearchPaths(homeDirectoryPath: "/Users/testuser")
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/python3"))
        XCTAssertTrue(paths.contains("/usr/local/bin/python3"))
        XCTAssertTrue(paths.contains("/usr/bin/python3"))
        XCTAssertTrue(paths.contains("/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"))
        XCTAssertTrue(paths.contains("/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"))
        XCTAssertTrue(paths.contains("/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Python/3.13/bin/python3"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Python/3.12/bin/python3"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Python/3.11/bin/python3"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Python/3.10/bin/python3"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Python/3.9/bin/python3"))
    }

    func testPythonSearchPathsCount() {
        let paths = PythonEnvironmentSupport.pythonSearchPaths(homeDirectoryPath: "/home/user")
        XCTAssertEqual(paths.count, 11)
    }

    func testPythonSearchPathsUsesHomeDirectory() {
        let paths = PythonEnvironmentSupport.pythonSearchPaths(homeDirectoryPath: "/custom/home")
        XCTAssertTrue(paths.contains("/custom/home/Library/Python/3.11/bin/python3"))
        XCTAssertTrue(paths.contains("/custom/home/Library/Python/3.13/bin/python3"))
    }
}
