import AppKit
import XCTest
@testable import GhostEditCore

final class MenuBarIconSupportTests: XCTestCase {
    func testDescriptorForIdleState() {
        let descriptor = MenuBarIconSupport.descriptor(for: .idle)

        XCTAssertEqual(descriptor.assetName, "MenuBarIconIdle")
        XCTAssertEqual(descriptor.fallbackGlyph, "ⓖ")
    }

    func testDescriptorForProcessingState() {
        let descriptor = MenuBarIconSupport.descriptor(for: .processing)

        XCTAssertEqual(descriptor.assetName, "MenuBarIconProcessing")
        XCTAssertEqual(descriptor.fallbackGlyph, "🤓")
    }

    func testResolveImagePrefersBundleLookup() {
        var bundleCalls = 0
        var frameworkCalls = 0
        var globalCalls = 0
        let expected = NSImage(size: NSSize(width: 1, height: 1))

        let resolved = MenuBarIconSupport.resolveImage(
            named: NSImage.Name("menu-bar-icon"),
            bundleLookup: { _ in
                bundleCalls += 1
                return expected
            },
            frameworkLookup: { _ in
                frameworkCalls += 1
                return NSImage(size: NSSize(width: 2, height: 2))
            },
            globalLookup: { _ in
                globalCalls += 1
                return NSImage(size: NSSize(width: 3, height: 3))
            }
        )

        XCTAssertTrue(resolved === expected)
        XCTAssertEqual(bundleCalls, 1)
        XCTAssertEqual(frameworkCalls, 0)
        XCTAssertEqual(globalCalls, 0)
    }

    func testResolveImageFallsBackToFrameworkLookup() {
        var bundleCalls = 0
        var frameworkCalls = 0
        var globalCalls = 0
        let expected = NSImage(size: NSSize(width: 1, height: 1))

        let resolved = MenuBarIconSupport.resolveImage(
            named: NSImage.Name("menu-bar-icon"),
            bundleLookup: { _ in
                bundleCalls += 1
                return nil
            },
            frameworkLookup: { _ in
                frameworkCalls += 1
                return expected
            },
            globalLookup: { _ in
                globalCalls += 1
                return NSImage(size: NSSize(width: 3, height: 3))
            }
        )

        XCTAssertTrue(resolved === expected)
        XCTAssertEqual(bundleCalls, 1)
        XCTAssertEqual(frameworkCalls, 1)
        XCTAssertEqual(globalCalls, 0)
    }

    func testResolveImageFallsBackToGlobalLookup() {
        var bundleCalls = 0
        var frameworkCalls = 0
        var globalCalls = 0
        let expected = NSImage(size: NSSize(width: 1, height: 1))

        let resolved = MenuBarIconSupport.resolveImage(
            named: NSImage.Name("menu-bar-icon"),
            bundleLookup: { _ in
                bundleCalls += 1
                return nil
            },
            frameworkLookup: { _ in
                frameworkCalls += 1
                return nil
            },
            globalLookup: { _ in
                globalCalls += 1
                return expected
            }
        )

        XCTAssertTrue(resolved === expected)
        XCTAssertEqual(bundleCalls, 1)
        XCTAssertEqual(frameworkCalls, 1)
        XCTAssertEqual(globalCalls, 1)
    }

    func testResolveImageReturnsNilWhenNoLookupSucceeds() {
        var bundleCalls = 0
        var frameworkCalls = 0
        var globalCalls = 0

        let resolved = MenuBarIconSupport.resolveImage(
            named: NSImage.Name("menu-bar-icon"),
            bundleLookup: { _ in
                bundleCalls += 1
                return nil
            },
            frameworkLookup: { _ in
                frameworkCalls += 1
                return nil
            },
            globalLookup: { _ in
                globalCalls += 1
                return nil
            }
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(bundleCalls, 1)
        XCTAssertEqual(frameworkCalls, 1)
        XCTAssertEqual(globalCalls, 1)
    }

    func testResolveImageWithDefaultLookupsHandlesUnknownName() {
        let resolved = MenuBarIconSupport.resolveImage(named: NSImage.Name("ghostedit-unknown-icon-name"))

        XCTAssertNil(resolved)
    }
}
