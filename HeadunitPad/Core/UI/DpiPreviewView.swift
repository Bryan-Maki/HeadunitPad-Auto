//
//  DpiPreviewView.swift
//  HeadunitPad
//
//  Schematic CoreGraphics Coolwalk split-screen layout visualizer.
//  1:1 port and aesthetic enhancement of open-headunit DpiPreviewView.kt & DpiPickerView.kt.
//  Dynamically scales all UI components (dock, cards, icons, fonts, padding) proportionally
//  with density scale = CGFloat(dpi) / 160.0 and virtual resolution dp.
//

import UIKit

public final class DpiPreviewView: UIView {
    public var dpi: Int = 160 {
        didSet {
            if oldValue != dpi {
                setNeedsDisplay()
            }
        }
    }

    public var panelWidthPx: Int = 1920 {
        didSet {
            if oldValue != panelWidthPx {
                setNeedsDisplay()
            }
        }
    }

    public var panelHeightPx: Int = 1080 {
        didSet {
            if oldValue != panelHeightPx {
                setNeedsDisplay()
            }
        }
    }

    public var codecWidthPx: Int = 0 {
        didSet {
            if oldValue != codecWidthPx {
                setNeedsDisplay()
            }
        }
    }

    public var codecHeightPx: Int = 0 {
        didSet {
            if oldValue != codecHeightPx {
                setNeedsDisplay()
            }
        }
    }

    public var activeWidthPx: Int = 0 {
        didSet {
            if oldValue != activeWidthPx {
                setNeedsDisplay()
            }
        }
    }

    public var activeHeightPx: Int = 0 {
        didSet {
            if oldValue != activeHeightPx {
                setNeedsDisplay()
            }
        }
    }

    public var marginWidthPx: Int = 0 {
        didSet {
            if oldValue != marginWidthPx {
                setNeedsDisplay()
            }
        }
    }

    public var marginHeightPx: Int = 0 {
        didSet {
            if oldValue != marginHeightPx {
                setNeedsDisplay()
            }
        }
    }

    public var isRightHandDrive: Bool = false {
        didSet {
            if oldValue != isRightHandDrive {
                setNeedsDisplay()
            }
        }
    }

    public var fitMode: VideoFitMode = .fillMargin {
        didSet {
            if oldValue != fitMode {
                setNeedsDisplay()
            }
        }
    }

    public var virtualWidthDp: Int {
        guard dpi > 0 else { return 0 }
        let w = activeWidthPx > 0 ? activeWidthPx : panelWidthPx
        return (w * 160) / dpi
    }

    public var virtualHeightDp: Int {
        guard dpi > 0 else { return 0 }
        let h = activeHeightPx > 0 ? activeHeightPx : panelHeightPx
        return (h * 160) / dpi
    }

    public var isCoolwalkSplitScreen: Bool {
        return virtualWidthDp >= 800
    }

    public var densityScale: CGFloat {
        guard dpi > 0 else { return 1.0 }
        return CGFloat(dpi) / 160.0
    }

