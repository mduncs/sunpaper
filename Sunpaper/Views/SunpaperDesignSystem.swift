import SwiftUI
import AppKit

enum SunpaperSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum SunpaperRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let circle: CGFloat = 999
}

enum SunpaperSize {
    static let popoverWidth: CGFloat = 328
    static let popoverHeight: CGFloat = 360

    static let settingsMinWidth: CGFloat = 720
    static let settingsMinHeight: CGFloat = 560
    static let settingsIdealWidth: CGFloat = 860
    static let settingsIdealHeight: CGFloat = 680

    static let iconTile: CGFloat = 32
    static let compactIconTile: CGFloat = 26
}

enum SunpaperColor {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevatedSurface = Color(nsColor: .windowBackgroundColor)
    static let separator = Color.primary.opacity(0.12)
    static let subtleSeparator = Color.primary.opacity(0.08)
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.74)

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
}

enum SunpaperPhase: String, CaseIterable {
    case dawn
    case day
    case dusk
    case night
    case neutral
}

struct SunpaperPhaseStyle {
    let phase: SunpaperPhase
    let title: String
    let symbolName: String
    let tint: Color
    let secondaryTint: Color

    var softFill: Color {
        tint.opacity(0.14)
    }

    var stroke: Color {
        tint.opacity(0.28)
    }
}

enum SunpaperPhaseResolver {
    static func phase(for slot: TimeSlot?) -> SunpaperPhase {
        guard let slot else { return .neutral }
        return phase(for: slot)
    }

    static func phase(for slot: TimeSlot) -> SunpaperPhase {
        let name = slot.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if name.contains("dawn") || name.contains("morning") || name.contains("sunrise") {
            return .dawn
        }

        if name.contains("day") || name.contains("noon") || name.contains("midday") {
            return .day
        }

        if name.contains("dusk") || name.contains("evening") || name.contains("sunset") {
            return .dusk
        }

        if name.contains("night") || name.contains("midnight") {
            return .night
        }

        return phase(for: slot.trigger)
    }

    static func phase(for trigger: Trigger) -> SunpaperPhase {
        switch trigger {
        case .solar(let event, let offset):
            return phase(for: event, offset: offset)
        case .fixed(let hour, _):
            return phase(forHour: hour)
        }
    }

    static func style(for slot: TimeSlot?) -> SunpaperPhaseStyle {
        style(for: phase(for: slot))
    }

    static func style(for slot: TimeSlot) -> SunpaperPhaseStyle {
        style(for: phase(for: slot))
    }

    static func style(for trigger: Trigger) -> SunpaperPhaseStyle {
        style(for: phase(for: trigger))
    }

    static func style(for phase: SunpaperPhase) -> SunpaperPhaseStyle {
        switch phase {
        case .dawn:
            return SunpaperPhaseStyle(
                phase: .dawn,
                title: "Dawn",
                symbolName: "sunrise.fill",
                tint: .orange,
                secondaryTint: .pink
            )
        case .day:
            return SunpaperPhaseStyle(
                phase: .day,
                title: "Day",
                symbolName: "sun.max.fill",
                tint: .yellow,
                secondaryTint: .blue
            )
        case .dusk:
            return SunpaperPhaseStyle(
                phase: .dusk,
                title: "Dusk",
                symbolName: "sunset.fill",
                tint: .orange,
                secondaryTint: .purple
            )
        case .night:
            return SunpaperPhaseStyle(
                phase: .night,
                title: "Night",
                symbolName: "moon.stars.fill",
                tint: .indigo,
                secondaryTint: .cyan
            )
        case .neutral:
            return SunpaperPhaseStyle(
                phase: .neutral,
                title: "Scheduled",
                symbolName: "clock.fill",
                tint: .secondary,
                secondaryTint: .secondary
            )
        }
    }

    private static func phase(for event: SolarEvent, offset: TimeInterval) -> SunpaperPhase {
        switch event {
        case .civilDawn, .sunrise:
            return .dawn
        case .solarNoon:
            return offset < -3_600 ? .dawn : .day
        case .civilDusk, .sunset:
            return offset > 3_600 ? .night : .dusk
        }
    }

    private static func phase(forHour hour: Int) -> SunpaperPhase {
        switch hour {
        case 5..<10:
            return .dawn
        case 10..<17:
            return .day
        case 17..<21:
            return .dusk
        default:
            return .night
        }
    }
}

struct SunpaperGlassCardModifier: ViewModifier {
    var radius: CGFloat = SunpaperRadius.lg
    var material: Material = .regularMaterial
    var stroke: Color = SunpaperColor.subtleSeparator

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}

extension View {
    func sunpaperGlassCard(
        radius: CGFloat = SunpaperRadius.lg,
        material: Material = .regularMaterial,
        stroke: Color = SunpaperColor.subtleSeparator
    ) -> some View {
        modifier(SunpaperGlassCardModifier(radius: radius, material: material, stroke: stroke))
    }
}

struct SunpaperIconTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = SunpaperSize.iconTile
    var material: Material = .thinMaterial

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(material, in: RoundedRectangle(cornerRadius: SunpaperRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SunpaperRadius.md, style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct SunpaperStatusChip: View {
    let title: String
    var systemName: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: SunpaperSpacing.xs) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SunpaperSpacing.sm)
        .padding(.vertical, SunpaperSpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
    }
}
