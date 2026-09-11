import AppKit

/// The scroll view behind the canvas, owning every way of moving around it.
/// Events land here rather than on the drawing because on an unbounded canvas
/// the pointer is usually over empty space beside the drawing.
///
/// Trackpad pinch is handled by NSScrollView and two-finger scroll pans. A
/// mouse wheel has no pinch and only one axis, so its plain scroll zooms about
/// the pointer, shift scrolls sideways and control scrolls up and down.
/// Command or option with any device zooms, and a middle-button drag pans.
final class CanvasScrollView: NSScrollView {
    /// Called with the click location in the content view's coordinates.
    var onDoubleClick: ((CGPoint) -> Void)?

    private var dragAnchor: CGPoint?

    /// Positions the viewport so `origin` is its bounds origin, clamped the
    /// way the clip view clamps its own scrolling.
    func scroll(toOrigin origin: CGPoint) {
        let clipView = contentView
        let wanted = CGRect(origin: origin, size: clipView.bounds.size)
        clipView.scroll(to: clipView.constrainBoundsRect(wanted).origin)
        reflectScrolledClipView(clipView)
    }

    // MARK: - Scroll wheel

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isWheel = !event.hasPreciseScrollingDeltas
        let pointer = contentView.convert(event.locationInWindow, from: nil)

        if flags.contains(.command) || flags.contains(.option) {
            zoom(by: isWheel ? event.scrollingDeltaY * 0.1 : event.scrollingDeltaY * 0.01, at: pointer)
        } else if isWheel, flags.contains(.shift) {
            // AppKit swaps the axes for shift+wheel on some mice; take whichever
            // one carries the movement.
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            pan(dx: delta * horizontalLineScroll, dy: 0)
        } else if isWheel, flags.contains(.control) {
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            pan(dx: 0, dy: delta * verticalLineScroll)
        } else if isWheel {
            zoom(by: event.scrollingDeltaY * 0.1, at: pointer)
        } else {
            // Trackpad, including momentum. Handled here rather than by
            // NSScrollView, which refuses to scroll a document that fits.
            pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }
    }

    /// Multiplies the magnification by e^delta, keeping the document point
    /// under `pointer` (in content view coordinates) fixed on screen.
    private func zoom(by delta: CGFloat, at pointer: CGPoint) {
        guard delta != 0 else { return }
        let current = magnification
        let target = max(minMagnification, min(maxMagnification, current * exp(max(-1, min(1, delta)))))
        guard target != current else { return }

        // The pointer's distance from the viewport's origin corner in screen
        // points; the same corner is the bounds origin at any magnification.
        let bounds = contentView.bounds
        let offset = CGPoint(x: (pointer.x - bounds.minX) * current, y: (pointer.y - bounds.minY) * current)

        magnification = target
        scroll(toOrigin: CGPoint(x: pointer.x - offset.x / target, y: pointer.y - offset.y / target))
    }

    /// Scrolls by screen-point deltas. Positive deltas mean the content moves
    /// right or down, matching NSEvent's scrolling deltas.
    private func pan(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }
        var origin = contentView.bounds.origin
        origin.x -= dx / magnification
        origin.y += (contentView.isFlipped ? -dy : dy) / magnification
        scroll(toOrigin: origin)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return super.mouseDown(with: event) }
        onDoubleClick?(contentView.convert(event.locationInWindow, from: nil))
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        dragAnchor = contentView.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let dragAnchor else { return super.otherMouseDragged(with: event) }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var origin = contentView.bounds.origin
        origin.x += dragAnchor.x - point.x
        origin.y += dragAnchor.y - point.y
        scroll(toOrigin: origin)
        // The anchor is in content coordinates, which just moved with the scroll.
        self.dragAnchor = contentView.convert(event.locationInWindow, from: nil)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard dragAnchor != nil else { return super.otherMouseUp(with: event) }
        dragAnchor = nil
        NSCursor.pop()
    }
}
