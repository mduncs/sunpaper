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
            nowCard.padding([.horizontal, .top], 10)
            Button {
                controller.setFollowing(!isFollowing)
            } label: {
                Label(isFollowing ? "Pause schedule" : "Resume schedule",
                      systemImage: isFollowing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(SunpaperActionButtonStyle(prominent: !isFollowing))
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider().padding(.horizontal, 14)
            VStack(spacing: 2) {
                command("Use another wallpaper…", symbol: "photo.on.rectangle", action: onChooseWallpaper)
                command("Edit schedule…", symbol: "calendar.day.timeline.left", action: onEditSchedule)
            }.padding(.horizontal, 8).padding(.vertical, 6)
            Divider().padding(.horizontal, 14)
            HStack {
                Button("Settings…", action: onOpenSettings).keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit Sunpaper", action: onQuit).keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .frame(width: SunpaperSize.popoverWidth, height: SunpaperSize.popoverHeight, alignment: .top)
        .background(SunpaperColor.surface)
        .tint(SunpaperColor.accent)
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sun.horizon.fill").symbolRenderingMode(.multicolor)
                Text("Sunpaper").font(.subheadline.weight(.semibold))
                Spacer()
                if controller.config.displayMode == .perDisplay {
                    Label(controller.scopeName, systemImage: "display").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                WallpaperThumbnail(source: controller.shownSource, size: CGSize(width: 100, height: 62), cornerRadius: 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(title: controller.stateTitle, tone: controller.statusTone)
                    Text(wallpaperName(controller.shownSource)).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            detailLine.frame(height: 24).padding(.top, 10)
            DayRibbon(controller: controller, stripHeight: 22, showsLabels: false).padding(.top, 8)
        }
        .padding(14)
        .ambientCard(controller.shownSource, cornerRadius: 12)
    }

    @ViewBuilder private var detailLine: some View {
        if controller.scheduler.lastError != nil {
            HStack {
                Label("Couldn’t finish the last change.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Retry") { controller.scheduler.retryLastApplication() }.controlSize(.small)
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
            Text(controller.stateDetail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxHeight: .infinity, alignment: .leading)
        }
    }

    private func command(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(SunpaperColor.accent).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
        }
        .buttonStyle(SunpaperRowButtonStyle())
    }
}
