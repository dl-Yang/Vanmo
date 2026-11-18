import SwiftUI
import VanmoCore

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            HStack {
                Spacer()
                CatAmberHalo(width: 170, height: 110, opacity: 0.18)
                    .padding(.top, 95)
                    .padding(.trailing, 18)
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    iCloudSyncCard
                    playbackAudioGroup
                    systemStorageGroup
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 110)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task {
                await viewModel.calculateCacheSize()
                await viewModel.calculateMetadataCacheSize()
            }
        }
        .task {
            await viewModel.calculateCacheSize()
            await viewModel.calculateMetadataCacheSize()
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
        .onChange(of: cloudSyncCoordinator.statusMessage) { _, message in
            viewModel.cloudSyncStatusMessage = message
        }
        .onChange(of: cloudSyncCoordinator.lastSyncAt) { _, _ in
            viewModel.bindCloudSyncCoordinator(cloudSyncCoordinator)
        }
    }

    // MARK: - Header (`695:1198`)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr("设置"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Spacer()

            Text("v\(viewModel.appVersion)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CatDesign.textDim)
        }
        .padding(.top, 10)
    }

    // MARK: - iCloud Sync Card (`695:1202`)

    private var isCloudActive: Bool {
        CloudSyncAvailability.isCloudKitEnabled && viewModel.cloudSyncEnabled
    }

    private var iCloudSyncCard: some View {
        NavigationLink(value: SettingsRoute.iCloudSync) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image("CatSetCloud")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)

                        Text(L10n.tr("iCloud 同步"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CatDesign.textIvory)

                        Text(isCloudActive ? L10n.tr("已开启") : L10n.tr("已关闭"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(isCloudActive ? CatDesign.accentAmber : CatDesign.textMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                isCloudActive ? CatDesign.amberTintFill : CatDesign.surfacePill,
                                in: Capsule()
                            )

                        Spacer(minLength: 40)
                    }

                    Text("\(viewModel.cloudSyncLastUpdatedText) · \(L10n.tr("%d 个连接", connectionsViewModel.savedConnections.count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isCloudActive ? CatDesign.accentAmber : CatDesign.textMuted)
                        .lineLimit(1)

                    Text(L10n.tr("密码与 OAuth 凭据加密保存在本机 Keychain"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)
                }
                .padding(.leading, 15)
                .padding(.trailing, 72)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("CatCurledCircleSync")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(.trailing, 13)
                    .padding(.bottom, 12)
            }
            .frame(minHeight: 102)
            .catGlassCard(cornerRadius: 22, elevated: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Groups (`695:1220` & `695:1252`)

    private var playbackAudioGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr("播放与音频"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.textDim)

            VStack(spacing: 0) {
                CatSettingsNavRow(
                    route: .playback,
                    iconAsset: "CatSetFilm",
                    title: L10n.tr("播放"),
                    summary: "\(viewModel.hardwareDecoding ? L10n.tr("硬件解码") : L10n.tr("软解优先")) · \(String(format: "%.2gx", viewModel.defaultRate))"
                )

                groupSeparator

                CatSettingsNavRow(
                    route: .audio,
                    iconAsset: "CatSetAudio",
                    title: L10n.tr("音频"),
                    summary: viewModel.audioOutputMode.displayName
                )

                groupSeparator

                CatSettingsNavRow(
                    route: .subtitles,
                    iconAsset: "CatSetSubtitleTail",
                    title: L10n.tr("字幕"),
                    summary: "\(viewModel.subtitleAutoLoad ? L10n.tr("自动") : L10n.tr("手动")) · \(viewModel.subtitlePreferredLanguage.uppercased())"
                )
            }
            .catGlassCard(cornerRadius: 20)
        }
    }

    private var systemStorageGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr("媒体库、外观与存储"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.textDim)

            VStack(spacing: 0) {
                CatSettingsNavRow(
                    route: .libraryScan,
                    iconAsset: "CatSetScan",
                    title: L10n.tr("媒体库与扫描"),
                    summary: viewModel.libraryAutoScan ? L10n.tr("自动扫描开启") : L10n.tr("手动扫描")
                )

                groupSeparator

                CatSettingsNavRow(
                    route: .metadataCache,
                    iconAsset: "CatSetCloud",
                    title: L10n.tr("元数据缓存"),
                    summary: viewModel.metadataCacheSize
                )

                groupSeparator

                CatSettingsNavRow(
                    route: .appearance,
                    iconAsset: appearanceIconAsset,
                    iconSize: 24,
                    title: L10n.tr("外观与字幕"),
                    summary: "\(viewModel.theme.displayName) · \(viewModel.languagePreference.displayName)"
                )

                groupSeparator

                CatSettingsNavRow(
                    route: .storage,
                    iconAsset: "CatSetStorage",
                    title: L10n.tr("存储与下载"),
                    summary: viewModel.cacheSize
                )
            }
            .catGlassCard(cornerRadius: 20)
        }
    }

    private var appearanceIconAsset: String {
        switch viewModel.theme {
        case .system: return "CatThemeSystem"
        case .light: return "CatThemeDaySun"
        case .dark: return "CatThemeNightMoon"
        }
    }

    private var groupSeparator: some View {
        Rectangle()
            .fill(CatDesign.hairSeparator)
            .frame(height: 0.75)
    }
}

