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
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 9)

            if let error = lastError {
                ErrorStatusView(error: error, onOpenSettings: onOpenSettings)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }

            Divider()

            scheduleSection
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            commandSection
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(width: 328)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                PhaseIconTile(slot: currentSlot, isDownloading: isDownloading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Slot")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .accessibilityHidden(true)

                    Text(currentSlot?.name ?? "No active slot")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(currentSlot.map(slotWallpaperDescription) ?? "Waiting for a scheduled wallpaper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                StatusBadge(status: popoverStatus)
            }

            NextTransitionRow(nextTransition: nextTransition)
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
                        .foregroundStyle(.secondary)
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
                role: .destructive,
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
        CGFloat(maxVisibleScheduleRows * 32)
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

private struct PhaseIconTile: View {
    let slot: TimeSlot?
    let isDownloading: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.14))

            Image(systemName: slot.map(slotIcon) ?? "clock")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.accentColor)
                    .scaleEffect(0.48)
                    .frame(width: 12, height: 12)
                    .background(.background, in: Circle())
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        slot.map(slotColor) ?? .secondary
    }
}

private struct NextTransitionRow: View {
    let nextTransition: (slot: TimeSlot, date: Date)?

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: nextTransition == nil ? "checkmark.circle" : "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text("Next")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(nextText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next transition")
        .accessibilityValue(accessibilityValue)
    }

    private var nextText: String {
        guard let nextTransition else {
            return "No more transitions today"
        }

        return "\(nextTransition.slot.name) at \(formatScheduleTime(nextTransition.date))"
    }

    private var accessibilityValue: String {
        guard let nextTransition else {
            return "No more transitions today"
        }

        return "\(nextTransition.slot.name) at \(formatScheduleTime(nextTransition.date))"
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
            return "Idle"
        case .downloading:
            return "Syncing"
        case .attention:
            return "Issue"
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
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.tint.opacity(0.12), in: Capsule())
        .accessibilityHidden(true)
    }
}

private struct ErrorStatusView: View {
    let error: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Needs Attention")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        .padding(9)
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
        .frame(height: 32)
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
            rowContent
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

    private var rowContent: some View {
        HStack(spacing: 7) {
            Text(formatScheduleTime(time))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(timeColor)
                .frame(width: 54, alignment: .leading)

            phaseDot

            Text(slot.name)
                .font(.subheadline)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            trailingAccessory
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(rowBackgroundShape)
        .contentShape(Rectangle())
    }

    private var phaseDot: some View {
        ZStack {
            Circle()
                .fill(slotColor(slot).opacity(isCurrent ? 0.18 : 0.12))

            Image(systemName: slotIcon(slot))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(slotColor(slot))
                .accessibilityHidden(true)
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isCurrent {
            Text("Current")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.down.left.circle")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .opacity(isHovered ? 0.85 : 0)
                .accessibilityHidden(true)
        }
    }

    private var rowBackgroundShape: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(rowBackground)
    }

    private var timeColor: Color {
        isCurrent ? .primary : .secondary
    }

    private var rowBackground: Color {
        if isCurrent {
            return Color.accentColor.opacity(isHovered ? 0.14 : 0.1)
        }

        return isHovered ? Color.primary.opacity(0.07) : Color.clear
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
        slotWallpaperDescription(slot)
    }
}

private struct MenuCommandButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .foregroundStyle(role == .destructive ? .red : .primary)
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

private func slotWallpaperDescription(_ slot: TimeSlot) -> String {
    switch slot.source {
    case .none:
        return "No wallpaper assigned"
    default:
        return slot.source.displayName
    }
}

private func formatScheduleTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}
