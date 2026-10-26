import Foundation

/// A desktop size presented once per HiDPI state, regardless of how it is supplied.
public struct DisplayOption: Identifiable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let isHiDPI: Bool
    public let nativeModes: [DisplayMode]
    public let fallbackRates: [Double]

    public var id: String { "\(width)x\(height)-\(isHiDPI ? "hidpi" : "standard")" }
    public var title: String { "\(width) × \(height)" }
    public var requiresVirtual: Bool { nativeModes.isEmpty }
    public var refreshRates: [Double] {
        ModePolicy.uniqueRates(requiresVirtual ? fallbackRates : nativeModes.map(\.refreshRate).filter { $0 > 0 })
            .sorted(by: >)
    }
    public var preset: HiDPIPreset { HiDPIPreset(width: width, height: height) }

    public func nativeMode(requestedRate: Double?, currentRate: Double?) -> DisplayMode? {
        guard let first = nativeModes.first else { return nil }
        let choice = ResolutionChoice(width: width, height: height, pixelWidth: first.pixelWidth,
                                      pixelHeight: first.pixelHeight, modes: nativeModes)
        let supportedRate = requestedRate.flatMap { requested in refreshRates.first { abs($0 - requested) <= 0.01 } }
        return ModePolicy.resolveMode(choice: choice, requestedRate: supportedRate, currentRate: currentRate)
    }

    public static func choices(for display: DisplayInfo, includeVirtual: Bool) -> [DisplayOption] {
        var groups = [String: [DisplayMode]]()
        for mode in ModePolicy.sortedModes(display.modes + [display.currentMode].compactMap { $0 }, hiDPIOnly: false) {
            let key = "\(mode.width)x\(mode.height)-\(mode.isHiDPI)"
            groups[key, default: []].append(mode)
        }
        var options = groups.values.compactMap { modes -> DisplayOption? in
            guard let first = modes.first else { return nil }
            return DisplayOption(width: first.width, height: first.height, isHiDPI: first.isHiDPI,
                                 nativeModes: modes, fallbackRates: [])
        }
        // Prefer a mode macOS already supplies; only fill missing HiDPI sizes.
        if includeVirtual && !display.isBuiltin {
            let rates = ModePolicy.virtualRefreshRates(for: display)
            let existing = Set(options.filter(\.isHiDPI).map { "\($0.width)x\($0.height)" })
            for preset in ModePolicy.presets(for: display) where !existing.contains(preset.id) {
                options.append(DisplayOption(width: preset.width, height: preset.height, isHiDPI: true,
                                             nativeModes: [], fallbackRates: rates))
            }
        }
        return options.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            return $0.isHiDPI && !$1.isHiDPI
        }
    }
}
