import AppKit
import XCTest

@testable import PetTerminal

final class PetVoiceControlsTests: XCTestCase {
    func testHoverControlRemainsReachableAcrossGapAndThenHides() {
        var hover = PetHoverVisibility()
        hover.update(petHovered: false, controlsHovered: false, keepVisible: false, dragging: false, time: 0)
        XCTAssertFalse(hover.visible)
        hover.update(petHovered: true, controlsHovered: false, keepVisible: false, dragging: false, time: 1)
        XCTAssertTrue(hover.visible)
        hover.update(petHovered: false, controlsHovered: false, keepVisible: false, dragging: false, time: 1.3)
        XCTAssertTrue(hover.visible, "Crossing the gap must not hide the microphone button")
        hover.update(petHovered: false, controlsHovered: true, keepVisible: false, dragging: false, time: 1.5)
        XCTAssertTrue(hover.visible)
        hover.update(petHovered: false, controlsHovered: false, keepVisible: false, dragging: false, time: 2.2)
        XCTAssertFalse(hover.visible)
    }

    func testRecordingKeepsStopAvailableButDraggingAndHideResetControls() {
        var hover = PetHoverVisibility()
        hover.update(petHovered: false, controlsHovered: false, keepVisible: true, dragging: false, time: 100)
        XCTAssertTrue(hover.visible)
        hover.update(petHovered: true, controlsHovered: false, keepVisible: true, dragging: true, time: 101)
        XCTAssertFalse(hover.visible)
        hover.update(petHovered: false, controlsHovered: false, keepVisible: false, dragging: false, time: 102)
        XCTAssertFalse(hover.visible)
        hover.update(petHovered: true, controlsHovered: false, keepVisible: false, dragging: false, time: 103)
        hover.reset()
        XCTAssertFalse(hover.visible)
    }

    func testControlsFitNegativeMonitorAndMoveToLeftAtRightEdge() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let pet = CGRect(x: -172, y: 0, width: 160, height: 174)
        let frame = PetVoiceLayout.frame(pet: pet, size: CGSize(width: 204, height: 38), screen: screen)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertLessThan(frame.maxX, pet.minX)
        for origin in [CGPoint(x: -1908, y: -188), CGPoint(x: -172, y: 694)] {
            let result = PetVoiceLayout.frame(
                pet: CGRect(origin: origin, size: pet.size), size: CGSize(width: 204, height: 38), screen: screen)
            XCTAssertTrue(screen.contains(result))
        }
    }

    @MainActor func testVoiceButtonsHaveIndependentClickTargetsAndAccessibleState() {
        let controls = PetVoiceControls()
        var actions = 0
        var cancellations = 0
        controls.onAction = { actions += 1 }
        controls.onCancel = { cancellations += 1 }
        XCTAssertFalse(controls.panel.ignoresMouseEvents)
        XCTAssertFalse(controls.panel.canBecomeKey)
        XCTAssertTrue(controls.actionButton.acceptsFirstMouse(for: nil))
        controls.actionButton.performClick(nil)
        XCTAssertEqual(actions, 1)
        controls.setState(.listening)
        XCTAssertEqual(controls.actionButton.title, "Stop & Insert")
        XCTAssertFalse(controls.cancelButton.isHidden)
        controls.cancelButton.performClick(nil)
        XCTAssertEqual(cancellations, 1)
        controls.setState(.finalizing)
        XCTAssertFalse(controls.actionButton.isEnabled)
        controls.hide()
    }
}
