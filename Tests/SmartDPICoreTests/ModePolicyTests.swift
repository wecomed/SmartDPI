import Testing
@testable import SmartDPICore

@Suite struct ModePolicyTests {
    private func mode(_ id: UInt32 = 1, width: Int = 1920, height: Int = 1080,
                      pixelWidth: Int = 3840, pixelHeight: Int = 2160,
                      refresh: Double = 60, usable: Bool = true, native: Bool = false) -> DisplayMode {
        DisplayMode(modeID: id, width: width, height: height,
                    pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                    refreshRate: refresh, usable: usable, isNative: native)
    }

    private func display(builtin: Bool = false, source: UInt32 = 0, inMirrorSet: Bool = false,
                         current: DisplayMode? = nil, modes: [DisplayMode] = [],
                         nativeWidth: Int? = nil, nativeHeight: Int? = nil,
                         estimated: Bool = true) -> DisplayInfo {
        DisplayInfo(id: 42, name: "Test display", isBuiltin: builtin, isMain: true,
                    vendor: 1, product: 2, mirrorSource: source,
                    currentMode: current, modes: modes, isInMirrorSet: inMirrorSet,
                    nativeWidth: nativeWidth, nativeHeight: nativeHeight, nativeSizeIsEstimated: estimated)
    }

    private func physical(_ id: UInt32 = 1, width: Int = 2560, height: Int = 1440,
                          refresh: Double = 75, native: Bool = true, usable: Bool = true) -> DisplayMode {
        mode(id, width: width, height: height, pixelWidth: width, pixelHeight: height,
             refresh: refresh, usable: usable, native: native)
    }

    @Test func testHiDPIRequiresBothDimensionsToHaveMorePixels() {
        #expect(mode().isHiDPI)
        #expect(!mode(pixelWidth: 1920).isHiDPI)
        #expect(!mode(pixelHeight: 1080).isHiDPI)
        #expect(!mode(pixelWidth: 1920, pixelHeight: 1080).isHiDPI)
        #expect(!mode(width: 0).isHiDPI)
        #expect(!mode(height: 0).isHiDPI)
        #expect(!mode(width: -1920).isHiDPI)
        #expect(!mode(height: -1080).isHiDPI)
    }

    @Test func testRetinaRequiresExactTwoTimesOnBothAxes() {
        #expect(mode().isRetina2x)
        let scaled = mode(pixelWidth: 2880, pixelHeight: 1620)
        #expect(scaled.isHiDPI)
        #expect(!scaled.isRetina2x)
        #expect(!mode(pixelWidth: 3841).isRetina2x)
        #expect(!mode(pixelHeight: 2159).isRetina2x)
        #expect(!mode(pixelHeight: 1620).isRetina2x)
        #expect(!mode(width: 0, pixelWidth: 0).isRetina2x)
        #expect(!mode(height: 0, pixelHeight: 0).isRetina2x)
    }

