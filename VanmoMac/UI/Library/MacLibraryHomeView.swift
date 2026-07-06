import SwiftUI
import SwiftData
import VanmoCore

struct MacLibraryHomeView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @Environment(\.macTheme) private var theme
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            MacHeaderToolbar(
                title: appState.selectedSection.title,
                isEmptyLibrary: libraryViewModel.isLibraryEmpty
            )

            if libraryViewModel.isLibraryEmpty {
                MacLibraryEmptyStateView {
                    appState.presentAddConnection()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MacFilterPills()
                            .padding(.bottom, 24)

                        if !libraryViewModel.continueWatching.isEmpty {
                            MacLibrarySectionHeader(title: "Continue Watching")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(libraryViewModel.continueWatching) { item in
                                        MacContinueWatchingCard(
                                            title: item.title,
                                            subtitle: item.subtitle,
                                            posterURL: item.posterURL,
                                            progress: item.progress
                                        ) {
                                            guard let mediaItem = libraryViewModel.resolveMediaItem(for: item) else { return }
                                            appState.openDetail(mediaItem)
                                        }
                                    }
                                }
                            }
                        }

                        if !libraryViewModel.recentlyAdded.isEmpty {
                            MacLibrarySectionHeader(title: "Recently Added")

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: MacDesignTokens.Layout.posterWidth), spacing: MacDesignTokens.Layout.posterSpacing)],
                                alignment: .leading,
                                spacing: MacDesignTokens.Layout.posterSpacing
                            ) {
                                ForEach(libraryViewModel.recentlyAdded) { item in
                                    MacPosterCard(
                                        title: item.title,
                                        subtitle: item.subtitle,
                                        posterURL: item.posterURL
                                    ) {
                                        guard let mediaItem = libraryViewModel.resolveMediaItem(for: item) else { return }
                                        appState.openDetail(mediaItem)
                                    }
                                }
                            }
                        }
                    }
                    .padding(MacDesignTokens.Layout.contentPadding)
                }
            }
        }
        .background(theme.appBackground)
        .onAppear {
            libraryViewModel.setModelContext(modelContext)
        }
        .onChange(of: appState.selectedFilter) { _, newValue in
            libraryViewModel.reload(filter: newValue, section: appState.selectedSection)
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            libraryViewModel.reload(filter: appState.selectedFilter, section: newValue)
        }
    }
}

#Preview {
    MacLibraryHomeView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .macTheme(.light)
}
