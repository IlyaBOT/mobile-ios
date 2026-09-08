//
//  AudioListView.swift
//  OpenVK for iOS
//
//  Экран аудиозаписей и глобальный аудиоплеер.
//

import SwiftUI

private enum AudioLibraryTab: Int, CaseIterable {
    case mine
    case popular

    var title: String {
        switch self {
        case .mine: return "Моя музыка"
        case .popular: return "Популярная"
        }
    }
}

struct AudioListView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var viewModel = AudioLibraryViewModel()
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery = ""
    @State private var selectedTab: AudioLibraryTab = .mine

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var displayedTracks: [AudioTrack] {
        if isSearching {
            return viewModel.searchResults
        }
        switch selectedTab {
        case .mine: return viewModel.tracks
        case .popular: return viewModel.popularTracks
        }
    }

    private var isCurrentSectionLoading: Bool {
        if isSearching {
            return viewModel.isSearching && viewModel.searchResults.isEmpty
        }
        switch selectedTab {
        case .mine:
            return viewModel.isLoading && viewModel.tracks.isEmpty && viewModel.playlists.isEmpty
        case .popular:
            return viewModel.isLoadingPopular && viewModel.popularTracks.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AudioLibraryTabs(selectedTab: $selectedTab)
                .padding(.top, 4)

            AudioGlobalSearchField(text: $searchQuery)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if isCurrentSectionLoading {
                        AudioLibraryLoadingView()
                            .padding(.top, 12)
                    } else {
                        if selectedTab == .mine && !isSearching {
                            playlistsSection
                        }
                        tracksSection
                    }

                    if let message = viewModel.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, player.currentTrack == nil ? 24 : 92)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Музыка")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton(title: "Назад")
        .refreshable {
            await refresh()
        }
        .onAppear {
            guard let ownerID = auth.currentUser?.uid else { return }
            viewModel.load(ownerID: ownerID)
        }
        .onChange(of: selectedTab) { tab in
            if tab == .popular && !isSearching {
                viewModel.loadPopular()
            }
        }
        .onChange(of: searchQuery) { query in
            viewModel.search(query: query)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               selectedTab == .popular {
                viewModel.loadPopular()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openvkAudioLibraryDidChange)) { _ in
            guard let ownerID = auth.currentUser?.uid else { return }
            viewModel.load(ownerID: ownerID, force: true)
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ПЛЕЙЛИСТЫ")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            if viewModel.playlists.isEmpty {
                Text("You haven't added any playlists yet.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.playlists) { playlist in
                            NavigationLink(destination: AudioPlaylistDetailView(playlist: playlist)) {
                                AudioPlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sectionTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if displayedTracks.isEmpty && !isCurrentSectionLoading {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text(emptyText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(displayedTracks) { track in
                    AudioTrackRow(track: track, queue: displayedTracks)
                        .padding(.horizontal, 16)
                    SectionSeparator()
                }
            }
        }
    }

    private var sectionTitle: String {
        if isSearching { return "РЕЗУЛЬТАТЫ ПОИСКА" }
        return selectedTab == .mine ? "АУДИОЗАПИСИ" : "ПОПУЛЯРНОЕ"
    }

    private var emptyText: String {
        if isSearching { return "Ничего не найдено" }
        return selectedTab == .mine
            ? "В вашей коллекции пока нет аудиозаписей"
            : "Популярные аудиозаписи пока недоступны"
    }

    private func refresh() async {
        if isSearching {
            await withCheckedContinuation { continuation in
                viewModel.search(query: searchQuery, force: true) {
                    continuation.resume()
                }
            }
            return
        }

        switch selectedTab {
        case .mine:
            guard let ownerID = auth.currentUser?.uid else { return }
            await withCheckedContinuation { continuation in
                viewModel.load(ownerID: ownerID, force: true) {
                    continuation.resume()
                }
            }
        case .popular:
            await withCheckedContinuation { continuation in
                viewModel.loadPopular(force: true) {
                    continuation.resume()
                }
            }
        }
    }
}

private struct AudioLibraryTabs: View {
    @Binding var selectedTab: AudioLibraryTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AudioLibraryTab.allCases, id: \.rawValue) { tab in
                Button(action: {
                    HapticManager.impact(.light)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 7) {
                        Text(tab.title)
                            .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .appAccent : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.appAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct AudioGlobalSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(.secondaryLabel))

            TextField("Поиск по всей музыке", text: $text)
                .font(.system(size: 16))
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private final class AudioLibraryViewModel: ObservableObject {
    @Published var playlists: [AudioPlaylist] = []
    @Published var tracks: [AudioTrack] = []
    @Published var popularTracks: [AudioTrack] = []
    @Published var searchResults: [AudioTrack] = []
    @Published var isLoading = false
    @Published var isLoadingPopular = false
    @Published var isSearching = false
    @Published var errorMessage: String?

    private var loadedOwnerID: Int?
    private var didLoadPopular = false
    private var searchWorkItem: DispatchWorkItem?
    private var searchGeneration = 0

    func load(ownerID: Int, force: Bool = false, completion: (() -> Void)? = nil) {
        if !force, loadedOwnerID == ownerID, (!playlists.isEmpty || !tracks.isEmpty) {
            completion?()
            return
        }

        isLoading = true
        errorMessage = nil
        loadedOwnerID = ownerID

        let group = DispatchGroup()
        var firstError: String?

        group.enter()
        AudioService.shared.getPlaylists(ownerID: ownerID) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let playlists) = result {
                    self?.playlists = playlists
                } else if case .failure(let error) = result {
                    firstError = error.localizedDescription
                }
                group.leave()
            }
        }

        group.enter()
        AudioService.shared.getTracks(ownerID: ownerID) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let tracks) = result {
                    self?.tracks = tracks
                    AudioLibraryMembership.shared.seedAdded(tracks)
                } else if case .failure(let error) = result {
                    firstError = firstError ?? error.localizedDescription
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.errorMessage = firstError
            completion?()
        }
    }

    func loadPopular(force: Bool = false, completion: (() -> Void)? = nil) {
        if didLoadPopular && !force {
            completion?()
            return
        }

        isLoadingPopular = true
        errorMessage = nil
        AudioService.shared.getPopularTracks(count: 100) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let tracks):
                    self.popularTracks = tracks
                    self.didLoadPopular = true
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isLoadingPopular = false
                completion?()
            }
        }
    }

    func search(query: String, force: Bool = false, completion: (() -> Void)? = nil) {
        searchWorkItem?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            errorMessage = nil
            completion?()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, generation == self.searchGeneration else { return }
            self.isSearching = true
            self.searchResults = []
            self.errorMessage = nil
            AudioService.shared.searchTracks(query: trimmed, count: 100) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else {
                        completion?()
                        return
                    }
                    guard generation == self.searchGeneration else {
                        completion?()
                        return
                    }
                    switch result {
                    case .success(let tracks):
                        self.searchResults = tracks
                    case .failure(let error):
                        self.searchResults = []
                        self.errorMessage = error.localizedDescription
                    }
                    self.isSearching = false
                    completion?()
                }
            }
        }

        searchWorkItem = work
        if force {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        }
    }
}

