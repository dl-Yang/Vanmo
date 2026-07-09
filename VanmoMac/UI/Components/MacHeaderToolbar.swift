import SwiftUI

struct MacLibraryViewControls: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                segmentButton(mode: .grid, systemImage: "square.grid.2x2")
                segmentButton(mode: .list, systemImage: "list.bullet")
            }
            .padding(3)
            .background(theme.segmentedBackground)
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.segmentedControl))

            Menu {
                Picker("排序", selection: $libraryViewModel.sortOption) {
                    ForEach(MacLibrarySortOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .help("排序")
        }
    }

    @ViewBuilder
    private func segmentButton(mode: MacLibraryViewMode, systemImage: String) -> some View {
        let isSelected = appState.viewMode == mode
        Button {
            appState.viewMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                .frame(width: 24, height: 24)
                .background(isSelected ? theme.segmentedSelectedBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.segmentedSegment))
                .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct MacSidebarToggleButton: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    var body: some View {
        Button {
            appState.isSidebarExpanded.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .frame(width: 28, height: 28)
        .buttonStyle(.plain)
        .help(appState.isSidebarExpanded ? "收起侧边栏" : "展开侧边栏")
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

            if !isEmptyLibrary {
                MacLibraryViewControls()
            }
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
                            .padding(.horizontal, 16)
                            .frame(height: MacDesignTokens.Layout.filterPillHeight)
                            .background(isSelected ? theme.filterSelectedBackground : theme.filterUnselectedBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
