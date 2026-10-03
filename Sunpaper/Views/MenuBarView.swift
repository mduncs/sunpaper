import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: SunpaperController
    let onChooseWallpaper: () -> Void
    let onEditSchedule: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var isFollowing: Bool { controller.scheduler.playbackMode == .following }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nowCard.padding([.horizontal, .top], 12)
            Button {
                controller.setFollowing(!isFollowing)
            } label: {
                Label(isFollowing ? "Pause schedule" : "Resume schedule",
                      systemImage: isFollowing ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(SunpaperActionButtonStyle(prominent: !isFollowing, height: 36))
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider().padding(.horizontal, 14)
            VStack(spacing: 2) {
                command("Use another wallpaper…", symbol: "photo.on.rectangle", action: onChooseWallpaper)
                command("Edit schedule…", symbol: "calendar.day.timeline.left", action: onEditSchedule)
            }.padding(.horizontal, 8).padding(.vertical, 8)
            Divider().padding(.horizontal, 14)
            HStack {
                Button("Settings…", action: onOpenSettings).keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit Sunpaper", action: onQuit).keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .frame(width: SunpaperSize.popoverWidth, height: SunpaperSize.popoverHeight, alignment: .top)
        .background(SunpaperColor.surface)
        .tint(SunpaperColor.accent)
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sun.horizon.fill").symbolRenderingMode(.multicolor)
                Text("Sunpaper").font(.headline)
                Spacer()
                if controller.config.displayMode == .perDisplay {
                    Label(controller.scopeName, systemImage: "display").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                WallpaperThumbnail(source: controller.shownSource, size: CGSize(width: 120, height: 75), cornerRadius: 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(title: controller.stateTitle, tone: controller.statusTone, font: .subheadline)
                    Text(wallpaperName(controller.shownSource)).font(.title3.weight(.semibold)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            detailLine.frame(height: 28).padding(.top, 10)
            DayRibbon(controller: controller, stripHeight: 30, showsLabels: false).padding(.top, 8)
        }
        .padding(16)
        .ambientCard(controller.shownSource, cornerRadius: 12)
    }

    @ViewBuilder private var detailLine: some View {
        if controller.scheduler.lastError != nil {
            HStack {
                Label("Couldn’t finish the last change.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Retry") { Task { await controller.retryWallpaperChange() } }.controlSize(.small)
            }
        } else if case .temporary = controller.scheduler.playbackMode {
            HStack {
                Menu {
                    ForEach(WallpaperOverrideDuration.allCases) { duration in
                        Button(duration.title) { controller.scheduler.setOverrideDuration(duration) }
                    }
                } label: { Label(controller.scheduler.currentOverrideDuration.title, systemImage: "clock") }
                .fixedSize().controlSize(.small)
                Spacer(minLength: 0)
            }
        } else {
            Text(controller.stateDetail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxHeight: .infinity, alignment: .leading)
        }
    }

    private func command(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(SunpaperColor.accent).frame(width: 22)
                Text(title)
                Spacer()
            }
            .font(.body).padding(.horizontal, 8).padding(.vertical, 9)
        }
        .buttonStyle(SunpaperRowButtonStyle())
    }
}
