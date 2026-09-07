import AppKit
import Darwin
import SwiftTerm
import XCTest

@testable import PetTerminal

private func bundledAtlasURL() throws -> URL {
    let resources = try XCTUnwrap(Bundle(for: AppDelegate.self).resourceURL)
    let definition = try PetDefinition.load(directory: resources)
    return resources.appendingPathComponent(definition.spritesheetPath)
}

final class GeometryTests: XCTestCase {
    func testAttachedLayoutAtEveryCorner() {
        let screen = CGRect(x: 0, y: 30, width: 1440, height: 850)
        for x in [-300.0, 0, 1400, 2400] {
            for y in [-500.0, 30, 880, 1400] {
                let layout = OverlayGeometry.layout(
                    pet: CGRect(x: x, y: y, width: 160, height: 174), terminalSize: CGSize(width: 560, height: 340),
                    in: screen)
                XCTAssertTrue(screen.contains(layout.pet))
                XCTAssertTrue(screen.contains(layout.terminal!))
                XCTAssertGreaterThanOrEqual(layout.terminal!.minY, layout.pet.maxY)
            }
        }
    }
    func testNegativeMonitorCoordinates() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let result = OverlayGeometry.layout(
            pet: CGRect(x: 900, y: 900, width: 160, height: 174), terminalSize: CGSize(width: 560, height: 340),
            in: screen)
        XCTAssertTrue(screen.contains(result.pet))
        XCTAssertTrue(screen.contains(result.terminal!))
    }
    func testSmallDisplayFitsBothWindows() {
        let screen = CGRect(x: 0, y: 0, width: 420, height: 600)
        let result = OverlayGeometry.layout(
            pet: CGRect(x: 600, y: 500, width: 160, height: 174), terminalSize: CGSize(width: 900, height: 900),
            in: screen)
        XCTAssertTrue(screen.contains(result.pet))
        XCTAssertTrue(screen.contains(result.terminal!))
        XCTAssertLessThanOrEqual(result.terminal!.width, 396)
    }
    func testHiddenTerminalAllowsFullHeight() {
        let result = OverlayGeometry.layout(
            pet: CGRect(x: 500, y: 700, width: 160, height: 174), terminalSize: nil,
            in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertNil(result.terminal)
        XCTAssertEqual(result.pet.minY, 700)
    }
    func testMotionDoesNotOvershootOrJumpAfterSleep() {
        XCTAssertEqual(
            OverlayGeometry.step(from: .zero, toward: CGPoint(x: 1, y: 0), speed: 100, elapsed: 1), CGPoint(x: 1, y: 0))
        let step = OverlayGeometry.step(from: .zero, toward: CGPoint(x: 1000, y: 0), speed: 50, elapsed: 3600)
        XCTAssertEqual(step.x, 5, accuracy: 0.001)
        XCTAssertEqual(OverlayGeometry.step(from: .zero, toward: .zero, speed: 50, elapsed: 1), .zero)
    }
    func testAtlasLoadsOriginalV2Frames() throws {
        let url = try bundledAtlasURL()
        let atlas = try SpriteAtlas(url: url)
        XCTAssertEqual(atlas.rows.map(\.count), [6, 8, 8, 4])
        XCTAssertEqual(atlas.rows[0][0].bitmap.pixelsWide, 192)
    }
}

final class EyeTrackingTests: XCTestCase {
    func testAllSixteenDirectionsInScreenCoordinates() {
        // A display to the left/below the primary display must use the same directions.
        for center in [CGPoint.zero, CGPoint(x: -1600, y: -500)] {
            for direction in 0..<16 {
                let angle = CGFloat(direction) * .pi / 8
                let point = CGPoint(x: center.x + sin(angle) * 500, y: center.y + cos(angle) * 500)
                XCTAssertEqual(EyeTracking.direction(pointer: point, face: center, previous: nil), direction)
            }
        }
    }

    func testNeutralAndBoundaryHysteresis() {
        XCTAssertNil(EyeTracking.direction(pointer: .zero, face: .zero, previous: 4))
        XCTAssertNil(EyeTracking.direction(pointer: CGPoint(x: CGFloat.infinity, y: 1), face: .zero, previous: nil))
        func point(_ degrees: CGFloat) -> CGPoint {
            CGPoint(x: sin(degrees * .pi / 180) * 100, y: cos(degrees * .pi / 180) * 100)
        }
        XCTAssertEqual(EyeTracking.direction(pointer: point(12), face: .zero, previous: 0), 0)
        XCTAssertEqual(EyeTracking.direction(pointer: point(16), face: .zero, previous: 0), 1)
        XCTAssertEqual(EyeTracking.direction(pointer: point(359), face: .zero, previous: 0), 0)
    }

