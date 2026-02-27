import XCTest
@testable import GhostEditCore

final class HardwareCompatibilitySupportTests: XCTestCase {

    // MARK: - HardwareInfo

    func testHardwareInfoEquality() {
        let a = HardwareInfo(totalRAMBytes: 16_000_000_000, availableDiskBytes: 100_000_000_000, architecture: "arm64")
        let b = HardwareInfo(totalRAMBytes: 16_000_000_000, availableDiskBytes: 100_000_000_000, architecture: "arm64")
        XCTAssertEqual(a, b)
    }

    func testHardwareInfoInequality() {
        let a = HardwareInfo(totalRAMBytes: 16_000_000_000, availableDiskBytes: 100_000_000_000, architecture: "arm64")
        let b = HardwareInfo(totalRAMBytes: 8_000_000_000, availableDiskBytes: 100_000_000_000, architecture: "arm64")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ModelRecommendation

    func testModelRecommendationRawValues() {
        XCTAssertEqual(ModelRecommendation.recommended.rawValue, "recommended")
        XCTAssertEqual(ModelRecommendation.compatible.rawValue, "compatible")
        XCTAssertEqual(ModelRecommendation.notRecommended.rawValue, "notRecommended")
    }

    // MARK: - estimatedRAMGB

    func testEstimatedRAMGB() {
        XCTAssertEqual(HardwareCompatibilitySupport.estimatedRAMGB(modelDiskGB: 3.0), 6.0)
        XCTAssertEqual(HardwareCompatibilitySupport.estimatedRAMGB(modelDiskGB: 0.3), 0.6)
        XCTAssertEqual(HardwareCompatibilitySupport.estimatedRAMGB(modelDiskGB: 11.0), 22.0)
    }

    // MARK: - recommendation

    func testRecommendationRecommended() {
        // 16GB RAM, 50GB disk, model is 3GB → needs 3.6GB disk, 6GB RAM, 9GB for recommended
        let hw = HardwareInfo(
            totalRAMBytes: UInt64(16.0 * 1_073_741_824.0),
            availableDiskBytes: UInt64(50.0 * 1_073_741_824.0),
            architecture: "arm64"
        )
        let result = HardwareCompatibilitySupport.recommendation(modelDiskGB: 3.0, hardware: hw)
        XCTAssertEqual(result, .recommended)
    }

    func testRecommendationCompatible() {
        // 7GB RAM, 50GB disk, model is 3GB → needs 6GB RAM (just enough), but 9GB for recommended
        let hw = HardwareInfo(
            totalRAMBytes: UInt64(7.0 * 1_073_741_824.0),
            availableDiskBytes: UInt64(50.0 * 1_073_741_824.0),
            architecture: "arm64"
        )
        let result = HardwareCompatibilitySupport.recommendation(modelDiskGB: 3.0, hardware: hw)
        XCTAssertEqual(result, .compatible)
    }

    func testRecommendationNotRecommendedInsufficientRAM() {
        // 4GB RAM, 50GB disk, model is 3GB → needs 6GB RAM
        let hw = HardwareInfo(
            totalRAMBytes: UInt64(4.0 * 1_073_741_824.0),
            availableDiskBytes: UInt64(50.0 * 1_073_741_824.0),
            architecture: "arm64"
        )
        let result = HardwareCompatibilitySupport.recommendation(modelDiskGB: 3.0, hardware: hw)
        XCTAssertEqual(result, .notRecommended)
    }

    func testRecommendationNotRecommendedInsufficientDisk() {
        // 16GB RAM, 3GB disk, model is 3GB → needs 3.6GB disk
        let hw = HardwareInfo(
            totalRAMBytes: UInt64(16.0 * 1_073_741_824.0),
            availableDiskBytes: UInt64(3.0 * 1_073_741_824.0),
            architecture: "arm64"
        )
        let result = HardwareCompatibilitySupport.recommendation(modelDiskGB: 3.0, hardware: hw)
        XCTAssertEqual(result, .notRecommended)
    }

    func testRecommendationSmallModel() {
        // 8GB RAM, 10GB disk, model is 0.3GB
        let hw = HardwareInfo(
            totalRAMBytes: UInt64(8.0 * 1_073_741_824.0),
            availableDiskBytes: UInt64(10.0 * 1_073_741_824.0),
            architecture: "arm64"
        )
        let result = HardwareCompatibilitySupport.recommendation(modelDiskGB: 0.3, hardware: hw)
        XCTAssertEqual(result, .recommended)
    }

    // MARK: - parseMemsize

    func testParseMemsizeWithLabel() {
        let result = HardwareCompatibilitySupport.parseMemsize("hw.memsize: 17179869184")
        XCTAssertEqual(result, 17179869184)
    }

    func testParseMemsizeBareNumber() {
        let result = HardwareCompatibilitySupport.parseMemsize("17179869184")
        XCTAssertEqual(result, 17179869184)
    }

    func testParseMemsizeWithWhitespace() {
        let result = HardwareCompatibilitySupport.parseMemsize("  hw.memsize: 8589934592  \n")
        XCTAssertEqual(result, 8589934592)
    }

    func testParseMemsizeInvalid() {
        XCTAssertNil(HardwareCompatibilitySupport.parseMemsize(""))
        XCTAssertNil(HardwareCompatibilitySupport.parseMemsize("not a number"))
        XCTAssertNil(HardwareCompatibilitySupport.parseMemsize("hw.memsize: abc"))
    }

    // MARK: - parseDiskSpace

    func testParseDiskSpaceStandardOutput() {
        let output = """
            Filesystem   1024-blocks     Used Available Capacity  Mounted on
            /dev/disk3s1 488245288  234567890 253677398    48%    /
            """
        let result = HardwareCompatibilitySupport.parseDiskSpace(output)
        XCTAssertEqual(result, 253677398 * 1024)
    }

    func testParseDiskSpaceInsufficientLines() {
        XCTAssertNil(HardwareCompatibilitySupport.parseDiskSpace("Filesystem  1024-blocks"))
    }

    func testParseDiskSpaceInsufficientColumns() {
        let output = "Filesystem  1024-blocks\n/dev/disk3s1 488245288"
        XCTAssertNil(HardwareCompatibilitySupport.parseDiskSpace(output))
    }

    func testParseDiskSpaceInvalidNumber() {
        let output = "Filesystem  1024-blocks Used Available\n/dev/disk3s1 488245288 234 abc"
        XCTAssertNil(HardwareCompatibilitySupport.parseDiskSpace(output))
    }

    // MARK: - parseArchitecture

    func testParseArchitectureArm64() {
        XCTAssertEqual(HardwareCompatibilitySupport.parseArchitecture("arm64"), "arm64")
    }

    func testParseArchitectureX86() {
        XCTAssertEqual(HardwareCompatibilitySupport.parseArchitecture("x86_64"), "x86_64")
    }

    func testParseArchitectureWithWhitespace() {
        XCTAssertEqual(HardwareCompatibilitySupport.parseArchitecture("  arm64  \n"), "arm64")
    }

    func testParseArchitectureEmpty() {
        XCTAssertEqual(HardwareCompatibilitySupport.parseArchitecture(""), "unknown")
        XCTAssertEqual(HardwareCompatibilitySupport.parseArchitecture("   "), "unknown")
    }

    // MARK: - recommendationLabel

    func testRecommendationLabel() {
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationLabel(.recommended),
            "Recommended"
        )
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationLabel(.compatible),
            "Compatible"
        )
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationLabel(.notRecommended),
            "Not Recommended"
        )
    }

    // MARK: - recommendationColor

    func testRecommendationColor() {
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationColor(.recommended),
            "green"
        )
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationColor(.compatible),
            "orange"
        )
        XCTAssertEqual(
            HardwareCompatibilitySupport.recommendationColor(.notRecommended),
            "red"
        )
    }
}
