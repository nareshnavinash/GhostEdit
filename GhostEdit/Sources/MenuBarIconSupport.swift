import AppKit

enum MenuBarIconState {
    case idle
    case processing
}

struct MenuBarIconDescriptor: Equatable {
    let assetName: String
    let fallbackGlyph: String
}

enum MenuBarIconSupport {
    static let idleAssetName = "MenuBarIconIdle"
    static let processingAssetName = "MenuBarIconProcessing"
    static let idleFallbackGlyph = "ⓖ"
    static let processingFallbackGlyph = "🤓"

    static func descriptor(for state: MenuBarIconState) -> MenuBarIconDescriptor {
        switch state {
        case .idle:
            return MenuBarIconDescriptor(
                assetName: idleAssetName,
                fallbackGlyph: idleFallbackGlyph
            )
        case .processing:
            return MenuBarIconDescriptor(
                assetName: processingAssetName,
                fallbackGlyph: processingFallbackGlyph
            )
        }
    }

    static func resolveImage(named name: NSImage.Name) -> NSImage? {
        resolveImage(
            named: name,
            bundleLookup: { Bundle.main.image(forResource: $0) },
            frameworkLookup: { Bundle(for: AppDelegate.self).image(forResource: $0) },
            globalLookup: { NSImage(named: $0) }
        )
    }

    static func resolveImage(
        named name: NSImage.Name,
        bundleLookup: (NSImage.Name) -> NSImage?,
        frameworkLookup: (NSImage.Name) -> NSImage?,
        globalLookup: (NSImage.Name) -> NSImage?
    ) -> NSImage? {
        if let image = bundleLookup(name) {
            return image
        }

        if let image = frameworkLookup(name) {
            return image
        }

        return globalLookup(name)
    }
}