    func testOriginalVisorsAndEveryGazePreserveSpriteSilhouette() throws {
        let definition = try PetDefinition.load(directory: XCTUnwrap(Bundle(for: AppDelegate.self).resourceURL))
        guard definition.gazeMode == .visor else { throw XCTSkip("This artwork does not use the visor compositor.") }
        let url = try bundledAtlasURL()
        let atlas = try SpriteAtlas(url: url)
        XCTAssertEqual(atlas.looks.count, 16)
        let looks = try atlas.looks.map { try XCTUnwrap($0.visor) }
        for row in atlas.rows {
            for frame in row {
                let face = try XCTUnwrap(frame.visor)
                for look in looks {
                    let cg = try XCTUnwrap(face.applying(look))
                    let result = try XCTUnwrap(VisorSurface(image: cg))
                    XCTAssertTrue(
                        stride(from: 3, to: face.pixels.count, by: 4).allSatisfy {
                            result.pixels[$0] == face.pixels[$0]
                        }, "Eye tracking changed sprite alpha")
                    // Only visor pixels may change; body, helmet, and flames are untouched.
                    var unchangedOutside = true
                    for y in 0..<208 {
                        for x in 0..<192 {
                            let r = y - face.top
                            let inside =
                                r >= 0 && r < face.spans.count && x >= face.spans[r].left && x <= face.spans[r].right
                            if !inside {
                                let i = (y * 192 + x) * 4
                                if result.pixels[i..<i + 4] != face.pixels[i..<i + 4] { unchangedOutside = false }
                            }
                        }
                    }
                    XCTAssertTrue(unchangedOutside, "Eye tracking changed artwork outside the visor")
                }
            }
        }
    }

    @MainActor func testMouseTrackingWithMovedResizedWindowAndReducedMotion() throws {
        let url = try bundledAtlasURL()
        let pet = PetView(atlas: try SpriteAtlas(url: url))
        let panel = PetPanel(
            contentRect: CGRect(x: -900, y: -400, width: 160, height: 208 * 160 / 192),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = pet
        pet.animate(row: 1, time: 100, reduced: true)
        pet.trackMouse(at: CGPoint(x: 2000, y: panel.frame.minY + 100.5 * pet.bounds.height / 208))
        XCTAssertEqual(pet.gaze, 4)
        panel.setFrame(CGRect(x: 500, y: 300, width: 210, height: 208 * 210 / 192), display: false)
        pet.trackMouse(at: CGPoint(x: -2000, y: panel.frame.minY + 100.5 * pet.bounds.height / 208))
        XCTAssertEqual(pet.gaze, 12)
        pet.trackMouse(at: CGPoint(x: panel.frame.minX + pet.bounds.width / 2, y: 3000))
        XCTAssertEqual(pet.gaze, 0)
        panel.close()
    }
}

final class ConfigurationTests: XCTestCase {
    private let base: [String: Any] = [
        "id": "moon-cat", "displayName": "Moon Cat", "description": "A custom companion", "spriteVersionNumber": 2,
        "spritesheetPath": "cat.png",
    ]
    private func decode(_ values: [String: Any]) throws -> PetDefinition {
        try JSONDecoder().decode(PetDefinition.self, from: JSONSerialization.data(withJSONObject: values))
    }
    func testPortableManifestDefaults() throws {
        let pet = try decode(base)
        XCTAssertEqual(pet.displayName, "Moon Cat")
        XCTAssertEqual(pet.gazeMode, .directional)
        XCTAssertEqual(pet.terminal.background.values, [0, 0, 0, 0])
    }
    func testRejectsUnsafePathsAndUnsupportedGeometry() throws {
        for path in ["../cat.png", "/tmp/cat.png", "folder\\cat.webp", "cat.jpg"] {
            var values = base
            values["spritesheetPath"] = path
            XCTAssertThrowsError(try decode(values))
        }
        var values = base
        values["spriteVersionNumber"] = 1
        XCTAssertThrowsError(try decode(values))
        values = base
        values["id"] = "cat%#"
        XCTAssertThrowsError(try decode(values))
    }
    func testValidatesRGBAAndGazeMode() throws {
        for json in ["[0,0,0]", "[0,0,0,1.1]", "[-1,0,0,1]"] {
            XCTAssertThrowsError(try JSONDecoder().decode(RGBA.self, from: Data(json.utf8)))
        }
        var values = base
        values["gazeMode"] = "unrecognized"
        XCTAssertThrowsError(try decode(values))
        values["gazeMode"] = "off"
        XCTAssertEqual(try decode(values).gazeMode, .off)
    }
    func testDirectionalAndOffRenderingModes() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let definition = try PetDefinition.load(directory: XCTUnwrap(bundle.resourceURL))
        let atlas = try SpriteAtlas(
            url: XCTUnwrap(bundle.resourceURL).appendingPathComponent(definition.spritesheetPath))
        XCTAssertTrue(atlas.image(row: 1, column: 0, gaze: 8, mode: .directional) === atlas.looks[8].image)
        XCTAssertTrue(atlas.image(row: 1, column: 0, gaze: 8, mode: .off) === atlas.rows[1][0].image)
        XCTAssertTrue(atlas.image(row: 0, column: 0, gaze: nil, mode: .directional) === atlas.rows[0][0].image)
    }
}

