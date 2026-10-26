import Testing
@testable import SmartDPICore

@Suite struct DisplayOptionTests {
    @Test func missingHiDPISizesJoinSystemModesWithoutDuplicatingIDs() throws {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let ordinary1080 = mode(2, width: 1920, height: 1080, rate: 75)
        let hiDPI720 = mode(3, width: 1280, height: 720, scale: 2, rate: 75)
        let options = DisplayOption.choices(for: display(current: native, modes: [native, ordinary1080, hiDPI720]),
                                            includeVirtual: true)

        #expect(Set(options.map(\.id)).count == options.count)
        let fullHD = options.filter { $0.width == 1920 && $0.height == 1080 }
        #expect(fullHD.count == 2)
        let hiDPI = try #require(fullHD.first { $0.isHiDPI })
        let ordinary = try #require(fullHD.first { !$0.isHiDPI })
        #expect(hiDPI.requiresVirtual)
        #expect(hiDPI.refreshRates == [75])
        #expect(!ordinary.requiresVirtual)
        #expect(ordinary.nativeModes == [ordinary1080])
        #expect(options.contains { $0.width == 1280 && $0.isHiDPI && !$0.requiresVirtual })
    }

    @Test func suppliedHiDPIWinsOverGeneratedFallbackWithoutLosingOrdinaryAlternative() throws {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let ordinary = mode(2, width: 1920, height: 1080, rate: 75)
        let hiDPI = mode(3, width: 1920, height: 1080, scale: 2, rate: 60)
        let options = DisplayOption.choices(for: display(current: native, modes: [native, ordinary, hiDPI]),
                                            includeVirtual: true)
        let fullHD = options.filter { $0.width == 1920 && $0.height == 1080 }

        #expect(fullHD.count == 2)
        let supplied = try #require(fullHD.first { $0.isHiDPI })
        #expect(!supplied.requiresVirtual)
        #expect(supplied.nativeModes == [hiDPI])
        #expect(supplied.refreshRates == [60])
        #expect(supplied.fallbackRates.isEmpty)
        #expect(fullHD.contains { !$0.isHiDPI && $0.nativeModes == [ordinary] })
    }