private struct AudioPlaylistCard: View {
    let playlist: AudioPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AudioArtworkView(urlString: playlist.coverURL, cornerRadius: 12)
                .frame(width: 132, height: 132)

            Text(playlist.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)

            Text(trackCountText(playlist.size))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)
        }
    }

    private func trackCountText(_ count: Int) -> String {
        let lastTwo = count % 100
        if (11...14).contains(lastTwo) { return "\(count) треков" }
        switch count % 10 {
        case 1: return "\(count) трек"
        case 2, 3, 4: return "\(count) трека"
        default: return "\(count) треков"
        }
    }
}

private struct AudioPlaylistDetailView: View {
    let playlist: AudioPlaylist
    @State private var tracks: [AudioTrack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 10) {
                    AudioArtworkView(urlString: playlist.coverURL, cornerRadius: 16)
                        .frame(width: 190, height: 190)
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)

                    Text(playlist.title)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)

                    if !playlist.description.isEmpty {
                        Text(playlist.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 32)
                } else if tracks.isEmpty {
                    Text(errorMessage ?? "В этом плейлисте пока нет аудиозаписей")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    ForEach(tracks) { track in
                        AudioTrackRow(track: track, queue: tracks)
                            .padding(.horizontal, 16)
                        SectionSeparator()
                    }
                }
            }
            .padding(.bottom, AudioPlayerService.shared.currentTrack == nil ? 24 : 92)
        }
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton(title: "Моя музыка")
        .onAppear(perform: load)
    }

    private func load() {
        guard isLoading else { return }
        AudioService.shared.getTracks(
            ownerID: playlist.ownerID,
            playlistID: playlist.id,
            artworkURL: playlist.coverURL
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let resultTracks):
                    tracks = resultTracks
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }
}