    // Inspectable metrics for unit testing scaling behavior
    public private(set) var lastCalculatedRailWidth: CGFloat = 0
    public private(set) var lastCalculatedSecondaryCardWidth: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        layer.masksToBounds = true
        layer.cornerRadius = 14
    }

    @discardableResult
    public func calculateLayoutMetrics(in rect: CGRect) -> (railWidth: CGFloat, secondaryCardWidth: CGFloat, isSplit: Bool) {
        let pad: CGFloat = 8.0
        let availW = rect.width - pad * 2
        let availH = rect.height - pad * 2
        guard availW > 40 && availH > 40 else {
            lastCalculatedRailWidth = 0
            lastCalculatedSecondaryCardWidth = 0
            return (0, 0, false)
        }

        let panelAspect: CGFloat = (panelWidthPx > 0 && panelHeightPx > 0)
            ? CGFloat(panelWidthPx) / CGFloat(panelHeightPx)
            : 16.0 / 9.0

        var screenW = availW
        var screenH = screenW / panelAspect
        if screenH > availH - 24 {
            screenH = availH - 24
            screenW = screenH * panelAspect
        }

        let innerPadding: CGFloat = 4.0
        let contentWidth = screenW - innerPadding * 2
        let contentHeight = screenH - innerPadding * 2

        let dpToCanvas = screenW / CGFloat(max(1, virtualWidthDp))
        let isSplit = isCoolwalkSplitScreen

        let railWidth: CGFloat = isSplit ? min(contentWidth * 0.35, max(8.0, 64.0 * dpToCanvas)) : 0
        let bottomBarHeight: CGFloat = isSplit ? 0 : min(contentHeight * 0.30, max(8.0, 56.0 * dpToCanvas))

        let cardsW = contentWidth - (isSplit ? (railWidth + 3) : 0)
        let gap: CGFloat = 4.0
        let targetSecondaryW = 340.0 * dpToCanvas
        let maxSecondaryW = (cardsW - gap) * 0.48
        let secondaryCardWidth = isSplit ? min(maxSecondaryW, max(16.0, targetSecondaryW)) : 0

        lastCalculatedRailWidth = isSplit ? railWidth : bottomBarHeight
        lastCalculatedSecondaryCardWidth = secondaryCardWidth

        return (lastCalculatedRailWidth, lastCalculatedSecondaryCardWidth, isSplit)
    }

    public override func draw(_ rect: CGRect) {
        _ = calculateLayoutMetrics(in: rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()

        let pad: CGFloat = 8.0
        let availW = rect.width - pad * 2
        let availH = rect.height - pad * 2
        guard availW > 40 && availH > 40 else {
            ctx.restoreGState()
            return
        }

        // Outer chassis background (dark carbon tint)
        let outerBezel = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.95).cgColor)
        outerBezel.fill()
        ctx.setStrokeColor(UIColor(white: 0.25, alpha: 0.8).cgColor)
        ctx.setLineWidth(1.0)
        outerBezel.stroke()

        // Maintain panel aspect ratio
        let panelAspect: CGFloat = (panelWidthPx > 0 && panelHeightPx > 0)
            ? CGFloat(panelWidthPx) / CGFloat(panelHeightPx)
            : 16.0 / 9.0

        var screenW = availW
        var screenH = screenW / panelAspect
        if screenH > availH - 24 {
            screenH = availH - 24
            screenW = screenH * panelAspect
        }

        let screenLeft = pad + (availW - screenW) / 2.0
        let screenTop = pad + 20 + (availH - 24 - screenH) / 2.0
        let screenRect = CGRect(x: screenLeft, y: screenTop, width: screenW, height: screenH)

        // Draw screen bezel
        let screenBezel = UIBezierPath(roundedRect: screenRect, cornerRadius: 8)
        ctx.setFillColor(UIColor(white: 0.02, alpha: 1.0).cgColor)
        screenBezel.fill()
        ctx.setStrokeColor(UIColor(white: 0.35, alpha: 0.6).cgColor)
        ctx.setLineWidth(1.5)
        screenBezel.stroke()

        // Coolwalk layout inside screenRect
        let innerPadding: CGFloat = 4.0
        let contentRect = screenRect.insetBy(dx: innerPadding, dy: innerPadding)

        // Mathematical scaling ratio: canvas points per Android dp
        let dpToCanvas = screenW / CGFloat(max(1, virtualWidthDp))
        let scale = densityScale

        let isSplit = isCoolwalkSplitScreen
        let railWidth = isSplit ? lastCalculatedRailWidth : 0
        let bottomBarHeight = isSplit ? 0 : lastCalculatedRailWidth

        // Rail rect
        let railRect: CGRect
        let cardsContainerRect: CGRect

        if isSplit {
            if isRightHandDrive {
                railRect = CGRect(
                    x: contentRect.maxX - railWidth,
                    y: contentRect.minY,
                    width: railWidth,
                    height: contentRect.height
                )
                cardsContainerRect = CGRect(
                    x: contentRect.minX,
                    y: contentRect.minY,
                    width: contentRect.width - railWidth - 3,
                    height: contentRect.height
                )
            } else {
                railRect = CGRect(
                    x: contentRect.minX,
                    y: contentRect.minY,
                    width: railWidth,
                    height: contentRect.height
                )
                cardsContainerRect = CGRect(
                    x: contentRect.minX + railWidth + 3,
                    y: contentRect.minY,
                    width: contentRect.width - railWidth - 3,
                    height: contentRect.height
                )
            }
        } else {
            railRect = CGRect(
                x: contentRect.minX,
                y: contentRect.maxY - bottomBarHeight,
                width: contentRect.width,
                height: bottomBarHeight
            )
            cardsContainerRect = CGRect(
                x: contentRect.minX,
                y: contentRect.minY,
                width: contentRect.width,
                height: contentRect.height - bottomBarHeight - 3
            )
        }

        // Draw Rail
        drawNavigationRail(ctx: ctx, rect: railRect, isVertical: isSplit, scale: scale, dpToCanvas: dpToCanvas)

        // Draw Cards
        if isSplit {
            let gap: CGFloat = 4.0
            let secondaryCardWidth = lastCalculatedSecondaryCardWidth
            let primaryCardWidth = cardsContainerRect.width - gap - secondaryCardWidth

            let mapRect: CGRect
            let secondaryContainerRect: CGRect

            if isRightHandDrive {
                secondaryContainerRect = CGRect(
                    x: cardsContainerRect.minX,
                    y: cardsContainerRect.minY,
                    width: secondaryCardWidth,
                    height: cardsContainerRect.height
                )
                mapRect = CGRect(
                    x: cardsContainerRect.minX + secondaryCardWidth + gap,
                    y: cardsContainerRect.minY,
                    width: primaryCardWidth,
                    height: cardsContainerRect.height
                )
            } else {
                mapRect = CGRect(
                    x: cardsContainerRect.minX,
                    y: cardsContainerRect.minY,
                    width: primaryCardWidth,
                    height: cardsContainerRect.height
                )
                secondaryContainerRect = CGRect(
                    x: cardsContainerRect.minX + primaryCardWidth + gap,
                    y: cardsContainerRect.minY,
                    width: secondaryCardWidth,
                    height: cardsContainerRect.height
                )
            }

            drawMapCard(ctx: ctx, rect: mapRect, scale: scale)

            let halfHeight = (secondaryContainerRect.height - gap) / 2.0
            let mediaRect = CGRect(
                x: secondaryContainerRect.minX,
                y: secondaryContainerRect.minY,
                width: secondaryContainerRect.width,
                height: halfHeight
            )
            let widgetRect = CGRect(
                x: secondaryContainerRect.minX,
                y: secondaryContainerRect.minY + halfHeight + gap,
                width: secondaryContainerRect.width,
                height: halfHeight
            )

            drawMediaCard(ctx: ctx, rect: mediaRect, scale: scale)
            drawWidgetCard(ctx: ctx, rect: widgetRect, scale: scale)
        } else {
            lastCalculatedSecondaryCardWidth = 0
            drawMapCard(ctx: ctx, rect: cardsContainerRect, scale: scale)
        }

        // Status Header string: "Active Res: <activeW>x<activeH> (<codecW>x<codecH> cropped) @ <dpi> DPI"
        let statusText: String
        let modeDesc = isSplit ? "Coolwalk Split Screen" : "Single Card Compact"
        if marginWidthPx > 0 || marginHeightPx > 0 {
            statusText = String(
                format: "Active Res: %d×%d (%d×%d cropped) @ %d DPI (%d×%d dp) | %@",
                activeWidthPx, activeHeightPx, codecWidthPx, codecHeightPx, dpi, virtualWidthDp, virtualHeightDp, modeDesc
            )
        } else {
            let effW = activeWidthPx > 0 ? activeWidthPx : panelWidthPx
            let effH = activeHeightPx > 0 ? activeHeightPx : panelHeightPx
            statusText = String(
                format: "Active Res: %d×%d @ %d DPI (%d×%d dp) | %@",
                effW, effH, dpi, virtualWidthDp, virtualHeightDp, modeDesc
            )
        }
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        let textColor = isSplit
            ? UIColor(red: 0.2, green: 0.85, blue: 0.5, alpha: 0.95)
            : UIColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 0.95)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (statusText as NSString).size(withAttributes: attrs)
        let textRect = CGRect(
            x: (rect.width - textSize.width) / 2.0,
            y: pad + 3,
            width: textSize.width,
            height: textSize.height
        )
        (statusText as NSString).draw(in: textRect, withAttributes: attrs)

        ctx.restoreGState()
    }

    private func drawNavigationRail(ctx: CGContext, rect: CGRect, isVertical: Bool, scale: CGFloat, dpToCanvas: CGFloat) {
        let railCorner = max(3.0, 6.0 * scale)
        let railPath = UIBezierPath(roundedRect: rect, cornerRadius: railCorner)
        ctx.setFillColor(UIColor(white: 0.12, alpha: 0.95).cgColor)
        railPath.fill()

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)

        if isVertical {
            // Draw 3x3 App Launcher icon at top
            let iconX = rect.midX
            let iconY = rect.minY + max(12.0, 18.0 * scale)
            let dotRadius: CGFloat = max(1.0, 1.6 * scale)
            let dotSpacing: CGFloat = max(2.5, 4.2 * scale)
            for r in -1...1 {
                for c in -1...1 {
                    let cx = iconX + CGFloat(c) * dotSpacing
                    let cy = iconY + CGFloat(r) * dotSpacing
                    ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                }
            }

            // Draw small home/map pill
            let pillY = iconY + max(18.0, 26.0 * scale)
            let pillW = min(rect.width * 0.7, max(12.0, 20.0 * scale))
            let pillH = max(8.0, 12.0 * scale)
            let pillRect = CGRect(x: rect.midX - pillW / 2.0, y: pillY, width: pillW, height: pillH)
            let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2.0)
            ctx.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.8).cgColor)
            pill.fill()

            // Draw music circle
            let musicY = pillY + max(16.0, 22.0 * scale)
            let musicR: CGFloat = min(rect.width * 0.35, max(5.0, 8.0 * scale))
            ctx.setFillColor(UIColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.midX - musicR, y: musicY, width: musicR * 2, height: musicR * 2))

            // Time text at bottom
            let fontSize = max(6.0, 8.0 * scale)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let timeStr = "12:45"
            let timeSize = (timeStr as NSString).size(withAttributes: timeAttrs)
            (timeStr as NSString).draw(
                at: CGPoint(x: rect.midX - timeSize.width / 2.0, y: rect.maxY - timeSize.height - 4),
                withAttributes: timeAttrs
            )
        } else {
            // Horizontal bottom bar
            let iconY = rect.midY
            let dotRadius: CGFloat = max(1.0, 1.8 * scale)
            let dotSpacing: CGFloat = max(2.5, 4.5 * scale)
            let iconX = rect.minX + max(16.0, 24.0 * scale)
            for r in -1...1 {
                for c in -1...1 {
                    let cx = iconX + CGFloat(c) * dotSpacing
                    let cy = iconY + CGFloat(r) * dotSpacing
                    ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                }
            }

            // Central pills
            let midX = rect.midX
            let pillW = max(14.0, 20.0 * scale)
            let pillH = max(10.0, 14.0 * scale)
            let p1 = CGRect(x: midX - pillW - 2, y: rect.midY - pillH / 2.0, width: pillW, height: pillH)
            let p2 = CGRect(x: midX + 2, y: rect.midY - pillH / 2.0, width: pillW, height: pillH)
            ctx.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.8).cgColor)
            UIBezierPath(roundedRect: p1, cornerRadius: pillH / 3.0).fill()
            ctx.setFillColor(UIColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 0.8).cgColor)
            UIBezierPath(roundedRect: p2, cornerRadius: pillH / 3.0).fill()

            // Time right
            let fontSize = max(6.0, 8.0 * scale)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let timeStr = "12:45"
            let timeSize = (timeStr as NSString).size(withAttributes: timeAttrs)
            (timeStr as NSString).draw(
                at: CGPoint(x: rect.maxX - timeSize.width - 12, y: rect.midY - timeSize.height / 2.0),
                withAttributes: timeAttrs
            )
        }
    }

    private func drawMapCard(ctx: CGContext, rect: CGRect, scale: CGFloat) {
        let cardRadius = max(3.0, 6.0 * scale)
        let card = UIBezierPath(roundedRect: rect, cornerRadius: cardRadius)
        ctx.setFillColor(UIColor(red: 0.1, green: 0.14, blue: 0.18, alpha: 0.95).cgColor)
        card.fill()

        // Roads
        ctx.setStrokeColor(UIColor(white: 0.25, alpha: 0.4).cgColor)
        ctx.setLineWidth(max(1.0, 1.5 * scale))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.4))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
        ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.maxY))
        ctx.strokePath()

        // Route polyline (glowing cyan-blue)
        ctx.setStrokeColor(UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).cgColor)
        ctx.setLineWidth(max(1.5, 2.5 * scale))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.8))
        ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.45))
        ctx.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.minY + rect.height * 0.53))
        ctx.strokePath()

        // Turn banner pill
        let bannerW = min(rect.width * 0.85, max(60.0, 110.0 * scale))
        let bannerH = max(12.0, 18.0 * scale)
        let bannerRect = CGRect(x: rect.minX + 6, y: rect.minY + 6, width: bannerW, height: bannerH)
        let banner = UIBezierPath(roundedRect: bannerRect, cornerRadius: bannerH / 4.0)
        ctx.setFillColor(UIColor(red: 0.08, green: 0.45, blue: 0.25, alpha: 0.9).cgColor)
        banner.fill()

        let bannerFontSize = max(6.0, 7.5 * scale)
        let bannerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: bannerFontSize, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        (" Turn Right (200m)" as NSString).draw(
            in: bannerRect.insetBy(dx: 4, dy: max(1.0, (bannerH - bannerFontSize - 2) / 2.0)),
            withAttributes: bannerAttrs
        )
    }

    private func drawMediaCard(ctx: CGContext, rect: CGRect, scale: CGFloat) {
        let cardRadius = max(3.0, 6.0 * scale)
        let card = UIBezierPath(roundedRect: rect, cornerRadius: cardRadius)
        ctx.setFillColor(UIColor(red: 0.16, green: 0.12, blue: 0.18, alpha: 0.95).cgColor)
        card.fill()

        // Album art square
        let artSide = min(rect.height - 8, max(14.0, 36.0 * scale))
        let artRect = CGRect(x: rect.minX + 6, y: rect.midY - artSide / 2.0, width: artSide, height: artSide)
        let art = UIBezierPath(roundedRect: artRect, cornerRadius: max(2.0, 4.0 * scale))
        ctx.setFillColor(UIColor(red: 0.85, green: 0.25, blue: 0.4, alpha: 0.8).cgColor)
        art.fill()

        // Song title and artist placeholders
        let labelX = artRect.maxX + 6
        let line1W = min(rect.maxX - labelX - 6, max(25.0, 45.0 * scale))
        let line1H = max(2.0, 4.0 * scale)
        let line2H = max(1.5, 3.0 * scale)
        let line1 = CGRect(x: labelX, y: rect.midY - line1H - 1, width: line1W, height: line1H)
        let line2 = CGRect(x: labelX, y: rect.midY + 2, width: line1W * 0.65, height: line2H)

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        UIBezierPath(roundedRect: line1, cornerRadius: line1H / 2.0).fill()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        UIBezierPath(roundedRect: line2, cornerRadius: line2H / 2.0).fill()
    }

    private func drawWidgetCard(ctx: CGContext, rect: CGRect, scale: CGFloat) {
        let cardRadius = max(3.0, 6.0 * scale)
        let card = UIBezierPath(roundedRect: rect, cornerRadius: cardRadius)
        ctx.setFillColor(UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.95).cgColor)
        card.fill()

        // Calendar or weather widget mock
        let iconSide = min(rect.height - 8, max(12.0, 18.0 * scale))
        let iconRect = CGRect(x: rect.minX + 6, y: rect.midY - iconSide / 2.0, width: iconSide, height: iconSide)
        ctx.setFillColor(UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 0.85).cgColor)
        UIBezierPath(ovalIn: iconRect).fill()

        let textX = iconRect.maxX + 6
        let textW = min(rect.maxX - textX - 6, max(30.0, 50.0 * scale))
        let text1H = max(2.0, 4.0 * scale)
        let text2H = max(1.5, 3.0 * scale)
        let text1 = CGRect(x: textX, y: rect.midY - text1H - 1, width: textW, height: text1H)
        let text2 = CGRect(x: textX, y: rect.midY + 2, width: textW * 0.5, height: text2H)

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        UIBezierPath(roundedRect: text1, cornerRadius: text1H / 2.0).fill()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        UIBezierPath(roundedRect: text2, cornerRadius: text2H / 2.0).fill()
    }
}
