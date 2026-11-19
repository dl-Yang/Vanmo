import SwiftUI
import VanmoCore

enum MacPlayerDrawerTab: String, CaseIterable, Identifiable {
    case audio
    case subtitles
    case episodes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: L10n.tr("音轨")
        case .subtitles: L10n.tr("字幕")
        case .episodes: L10n.tr("选集")
        }
    }
}

/// 右侧悬浮三合一毛玻璃抽屉（`Audio | Subtitles | Episodes`），对齐 Figma `169:942`。
struct MacPlayerTrackDrawer: View {
    @ObservedObject var viewModel: MacPlayerViewModel
    @Binding var activeTab: MacPlayerDrawerTab?
    @State private var showOnlineSubtitles = false
    @State private var showStyleControls = false

    private var availableTabs: [MacPlayerDrawerTab] {
        viewModel.canSelectEpisode ? [.audio, .subtitles, .episodes] : [.audio, .subtitles]
    }

    private var currentTab: MacPlayerDrawerTab {
        if let activeTab, availableTabs.contains(activeTab) {
            return activeTab
        }
        return .subtitles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            segmentedTabs

            switch currentTab {
            case .audio:
                audioTracksContent
            case .subtitles:
                subtitlesContent
            case .episodes:
                MacEpisodeSelectorDrawerContent(viewModel: viewModel) {
                    activeTab = nil
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: MacDesignTokens.Layout.playerDrawerWidth)
        .background(
            MacDesignTokens.Cinema.drawerGlass,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.75), radius: 22, y: 12)
    }