    @Test func orderingStaysStableWhenDisplayModeEnumerationOrderChanges() {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let ordinary = mode(2, width: 1920, height: 1080, rate: 75)
        let hiDPI = mode(3, width: 1920, height: 1080, scale: 2, rate: 60)
        let taller = mode(4, width: 1920, height: 1200, rate: 60)
        let small = mode(5, width: 1280, height: 720, scale: 2, rate: 75)
        let modes = [small, ordinary, native, taller, hiDPI]
        let original = DisplayOption.choices(for: display(current: native, modes: modes), includeVirtual: true)
        let reordered = DisplayOption.choices(for: display(current: native, modes: Array(modes.reversed())),
                                              includeVirtual: true)

        #expect(original.map(\.id) == reordered.map(\.id))
        let fullHD = original.filter { $0.width == 1920 && $0.height == 1080 }
        #expect(fullHD.map(\.isHiDPI) == [true, false])
        let systemOnly = DisplayOption.choices(for: display(current: native, modes: modes), includeVirtual: false)
        #expect(systemOnly.map(\.id) == ["2560x1440-standard", "1920x1200-standard",
                                        "1920x1080-hidpi", "1920x1080-standard", "1280x720-hidpi"])
    }

    @Test func differentBackingSizesShareOneHiDPIRowAndRetainTheirActualModes() throws {
        let twoTimes = mode(1, width: 1920, height: 1080, scale: 2, rate: 60)
        let scaled = DisplayMode(modeID: 2, width: 1920, height: 1080, pixelWidth: 2880,
                                 pixelHeight: 1620, refreshRate: 75)
        let ordinary = mode(3, width: 1920, height: 1080, rate: 75)
        let options = DisplayOption.choices(for: display(current: twoTimes, modes: [scaled, ordinary, twoTimes]),
                                            includeVirtual: false)

        #expect(options.count == 2)
        let hiDPI = try #require(options.first { $0.isHiDPI })
        #expect(Set(hiDPI.nativeModes.map(\.modeID)) == Set([twoTimes.modeID, scaled.modeID]))
        #expect(hiDPI.refreshRates == [75, 60])
        #expect(hiDPI.nativeMode(requestedRate: 75, currentRate: 60) == scaled)
        #expect(hiDPI.nativeMode(requestedRate: 60, currentRate: 75) == twoTimes)
    }

    @Test func fractionalRatesRemainDistinctAndAutomaticSelectionPreservesCurrentTiming() throws {
        let fractional = mode(1, width: 1920, height: 1080, scale: 2, rate: 59.94)
        let sixty = mode(2, width: 1920, height: 1080, scale: 2, rate: 60)
        let fast = mode(3, width: 1920, height: 1080, scale: 2, rate: 75)
        let options = DisplayOption.choices(for: display(current: fractional, modes: [fast, sixty, fractional]),
                                            includeVirtual: false)
        let option = try #require(options.first)

        #expect(option.refreshRates == [75, 60, 59.94])
        #expect(option.nativeMode(requestedRate: nil, currentRate: 59.94) == fractional)
        #expect(option.nativeMode(requestedRate: 60, currentRate: 59.94) == sixty)
        #expect(option.nativeMode(requestedRate: 59.94, currentRate: 60) == fractional)
        #expect(option.nativeMode(requestedRate: 144, currentRate: 59.94) == fractional)
        #expect(option.nativeMode(requestedRate: nil, currentRate: 120) == fast)
    }

    @Test func eachRowAdvertisesOnlyItsOwnRatesAndDoesNotBorrowFallbackRates() throws {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let fullHD = mode(2, width: 1920, height: 1080, scale: 2, rate: 60)
        let smaller = mode(3, width: 1600, height: 900, scale: 2, rate: 59.94)
        let options = DisplayOption.choices(for: display(current: native, modes: [native, fullHD, smaller]),
                                            includeVirtual: true)
        let fullHDOption = try #require(options.first { $0.width == 1920 && $0.isHiDPI })
        let smallerOption = try #require(options.first { $0.width == 1600 && $0.isHiDPI })
        let fallback = try #require(options.first { $0.requiresVirtual })

        #expect(fullHDOption.refreshRates == [60])
        #expect(smallerOption.refreshRates == [59.94])
        #expect(fallback.refreshRates == [75])
        #expect(fullHDOption.nativeMode(requestedRate: 75, currentRate: 75) == fullHD)
        #expect(fallback.nativeMode(requestedRate: 75, currentRate: 75) == nil)
    }

    @Test func builtinDisplaysNeverReceiveVirtualFallbacks() {
        let native = mode(1, width: 2560, height: 1440, rate: 60, native: true)
        let monitor = display(builtin: true, current: native, modes: [native])
        let options = DisplayOption.choices(for: monitor, includeVirtual: true)

        #expect(options.map(\.id) == ["2560x1440-standard"])
        #expect(options.first?.requiresVirtual == false)
    }

    @Test func disablingFallbackIncludesOnlySystemChoices() {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let options = DisplayOption.choices(for: display(current: native, modes: [native]), includeVirtual: false)

        #expect(options.map(\.id) == ["2560x1440-standard"])
        #expect(options.first?.nativeModes == [native])
    }

    @Test func currentModeStaysVisibleEvenWhenMissingFromEnumeratedModes() throws {
        let native = mode(1, width: 2560, height: 1440, rate: 75, native: true)
        let current = mode(2, width: 1280, height: 720, scale: 2, rate: 60)
        let options = DisplayOption.choices(for: display(current: current, modes: [native]), includeVirtual: true)
        let currentOption = try #require(options.first { $0.width == 1280 && $0.height == 720 && $0.isHiDPI })

        #expect(!currentOption.requiresVirtual)
        #expect(currentOption.nativeModes == [current])
        #expect(currentOption.refreshRates == [60])
        #expect(currentOption.nativeMode(requestedRate: nil, currentRate: 60) == current)
        #expect(Set(options.map(\.id)).count == options.count)
    }

    @Test func duplicateCurrentAndEnumeratedModeDoesNotDuplicateRowOrRate() throws {
        let current = mode(1, width: 1920, height: 1080, scale: 2, rate: 60)
        let duplicate = mode(2, width: 1920, height: 1080, scale: 2, rate: 60)
        let options = DisplayOption.choices(for: display(current: current, modes: [current, duplicate]),
                                            includeVirtual: false)
        let option = try #require(options.first)

        #expect(options.count == 1)
        #expect(option.nativeModes.count == 1)
        #expect(option.refreshRates == [60])
    }

    private func mode(_ id: UInt32, width: Int, height: Int, scale: Int = 1,
                      rate: Double, native: Bool = false) -> DisplayMode {
        DisplayMode(modeID: id, width: width, height: height, pixelWidth: width * scale,
                    pixelHeight: height * scale, refreshRate: rate, isNative: native)
    }

    private func display(builtin: Bool = false, current: DisplayMode?, modes: [DisplayMode]) -> DisplayInfo {
        DisplayInfo(id: 42, name: "Display option test", isBuiltin: builtin, isMain: true,
                    vendor: 1, product: 2, mirrorSource: 0, currentMode: current, modes: modes,
                    nativeWidth: 2560, nativeHeight: 1440, nativeSizeIsEstimated: false)
    }
}
