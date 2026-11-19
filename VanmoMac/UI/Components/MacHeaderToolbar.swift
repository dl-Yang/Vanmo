import SwiftUI
import VanmoCore

struct MacLibraryViewControls: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme

    /// 是否显示排序菜单。History 等固定顺序的页面置 false，仅保留视图切换。
    var showsSortMenu: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                segmentButton(mode: .grid, assetName: "MacGridView")
                segmentButton(mode: .list, assetName: "MacListView")
            }
            .padding(4)
            .frame(height: 34)
            .background(theme.segmentedBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
            }

            if showsSortMenu {
                Menu {
                    Picker(L10n.tr("排序"), selection: $libraryViewModel.sortOption) {
                        ForEach(MacLibrarySortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 34)
                .background(theme.surfaceGlass, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                }
                .help(L10n.tr("排序"))
            }
        }
    }

    @ViewBuilder
    private func segmentButton(mode: MacLibraryViewMode, assetName: String) -> some View {
        let isSelected = appState.viewMode == mode
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                appState.viewMode = mode
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                    .frame(width: 32, height: 26)
                    .background(
                        isSelected ? theme.segmentedSelectedBackground : Color.clear,
                        in: Capsule()
                    )
                    .overlay {
                        if isSelected {
                            Capsule()
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }
                    }

                if isSelected {
                    MacPawDotIndicator(size: 7)
                        .offset(x: -3, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MacSidebarToggleButton: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var downloadHero: MacDownloadHeroController
    @Environment(\.macTheme) private var theme
    @Environment(\.openWindow) private var openWindow

    private var hasActiveDownloads: Bool {
        downloadManager.tasks.contains {
            $0.status == .downloading || $0.status == .queued
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if appState.isSidebarExpanded {
                Spacer(minLength: 0)
            } else if appState.canGoBack && appState.selectedMediaItem == nil {
                Button {
                    appState.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 28, height: 28)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("返回上一步"))
            }

            Button {
                openWindow(id: "downloads")
            } label: {
                Image("MacDownloadsTray")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(hasActiveDownloads ? theme.accentAmber : theme.primaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        hasActiveDownloads ? theme.amberTintFill : theme.surfacePill,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        if hasActiveDownloads {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                        }
                    }
                    .scaleEffect(downloadHero.destinationScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("查看下载列表"))
            .macDownloadHeroFrame("destination")
            .accessibilityIdentifier("download.sidebar.icon")

            Button {
                appState.isSidebarExpanded.toggle()
            } label: {
                Image("MacSidebarCollapse")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        appState.isSidebarExpanded ? Color.clear : theme.surfaceGlass,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        if !appState.isSidebarExpanded {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.85)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.isSidebarExpanded ? L10n.tr("收起侧边栏") : L10n.tr("展开侧边栏"))
        }
    }
}

struct MacHeaderToolbar: View {
    @Environment(\.macTheme) private var theme

    let title: String
    var isEmptyLibrary: Bool = false
    var showsTitle: Bool = true

    var body: some View {
        HStack {
            if showsTitle {
                Text(title)
                    .font(MacDesignTokens.Typography.headerTitle)
                    .foregroundStyle(theme.primaryText)
            }

            Spacer()
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.headerBorder).frame(height: 1)
        }
    }
}

struct MacFilterPills: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MacLibraryFilter.allCases) { filter in
                    let isSelected = appState.selectedFilter == filter
                    Button {
                        appState.selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(MacDesignTokens.Typography.filterPill)
                            .foregroundStyle(isSelected ? theme.filterSelectedText : theme.filterUnselectedText)
                            .padding(.horizontal, 14)
                            .frame(height: MacDesignTokens.Layout.filterPillHeight)
                            .background(
                                isSelected ? theme.filterSelectedBackground : theme.filterUnselectedBackground,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(isSelected ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.85)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
