import AppKit

/// Menu-bar battery icon drawn with AppKit so it matches the system indicator:
/// a rounded outline with a proportional fill, plus a lightning-bolt cutout while
/// charging. The image is a template, so macOS tints it for light/dark menu bars.
///
/// This is a generic battery glyph (not derived from any third-party app artwork).
enum MenuBarIcon {
    private static let size = NSSize(width: 26, height: 13)

    static func image(for sample: PowerSample?, style: MenuBarIconStyle) -> NSImage {
        switch style {
        case .battery:
            guard let sample, sample.hasBattery else { return symbol("powerplug") }
            return batteryImage(percent: sample.stateOfChargePercent,
                                charging: sample.status == .charging)
        case .bolt:
            return symbol("bolt.batteryblock.fill")
        case .plug:
            return symbol("powerplug")
        }
    }

    // MARK: Battery glyph

    static func batteryImage(percent: Int?, charging: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawBattery(in: rect, percent: percent, charging: charging)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawBattery(in rect: NSRect, percent: Int?, charging: Bool) {
        let black = NSColor.black
        // Keep the glyph at its designed size even if AppKit offers a larger rect.
        let scaleX = rect.width / size.width
        let scaleY = rect.height / size.height
        let scale = min(scaleX, scaleY)
        let body = NSRect(x: 0.6, y: 1.0, width: 21.2, height: 11.0)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
        let radius: CGFloat = 3.0 * scale
        let outline = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.1 * scale

        let inset: CGFloat = 1.3 * scale
        let fillWidth = (body.width - inset * 2) * fraction(percent)
        if fillWidth > 0.2 {
            black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: body.minX + inset,
                                    y: body.minY + inset,
                                    width: fillWidth,
                                    height: body.height - inset * 2),
                xRadius: 1.2 * scale,
                yRadius: 1.2 * scale
            ).fill()
        }

        if charging {
            // Cut the bolt out of the fill so it shows the menu-bar color, like
            // the system charging indicator.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            boltPath(in: NSRect(x: body.midX - 2.7 * scale,
                                y: body.minY + 1.5 * scale,
                                width: 5.4 * scale,
                                height: 8.0 * scale)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        // Outline and terminal cap are drawn last so the bolt cannot erode them.
        black.setStroke()
        outline.stroke()
        black.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 22.4 * scale, y: 4.4 * scale,
                                width: 2.0 * scale, height: 4.2 * scale),
            xRadius: 1.0 * scale,
            yRadius: 1.0 * scale
        ).fill()
    }

    private static func fraction(_ percent: Int?) -> CGFloat {
        guard let percent else { return 0 }
        return CGFloat(max(0, min(100, percent))) / 100.0
    }

    private static func boltPath(in r: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        }
        path.move(to: point(0.56, 1.0))
        path.line(to: point(0.12, 0.44))
        path.line(to: point(0.44, 0.44))
        path.line(to: point(0.34, 0.0))
        path.line(to: point(0.88, 0.56))
        path.line(to: point(0.55, 0.56))
        path.close()
        return path
    }

    // MARK: SF Symbols (fallback / desktop)

    private static func symbol(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Akkim")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image ?? NSImage(size: size)
    }
}