    private var segmentedTabs: some View {
        HStack(spacing: 3) {
            ForEach(availableTabs) { tab in
                let isSelected = currentTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MacDesignTokens.Cinema.amber : MacDesignTokens.Cinema.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            isSelected ? MacDesignTokens.Cinema.amberTint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 0.8)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(MacDesignTokens.Cinema.surfacePill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Audio Tab

    private var audioTracksContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                if viewModel.audioTracks.isEmpty {
                    Text(L10n.tr("无可用音轨"))
                        .font(.system(size: 12))
                        .foregroundStyle(MacDesignTokens.Cinema.textDim)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.audioTracks) { track in
                        let isSelected = viewModel.config.selectedAudioTrack == track.id
                        trackRow(
                            title: track.displayName,
                            detail: track.codec ?? L10n.tr("音轨"),
                            isSelected: isSelected
                        ) {
                            viewModel.selectAudioTrack(track.id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Subtitles Tab

    private var subtitlesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(viewModel.subtitleTracks) { track in
                        let isSelected = viewModel.config.selectedSubtitleTrack == track.id
                        let sourceTag = track.isEmbedded ? L10n.tr("内嵌") : L10n.tr("外挂")
                        let detail = isSelected
                            ? "\(sourceTag) · \(L10n.tr("当前启用"))"
                            : sourceTag
                        trackRow(
                            title: track.displayName,
                            detail: detail,
                            isSelected: isSelected
                        ) {
                            viewModel.selectSubtitleTrack(track.id)
                        }
                    }

                    trackRow(
                        title: L10n.tr("关闭"),
                        detail: L10n.tr("关闭字幕"),
                        isSelected: viewModel.config.selectedSubtitleTrack == nil
                    ) {
                        viewModel.selectSubtitleTrack(nil)
                    }
                }
            }
            .frame(maxHeight: 220)

            // Search OpenSubtitles Link
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showOnlineSubtitles.toggle()
                    if showOnlineSubtitles && viewModel.onlineSubtitleResults.isEmpty {
                        viewModel.searchOnlineSubtitles()
                    }
                }
            } label: {
                HStack {
                    Text(L10n.tr("搜索 OpenSubtitles…"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if viewModel.isSearchingOnlineSubtitles {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(showOnlineSubtitles ? "▾" : "›")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundStyle(MacDesignTokens.Cinema.amber)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showOnlineSubtitles {
                onlineSubtitlesSection
            }

            // 字幕样式与时间偏移（可折叠）
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showStyleControls.toggle()
                }
            } label: {
                HStack {
                    Text(L10n.tr("字幕样式与时间偏移"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(showStyleControls ? "▾" : "›")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showStyleControls {
                subtitleStyleSection
            }
        }
    }

    private var onlineSubtitlesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = viewModel.onlineSubtitleStatusMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacDesignTokens.Cinema.textMuted)
            }

            if !viewModel.onlineSubtitleResults.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(viewModel.onlineSubtitleResults.prefix(8)) { result in
                            Button {
                                viewModel.downloadOnlineSubtitle(result)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                                            .lineLimit(1)
                                        Text(onlineSubtitleMetadata(for: result))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(MacDesignTokens.Cinema.textDim)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if viewModel.downloadingOnlineSubtitleID == result.id {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12))
                                            .foregroundStyle(MacDesignTokens.Cinema.amber)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(MacDesignTokens.Cinema.surfaceRow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.downloadingOnlineSubtitleID == result.id)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private var subtitleStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("大小"))
                    .font(.system(size: 11))
                    .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                Spacer()
                Stepper(
                    "\(Int(viewModel.subtitleStyle.fontSize))pt",
                    value: $viewModel.subtitleStyle.fontSize,
                    in: 12...36,
                    step: 2
                )
                .font(.system(size: 11))
                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
            }

            HStack(spacing: 6) {
                Text(L10n.tr("时间偏移"))
                    .font(.system(size: 11))
                    .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                Spacer()
                Text(String(format: "%+.1fs", viewModel.config.subtitleDelay))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(MacDesignTokens.Cinema.amber)
                Button("-0.5s") { viewModel.setSubtitleDelay(viewModel.config.subtitleDelay - 0.5) }
                    .buttonStyle(MacCatCinemaMiniButtonStyle())
                Button(L10n.tr("重置")) { viewModel.setSubtitleDelay(0) }
                    .buttonStyle(MacCatCinemaMiniButtonStyle())
                Button("+0.5s") { viewModel.setSubtitleDelay(viewModel.config.subtitleDelay + 0.5) }
                    .buttonStyle(MacCatCinemaMiniButtonStyle())
            }

            HStack {
                Text(L10n.tr("位置"))
                    .font(.system(size: 11))
                    .foregroundStyle(MacDesignTokens.Cinema.textMuted)
                Spacer()
                Picker("", selection: $viewModel.subtitleStyle.position) {
                    Text(L10n.tr("顶部")).tag(MacSubtitleStyle.MacSubtitlePosition.top)
                    Text(L10n.tr("底部")).tag(MacSubtitleStyle.MacSubtitlePosition.bottom)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
        .padding(10)
        .background(MacDesignTokens.Cinema.surfaceRow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func trackRow(
        title: String,
        detail: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isSelected {
                    MacPawDotIndicator(size: 10, useCinemaGlow: true)
                } else {
                    Color.clear.frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MacDesignTokens.Cinema.textIvory : MacDesignTokens.Cinema.textMuted)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? MacDesignTokens.Cinema.amber : MacDesignTokens.Cinema.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? MacDesignTokens.Cinema.amberTint : MacDesignTokens.Cinema.surfaceRow,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 0.85)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func onlineSubtitleMetadata(for result: OnlineSubtitleResult) -> String {
        var parts = [
            result.provider,
            result.language,
            result.format.fileExtension.uppercased(),
        ].compactMap { $0 }
        if let downloadCount = result.downloadCount {
            parts.append(L10n.tr("%d 次下载", downloadCount))
        }
        return parts.joined(separator: " · ")
    }
}

private struct MacCatCinemaMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacDesignTokens.Cinema.textIvory)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                MacDesignTokens.Cinema.surfacePill.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}