struct AudioTrackRow: View {
    let track: AudioTrack
    let queue: [AudioTrack]
    @ObservedObject private var player = AudioPlayerService.shared

    private var isCurrent: Bool {
        guard let current = player.currentTrack else { return false }
        if let lhsOwner = current.ownerID, let rhsOwner = track.ownerID,
           let lhsID = current.vkID, let rhsID = track.vkID {
            return lhsOwner == rhsOwner && lhsID == rhsID
        }
        return current.id == track.id
    }

    var body: some View {
        Button(action: toggleTrack) {
            HStack(spacing: 12) {
                ZStack {
                    AudioArtworkView(urlString: track.artworkURL, cornerRadius: 8)

                    if isCurrent && player.isPreparing {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.15))
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if isCurrent && player.isPlaying {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.15))
                        AudioPauseBadge()
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isCurrent ? .appAccent : .primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.duration)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func toggleTrack() {
        HapticManager.impact(.light)
        if isCurrent {
            player.togglePlayPause()
        } else {
            player.play(track: track, in: queue)
        }
    }
}

struct AudioPauseBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)

            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.gray.opacity(0.82))
                    .frame(width: 4, height: 12)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.gray.opacity(0.82))
                    .frame(width: 4, height: 12)
            }
        }
    }
}

private struct AudioLibraryLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 132, height: 132)
                }
            }
            .padding(.horizontal, 16)

            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemFill))
                            .frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 120, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct AudioArtworkView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let raw = urlString, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        GeometryReader { geometry in
            Image(systemName: "music.note")
                .font(.system(
                    size: min(76, max(20, geometry.size.width * 0.25)),
                    weight: .medium
                ))
                .foregroundColor(Color(.secondaryLabel))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Global player overlay

private final class AudioKeyboardObserver: ObservableObject {
    @Published var endFrame: CGRect = .null

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                self.endFrame = frame
            }
        })
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                self?.endFrame = .null
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

struct GlobalAudioPlayerOverlay: View {
    let bottomInset: CGFloat
    @ObservedObject private var player = AudioPlayerService.shared
    @StateObject private var keyboard = AudioKeyboardObserver()
    @State private var dragOffset: CGFloat = 0

    private let miniPlayerHeight: CGFloat = 60
    private let tabBarBaseHeight: CGFloat = 49