final class ProcessProbe: LocalProcessDelegate {
    var text = ""
    var output: ((String) -> Void)?
    var exited: (() -> Void)?
    func sizeChanged() {}
    func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }
    func dataReceived(slice: ArraySlice<UInt8>) {
        text += String(decoding: slice, as: UTF8.self)
        output?(text)
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) { exited?() }
}

final class TerminalIntegrationTests: XCTestCase {
    func testRealPTYDirectoryAndANSIOutput() throws {
        let probe = ProcessProbe()
        let gotOutput = expectation(description: "PTY output")
        let process = LocalProcess(delegate: probe)
        var fulfilled = false
        probe.output = { text in
            if text.contains("EMBER-PTY-OK"), text.contains("/private/tmp"), text.contains("\u{1b}[36m"), !fulfilled {
                fulfilled = true
                gotOutput.fulfill()
            }
        }
        process.startProcess(executable: "/bin/zsh", args: ["-f"], currentDirectory: "/private/tmp")
        process.send(data: Array("pwd; printf '\\033[36mEMBER-PTY-OK\\033[0m\\n'\r".utf8)[...])
        wait(for: [gotOutput], timeout: 5)
        XCTAssertTrue(probe.text.contains("\u{1b}[36m"))
        let exited = expectation(description: "shell exited")
        probe.exited = { exited.fulfill() }
        process.send(data: Array("exit\r".utf8)[...])
        wait(for: [exited], timeout: 5)
    }
    func testInteractiveInputResizeAndControlC() {
        let probe = ProcessProbe()
        let ready = expectation(description: "shell ready")
        let interrupted = expectation(description: "Ctrl-C received")
        let process = LocalProcess(delegate: probe)
        var readyDone = false
        var interruptDone = false
        probe.output = { text in
            if text.components(separatedBy: "READY-EMBER").count >= 3, !readyDone {
                readyDone = true
                ready.fulfill()
            }
            if text.components(separatedBy: "AFTER-INT-EMBER").count >= 3, !interruptDone {
                interruptDone = true
                interrupted.fulfill()
            }
        }
        process.startProcess(executable: "/bin/zsh", args: ["-f"], environment: ["TERM=xterm-256color", "PS1=EMBER> "])
        process.send(data: Array("echo READY-EMBER\r".utf8)[...])
        wait(for: [ready], timeout: 5)
        var dimensions = winsize(ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        XCTAssertEqual(ioctl(process.childfd, TIOCSWINSZ, &dimensions), 0)
        var actual = winsize()
        XCTAssertEqual(ioctl(process.childfd, TIOCGWINSZ, &actual), 0)
        XCTAssertEqual(actual.ws_col, 100)
        XCTAssertEqual(actual.ws_row, 30)
        process.send(data: Array("sleep 20\r".utf8)[...])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            process.send(data: [3][...])
            process.send(data: Array("echo AFTER-INT-EMBER\r".utf8)[...])
        }
        wait(for: [interrupted], timeout: 5)
        let exited = expectation(description: "shell reaped")
        probe.exited = { exited.fulfill() }
        let pid = process.shellPid
        process.send(data: Array("exit\r".utf8)[...])
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(kill(pid, 0), -1)
    }

    @MainActor func testControllerStopReapsShellAndForegroundJob() {
        let controller = TerminalController(
            directory: URL(fileURLWithPath: "/private/tmp"), size: CGSize(width: 560, height: 340))
        controller.start(shellArguments: ["-f"])
        let pid = controller.terminal.process.shellPid
        XCTAssertGreaterThan(pid, 0)
        controller.terminal.process.send(data: Array("sleep 20\r".utf8)[...])
        let ready = expectation(description: "foreground job started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ready.fulfill() }
        wait(for: [ready], timeout: 2)
        let foreground = tcgetpgrp(controller.terminal.process.childfd)
        XCTAssertGreaterThan(foreground, 0)
        XCTAssertNotEqual(foreground, pid)
        let stopped = expectation(description: "owned process cleanup")
        controller.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 3)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(kill(foreground, 0), -1)
    }
}
