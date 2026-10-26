import Foundation

public struct DisplayMode: Identifiable, Hashable, Codable, Sendable {
    public let modeID: UInt32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let usable: Bool
    public let isNative: Bool

    public init(modeID: UInt32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, usable: Bool = true, isNative: Bool = false) {
        self.modeID = modeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.usable = usable
        self.isNative = isNative
    }

    public var id: String { "\(modeID)-\(width)x\(height)-\(pixelWidth)x\(pixelHeight)-\(refreshRate)" }
    public var isHiDPI: Bool { width > 0 && height > 0 && pixelWidth > width && pixelHeight > height }
    public var isRetina2x: Bool { width > 0 && height > 0 && pixelWidth == width * 2 && pixelHeight == height * 2 }
    public var title: String { "\(width) × \(height)" }
    public var refreshLabel: String { ModePolicy.refreshLabel(refreshRate) }
    public var scaleLabel: String { width > 0 ? String(format: "%.1f×", Double(pixelWidth) / Double(width)) : "—" }

    public func matchesConfiguration(of other: DisplayMode, refreshTolerance: Double = 0.01) -> Bool {
        width == other.width && height == other.height &&
            pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight &&
            abs(refreshRate - other.refreshRate) <= refreshTolerance
    }
}

public struct DisplayInfo: Identifiable, Codable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let isBuiltin: Bool
    public let isMain: Bool
    public let vendor: UInt32
    public let product: UInt32
    public let mirrorSource: UInt32
    public let isInMirrorSet: Bool
    public let currentMode: DisplayMode?
    public let modes: [DisplayMode]
    public let nativeWidth: Int?
    public let nativeHeight: Int?
    public let nativeSizeIsEstimated: Bool

    public init(id: UInt32, name: String, isBuiltin: Bool, isMain: Bool, vendor: UInt32,
                product: UInt32, mirrorSource: UInt32, currentMode: DisplayMode?, modes: [DisplayMode],
                isInMirrorSet: Bool = false, nativeWidth: Int? = nil, nativeHeight: Int? = nil,
                nativeSizeIsEstimated: Bool = true) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.vendor = vendor
        self.product = product
        self.mirrorSource = mirrorSource
        self.isInMirrorSet = isInMirrorSet || mirrorSource != 0
        self.currentMode = currentMode
        self.modes = modes
        if let nativeWidth, let nativeHeight, nativeWidth > 0, nativeHeight > 0 {
            self.nativeWidth = nativeWidth
            self.nativeHeight = nativeHeight
            self.nativeSizeIsEstimated = nativeSizeIsEstimated
        } else {
            let inferred = ModePolicy.nativeSize(modes: modes, currentMode: currentMode)
            self.nativeWidth = inferred?.width
            self.nativeHeight = inferred?.height
            self.nativeSizeIsEstimated = inferred?.estimated ?? true
        }
    }
}

/// One desktop/rendering size with only the refresh rates actually offered for that size.
public struct ResolutionChoice: Identifiable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let modes: [DisplayMode]

    public var id: String { "\(width)x\(height)-\(pixelWidth)x\(pixelHeight)" }
    public var title: String { "\(width) × \(height)" }
    public var isHiDPI: Bool { width > 0 && height > 0 && pixelWidth > width && pixelHeight > height }
    public var isNative: Bool { modes.contains(where: \.isNative) }
    public var refreshRates: [Double] { ModePolicy.uniqueRates(modes.map(\.refreshRate).filter { $0 > 0 }) }

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, modes: [DisplayMode]) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.modes = modes
    }
}