    var body: some View {
        GeometryReader { geometry in
            if !player.isOverlayHidden, let track = player.currentTrack {
                let globalFrame = geometry.frame(in: .global)
                let keyboardOverlap = keyboard.endFrame.isNull
                    ? CGFloat(0)
                    : max(0, globalFrame.maxY - keyboard.endFrame.minY)
                let dockInset = keyboardOverlap > 0
                    ? keyboardOverlap
                    : tabBarBaseHeight + bottomInset
                let collapsedOffset = max(
                    0,
                    geometry.size.height - dockInset - miniPlayerHeight
                )
                let baseOffset = player.isExpanded ? 0 : collapsedOffset
                let sheetOffset = min(collapsedOffset, max(0, baseOffset + dragOffset))
                let expansionProgress = collapsedOffset > 0
                    ? 1 - (sheetOffset / collapsedOffset)
                    : 1

                AudioPlayerSheet(
                    track: track,
                    expansionProgress: expansionProgress,
                    bottomInset: bottomInset,
                    onExpand: expandPlayer
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(y: sheetOffset)
                .simultaneousGesture(playerDragGesture(collapsedOffset: collapsedOffset))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(player.currentTrack != nil)
    }

    private func expandPlayer() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
            dragOffset = 0
            player.isExpanded = true
        }
    }

    private func playerDragGesture(collapsedOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                if player.isExpanded {
                    dragOffset = min(collapsedOffset, max(0, value.translation.height))
                } else {
                    dragOffset = max(-collapsedOffset, min(0, value.translation.height))
                }
            }
            .onEnded { value in
                let vertical = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let isVertical = abs(vertical) > abs(value.translation.width)

                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
                    if isVertical {
                        if player.isExpanded {
                            if vertical > 70 || predicted > 130 {
                                player.isExpanded = false
                            }
                        } else if vertical < -45 || predicted < -90 {
                            player.isExpanded = true
                        }
                    }
                    dragOffset = 0
                }
            }
    }
}

private struct AudioPlayerSheet: View {
    let track: AudioTrack
    let expansionProgress: CGFloat
    let bottomInset: CGFloat
    let onExpand: () -> Void

    @ObservedObject private var player = AudioPlayerService.shared

    private var progress: CGFloat {
        min(1, max(0, expansionProgress))
    }

    private var miniOpacity: Double {
        Double(min(1, max(0, 1 - progress * 2.2)))
    }

    private var expandedOpacity: Double {
        Double(min(1, max(0, (progress - 0.08) / 0.92)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(miniOpacity)

                Color(.systemBackground)
                    .opacity(expandedOpacity)

                MiniAudioPlayerView(track: track)
                    .opacity(miniOpacity)

                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 38, height: 5)
                    .padding(.top, 44)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(expandedOpacity)
            }
            .frame(height: 60)
            .overlay(alignment: .top) {
                if player.duration > 0 {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.appAccent)
                            .frame(
                                width: geometry.size.width * CGFloat(
                                    min(1, max(0, player.currentTime / player.duration))
                                ),
                                height: 2
                            )
                    }
                    .frame(height: 2)
                    .opacity(miniOpacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if progress < 0.5 {
                    onExpand()
                }
            }

            ExpandedAudioPlayerView(track: track, bottomInset: bottomInset)
                .opacity(expandedOpacity)
                .allowsHitTesting(progress > 0.96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(expandedOpacity))
    }
}

