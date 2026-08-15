import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    let isEnabled: Bool
    let isDragLocked: Bool
    let onMove: (CGSize) -> Void
    let onScroll: (CGFloat) -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onRightTap: () -> Void
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMove: onMove, onScroll: onScroll, onTap: onTap,
                    onDoubleTap: onDoubleTap, onRightTap: onRightTap,
                    onDragBegin: onDragBegin, onDragEnd: onDragEnd)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.move(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1

        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.numberOfTouchesRequired = 1
        tap.require(toFail: move)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        tap.require(toFail: doubleTap)

        let rightTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rightTap))
        rightTap.numberOfTouchesRequired = 2

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        longPress.minimumPressDuration = 0.42
        longPress.allowableMovement = 12
        longPress.delegate = context.coordinator
        move.delegate = context.coordinator

        view.addGestureRecognizer(move)
        view.addGestureRecognizer(scroll)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(rightTap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = isEnabled
        context.coordinator.onMove = onMove
        context.coordinator.onScroll = onScroll
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onRightTap = onRightTap
        context.coordinator.onDragBegin = onDragBegin
        context.coordinator.onDragEnd = onDragEnd
        context.coordinator.isDragLocked = isDragLocked
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onMove: (CGSize) -> Void
        var onScroll: (CGFloat) -> Void
        var onTap: () -> Void
        var onDoubleTap: () -> Void
        var onRightTap: () -> Void
        var onDragBegin: () -> Void
        var onDragEnd: () -> Void
        var isDragLocked = false

        init(onMove: @escaping (CGSize) -> Void,
             onScroll: @escaping (CGFloat) -> Void,
             onTap: @escaping () -> Void,
             onDoubleTap: @escaping () -> Void,
             onRightTap: @escaping () -> Void,
             onDragBegin: @escaping () -> Void,
             onDragEnd: @escaping () -> Void) {
            self.onMove = onMove
            self.onScroll = onScroll
            self.onTap = onTap
            self.onDoubleTap = onDoubleTap
            self.onRightTap = onRightTap
            self.onDragBegin = onDragBegin
            self.onDragEnd = onDragEnd
        }

        @objc func move(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            onMove(CGSize(width: delta.x, height: delta.y))
        }

        @objc func scroll(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            onScroll(delta.y)
        }

        @objc func tap() {
            onTap()
        }

        @objc func doubleTap() {
            onDoubleTap()
        }

        @objc func rightTap() {
            onRightTap()
        }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                if !isDragLocked { onDragBegin() }
            case .ended, .cancelled, .failed:
                if !isDragLocked { onDragEnd() }
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer
        }
    }
}
