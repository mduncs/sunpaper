import SwiftUI

struct MenuBarView: View {
    let currentSlot: TimeSlot?
    let nextTransition: (slot: TimeSlot, date: Date)?
    let todaySchedule: [(slot: TimeSlot, time: Date)]
    let lastError: String?
    let onApplySlot: (TimeSlot) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("Sunpaper")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Mini schedule - clickable slots
            if !todaySchedule.isEmpty {
                VStack(spacing: 4) {
                    ForEach(todaySchedule, id: \.slot.id) { item in
                        ScheduleSlotButton(
                            slot: item.slot,
                            time: item.time,
                            isCurrent: item.slot.id == currentSlot?.id,
                            onTap: { onApplySlot(item.slot) }
                        )
                    }
                }
            } else {
                Text("No schedule configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            // Error indicator
            if let error = lastError {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Actions
            Button(action: onOpenSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuButtonStyle())

            Divider()
                .padding(.vertical, 4)

            Button(action: onQuit) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Sunpaper")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuButtonStyle())
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Schedule Slot Button

struct ScheduleSlotButton: View {
    let slot: TimeSlot
    let time: Date
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Time
                Text(formatTime(time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .frame(width: 52, alignment: .leading)

                // Icon
                Image(systemName: slotIcon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                    .frame(width: 16)

                // Name
                Text(slot.name)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                // Current indicator
                if isCurrent {
                    Text("Now")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor.opacity(0.1) :
                          isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var slotIcon: String {
        let name = slot.name.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return "sunrise.fill"
        } else if name.contains("day") || name.contains("noon") {
            return "sun.max.fill"
        } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return "sunset.fill"
        } else if name.contains("night") {
            return "moon.stars.fill"
        }

        // Fall back to trigger-based icon
        switch slot.trigger {
        case .solar(let event, _):
            return event.icon
        case .fixed:
            return "clock.fill"
        }
    }

    private var iconColor: Color {
        let name = slot.name.lowercased()
        if name.contains("morning") || name.contains("dawn") || name.contains("sunrise") {
            return .orange
        } else if name.contains("day") || name.contains("noon") {
            return .yellow
        } else if name.contains("evening") || name.contains("dusk") || name.contains("sunset") {
            return .orange
        } else if name.contains("night") {
            return .indigo
        }
        return .secondary
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Native-feeling menu button style
struct MenuButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.15) :
                          isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .foregroundStyle(.primary)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