    @Test func testFilteringRemovesUnusableTinyAndNonHiDPIModes() {
        let valid = mode(1)
        let unusable = mode(2, usable: false)
        let narrow = mode(3, width: 639)
        let short = mode(4, height: 479)
        let lowDPI = mode(5, pixelWidth: 1920, pixelHeight: 1080)
        let widthOnly = mode(6, pixelHeight: 1080)
        let input = [unusable, lowDPI, narrow, short, widthOnly, valid]

        #expect(ModePolicy.sortedModes(input, hiDPIOnly: true) == [valid])
        #expect(Set(ModePolicy.sortedModes(input, hiDPIOnly: false).map(\.modeID)) ==
                Set([valid.modeID, lowDPI.modeID, widthOnly.modeID]))
    }

    @Test func testDuplicateGeometryDoesNotDiscardRefreshOrBackingVariants() {
        let sixty = mode(1)
        let duplicate = mode(2)
        let fractional = mode(3, refresh: 59.94)
        let fast = mode(4, refresh: 120)
        let lowDPI = mode(5, pixelWidth: 1920, pixelHeight: 1080)
        let result = ModePolicy.sortedModes([sixty, duplicate, fractional, fast, lowDPI], hiDPIOnly: false)

        #expect(result.count == 4)
        #expect(result.filter(\.isHiDPI).map(\.refreshRate) == [120, 60, 59.94])
        #expect(result.last == lowDPI)
        #expect(result.filter { $0.refreshRate == 60 && $0.isHiDPI }.count == 1)
    }

    @Test func testModesSortByDesktopSizeBeforeRefreshRate() {
        let larger = mode(1, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880)
        let taller = mode(2, height: 1200, pixelHeight: 2400)
        let faster = mode(3, refresh: 144)
        #expect(ModePolicy.sortedModes([faster, taller, larger], hiDPIOnly: true) ==
                [larger, taller, faster])
    }

    @Test func testRefreshLabelsKeepFractionalTimingAndDoNotInferVariableRefresh() {
        #expect(mode(refresh: 59.94).refreshLabel == "59.94 Hz")
        #expect(mode(refresh: 60).refreshLabel == "60 Hz")
        #expect(mode(refresh: 74.5).refreshLabel == "74.5 Hz")
        #expect(mode(refresh: 0).refreshLabel == "未报告")
        #expect(ModePolicy.refreshLabel(.nan) == "未报告")
        #expect(ModePolicy.refreshLabel(.infinity) == "未报告")
    }

    @Test func testResolutionGroupsRetainOnlyRatesOfferedForTheirRenderingSize() throws {
        let low = physical(refresh: 75)
        let hd = mode(2, refresh: 60)
        let fractional = mode(3, refresh: 59.94)
        let reducedBacking = mode(4, pixelWidth: 2880, pixelHeight: 1620, refresh: 120)
        let choices = ModePolicy.resolutionChoices(modes: [low, hd, fractional, reducedBacking], hiDPIOnly: false)
        #expect(choices.count == 3)
        let retina = try #require(choices.first { $0.pixelWidth == 3840 })
        #expect(retina.refreshRates == [60, 59.94])
        #expect(retina.modes.count == 2)
        #expect(!retina.refreshRates.contains(75))
        #expect(choices.first { $0.width == 2560 }?.isNative == true)
        #expect(ModePolicy.resolutionChoices(modes: [low, hd, fractional, reducedBacking], hiDPIOnly: true).count == 2)
    }

    @Test func testDuplicateNativeModeKeepsNativeMetadata() throws {
        let ordinary = physical(1, native: false)
        let native = physical(2)
        let choice = try #require(ModePolicy.resolutionChoices(modes: [ordinary, native], hiDPIOnly: false).first)
        #expect(choice.modes.count == 1)
        #expect(choice.isNative)
    }

    @Test func testUnknownRateIsSelectableAutomaticallyWithoutAnExplicit0HzOption() throws {
        let unknown = mode(refresh: 0)
        let choice = try #require(ModePolicy.resolutionChoices(modes: [unknown], hiDPIOnly: true).first)
        #expect(choice.refreshRates.isEmpty)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: 60) == unknown)
        #expect(unknown.refreshLabel == "未报告")
    }

    @Test func testAutomaticResolutionSwitchPreservesCurrentRateOrUsesHighestAvailable() throws {
        let choices = ModePolicy.resolutionChoices(modes: [mode(1, refresh: 59.94), mode(2, refresh: 60), mode(3, refresh: 120)],
                                                   hiDPIOnly: true)
        let choice = try #require(choices.first)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: 59.94)?.refreshRate == 59.94)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: 60)?.refreshRate == 60)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: 75)?.refreshRate == 120)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: nil)?.refreshRate == 120)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: 60, currentRate: 120)?.refreshRate == 60)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: 75, currentRate: 120) == nil)
    }

    @Test func test60HzOnlyHiDPICannotBePresentedAs75Hz() throws {
        let monitor = display(current: physical(refresh: 75), modes: [physical(refresh: 75), mode(2, refresh: 60)])
        let choice = try #require(ModePolicy.resolutionChoices(modes: monitor.modes, hiDPIOnly: true).first)
        #expect(choice.refreshRates == [60])
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: nil, currentRate: 75)?.refreshRate == 60)
        #expect(ModePolicy.resolveMode(choice: choice, requestedRate: 75, currentRate: 75) == nil)
        #expect(ModePolicy.virtualRefreshRates(for: monitor) == [75])
    }

    @Test func testConfigurationMatchingSeparatesFractionalRateAndRenderSize() {
        #expect(mode().matchesConfiguration(of: mode(2)))
        #expect(!mode().matchesConfiguration(of: mode(refresh: 59.94)))
        #expect(!mode().matchesConfiguration(of: mode(pixelWidth: 2880, pixelHeight: 1620)))
    }

    @Test func testNativePanelGeometryNeverComesFromUnflaggedHiDPIBackingBuffer() {
        let current = mode()
        let monitor = display(current: current, modes: [current, physical(native: false), physical(3, width: 1920, height: 1080, native: false)])
        #expect(monitor.nativeWidth == 2560)
        #expect(monitor.nativeHeight == 1440)
        #expect(monitor.nativeSizeIsEstimated)
        let unknown = display(current: current, modes: [current])
        #expect(unknown.nativeWidth == nil)
        #expect(unknown.nativeHeight == nil)
        #expect(unknown.nativeSizeIsEstimated)
    }

    @Test func testNativeFlagOutranksLargerRenderedSizesAndFlagsPreferLoDPI() {
        let flaggedHiDPI = mode(native: true)
        let native = physical(2, refresh: 75)
        let large = physical(3, width: 5120, height: 2880, refresh: 60, native: false)
        let monitor = display(current: flaggedHiDPI, modes: [flaggedHiDPI, large, native])
        #expect(monitor.nativeWidth == 2560)
        #expect(monitor.nativeHeight == 1440)
        #expect(!monitor.nativeSizeIsEstimated)
    }

    @Test func testHiDPIOnlyNativeFlagCannotIdentifyPanelFromItsRenderBuffer() {
        let flagged = mode(native: true)
        let monitor = display(current: flagged, modes: [flagged])
        #expect(monitor.nativeWidth == nil)
        #expect(monitor.nativeHeight == nil)
        #expect(monitor.nativeSizeIsEstimated)
        let estimated = display(current: flagged, modes: [flagged, physical(2, native: false)])
        #expect(estimated.nativeWidth == 2560)
        #expect(estimated.nativeHeight == 1440)
        #expect(estimated.nativeSizeIsEstimated)
    }

    @Test func testConflictingNativeFlagsFallBackToAnExplicitlyEstimatedGeometry() {
        let smallerFast = physical(1, width: 1920, height: 1080, refresh: 144)
        let larger = physical(2, refresh: 75)
        let monitor = display(current: mode(), modes: [smallerFast, larger])
        #expect(monitor.nativeWidth == 2560)
        #expect(monitor.nativeHeight == 1440)
        #expect(monitor.nativeSizeIsEstimated)
    }

    @Test func testNativeGeometryEstimationRespectsCurrentAspectAndCurrentLoDPI() {
        let widescreen = physical(width: 2560, height: 1440, native: false)
        let wrongAspect = physical(2, width: 3840, height: 2400, native: false)
        let monitor = display(current: mode(), modes: [widescreen, wrongAspect])
        #expect(monitor.nativeWidth == 2560)
        #expect(monitor.nativeHeight == 1440)
        let currentOnly = display(current: widescreen)
        #expect(currentOnly.nativeWidth == 2560)
        #expect(currentOnly.nativeSizeIsEstimated)
    }

    @Test func testExplicitNativeDimensionsArePreserved() {
        let monitor = display(current: mode(), modes: [physical()], nativeWidth: 3440, nativeHeight: 1440, estimated: false)
        #expect(monitor.nativeWidth == 3440)
        #expect(monitor.nativeHeight == 1440)
        #expect(!monitor.nativeSizeIsEstimated)
    }

    @Test func testVirtualRatesFollowNativeTimingsAndKeepFractionalRates() {
        let monitor = display(current: mode(refresh: 59.94), modes: [physical(1, refresh: 59.94), physical(2, refresh: 60),
            physical(3, refresh: 75), physical(4, refresh: 75), physical(5, width: 1920, height: 1080, refresh: 144, native: false)])
        #expect(ModePolicy.virtualRefreshRates(for: monitor) == [59.94, 60, 75])
        #expect(ModePolicy.preferredVirtualRefreshRate(for: monitor) == 59.94)
        let unavailableCurrent = display(current: mode(refresh: 120), modes: monitor.modes)
        #expect(ModePolicy.preferredVirtualRefreshRate(for: unavailableCurrent) == 75)
    }

    @Test func testVirtualRateFallbackUsesObservedLargestLoDPIOrCurrent() {
        let monitor = display(current: mode(refresh: 120), modes: [physical(1, refresh: 100, native: false),
            physical(2, refresh: 120, native: false), physical(3, width: 1920, height: 1080, refresh: 144, native: false)])
        #expect(ModePolicy.virtualRefreshRates(for: monitor) == [100, 120])
        #expect(ModePolicy.preferredVirtualRefreshRate(for: monitor) == 120)
        #expect(ModePolicy.virtualRefreshRates(for: display(current: mode(refresh: 74.97))) == [74.97])
    }

    @Test func testUnreportedVirtualRateDoesNotBecomeGuessed60HzOrLowerSizeTiming() {
        let monitor = display(current: mode(refresh: 0), modes: [physical(refresh: 0),
            physical(2, width: 1920, height: 1080, refresh: 144, native: false)])
        #expect(ModePolicy.virtualRefreshRates(for: monitor).isEmpty)
        #expect(ModePolicy.preferredVirtualRefreshRate(for: monitor) == nil)
        #expect(ModePolicy.virtualRefreshRates(for: display()).isEmpty)
        #expect(ModePolicy.virtualRefreshRates(for: display(current: mode(refresh: 0))).isEmpty)
        #expect(ModePolicy.virtualRefreshRates(for: display(current: mode(refresh: 1001), modes: [physical(refresh: 1001)])).isEmpty)
        #expect(ModePolicy.virtualRefreshRates(for: display(modes: [physical(refresh: 360)])) == [360])
    }

    @Test func testAdaptivePresetsCoverNativeHalfUsefulScaledAndExistingHiDPISizes() {
        let twoK = display(current: mode(), modes: [physical(), mode(2, width: 2048, height: 1152, pixelWidth: 4096, pixelHeight: 2304)])
        let choices = ModePolicy.presets(for: twoK)
        #expect(choices.contains(HiDPIPreset(width: 1280, height: 720)))
        #expect(choices.contains(HiDPIPreset(width: 1920, height: 1080)))
        #expect(choices.contains(HiDPIPreset(width: 2048, height: 1152)))
        #expect(choices.contains(HiDPIPreset(width: 2560, height: 1440)))
        let fourK = display(modes: [physical(width: 3840, height: 2160)])
        #expect(ModePolicy.presets(for: fourK).contains(HiDPIPreset(width: 2560, height: 1440)))
        let fullHD = display(modes: [physical(width: 1920, height: 1080)])
        #expect(ModePolicy.presets(for: fullHD).contains(HiDPIPreset(width: 960, height: 540)))
    }

    @Test func testAdaptivePresetsPreserveUltrawideAndPortraitWithinBridgeLimits() {
        for (width, height) in [(1920, 1080), (2560, 1440), (3840, 2160), (3440, 1440), (5120, 1440),
                                (1080, 1920), (1440, 2560), (2160, 3840)] {
            let monitor = display(modes: [physical(width: width, height: height)])
            let choices = ModePolicy.presets(for: monitor)
            #expect(!choices.isEmpty)
            #expect(Set(choices.map(\.id)).count == choices.count)
            for preset in choices {
                #expect(preset.width >= 480 && preset.height >= 480)
                #expect(preset.width * 2 <= 7680 && preset.height * 2 <= 4320)
                #expect(preset.width % 2 == 0 && preset.height % 2 == 0)
                let idealHeight = Double(preset.width) * Double(height) / Double(width)
                #expect(abs(Double(preset.height) - idealHeight) <= 1.000001)
            }
        }
        #expect(ModePolicy.presets(for: display(current: mode(), modes: [mode()])).isEmpty)
    }

    @Test func testTwoKPresetsIncludeComfortableFullHDDesktop() {
        let choices = ModePolicy.presets(aspectWidth: 2560, aspectHeight: 1440)
        #expect(choices.contains(HiDPIPreset(width: 1920, height: 1080)))
        assertBoundedAspectPresets(choices, width: 2560, height: 1440)
    }

    @Test func testUltrawidePresetsKeepPanelAspectRatio() {
        for (width, height) in [(3440, 1440), (5120, 1440)] {
            let choices = ModePolicy.presets(aspectWidth: width, aspectHeight: height)
            #expect(!choices.isEmpty, "An ultrawide target should offer useful choices")
            assertBoundedAspectPresets(choices, width: width, height: height)
        }
    }

    @Test func testPortraitPresetsRemainAvailableWithinFramebufferLimits() {
        let choices = ModePolicy.presets(aspectWidth: 1440, aspectHeight: 2560)
        #expect(!choices.isEmpty, "A portrait target needs smaller desktop widths to fit the height limit")
        assertBoundedAspectPresets(choices, width: 1440, height: 2560)
        #expect(choices.allSatisfy { $0.height > $0.width })
    }

    @Test func testInvalidPanelDimensionsOfferNoPresets() {
        for (width, height) in [(0, 1440), (2560, 0), (-1, 1440), (2560, -1), (0, 0)] {
            #expect(ModePolicy.presets(aspectWidth: width, aspectHeight: height).isEmpty)
        }
    }

    @Test func testVirtualTargetRejectsBuiltinAndPreexistingForeignMirrors() {
        #expect(ModePolicy.supportsVirtualTarget(display(), managedSource: nil))
        #expect(ModePolicy.supportsVirtualTarget(display(), managedSource: 100))
        #expect(!ModePolicy.supportsVirtualTarget(display(builtin: true), managedSource: nil))
        #expect(!ModePolicy.supportsVirtualTarget(display(source: 100), managedSource: nil))
        #expect(!ModePolicy.supportsVirtualTarget(display(source: 100), managedSource: 200))
        #expect(ModePolicy.supportsVirtualTarget(display(source: 100), managedSource: 100))
        #expect(!ModePolicy.supportsVirtualTarget(display(builtin: true, source: 100), managedSource: 100))
    }

    @Test func testMirrorMasterIsRejectedAndOnlyManagedFollowerIsAllowed() {
        let master = display(source: 0, inMirrorSet: true)
        let follower = display(source: 100, inMirrorSet: true)
        #expect(!ModePolicy.supportsVirtualTarget(master, managedSource: nil))
        #expect(!ModePolicy.supportsVirtualTarget(master, managedSource: 100))
        #expect(!ModePolicy.supportsVirtualTarget(follower, managedSource: nil))
        #expect(!ModePolicy.supportsVirtualTarget(follower, managedSource: 200))
        #expect(ModePolicy.supportsVirtualTarget(follower, managedSource: 100))
    }

    private func assertBoundedAspectPresets(_ choices: [HiDPIPreset], width: Int, height: Int,
                                           sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(choices.map(\.id)).count == choices.count, "Presets must be unique", sourceLocation: sourceLocation)
        for preset in choices {
            #expect(preset.width > 0, sourceLocation: sourceLocation)
            #expect(preset.height >= 480, sourceLocation: sourceLocation)
            #expect(preset.width * 2 <= 6144, sourceLocation: sourceLocation)
            #expect(preset.height * 2 <= 4320, sourceLocation: sourceLocation)
            #expect(preset.height % 2 == 0, sourceLocation: sourceLocation)
            let idealHeight = Double(preset.width) * Double(height) / Double(width)
            #expect(abs(Double(preset.height) - idealHeight) <= 1.000001,
                    "Aspect ratio should differ by at most one logical pixel", sourceLocation: sourceLocation)
        }
    }
}
