//
//  DpiPreviewView.swift
//  HeadunitPad
//
//  Schematic CoreGraphics Coolwalk split-screen layout visualizer.
//  1:1 port and aesthetic enhancement of open-headunit DpiPreviewView.kt & DpiPickerView.kt.
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

    public var panelWidthPx: Int = 2048 {
        didSet {
            if oldValue != panelWidthPx {
                setNeedsDisplay()
            }
        }
    }

    public var panelHeightPx: Int = 1536 {
        didSet {
            if oldValue != panelHeightPx {
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
        return (panelWidthPx * 160) / dpi
    }

    public var virtualHeightDp: Int {
        guard dpi > 0 else { return 0 }
        return (panelHeightPx * 160) / dpi
    }

    public var isCoolwalkSplitScreen: Bool {
        return virtualWidthDp >= 800
    }

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

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()

        let pad: CGFloat = 8.0
        let availW = rect.width - pad * 2
        let availH = rect.height - pad * 2
        guard availW > 40 && availH > 40 else {
            ctx.restoreGState()
            return
        }

        // Draw outer chassis background (dark carbon / brushed titanium tint)
        let outerBezel = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.95).cgColor)
        outerBezel.fill()
        ctx.setStrokeColor(UIColor(white: 0.25, alpha: 0.8).cgColor)
        ctx.setLineWidth(1.0)
        outerBezel.stroke()

        // Maintain panel aspect ratio
        let panelAspect: CGFloat = (panelWidthPx > 0 && panelHeightPx > 0)
            ? CGFloat(panelWidthPx) / CGFloat(panelHeightPx)
            : 4.0 / 3.0

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

        // Draw Coolwalk layout inside screenRect
        let innerPadding: CGFloat = 4.0
        let contentRect = screenRect.insetBy(dx: innerPadding, dy: innerPadding)

        let isSplit = isCoolwalkSplitScreen
        let railWidth: CGFloat = isSplit ? min(contentRect.width * 0.12, 44.0) : 0
        let bottomBarHeight: CGFloat = isSplit ? 0 : min(contentRect.height * 0.16, 36.0)

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
        drawNavigationRail(ctx: ctx, rect: railRect, isVertical: isSplit)

        // Draw Cards
        if isSplit {
            let gap: CGFloat = 4.0
            let primaryCardWidth = (cardsContainerRect.width - gap) * 0.64
            let secondaryCardWidth = cardsContainerRect.width - gap - primaryCardWidth

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

            drawMapCard(ctx: ctx, rect: mapRect)

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

            drawMediaCard(ctx: ctx, rect: mediaRect)
            drawWidgetCard(ctx: ctx, rect: widgetRect)
        } else {
            drawMapCard(ctx: ctx, rect: cardsContainerRect)
        }

        // Status Header string
        let statusText = String(
            format: "%d×%d px  |  %d DPI  |  %d×%d dp  |  %@",
            panelWidthPx, panelHeightPx, dpi, virtualWidthDp, virtualHeightDp,
            isSplit ? "Coolwalk Split Screen" : "Single Screen (Phone Mode)"
        )
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        let textColor = isSplit ? UIColor(red: 0.2, green: 0.85, blue: 0.5, alpha: 0.95) : UIColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 0.95)
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

    private func drawNavigationRail(ctx: CGContext, rect: CGRect, isVertical: Bool) {
        let railPath = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.setFillColor(UIColor(white: 0.12, alpha: 0.95).cgColor)
        railPath.fill()

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)

        if isVertical {
            // Draw 3x3 App Launcher icon at top
            let iconX = rect.midX
            let iconY = rect.minY + min(rect.width * 0.45, 18.0)
            let dotRadius: CGFloat = 1.6
            let dotSpacing: CGFloat = 4.2
            for r in -1...1 {
                for c in -1...1 {
                    let cx = iconX + CGFloat(c) * dotSpacing
                    let cy = iconY + CGFloat(r) * dotSpacing
                    ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                }
            }

            // Draw small home/map pill
            let pillY = iconY + 28
            let pillW = min(rect.width * 0.65, 20.0)
            let pillRect = CGRect(x: rect.midX - pillW / 2.0, y: pillY, width: pillW, height: 12)
            let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: 6)
            ctx.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.8).cgColor)
            pill.fill()

            // Draw music note circle
            let musicY = pillY + 20
            let musicR: CGFloat = min(rect.width * 0.3, 8.0)
            ctx.setFillColor(UIColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.midX - musicR, y: musicY, width: musicR * 2, height: musicR * 2))

            // Time text at bottom
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
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
            let dotRadius: CGFloat = 1.8
            let dotSpacing: CGFloat = 4.5
            let iconX = rect.minX + 24
            for r in -1...1 {
                for c in -1...1 {
                    let cx = iconX + CGFloat(c) * dotSpacing
                    let cy = iconY + CGFloat(r) * dotSpacing
                    ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                }
            }

            // Central pills
            let midX = rect.midX
            let p1 = CGRect(x: midX - 22, y: rect.midY - 7, width: 20, height: 14)
            let p2 = CGRect(x: midX + 2, y: rect.midY - 7, width: 20, height: 14)
            ctx.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.8).cgColor)
            UIBezierPath(roundedRect: p1, cornerRadius: 4).fill()
            ctx.setFillColor(UIColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 0.8).cgColor)
            UIBezierPath(roundedRect: p2, cornerRadius: 4).fill()

            // Time right
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
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

    private func drawMapCard(ctx: CGContext, rect: CGRect) {
        let card = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.setFillColor(UIColor(red: 0.1, green: 0.14, blue: 0.18, alpha: 0.95).cgColor)
        card.fill()

        // Subtle roads
        ctx.setStrokeColor(UIColor(white: 0.25, alpha: 0.4).cgColor)
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.4))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
        ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.maxY))
        ctx.strokePath()

        // Route polyline (glowing blue)
        ctx.setStrokeColor(UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).cgColor)
        ctx.setLineWidth(2.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.8))
        ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.45))
        ctx.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.minY + rect.height * 0.53))
        ctx.strokePath()

        // Turn banner pill
        let bannerRect = CGRect(x: rect.minX + 6, y: rect.minY + 6, width: min(rect.width * 0.75, 110.0), height: 18)
        let banner = UIBezierPath(roundedRect: bannerRect, cornerRadius: 4)
        ctx.setFillColor(UIColor(red: 0.08, green: 0.45, blue: 0.25, alpha: 0.9).cgColor)
        banner.fill()

        let bannerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        (" Turn Right (200m)" as NSString).draw(
            in: bannerRect.insetBy(dx: 4, dy: 3),
            withAttributes: bannerAttrs
        )
    }

    private func drawMediaCard(ctx: CGContext, rect: CGRect) {
        let card = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.setFillColor(UIColor(red: 0.16, green: 0.12, blue: 0.18, alpha: 0.95).cgColor)
        card.fill()

        // Album art square
        let artSide = min(rect.height - 12, rect.width * 0.35)
        let artRect = CGRect(x: rect.minX + 6, y: rect.midY - artSide / 2.0, width: artSide, height: artSide)
        let art = UIBezierPath(roundedRect: artRect, cornerRadius: 4)
        ctx.setFillColor(UIColor(red: 0.85, green: 0.25, blue: 0.4, alpha: 0.8).cgColor)
        art.fill()

        // Song title and artist placeholders
        let labelX = artRect.maxX + 6
        let line1W = min(rect.maxX - labelX - 6, 45.0)
        let line1 = CGRect(x: labelX, y: rect.midY - 6, width: line1W, height: 4)
        let line2 = CGRect(x: labelX, y: rect.midY + 2, width: line1W * 0.65, height: 3)

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        UIBezierPath(roundedRect: line1, cornerRadius: 2).fill()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        UIBezierPath(roundedRect: line2, cornerRadius: 1.5).fill()
    }

    private func drawWidgetCard(ctx: CGContext, rect: CGRect) {
        let card = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.setFillColor(UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.95).cgColor)
        card.fill()

        // Subtle calendar or weather widget mock
        let iconSide = min(rect.height - 12, 18.0)
        let iconRect = CGRect(x: rect.minX + 6, y: rect.midY - iconSide / 2.0, width: iconSide, height: iconSide)
        ctx.setFillColor(UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 0.85).cgColor)
        UIBezierPath(ovalIn: iconRect).fill()

        let textX = iconRect.maxX + 6
        let textW = min(rect.maxX - textX - 6, 50.0)
        let text1 = CGRect(x: textX, y: rect.midY - 5, width: textW, height: 4)
        let text2 = CGRect(x: textX, y: rect.midY + 3, width: textW * 0.5, height: 3)

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        UIBezierPath(roundedRect: text1, cornerRadius: 2).fill()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        UIBezierPath(roundedRect: text2, cornerRadius: 1.5).fill()
    }
}
