import SwiftUI

struct Theme: Identifiable, Equatable {
    enum Family: String, CaseIterable {
        case classic = "Classic"
        case vivid = "Vivid"
        case scenic = "Scenic"
    }

    enum Scenery {
        case plain
        case horizon
        case stars
        case waves
    }

    let id: String
    let name: String
    let family: Family
    let isDark: Bool
    let accent: Color
    let sidebarTop: Color
    let sidebarBottom: Color
    let background: Color
    let surface: Color
    let border: Color
    var scenery: Scenery = .plain

    var swatch: LinearGradient {
        LinearGradient(colors: [accent, sidebarBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var sidebarGradient: LinearGradient {
        LinearGradient(colors: [sidebarTop, sidebarBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Theme {
    static let all: [Theme] = [
        Theme(id: "phoenix", name: "Phoenix", family: .classic, isDark: true,
              accent: Color(hex: 0xFF6A3D), sidebarTop: Color(hex: 0x2A1418), sidebarBottom: Color(hex: 0x4A1A1C),
              background: Color(hex: 0x141012), surface: Color(hex: 0x1E181A), border: Color(hex: 0x2E2426)),
        Theme(id: "daylight", name: "Daylight", family: .classic, isDark: false,
              accent: Color(hex: 0x6B4EE6), sidebarTop: Color(hex: 0xF1EEFB), sidebarBottom: Color(hex: 0xE4DEF7),
              background: Color(hex: 0xFAF9FC), surface: Color(hex: 0xFFFFFF), border: Color(hex: 0xE3E0EA)),
        Theme(id: "midnight", name: "Midnight", family: .classic, isDark: true,
              accent: Color(hex: 0x5B8CFF), sidebarTop: Color(hex: 0x10172B), sidebarBottom: Color(hex: 0x182544),
              background: Color(hex: 0x0C1020), surface: Color(hex: 0x141A2E), border: Color(hex: 0x222B45)),
        Theme(id: "dusk", name: "Dusk", family: .classic, isDark: true,
              accent: Color(hex: 0xB07CF2), sidebarTop: Color(hex: 0x1F1630), sidebarBottom: Color(hex: 0x2F1F48),
              background: Color(hex: 0x15111F), surface: Color(hex: 0x1D1729), border: Color(hex: 0x2D2340)),
        Theme(id: "graphite", name: "Graphite", family: .classic, isDark: true,
              accent: Color(hex: 0xB8BEC8), sidebarTop: Color(hex: 0x1C1D20), sidebarBottom: Color(hex: 0x2A2C30),
              background: Color(hex: 0x141517), surface: Color(hex: 0x1C1D20), border: Color(hex: 0x2C2E33)),
        Theme(id: "paper", name: "Paper", family: .classic, isDark: false,
              accent: Color(hex: 0xD2552B), sidebarTop: Color(hex: 0xF4EFE6), sidebarBottom: Color(hex: 0xEADFCC),
              background: Color(hex: 0xFBF8F2), surface: Color(hex: 0xFFFFFF), border: Color(hex: 0xE7DFD1)),

        Theme(id: "terminal", name: "Terminal", family: .vivid, isDark: true,
              accent: Color(hex: 0x3EDC81), sidebarTop: Color(hex: 0x0A140E), sidebarBottom: Color(hex: 0x0F2216),
              background: Color(hex: 0x070C09), surface: Color(hex: 0x0E1611), border: Color(hex: 0x1B2A20)),
        Theme(id: "ocean", name: "Ocean", family: .vivid, isDark: true,
              accent: Color(hex: 0x2EC4C9), sidebarTop: Color(hex: 0x0B1D26), sidebarBottom: Color(hex: 0x0F3140),
              background: Color(hex: 0x09151B), surface: Color(hex: 0x0F1F27), border: Color(hex: 0x1A3240)),
        Theme(id: "forest", name: "Forest", family: .vivid, isDark: true,
              accent: Color(hex: 0x8BC34A), sidebarTop: Color(hex: 0x141D12), sidebarBottom: Color(hex: 0x203019),
              background: Color(hex: 0x0F140D), surface: Color(hex: 0x171F14), border: Color(hex: 0x26331F)),
        Theme(id: "copper", name: "Copper", family: .vivid, isDark: true,
              accent: Color(hex: 0xE0955A), sidebarTop: Color(hex: 0x21170F), sidebarBottom: Color(hex: 0x352416),
              background: Color(hex: 0x16110C), surface: Color(hex: 0x1F1812), border: Color(hex: 0x33271C)),
        Theme(id: "rose", name: "Rose", family: .vivid, isDark: true,
              accent: Color(hex: 0xFF5C9A), sidebarTop: Color(hex: 0x26111C), sidebarBottom: Color(hex: 0x3D1629),
              background: Color(hex: 0x170D12), surface: Color(hex: 0x21141B), border: Color(hex: 0x36202B)),
        Theme(id: "frost", name: "Frost", family: .vivid, isDark: false,
              accent: Color(hex: 0x2F80ED), sidebarTop: Color(hex: 0xE8F1FB), sidebarBottom: Color(hex: 0xD3E5F8),
              background: Color(hex: 0xF6F9FD), surface: Color(hex: 0xFFFFFF), border: Color(hex: 0xDCE6F2)),

        Theme(id: "synthwave", name: "Synthwave", family: .scenic, isDark: true,
              accent: Color(hex: 0xFF4FA3), sidebarTop: Color(hex: 0x1E1033), sidebarBottom: Color(hex: 0x4A1446),
              background: Color(hex: 0x130B20), surface: Color(hex: 0x1C1230), border: Color(hex: 0x2E1D47),
              scenery: .horizon),
        Theme(id: "nebula", name: "Nebula", family: .scenic, isDark: true,
              accent: Color(hex: 0x8F7CFF), sidebarTop: Color(hex: 0x0D0B24), sidebarBottom: Color(hex: 0x23164A),
              background: Color(hex: 0x0A0919), surface: Color(hex: 0x141228), border: Color(hex: 0x241F44),
              scenery: .stars),
        Theme(id: "tide", name: "Tide", family: .scenic, isDark: true,
              accent: Color(hex: 0x4FD1E8), sidebarTop: Color(hex: 0x081A2A), sidebarBottom: Color(hex: 0x0C3550),
              background: Color(hex: 0x07131F), surface: Color(hex: 0x0D1E2D), border: Color(hex: 0x173148),
              scenery: .waves),
    ]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}

struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.all[0]
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// Drawn decorations at the foot of the sidebar for the scenic themes. They are
// static on purpose: nothing here animates or reacts to the pointer.
struct SidebarScenery: View {
    let theme: Theme

    var body: some View {
        switch theme.scenery {
        case .plain:
            EmptyView()
        case .horizon:
            Canvas { context, size in
                let horizon = size.height * 0.45
                let sunRadius = size.width * 0.2
                let sunCentre = CGPoint(x: size.width / 2, y: horizon)
                let sun = Path(ellipseIn: CGRect(x: sunCentre.x - sunRadius, y: sunCentre.y - sunRadius,
                                                 width: sunRadius * 2, height: sunRadius * 2))
                context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                context.fill(sun, with: .linearGradient(
                    Gradient(colors: [theme.accent, theme.accent.opacity(0.5)]),
                    startPoint: CGPoint(x: 0, y: horizon - sunRadius), endPoint: CGPoint(x: 0, y: horizon)
                ))
                for i in 1...4 {
                    let y = horizon - CGFloat(i) * sunRadius * 0.16
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: CGFloat(i) * 1.2)),
                                 with: .color(theme.sidebarBottom))
                }
            }
            .overlay(alignment: .bottom) {
                Canvas { context, size in
                    var grid = Path()
                    let vanishing = CGPoint(x: size.width / 2, y: 0)
                    for i in -8...8 {
                        grid.move(to: vanishing)
                        grid.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * size.width / 6, y: size.height))
                    }
                    for i in 1...7 {
                        let t = pow(CGFloat(i) / 7, 1.8)
                        grid.move(to: CGPoint(x: 0, y: size.height * t))
                        grid.addLine(to: CGPoint(x: size.width, y: size.height * t))
                    }
                    context.stroke(grid, with: .color(theme.accent.opacity(0.35)), lineWidth: 0.8)
                }
                .frame(height: 110)
            }
        case .stars:
            Canvas { context, size in
                var generator = SeededGenerator(seed: 7)
                for _ in 0..<70 {
                    let x = CGFloat.random(in: 0...size.width, using: &generator)
                    let y = CGFloat.random(in: 0...size.height, using: &generator)
                    let r = CGFloat.random(in: 0.4...1.4, using: &generator)
                    let alpha = Double.random(in: 0.25...0.9, using: &generator)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(alpha)))
                }
            }
        case .waves:
            Canvas { context, size in
                for layer in 0..<4 {
                    let base = size.height * (0.35 + CGFloat(layer) * 0.16)
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: base))
                    for x in stride(from: 0, through: size.width, by: 4) {
                        let y = base + sin(x / 28 + CGFloat(layer)) * 6
                        wave.addLine(to: CGPoint(x: x, y: y))
                    }
                    wave.addLine(to: CGPoint(x: size.width, y: size.height))
                    wave.addLine(to: CGPoint(x: 0, y: size.height))
                    wave.closeSubpath()
                    context.fill(wave, with: .color(theme.accent.opacity(0.08 + Double(layer) * 0.05)))
                }
            }
        }
    }
}

// The star field has to look the same on every redraw, so it can't use the
// system random source.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
