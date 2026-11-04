// Portions of this file are derived from ChargeWatching
// (https://github.com/TY-teo/ChargeWatching), MIT License,
// Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.

import SwiftUI

/// Liquid Glass (macOS 26+) with a graceful fallback.
extension View {
    /// Apple's newest material on macOS 26+, and translucent material on older
    /// systems so the look stays consistent instead of flat. A faint stroke is
    /// added on top because glass can be almost invisible against the dark
    /// popover material.
    @ViewBuilder
    func akkimGlass(cornerRadius: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial)
            )
        }
    }

    /// The panel backdrop: Liquid Glass on macOS 26+, popover
    /// material on older systems. Applied to a large surface so the
    /// glass reads clearly.
    @ViewBuilder
    func akkimPanelBackdrop() -> some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else {
            VisualEffectView(material: .popover)
        }
    }
}

extension View {
    /// Liquid Glass button on macOS 26+, plain bordered on older systems.
    @ViewBuilder
    func akkimGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(GlassButtonStyle())
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
