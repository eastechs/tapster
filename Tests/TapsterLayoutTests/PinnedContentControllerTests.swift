import AppKit
import XCTest

@testable import TapsterLayout

final class PinnedContentControllerTests: XCTestCase {
  @MainActor func testInternalSizePressureCannotInsetContent() {
    let child = NSViewController()
    child.view = NSView()
    let container = PinnedContentController(content: child)
    let root = container.view
    root.frame = NSRect(x: 0, y: 0, width: 1320, height: 780)

    // Match the lower-priority size constraints used by native divider dragging.
    let pressure = child.view.widthAnchor.constraint(equalToConstant: 1100)
    pressure.priority = .dragThatCannotResizeWindow
    pressure.isActive = true
    for width in [1320.0, 1100.0, 1500.0] {
      root.setFrameSize(NSSize(width: width, height: 780))
      root.layoutSubtreeIfNeeded()
      XCTAssertEqual(child.view.frame, root.bounds)
    }
    XCTAssertTrue(child.parent === container)
  }

  @MainActor func testDividerChangesAndCollapseKeepTheOuterBounds() {
    let split = NSSplitViewController()
    split.splitView.isVertical = true
    for index in 0..<3 {
      let pane = NSViewController()
      pane.view = NSView()
      let item =
        index == 0
        ? NSSplitViewItem(sidebarWithViewController: pane)
        : NSSplitViewItem(viewController: pane)
      item.minimumThickness = index == 0 ? 170 : 240
      item.holdingPriority = .init(index == 1 ? 240 : 260)
      item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
      split.addSplitViewItem(item)
    }
    let container = PinnedContentController(content: split)
    let root = container.view
    root.frame = NSRect(x: 0, y: 0, width: 1320, height: 780)
    root.layoutSubtreeIfNeeded()

    for position in [190.0, 250.0, 170.0, 220.0] {
      split.splitView.setPosition(position, ofDividerAt: 0)
      root.layoutSubtreeIfNeeded()
      XCTAssertEqual(split.view.frame, root.bounds)
      XCTAssertEqual(split.splitViewItems[0].viewController.view.frame.width, position, accuracy: 1)
    }
    for collapsed in [true, false, true, false] {
      split.splitViewItems[0].isCollapsed = collapsed
      root.layoutSubtreeIfNeeded()
      XCTAssertEqual(split.view.frame, root.bounds)
    }
  }
}
