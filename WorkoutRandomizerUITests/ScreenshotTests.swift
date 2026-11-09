import XCTest

/// App Store screenshot capture (and the slow pass used for the preview video).
///
/// Driven by capture.sh through TEST_RUNNER_ env vars (the prefix is stripped):
///   SCREENSHOT_DEVICE        tag used in file names, e.g. iphone69, duo_outer, duo_inner
///   SCREENSHOT_LANG          e.g. en
///   SCREENSHOT_ORIENTATIONS  comma list: portrait, landscape
///   SCREENSHOT_SLOW          seconds to linger on each screen (default 0.8); used while recording
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    private var deviceTag: String { env["SCREENSHOT_DEVICE"] ?? "device" }
    private var lang: String { env["SCREENSHOT_LANG"] ?? "en" }
    private var settle: TimeInterval { TimeInterval(env["SCREENSHOT_SLOW"] ?? "") ?? 0.8 }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            // Argument-domain defaults override @AppStorage: skip the onboarding guide
            // (a "seen" version newer than any release) and the video-mode prompt.
            "-lastSeenTutorialVersion", "99.0",
            "-lastSeenTutorialBuild", "1",
            "-didPromptForVideoMode", "YES",
            // A demo age so the Settings tab has no "!" badge.
            "-hrZone_manualAgeOverride", "35",
            "-AppleLanguages", "(\(lang))",
            "-AppleLocale", lang,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
    }

    @MainActor
    func testCaptureScreens() throws {
        // A fresh simulator shows a Health permission sheet; decline it whenever it appears.
        addUIInterruptionMonitor(withDescription: "Health permission") { alert in
            let decline = alert.buttons["Don’t Allow"]
            if decline.exists { decline.tap(); return true }
            return false
        }

        for orientation in requestedOrientations() {
            XCUIDevice.shared.orientation = orientation.value
            app.launch()

            // 01 – Generator
            pause(2)
            dismissHealthSheet()
            snap("01_home", orientation.name)

            // Generate a workout and scroll it into view.
            // A focus area has to be chosen first, or the button reads "Focus Area(s) must be selected".
            dismissHealthSheet()
            if app.buttons["All"].waitForExistence(timeout: 3) { app.buttons["All"].tap() }
            let generate = app.buttons["Generate Workout"]
            scrollUntilHittable(generate)
            if !generate.isHittable {
                // Diagnostic: capture what the test could see when the button wasn't reachable.
                let note = XCTAttachment(string: "exists=\(generate.exists) frame=\(generate.frame)\n\(app.debugDescription)")
                note.name = "\(deviceTag)_debug_generate_\(orientation.name).txt"
                note.lifetime = .keepAlways
                add(note)
                snap("99_debug", orientation.name)
            }
            if generate.isHittable || generate.exists {
                // tap() scrolls the element into view itself when gestures didn't manage to.
                generate.tap()
                pause(1.5)
                app.swipeUp()
                pause()
                snap("02_detail", orientation.name)
                runWorkoutAndRecap(orientation.name)
            }

            if app.buttons["Stretch"].exists == false { pause(1) }
            // Stretch mode of the generator.
            let stretch = app.buttons["Stretch"]
            if stretch.exists {
                stretch.tap()
                pause()
                snap("03_stretch", orientation.name)
                app.buttons["Workout"].tap()
            }

            // Remaining tabs.
            for (index, tab) in ["Timer", "Exercises", "Saved", "Settings"].enumerated() {
                if let button = tabElement(tab) {
                    button.tap()
                    pause()
                    snap("0\(index + 4)_\(tab.lowercased())", orientation.name)
                }
            }

            app.terminate()
        }
    }

    /// A real 5-minute workout with no skipping: sets Total Duration to 5 min, starts it, grabs the
    /// player a little way in (`10_player`), then waits for the routine to finish on its own and
    /// grabs the recap (`11_recap`). Takes about 6 minutes; capture.sh's run_pass.sh records it.
    @MainActor
    func testWorkoutPass() throws {
        guard let orientation = requestedOrientations().first else { return }
        XCUIDevice.shared.orientation = orientation.value
        app.launch()
        pause(2)
        dismissHealthSheet()

        // Timer tab → 5 min total.
        if let timerTab = tabElement("Timer") {
            timerTab.tap()
            pause()
            let fiveMinutes = app.buttons["5 min"].firstMatch
            if fiveMinutes.waitForExistence(timeout: 4) { fiveMinutes.tap() }
            pause()
        }
        if let generateTab = tabElement("Generate") { generateTab.tap() }
        pause()

        // Generate.
        dismissHealthSheet()
        if app.buttons["All"].waitForExistence(timeout: 3) { app.buttons["All"].tap() }
        let generate = app.buttons["Generate Workout"]
        scrollUntilHittable(generate)
        guard generate.isHittable || generate.exists else { return }
        generate.tap()
        pause(1.5)

        // Start Workout → the player's own Start.
        let startWorkout = app.buttons["Start Workout"]
        scrollUntilHittable(startWorkout)
        guard startWorkout.isHittable || startWorkout.exists else { return }
        startWorkout.tap()
        // With Health still undecided the player asks for it first (after a short status check).
        pause(7)
        dismissHealthSheet()
        let start = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Start'")).firstMatch
        guard start.waitForExistence(timeout: 8) else { return }
        start.tap()

        // Let the first exercise get going, then take the player.
        pause(14)
        snap("10_player", orientation.name)

        // Run to the end, hands off.
        let recap = app.staticTexts["Workout Complete!"]
        XCTAssertTrue(recap.waitForExistence(timeout: 480), "The workout never reached its recap")
        pause(2)
        snap("11_recap", orientation.name)
        pause(4)
    }

    // MARK: - Helpers

    /// Start Workout → player (countdown, running, skip) → skip to the end → recap → Done.
    /// Every step is guarded so a missing control just ends the sequence.
    private func runWorkoutAndRecap(_ orientation: String) {
        let startWorkout = app.buttons["Start Workout"]
        scrollUntilHittable(startWorkout)
        guard startWorkout.isHittable || startWorkout.exists else { return }
        startWorkout.tap()

        // The player's green Start button (its label includes the play icon's name).
        let start = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Start'")).firstMatch
        guard start.waitForExistence(timeout: 8) else { return }
        pause()
        snap("08_player_ready", orientation)
        start.tap()

        pause(1.2)
        snap("09_countdown", orientation)

        // Let it run: a long beat in the slow (recording) pass so the demo video and timer play.
        let running = settle > 1 ? 24.0 : 6.0
        pause(running)
        snap("10_player", orientation)

        let skip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Skip'")).firstMatch
        if skip.exists { skip.tap(); pause(settle > 1 ? 3 : 1) }

        // Tap Skip through the rest of the routine until the recap appears.
        let recap = app.staticTexts["Workout Complete!"]
        var skips = 0
        while !recap.exists && skips < 120 {
            dismissHealthSheet()
            if skip.exists { skip.tap() }
            skips += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        if recap.waitForExistence(timeout: 6) {
            pause(1.5)
            snap("11_recap", orientation)
            if settle > 1 { pause(4) }
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() }
            pause(1.5)
        }
    }

    /// Scroll toward `element` until it's tappable. On the Duo's inner display, gestures can be
    /// applied in a rotated frame, so if a vertical swipe doesn't move the element, try the
    /// other directions and keep using whichever one does.
    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 14) {
        let swipes: [() -> Void] = [
            { self.app.swipeUp() }, { self.app.swipeLeft() }, { self.app.swipeRight() }, { self.app.swipeDown() },
        ]
        var working = 0
        var count = 0
        while !element.isHittable && count < maxSwipes {
            let before = element.exists ? element.frame : .zero
            swipes[working]()
            count += 1
            guard element.exists, !element.isHittable else { continue }
            if element.frame == before, working < swipes.count - 1 { working += 1 }
        }
    }

    /// The tab bar's button on compact layouts, or the sidebar row on regular-width ones
    /// (the Duo's inner display), which may surface as a button, cell or static text.
    private func tabElement(_ label: String) -> XCUIElement? {
        _ = app.tabBars.buttons[label].waitForExistence(timeout: 3)
        let candidates = [app.tabBars.buttons[label], app.buttons[label], app.cells[label], app.staticTexts[label]]
        return candidates.first { $0.exists && $0.isHittable }
    }

    /// The Duo has two displays and `XCUIScreen.main` is the outer one, which is dark when the
    /// phone is open. For the inner pass (tag contains \"inner\") use the biggest display, which is where the app is.
    private func largestScreenshot() -> XCUIScreenshot {
        // Only the inner-display pass needs the big screen; everything else uses the main one.
        guard deviceTag.contains("inner") else { return XCUIScreen.main.screenshot() }
        let shots = XCUIScreen.screens.map { $0.screenshot() }
        return shots.max { $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height }
            ?? XCUIScreen.main.screenshot()
    }

    /// If the Health sheet is up, answers it the way a user would: Select All, Continue, a data
    /// range, Allow. (The sheet is the app's own prompt now, so it can appear before a workout.)
    private func dismissHealthSheet() {
        let all = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        guard all.exists else { return }
        all.tap()
        pause(0.6)
        let proceed = app.buttons["Continue"].firstMatch
        scrollUntilHittable(proceed, maxSwipes: 8)
        if proceed.exists { proceed.tap() }
        pause(1.2)
        let range = app.staticTexts["Past 30 Days and Future Data"].firstMatch
        if range.waitForExistence(timeout: 3) { range.tap() }
        pause(0.6)
        let allow = app.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        pause(1.5)
    }

    private func snap(_ name: String, _ orientation: String) {
        dismissHealthSheet()
        let attachment = XCTAttachment(screenshot: largestScreenshot())
        // Exported by capture.sh as: iphone69_en_01_home_portrait
        attachment.name = "\(deviceTag)_\(lang)_\(name)_\(orientation)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Let transitions finish before capturing; longer in the slow (recording) pass.
    private func pause(_ minimum: TimeInterval = 0) {
        let seconds = max(settle, minimum)
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    private func requestedOrientations() -> [(name: String, value: UIDeviceOrientation)] {
        let raw = env["SCREENSHOT_ORIENTATIONS"] ?? "portrait"
        return raw.split(separator: ",").compactMap {
            switch $0.trimmingCharacters(in: .whitespaces) {
            case "portrait": return ("portrait", .portrait)
            case "landscape": return ("landscape", .landscapeLeft)
            default: return nil
            }
        }
    }
}