public struct HiDPIPreset: Identifiable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public var id: String { "\(width)x\(height)" }
    public var title: String { "\(width) × \(height)" }
    public var backingLabel: String { "\(width * 2) × \(height * 2)" }

    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public enum ModePolicy {
    // 59.94 Hz and 60 Hz are distinct modes, even when their UI labels are close.
    private static let rateTolerance = 0.01

    public static func refreshLabel(_ rate: Double) -> String {
        guard rate.isFinite, rate > 0 else { return "未报告" }
        var value = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rate)
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return "\(value) Hz"
    }

    public static func sortedModes(_ modes: [DisplayMode], hiDPIOnly: Bool) -> [DisplayMode] {
        var seen = Set<String>()
        // Keep native metadata if otherwise identical mode records are returned.
        let candidates = modes.filter(\.isNative) + modes.filter { !$0.isNative }
        return candidates.filter { mode in
            guard mode.usable, mode.width >= 640, mode.height >= 480,
                  mode.pixelWidth > 0, mode.pixelHeight > 0, mode.refreshRate.isFinite,
                  !hiDPIOnly || mode.isHiDPI else { return false }
            let key = "\(mode.width)-\(mode.height)-\(mode.pixelWidth)-\(mode.pixelHeight)-\(mode.refreshRate)"
            return seen.insert(key).inserted
        }.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
            if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
            if $0.pixelHeight != $1.pixelHeight { return $0.pixelHeight > $1.pixelHeight }
            return $0.refreshRate > $1.refreshRate
        }
    }

    public static func resolutionChoices(modes: [DisplayMode], hiDPIOnly: Bool) -> [ResolutionChoice] {
        let sorted = sortedModes(modes, hiDPIOnly: hiDPIOnly)
        var order = [String]()
        var grouped = [String: [DisplayMode]]()
        for mode in sorted {
            let key = "\(mode.width)x\(mode.height)-\(mode.pixelWidth)x\(mode.pixelHeight)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(mode)
        }
        return order.compactMap { key in
            guard let variants = grouped[key], let first = variants.first else { return nil }
            return ResolutionChoice(width: first.width, height: first.height,
                                    pixelWidth: first.pixelWidth, pixelHeight: first.pixelHeight, modes: variants)
        }
    }

    public static func resolveMode(choice: ResolutionChoice, requestedRate: Double?, currentRate: Double?) -> DisplayMode? {
        let offered = choice.modes.filter { $0.usable && $0.refreshRate.isFinite }
        if let requestedRate {
            guard requestedRate.isFinite else { return nil }
            return offered.filter { abs($0.refreshRate - requestedRate) <= rateTolerance }
                .min { abs($0.refreshRate - requestedRate) < abs($1.refreshRate - requestedRate) }
        }
        if let currentRate, currentRate.isFinite,
           let matching = offered.filter({ abs($0.refreshRate - currentRate) <= rateTolerance })
            .min(by: { abs($0.refreshRate - currentRate) < abs($1.refreshRate - currentRate) }) {
            return matching
        }
        return offered.max { $0.refreshRate < $1.refreshRate }
    }

    /// Physical timing candidates come from the monitor's own native-size LoDPI modes.
    /// A HiDPI mode's backing buffer is never evidence of the panel's physical size.
    public static func virtualRefreshRates(for display: DisplayInfo) -> [Double] {
        let usable = display.modes.filter {
            $0.usable && $0.width > 0 && $0.height > 0
        }
        let physical = usable.filter { $0.width == $0.pixelWidth && $0.height == $0.pixelHeight }
        func rates(from modes: [DisplayMode]) -> [Double] {
            uniqueRates(modes.map(\.refreshRate).filter { $0.isFinite && (1...1000).contains($0) }).sorted()
        }
        if let width = display.nativeWidth, let height = display.nativeHeight {
            let native = physical.filter { $0.width == width && $0.height == height }
            let nativeRates = rates(from: native)
            if !nativeRates.isEmpty { return nativeRates }
        }
        if let largest = physical.max(by: { Double($0.width) * Double($0.height) < Double($1.width) * Double($1.height) }) {
            let largestRates = rates(from: physical.filter { $0.width == largest.width && $0.height == largest.height })
            if !largestRates.isEmpty { return largestRates }
        }
        if let current = display.currentMode, current.usable, current.refreshRate.isFinite,
           (1...1000).contains(current.refreshRate) {
            return [current.refreshRate]
        }
        return []
    }

    public static func preferredVirtualRefreshRate(for display: DisplayInfo) -> Double? {
        let rates = virtualRefreshRates(for: display)
        if let current = display.currentMode?.refreshRate,
           let matching = rates.filter({ abs($0 - current) <= rateTolerance })
            .min(by: { abs($0 - current) < abs($1 - current) }) {
            return matching
        }
        return rates.max()
    }

    public static func uniqueRates(_ rates: [Double]) -> [Double] {
        var result = [Double]()
        for rate in rates where rate.isFinite && rate >= 0 {
            if !result.contains(where: { abs($0 - rate) <= rateTolerance }) { result.append(rate) }
        }
        return result
    }

    static func nativeSize(modes: [DisplayMode], currentMode: DisplayMode?) -> (width: Int, height: Int, estimated: Bool)? {
        let usable = (modes + [currentMode].compactMap { $0 }).filter {
            $0.usable && $0.width > 0 && $0.height > 0 && $0.pixelWidth > 0 && $0.pixelHeight > 0
        }
        let lowDPI = usable.filter { $0.width == $0.pixelWidth && $0.height == $0.pixelHeight }
        let declaredNative = lowDPI.filter(\.isNative)
        let nativeGeometries = Set(declaredNative.map { "\($0.width)x\($0.height)" })
        if nativeGeometries.count == 1, let native = declaredNative.max(by: { $0.refreshRate < $1.refreshRate }) {
            return (native.width, native.height, false)
        }
        let matchingAspect: [DisplayMode]
        if let currentMode, currentMode.width > 0, currentMode.height > 0 {
            matchingAspect = lowDPI.filter { sameAspect(width: $0.width, height: $0.height,
                                                       targetWidth: currentMode.width, targetHeight: currentMode.height) }
        } else {
            matchingAspect = lowDPI
        }
        guard let largest = matchingAspect.max(by: {
            let lhsArea = Double($0.width) * Double($0.height)
            let rhsArea = Double($1.width) * Double($1.height)
            return lhsArea == rhsArea ? $0.refreshRate < $1.refreshRate : lhsArea < rhsArea
        }) else { return nil }
        return (largest.width, largest.height, true)
    }

    private static func sameAspect(width: Int, height: Int, targetWidth: Int, targetHeight: Int) -> Bool {
        guard width > 0, height > 0, targetWidth > 0, targetHeight > 0 else { return false }
        let actual = Double(width) / Double(height)
        let target = Double(targetWidth) / Double(targetHeight)
        return abs(actual - target) / target <= 0.01
    }

    public static func presets(aspectWidth: Int, aspectHeight: Int) -> [HiDPIPreset] {
        guard aspectWidth > 0, aspectHeight > 0 else { return [] }
        let ratio = Double(aspectHeight) / Double(aspectWidth)
        let widths = aspectHeight > aspectWidth ? [720, 810, 900, 1080, 1200] :
            [1280, 1440, 1600, 1680, 1920, 2048, 2304, 2560, 3008]
        return widths.compactMap { width in
            let height = Int((Double(width) * ratio / 2).rounded()) * 2
            guard width <= 3072, height >= 480, height <= 2160 else { return nil }
            return HiDPIPreset(width: width, height: height)
        }
    }

    public static func presets(for display: DisplayInfo) -> [HiDPIPreset] {
        guard let width = display.nativeWidth, let height = display.nativeHeight,
              width > 0, height > 0 else { return [] }
        let ratio = Double(height) / Double(width)
        var widths = [0.5, 2.0 / 3.0, 0.75, 0.8, 0.9, 1.0].map { Double(width) * $0 }
        widths += display.modes.filter {
            $0.usable && $0.isHiDPI && sameAspect(width: $0.width, height: $0.height,
                                                targetWidth: width, targetHeight: height)
        }.map { Double($0.width) }
        // Include the largest fitting choice for very wide or tall monitors.
        widths.append(floor(min(Double(width), 3840, 2160 / ratio) / 2) * 2)
        var seen = Set<String>()
        return widths.compactMap { proposedWidth in
            let logicalWidth = Int((proposedWidth / 2).rounded()) * 2
            let logicalHeight = Int((Double(logicalWidth) * ratio / 2).rounded()) * 2
            guard logicalWidth >= 480, logicalHeight >= 480,
                  logicalWidth <= 3840, logicalHeight <= 2160 else { return nil }
            let preset = HiDPIPreset(width: logicalWidth, height: logicalHeight)
            return seen.insert(preset.id).inserted ? preset : nil
        }.sorted { $0.width < $1.width }
    }

    public static func supportsVirtualTarget(_ display: DisplayInfo, managedSource: UInt32?) -> Bool {
        guard !display.isBuiltin else { return false }
        if let managedSource, managedSource != 0, display.mirrorSource == managedSource { return true }
        return !display.isInMirrorSet && display.mirrorSource == 0
    }
}