private struct MiniAudioPlayerView: View {
    let track: AudioTrack
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        HStack(spacing: 10) {
            AudioArtworkView(urlString: track.artworkURL, cornerRadius: 7)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if player.isPreparing {
                ProgressView()
                    .frame(width: 34, height: 34)
            } else {
                Button(action: { player.togglePlayPause() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Button(action: { player.next() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
    }
}

private struct ExpandedAudioPlayerView: View {
    let track: AudioTrack
    let bottomInset: CGFloat
    @State private var selectedPage = 0

    private var showQueue: Bool {
        selectedPage == 1
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The player is the first page and the queue is physically to its right.
            // Native paging keeps both pages exactly screen-sized and gives the expected
            // gesture: swipe left on the player to reveal the queue, swipe right to return.
            TabView(selection: $selectedPage) {
                ExpandedAudioPlayerControlsView(track: track)
                    .tag(0)

                AudioPlaybackQueueView()
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))

            AudioPlayerBottomBar(
                showQueue: showQueue,
                bottomInset: bottomInset,
                selectPlayer: { selectPage(0) },
                selectQueue: { selectPage(1) }
            )
        }
        .clipped()
        .background(Color(.systemBackground))
    }

    private func selectPage(_ page: Int) {
        withAnimation(.easeInOut(duration: 0.24)) {
            selectedPage = page
        }
    }
}

private struct ExpandedAudioPlayerControlsView: View {
    let track: AudioTrack
    @ObservedObject private var player = AudioPlayerService.shared
    @ObservedObject private var membership = AudioLibraryMembership.shared

    var body: some View {
        GeometryReader { geometry in
            let artworkSize = min(
                geometry.size.width - 48,
                max(170, min(340, geometry.size.height * 0.42))
            )

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                AudioArtworkView(urlString: track.artworkURL, cornerRadius: 16)
                    .frame(width: artworkSize, height: artworkSize)
                    .shadow(color: Color.black.opacity(0.14), radius: 14, y: 7)

                Spacer(minLength: 14)

                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(track.artist)
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 28)

                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: { min(player.currentTime, max(player.duration, 0.01)) },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 0.01)
                    )
                    .tint(.appAccent)

                    HStack {
                        Text(timeString(player.currentTime))
                        Spacer()
                        Text("-\(timeString(max(0, player.duration - player.currentTime)))")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 30)
                .padding(.top, 18)

                HStack(spacing: geometry.size.width < 350 ? 16 : 26) {
                    Button(action: { membership.toggle(track) }) {
                        Group {
                            if membership.isPending(track) {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: membership.isAdded(track) ? "checkmark" : "plus")
                                    .font(.system(size: 24, weight: .semibold))
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .disabled(!membership.canMutate(track) || membership.isPending(track))
                    .foregroundColor(membership.canMutate(track) ? .appAccent : .secondary)

                    Button(action: { player.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .frame(width: 46, height: 46)
                    }

                    Button(action: { player.togglePlayPause() }) {
                        Group {
                            if player.isPreparing {
                                ProgressView()
                                    .scaleEffect(1.15)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 34, weight: .semibold))
                                    .offset(x: player.isPlaying ? 0 : 2)
                            }
                        }
                        .frame(width: 56, height: 56)
                    }

                    Button(action: { player.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .frame(width: 46, height: 46)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.primary)
                .padding(.top, 12)

                Spacer(minLength: 82)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AudioPlaybackQueueView: View {
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Очередь воспроизведения")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text(player.shuffleEnabled ? "Перемешанный порядок" : "Следующие треки")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if player.upcomingQueue.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34))
                        .foregroundColor(Color(.tertiaryLabel))
                    Text("Очередь пуста")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 76)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(player.upcomingQueue) { entry in
                            Button(action: {
                                HapticManager.impact(.light)
                                player.playQueueItem(at: entry.queueIndex)
                            }) {
                                HStack(spacing: 12) {
                                    AudioArtworkView(urlString: entry.track.artworkURL, cornerRadius: 8)
                                        .frame(width: 48, height: 48)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.track.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(entry.track.artist)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    Text(entry.track.duration)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            SectionSeparator()
                                .padding(.leading, 80)
                        }
                    }
                    .padding(.bottom, 86)
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct AudioPlayerBottomBar: View {
    let showQueue: Bool
    let bottomInset: CGFloat
    let selectPlayer: () -> Void
    let selectQueue: () -> Void

    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        HStack(spacing: 16) {
            Button(action: { player.toggleShuffle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.shuffleEnabled ? .appAccent : .secondary)
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            HStack(spacing: 18) {
                Button(action: selectPlayer) {
                    Circle()
                        .fill(showQueue ? Color(.tertiaryLabel) : Color.appAccent)
                        .frame(width: 8, height: 8)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: selectQueue) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(showQueue ? .appAccent : Color(.tertiaryLabel))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            Button(action: { player.cycleRepeatMode() }) {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.repeatMode == .off ? .secondary : .appAccent)
                    .frame(width: 52, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 30)
        .padding(.bottom, max(12, bottomInset + 6))
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 76)
            .allowsHitTesting(false),
            alignment: .bottom
        )
    }
}

struct AudioListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AudioListView()
                .environmentObject(AuthService.shared)
        }
    }
}
