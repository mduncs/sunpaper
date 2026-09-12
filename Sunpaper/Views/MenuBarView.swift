import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: SunpaperController
    let onChooseWallpaper: () -> Void
    let onEditSchedule: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Sunpaper", systemImage: "sun.horizon.fill").font(.headline)
                Spacer()
                if controller.config.displayMode == .perDisplay {
                    Text(controller.scopeName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(.bottom, 18)
            HStack(spacing: 12) {
                WallpaperThumbnail(source: controller.shownSource, size: CGSize(width: 88, height: 58))
                VStack(alignment: .leading, spacing: 5) {
                    Text(wallpaperName(controller.shownSource)).font(.headline).lineLimit(2)
                    Text(controller.stateTitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.frame(height: 64)
            VStack(alignment: .leading, spacing: 7) {
                if case .temporary = controller.scheduler.playbackMode {
                    Menu {
                        ForEach(WallpaperOverrideDuration.allCases) { duration in
                            Button(duration.title) { controller.scheduler.setOverrideDuration(duration) }
                        }
                    } label: { Label(controller.scheduler.currentOverrideDuration.title, systemImage: "clock") }
                    .fixedSize().controlSize(.small)
                }
                if controller.scheduler.lastError != nil {
                    HStack {
                        Text("Couldn’t finish the last change.").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Retry") { controller.scheduler.retryLastApplication() }.controlSize(.small)
                    }
                } else {
                    Text(controller.stateDetail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.padding(.top, 14).frame(height: 86, alignment: .top)
            Button {
                if controller.scheduler.playbackMode == .following { controller.setFollowing(false) }
                else { controller.setFollowing(true) }
            } label: {
                Text(controller.scheduler.playbackMode == .following ? "Pause schedule" : "Resume schedule")
                    .frame(maxWidth: .infinity).frame(height: 24)
            }
            .buttonStyle(.borderedProminent).tint(SunpaperColor.accent)
            .padding(.bottom, 16)
            Divider()
            VStack(spacing: 0) {
                command("Use another wallpaper…", symbol: "photo", action: onChooseWallpaper)
                command("Edit schedule…", symbol: "calendar", action: onEditSchedule)
            }.padding(.vertical, 9)
            Divider()
            HStack {
                Button("Settings…", action: onOpenSettings).keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit Sunpaper", action: onQuit).keyboardShortcut("q", modifiers: .command)
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.top, 13)
        }
        .padding(18)
        .frame(width: SunpaperSize.popoverWidth, height: SunpaperSize.popoverHeight, alignment: .top)
        .background(SunpaperColor.surface)
        .tint(SunpaperColor.accent)
    }

    private func command(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
