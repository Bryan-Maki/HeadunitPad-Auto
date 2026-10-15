import UIKit

public final class TouchInputView: UIView {
    public typealias TouchCallback = ([(id: Int, x: Int, y: Int)], TouchAction, Int) -> Void

    public var onTouch: TouchCallback?
    public var onTouchEvent: TouchCallback? {
        get { return onTouch }
        set { onTouch = newValue }
    }

    public var screenConfig: HeadUnitScreenConfig?
    public var videoFitMode: VideoFitMode = .fillMargin
    public var surfaceSize: CGSize = .zero
    public var codecWidth: Int?
    public var codecHeight: Int?
    public var widthMargin: Int?
    public var heightMargin: Int?

    private var touchIdMap: [ObjectIdentifier: Int] = [:]
    private var activePoints: [Int: CGPoint] = [:]
    private var nextTouchId: Int = 0

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
    }

    public func mapTouchToActiveContent(_ point: CGPoint) -> (x: Int, y: Int) {
        let currentSize = (bounds.size.width > 0 && bounds.size.height > 0) ? bounds.size : surfaceSize
        let cfg = screenConfig ?? HeadUnitScreenConfig.shared
        let mode = videoFitMode
        let cW = codecWidth ?? cfg.getNegotiatedWidth()
        let cH = codecHeight ?? cfg.getNegotiatedHeight()
        let mW = widthMargin ?? cfg.getWidthMargin()
        let mH = heightMargin ?? cfg.getHeightMargin()

        let coord = TouchCoordinateMapper.map(
            rawX: Float(point.x),
            rawY: Float(point.y),
            inputSurfaceWidth: Float(max(currentSize.width, 1)),
            inputSurfaceHeight: Float(max(currentSize.height, 1)),
            negotiatedWidth: cW,
            negotiatedHeight: cH,
            marginWidth: Float(mW),
            marginHeight: Float(mH),
            fitMode: mode
        )
        return (coord.x, coord.y)
    }

    private func sortedMappedPointers() -> [(id: Int, x: Int, y: Int)] {
        return activePoints
            .map { (id: $0.key, point: $0.value) }
            .sorted { $0.id < $1.id }
            .map { pointer in
                let mapped = mapTouchToActiveContent(pointer.point)
                return (id: pointer.id, x: mapped.x, y: mapped.y)
            }
    }

    private func sendTouches(action: TouchAction, actionIndex: Int) {
        let pointers = sortedMappedPointers()
        onTouch?(pointers, action, actionIndex)
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let assignedId: Int
            if let existing = touchIdMap[key] {
                assignedId = existing
            } else {
                assignedId = nextTouchId
                nextTouchId += 1
                touchIdMap[key] = assignedId
            }

            activePoints[assignedId] = touch.location(in: self)
            let sorted = activePoints.keys.sorted()
            let action: TouchAction = activePoints.count == 1 ? .DOWN : .POINTER_DOWN
            let actionIndex = sorted.firstIndex(of: assignedId) ?? 0
            sendTouches(action: action, actionIndex: actionIndex)
        }
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var changed = false
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let id = touchIdMap[key] else { continue }
            activePoints[id] = touch.location(in: self)
            changed = true
        }
        if changed {
            sendTouches(action: .MOVE, actionIndex: 0)
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let id = touchIdMap[key] else { continue }
            activePoints[id] = touch.location(in: self)
            let sorted = activePoints.keys.sorted()
            let action: TouchAction = activePoints.count <= 1 ? .UP : .POINTER_UP
            let actionIndex = sorted.firstIndex(of: id) ?? 0
            sendTouches(action: action, actionIndex: actionIndex)
            activePoints.removeValue(forKey: id)
            touchIdMap.removeValue(forKey: key)
        }

        if activePoints.isEmpty {
            nextTouchId = 0
        }
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if let id = touchIdMap[key] {
                activePoints[id] = touch.location(in: self)
            }
        }
        if !activePoints.isEmpty {
            sendTouches(action: .CANCEL, actionIndex: 0)
        }
        activePoints.removeAll()
        touchIdMap.removeAll()
        nextTouchId = 0
    }
}
