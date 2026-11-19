import SwiftUI
import VanmoCore

enum PlayerPopoverTab: String, CaseIterable, Identifiable {
    case subtitles
    case audio
    case quality
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtitles: return L10n.tr("字幕")
        case .audio: return L10n.tr("音轨")
        case .quality: return L10n.tr("画质")
        case .speed: return L10n.tr("倍速")
        }
    }
}

/// 对应 Figma `18 · Liquid Glass Player — Popover & HUD` (`732:1724`)。
struct PlayerTracksPopover: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var selectedTab: PlayerPopoverTab
    let onClosePopover: () -> Void
    let onOpenSubtitleTools: () -> Void
    let onOpenChapters: () -> Void
    let onOpenEpisodes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            segmentedTabs

            ViewThatFits(in: .vertical) {
                VStack(spacing: 5) {
                    tabContent
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        tabContent
                    }
                }
                .frame(height: 132)
            }
            .frame(maxHeight: 132)

            quickUtilityFooter
        }
        .padding(12)
        .frame(width: 272)
        .catLiquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.21),
            fallbackFill: CatDesign.Cinema.surfaceGlassElevated,
            stroke: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.40),
            strokeWidth: 1
        )
        .shadow(color: .black.opacity(0.60), radius: 28, y: 12)
    }

    private var segmentedTabs: some View {
        HStack(spacing: 3) {
            ForEach(PlayerPopoverTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            isSelected
                                ? CatDesign.glowAmber
                                : Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.65)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(
                            isSelected ? CatDesign.glowAmber.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? CatDesign.glowAmber.opacity(0.60) : .clear, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 32)
        .background(
            Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .audio:
            if viewModel.audioTracks.isEmpty {
                emptyOptionRow(L10n.tr("无可用音轨"))
            } else {
                ForEach(viewModel.audioTracks) { track in
                    PlayerPopoverOptionRow(
                        title: track.displayName,
                        detail: track.codec ?? L10n.tr("音轨"),
                        isSelected: viewModel.config.selectedAudioTrack == track.id
                    ) {
                        viewModel.selectAudioTrack(track.id)
                    }
                }
            }

        case .subtitles:
            ForEach(viewModel.subtitleTracks) { track in
                PlayerPopoverOptionRow(
                    title: track.displayName,
                    detail: track.isEmbedded ? L10n.tr("内嵌字幕") : L10n.tr("外挂字幕"),
                    isSelected: viewModel.config.selectedSubtitleTrack == track.id
                ) {
                    viewModel.selectSubtitleTrack(track.id)
                }
            }

            PlayerPopoverOptionRow(
                title: L10n.tr("关闭字幕"),
                detail: L10n.tr("禁用字幕渲染"),
                isSelected: viewModel.config.selectedSubtitleTrack == nil
            ) {
                viewModel.selectSubtitleTrack(nil)
            }

            Button {
                onClosePopover()
                onOpenSubtitleTools()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CatDesign.glowAmber)
                    Text(L10n.tr("在线字幕与样式设置"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CatDesign.glowAmber)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CatDesign.glowAmber)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CatDesign.glowAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

        case .quality:
            ForEach(viewModel.availableVideoQualities, id: \.self) { quality in
                PlayerPopoverOptionRow(
                    title: quality.displayName,
                    detail: quality == .original ? L10n.tr("原始码率") : L10n.tr("转码输出"),
                    isSelected: viewModel.videoQuality == quality
                ) {
                    viewModel.setVideoQuality(quality)
                    onClosePopover()
                }
            }

        case .speed:
            ForEach(PlayerConfig.availableRates, id: \.self) { rate in
                PlayerPopoverOptionRow(
                    title: String(format: "%.2gx", rate),
                    detail: rate == 1.0 ? L10n.tr("标准速度") : L10n.tr("倍速播放"),
                    isSelected: abs(viewModel.config.playbackRate - rate) < 0.01
                ) {
                    viewModel.setRate(rate)
                    onClosePopover()
                }
            }
        }
    }

    private func emptyOptionRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(CatDesign.Cinema.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private var quickUtilityFooter: some View {
        HStack(spacing: 6) {
            utilityPill(
                icon: viewModel.config.scaleMode.icon,
                title: viewModel.config.scaleMode.displayName
            ) {
                viewModel.cycleScaleMode()
            }

            utilityPill(
                icon: "list.bullet",
                title: L10n.tr("章节")
            ) {
                onClosePopover()
                onOpenChapters()
            }

            if viewModel.canSelectEpisode {
                utilityPill(
                    icon: "rectangle.stack",
                    title: L10n.tr("选集")
                ) {
                    onClosePopover()
                    onOpenEpisodes()
                }
                .accessibilityIdentifier("player.episodes")
            }
        }
        .padding(.top, 2)
    }

    private func utilityPill(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(CatDesign.Cinema.textIvory)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(CatDesign.Cinema.surfacePill, in: Capsule())
            .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerPopoverOptionRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isSelected {
                    Image("CatPawDot")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(CatDesign.glowAmber)
                        .shadow(color: CatDesign.glowAmber.opacity(0.8), radius: 2.5)
                } else {
                    Color.clear
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? CatDesign.Cinema.textIvory : CatDesign.Cinema.textMuted)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? CatDesign.glowAmber : CatDesign.Cinema.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? CatDesign.glowAmber.opacity(0.11) : Color(red: 244/255, green: 239/255, blue: 230/255).opacity(0.03),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? CatDesign.Cinema.strokeAmber : .clear, lineWidth: 0.85)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 独立音轨 / 字幕高级 Sheet（在线字幕 & 样式延迟调节）

struct AudioTrackSelectorView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("音轨")) {
                    if viewModel.audioTracks.isEmpty {
                        Text(L10n.tr("无可用音轨"))
                            .foregroundStyle(CatDesign.textMuted)
                    } else {
                        ForEach(viewModel.audioTracks) { track in
                            Button {
                                viewModel.selectAudioTrack(track.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(CatDesign.textIvory)
                                        if let codec = track.codec {
                                            Text(codec)
                                                .font(.caption)
                                                .foregroundStyle(CatDesign.textMuted)
                                        }
                                    }
                                    Spacer()
                                    if viewModel.config.selectedAudioTrack == track.id {
                                        Image("CatPawDot")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundStyle(CatDesign.accentAmber)
                                    }
                                }
                            }
                            .tint(CatDesign.textIvory)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
            .navigationTitle(L10n.tr("音轨"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("完成")) { dismiss() }
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
        }
    }
}

struct SubtitleSelectorView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                subtitleSection
                SubtitleSettingsSections(
                    style: $viewModel.subtitleStyle,
                    delay: Binding(
                        get: { viewModel.config.subtitleDelay },
                        set: { viewModel.setSubtitleDelay($0) }
                    )
                )
            }
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
            .navigationTitle(L10n.tr("字幕"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("完成")) { dismiss() }
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
        }
    }

    private var subtitleSection: some View {
        Section(L10n.tr("字幕")) {
            Button {
                viewModel.selectSubtitleTrack(nil)
            } label: {
                HStack {
                    Text(L10n.tr("关闭字幕"))
                        .font(.subheadline)
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    if viewModel.config.selectedSubtitleTrack == nil {
                        Image("CatPawDot")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(CatDesign.accentAmber)
                    }
                }
            }

            Button {
                viewModel.searchOnlineSubtitles()
            } label: {
                HStack {
                    Label(L10n.tr("搜索在线字幕"), systemImage: "magnifyingglass")
                        .foregroundStyle(CatDesign.accentAmber)
                    Spacer()
                    if viewModel.isSearchingOnlineSubtitles {
                        ProgressView().tint(CatDesign.accentAmber)
                    }
                }
            }
            .disabled(viewModel.isSearchingOnlineSubtitles)

            if let message = viewModel.onlineSubtitleStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(CatDesign.textMuted)
            }

            ForEach(viewModel.onlineSubtitleResults) { result in
                Button {
                    viewModel.downloadOnlineSubtitle(result)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.subheadline)
                                .foregroundStyle(CatDesign.textIvory)
                            Text(onlineSubtitleMetadata(for: result))
                                .font(.caption)
                                .foregroundStyle(CatDesign.textMuted)
                        }
                        Spacer()
                        if viewModel.downloadingOnlineSubtitleID == result.id {
                            ProgressView().tint(CatDesign.accentAmber)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(CatDesign.accentAmber)
                        }
                    }
                }
                .disabled(viewModel.downloadingOnlineSubtitleID == result.id)
            }

            ForEach(viewModel.subtitleTracks) { track in
                Button {
                    viewModel.selectSubtitleTrack(track.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayName)
                                .font(.subheadline)
                                .foregroundStyle(CatDesign.textIvory)
                            Text(track.isEmbedded ? L10n.tr("内嵌字幕") : L10n.tr("外挂字幕"))
                                .font(.caption)
                                .foregroundStyle(CatDesign.textMuted)
                        }
                        Spacer()
                        if viewModel.config.selectedSubtitleTrack == track.id {
                            Image("CatPawDot")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                                .foregroundStyle(CatDesign.accentAmber)
                        }
                    }
                }
            }
        }
    }

    private func onlineSubtitleMetadata(for result: OnlineSubtitleResult) -> String {
        var parts = [
            result.provider,
            result.language,
            result.format.fileExtension.uppercased()
        ].compactMap { $0 }
        if let downloadCount = result.downloadCount {
            parts.append("\(downloadCount) 次下载")
        }
        if result.isTrusted == true {
            parts.append(L10n.tr("可信"))
        }
        if result.isMachineTranslated == true {
            parts.append(L10n.tr("机器翻译"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Tracks Popover") {
    ZStack {
        Color.black.ignoresSafeArea()
        PlayerTracksPopover(
            viewModel: PlayerViewModel(
                item: MediaItem(title: "Dune: Prophecy", fileURL: URL(fileURLWithPath: "/tmp/dune.mp4"))
            ),
            selectedTab: .constant(.subtitles),
            onClosePopover: {},
            onOpenSubtitleTools: {},
            onOpenChapters: {},
            onOpenEpisodes: {}
        )
    }
    .preferredColorScheme(.dark)
}