private struct CatSettingsNavRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let route: SettingsRoute
    let iconAsset: String
    var iconSize: CGFloat = 20
    let title: String
    let summary: String

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(colorScheme == .light ? Color(red: 0x24 / 255, green: 0x27 / 255, blue: 0x30 / 255) : CatDesign.surfacePill)
                    Image(iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                }
                .frame(width: 30, height: 30)

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - `14 · Appearance & Subtitles`

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showLanguageRestartAlert = false

    private let quickColors: [Color] = [
        Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255),
        Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255),
        Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255),
        Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                topNav
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        liveSubtitlePreviewSection
                        themeAppearanceSection
                        subtitleControlsCard
                        appLanguageCard
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                    .padding(.bottom, 34)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .alert(L10n.tr("语言"), isPresented: $showLanguageRestartAlert) {
            Button(L10n.tr("确定"), role: .cancel) {}
        } message: {
            Text(L10n.tr("语言将在下次启动后生效"))
        }
    }

    private var topNav: some View {
        HStack(spacing: 12) {
            CatBackButton(size: 36) { dismiss() }

            Text(L10n.tr("外观与字幕"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Spacer()
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Live Subtitle Preview

    private var previewStyle: SubtitleStyle {
        SubtitleStyle(
            fontSize: CGFloat(viewModel.subtitleFontSize),
            textColor: viewModel.subtitleTextColor,
            backgroundColor: viewModel.subtitleBackgroundColor,
            bottomPadding: 14,
            position: SubtitleStyle.SubtitlePosition(rawValue: viewModel.subtitlePositionRaw) ?? .bottom,
            outlineWeight: viewModel.subtitleOutlineWeight
        )
    }

    private var liveSubtitlePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("实时字幕预览"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.textMuted)

            ZStack(alignment: .topTrailing) {
                ZStack {
                    Image("DefaultHeroBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 166)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, CatDesign.catSilhouette.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    SubtitleOverlayView(
                        content: SubtitleContent(text: L10n.tr("黑猫影院 · 00:42:18")),
                        style: previewStyle
                    )
                }
                .frame(height: 166)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
                )
                .padding(.top, 18)

                Image("CatSittingSubtitleWatcher")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 38)
                    .padding(.trailing, 22)
                    .offset(y: -11)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Theme Appearance (`695:1362`)

    private var themeAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("主题外观"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.textMuted)

            HStack(spacing: 12) {
                themeCard(
                    theme: .system,
                    iconAsset: "CatThemeSystem",
                    title: L10n.tr("跟随系统"),
                    cardFill: CatDesign.surfaceGlass,
                    border: CatDesign.strokeGlass,
                    titleColor: CatDesign.textMuted,
                    selectedTitleColor: CatDesign.accentAmber
                )

                themeCard(
                    theme: .light,
                    iconAsset: "CatThemeDaySun",
                    title: L10n.tr("日间模式"),
                    cardFill: Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255),
                    border: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
                    titleColor: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255),
                    selectedTitleColor: Color(red: 0xB8 / 255, green: 0x6A / 255, blue: 0x08 / 255)
                )

                themeCard(
                    theme: .dark,
                    iconAsset: "CatThemeNightMoon",
                    title: L10n.tr("夜间模式"),
                    cardFill: Color(red: 26 / 255, green: 28 / 255, blue: 33 / 255).opacity(0.92),
                    border: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.14),
                    titleColor: Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255),
                    selectedTitleColor: Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255)
                )
            }
        }
    }

    private func themeCard(
        theme: ColorTheme,
        iconAsset: String,
        title: String,
        cardFill: Color,
        border: Color,
        titleColor: Color,
        selectedTitleColor: Color
    ) -> some View {
        let isSelected = viewModel.theme == theme
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                viewModel.theme = theme
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    if theme == .system && colorScheme == .light {
                        Circle()
                            .fill(Color(red: 0x24 / 255, green: 0x27 / 255, blue: 0x30 / 255))
                            .frame(width: 34, height: 34)
                    }
                    Image(iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                .frame(height: 34)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? selectedTitleColor : titleColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? CatDesign.strokeAmber : border,
                        lineWidth: isSelected ? 1.3 : 1
                    )
            )
            .shadow(color: isSelected ? CatDesign.amberGlowShadow : .clear, radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtitle Controls Card (`695:1386`)

    private var subtitleControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("字体大小"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text("\(Int(viewModel.subtitleFontSize)) pt")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CatDesign.accentAmber)
                }

                CatAmberSlider(
                    value: $viewModel.subtitleFontSize,
                    range: 12...36,
                    step: 2
                )
            }

            HStack {
                HStack(spacing: 8) {
                    Text(L10n.tr("颜色"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)

                    ForEach(quickColors.indices, id: \.self) { index in
                        let swatch = quickColors[index]
                        let isMatched = swatch.rgbaHex == viewModel.subtitleTextColor.rgbaHex
                        Button {
                            viewModel.subtitleTextColor = swatch
                        } label: {
                            Circle()
                                .fill(swatch)
                                .frame(width: isMatched ? 18 : 16, height: isMatched ? 18 : 16)
                                .overlay(
                                    Circle().strokeBorder(
                                        isMatched ? CatDesign.accentAmber : CatDesign.strokeGlass,
                                        lineWidth: isMatched ? 2 : 0.75
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    ColorPicker("", selection: Binding(
                        get: { viewModel.subtitleTextColor },
                        set: { viewModel.subtitleTextColor = $0 }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(0.75)
                    .frame(width: 22, height: 22)
                }

                Spacer(minLength: 6)

                Button {
                    viewModel.subtitleOutlineWeight = viewModel.subtitleOutlineWeight.next
                } label: {
                    HStack(spacing: 5) {
                        Text(L10n.tr("描边"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(CatDesign.textMuted)
                        Text(viewModel.subtitleOutlineWeight.displayName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(CatDesign.accentAmber)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(CatDesign.surfacePill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("背景透明度"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Text("\(Int((viewModel.subtitleBackgroundOpacity * 100).rounded()))%")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CatDesign.accentAmber)
                }

                CatAmberSlider(
                    value: Binding(
                        get: { viewModel.subtitleBackgroundOpacity },
                        set: { viewModel.subtitleBackgroundOpacity = $0 }
                    ),
                    range: 0...1,
                    step: 0.05
                )
            }

            HStack {
                Text(L10n.tr("字幕位置"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)

                Spacer()

                HStack(spacing: 4) {
                    positionPill(title: L10n.tr("底部"), value: .bottom)
                    positionPill(title: L10n.tr("顶部"), value: .top)
                }
                .padding(3)
                .background(CatDesign.surfacePill, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .catGlassCard(cornerRadius: 20)
    }

    private func positionPill(title: String, value: SubtitleStyle.SubtitlePosition) -> some View {
        let isActive = viewModel.subtitlePositionRaw == value.rawValue
        return Button {
            viewModel.subtitlePositionRaw = value.rawValue
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? CatDesign.accentAmber : CatDesign.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? CatDesign.amberTintFill : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isActive ? CatDesign.strokeAmber : .clear, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - App Language Card (`695:1425`)

    private var appLanguageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("应用语言"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                Spacer()
                Text(L10n.tr("下次启动生效"))
                    .font(.system(size: 10))
                    .foregroundStyle(CatDesign.textDim)
            }

            HStack(spacing: 4) {
                ForEach(AppLanguagePreference.allCases, id: \.self) { pref in
                    let isSelected = viewModel.languagePreference == pref
                    Button {
                        guard viewModel.languagePreference != pref else { return }
                        viewModel.languagePreference = pref
                        showLanguageRestartAlert = true
                    } label: {
                        Text(pref.displayName)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? CatDesign.accentAmber : CatDesign.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                isSelected ? CatDesign.amberTintFill : .clear,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(isSelected ? CatDesign.strokeAmber : .clear, lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(CatDesign.surfacePill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .catGlassCard(cornerRadius: 18)
    }
}

private struct CatAmberSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private var fraction: Double {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fillWidth = max(3, width * fraction)
            let pawOffset = min(max(fillWidth - 6, 0), max(width - 12, 0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CatDesign.progressTrack)
                    .frame(height: 3)

                Capsule()
                    .fill(CatDesign.glowAmber)
                    .frame(width: fillWidth, height: 3)

                Image("CatPawDot")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(CatDesign.glowAmber)
                    .shadow(color: CatDesign.glowAmber.opacity(0.8), radius: 2.5)
                    .offset(x: pawOffset)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag in
                        let rawFraction = min(max(drag.location.x / width, 0), 1)
                        let rawValue = range.lowerBound + rawFraction * (range.upperBound - range.lowerBound)
                        let stepped = (rawValue / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: 20)
    }
}

#Preview("Settings Main") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(CloudSyncCoordinator.shared)
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}

#Preview("Appearance") {
    NavigationStack {
        AppearanceSettingsView()
    }
    .preferredColorScheme(.dark)
}
