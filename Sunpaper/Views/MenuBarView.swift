import SwiftUI

struct MenuBarView: View {
    let currentSlot: TimeSlot?
    let nextTransition: (slot: TimeSlot, date: Date)?
    let todaySchedule: [(slot: TimeSlot, time: Date)]
    let lastError: String?
    let isDownloading: Bool
    let onApplySlot: (TimeSlot) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSummary
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if let error = lastError {
                ErrorStatusView(error: error, onOpenSettings: onOpenSettings)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            Divider()

            scheduleSection
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            Divider()

            commandSection
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 280)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: currentSlot.map(slotIcon) ?? "clock")
                    .font(.title3)
                    .foregroundStyle(currentSlot.map(slotColor) ?? .secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Current")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(currentSlot?.name ?? "No active slot")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                StatusBadge(status: popoverStatus)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                Text(nextTransitionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sunpaper status")
        .accessibilityValue(statusAccessibilityValue)
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                if !todaySchedule.isEmpty {
                    Text("\(todaySchedule.count) slots")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }

            if !todaySchedule.isEmpty {
                scheduleList
                    .accessibilityLabel("Today's schedule")
            } else {
                EmptyScheduleView(onOpenSettings: onOpenSettings)
            }
        }
    }

    private var commandSection: some View {
        VStack(spacing: 2) {
            MenuCommandButton(
                title: "Settings...",
                systemImage: "gearshape",
                accessibilityLabel: "Open Settings",
                accessibilityHint: "Opens Sunpaper settings.",
                action: onOpenSettings
            )

            MenuCommandButton(
                title: "Quit Sunpaper",
                systemImage: "power",
                accessibilityLabel: "Quit Sunpaper",
                accessibilityHint: "Exits Sunpaper.",
                action: onQuit
            )
        }
    }

    @ViewBuilder
    private var scheduleList: some View {
        if todaySchedule.count > maxVisibleScheduleRows {
            ScrollView {
                scheduleRows
            }
            .frame(maxHeight: scheduleListMaxHeight)
        } else {
            scheduleRows
        }
    }

    private var scheduleRows: some View {
        VStack(spacing: 3) {
            ForEach(todaySchedule, id: \.slot.id) { item in
                ScheduleSlotButton(
                    slot: item.slot,
                    time: item.time,
                    isCurrent: item.slot.id == currentSlot?.id,
                    onTap: { onApplySlot(item.slot) }
                )
            }
        }
    }

    private var popoverStatus: MenuBarPopoverStatus {
        if lastError != nil {
            return .attention
        }

        if isDownloading {
            return .downloading
        }

        if currentSlot == nil || todaySchedule.isEmpty {
            return .waiting
        }

        return .ready
    }

    private var maxVisibleScheduleRows: Int {
        lastError == nil ? 5 : 3
    }

    private var scheduleListMaxHeight: CGFloat {
        CGFloat(maxVisibleScheduleRows * 30)
    }

    private var nextTransitionText: String {
        guard let nextTransition else {
            return "Next: No more transitions today"
        }

        return "Next: \(nextTransition.slot.name) at \(formatScheduleTime(nextTransition.date))"
    }

    private var statusAccessibilityValue: String {
        var parts = [
            "State: \(popoverStatus.title)",
            currentSlot.map { "Current slot: \($0.name)" } ?? "No active slot",
            nextTransition.map { "Next transition: \($0.slot.name) at \(formatScheduleTime($0.date))" } ?? "No more transitions today"
        ]

        if let lastError {
            parts.append("Last issue: \(lastError)")
        } else if isDownloading {
            parts.append("A wallpaper download is in progress")
        }

        return parts.joined(separator: ". ")
    }
}

private enum MenuBarPopoverStatus: Equatable {
    case ready
    case waiting
    case downloading
    case attention

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .waiting:
            return "Waiting"
        case .downloading:
            return "Downloading"
        case .attention:
            return "Attention"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .waiting:
            return "clock.fill"
        case .downloading:
            return "arrow.down.circle.fill"
        case .attention:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .waiting:
            return .secondary
        case .downloading:
            return .accentColor
        case .attention:
            return .orange
        }
    }
}

private struct StatusBadge: View {
    let status: MenuBarPopoverStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .downloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(status.tint)
                    .scaleEffect(0.58)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: status.systemImage)
                    .font(.caption2)
                    .accessibilityHidden(true)
            }

            Text(status.title)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(status.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.tint.opacity(0.12), in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct ErrorStatusView: View {
    let error: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Needs attention")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenSettings) {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Open Settings")
                .accessibilityHint("Opens Sunpaper settings.")
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct EmptyScheduleView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text("No schedule available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Settings...", action: onOpenSettings)
                .font(.caption)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Open Settings")
                .accessibilityHint("Configure scheduled wallpaper changes.")
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .accessibilityElement(children: .contain)
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
            HStack(spacing: 7) {
                Text(formatScheduleTime(time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Image(systemName: slotIcon(slot))
                    .font(.caption)
                    .foregroundStyle(slotColor(slot))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(slot.name)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(isHovered ? 0.85 : 0.32)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor.opacity(0.1) :
                          isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .help(isCurrent ? "Reapply \(slot.name) now" : "Apply \(slot.name) now")
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var accessibilityLabel: String {
        "\(slot.name), \(formatScheduleTime(time))"
    }

    private var accessibilityValue: String {
        let currentState = isCurrent ? "Current slot" : "Scheduled slot"
        return "\(currentState). \(wallpaperDescription)."
    }

    private var accessibilityHint: String {
        isCurrent ? "Reapplies this slot now." : "Applies this slot now."
    }

    private var wallpaperDescription: String {
        switch slot.source {
        case .none:
            return "No wallpaper assigned"
        default:
            return "Wallpaper: \(slot.source.displayName)"
        }
    }
}

private struct MenuCommandButton: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private func slotIcon(_ slot: TimeSlot) -> String {
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

    switch slot.trigger {
    case .solar(let event, _):
        return event.icon
    case .fixed:
        return "clock.fill"
    }
}

private func slotColor(_ slot: TimeSlot) -> Color {
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

private func formatScheduleTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}
