// MusicKitService.swift
// Lecture Apple Music via MusicKit framework

import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.adriendonot.fluxapp", category: "MusicKit")

@Observable
final class MusicKitService {
    private struct QueueTrackContext {
        let url: URL
        let artworkURL: URL?
    }

    static let shared = MusicKitService()

    var isPlaying: Bool = false
    var isLoading: Bool = false
    var currentTrackTitle: String?
    var currentTrackArtist: String?
    var currentArticleURL: URL?
    var currentArtworkURL: URL?
    var lastError: String?
    var canNavigateTracks: Bool = false

    /// Le player est actif (en lecture ou en pause avec un morceau chargé)
    var isActive: Bool {
        currentArticleURL != nil && (isPlaying || currentTrackTitle != nil)
    }

    /// La queue contient plusieurs morceaux (playlist mode)
    var hasQueue: Bool {
        canNavigateTracks || player.queue.entries.count > 1
    }

    private let player = ApplicationMusicPlayer.shared
    private var pollTask: Task<Void, Never>?
    private var queuedTrackContextsByID: [MusicItemID: QueueTrackContext] = [:]
    private var currentPlaylistSignature: String?

    private init() {}

    // MARK: - Playback

    @MainActor
    func play(from url: URL, artworkURL: URL? = nil) async {
        lastError = nil

        isLoading = true
        currentArticleURL = url
        currentArtworkURL = artworkURL
        queuedTrackContextsByID = [:]
        currentPlaylistSignature = nil

        logger.info("Playing: \(url.absoluteString)")

        // Demander l'autorisation MusicKit
        let authStatus = await MusicAuthorization.request()
        guard authStatus == .authorized else {
            logger.error("MusicKit authorization denied: \(String(describing: authStatus))")
            lastError = "Accès Apple Music refusé"
            isLoading = false
            return
        }

        // Parser l'URL Apple Music
        guard let content = Self.parseAppleMusicURL(url) else {
            logger.error("Cannot parse Apple Music URL: \(url)")
            lastError = "URL Apple Music non reconnue"
            isLoading = false
            return
        }

        do {
            switch content {
            case .song(let id):
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let song = response.items.first else {
                    throw MusicKitServiceError.notFound
                }
                player.queue = [song]
                try await playWithRetry()
                currentTrackTitle = song.title
                currentTrackArtist = song.artistName
                canNavigateTracks = false

            case .album(let id):
                let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let album = response.items.first else {
                    throw MusicKitServiceError.notFound
                }
                player.queue = [album]
                try await playWithRetry()
                currentTrackTitle = album.title
                currentTrackArtist = album.artistName
                canNavigateTracks = true

            case .playlist(let id):
                let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
                let response = try await request.response()
                guard let playlist = response.items.first else {
                    throw MusicKitServiceError.notFound
                }
                player.queue = [playlist]
                try await playWithRetry()
                currentTrackTitle = playlist.name
                currentTrackArtist = playlist.curatorName
                canNavigateTracks = true
            }

            isPlaying = true
            isLoading = false
            startPolling()
            logger.info("Playback started: \(self.currentTrackTitle ?? "?")")

        } catch {
            logger.error("MusicKit playback error: \(error)")
            lastError = error.localizedDescription
            isLoading = false
        }
    }

    /// Joue une liste de morceaux Apple Music dans l'ordre (mode playlist)
    @MainActor
    func playPlaylist(tracks: [(url: URL, artworkURL: URL?)], startAtURL: URL? = nil) async {
        guard !tracks.isEmpty else { return }
        let requestedStartURL = startAtURL ?? tracks.first?.url
        let playlistSignature = Self.playlistSignature(for: tracks)

        lastError = nil
        isLoading = true
        currentArticleURL = requestedStartURL
        currentArtworkURL = tracks.first(where: { $0.url == requestedStartURL })?.artworkURL ?? tracks.first?.artworkURL
        canNavigateTracks = tracks.count > 1
        queuedTrackContextsByID = [:]
        currentPlaylistSignature = playlistSignature

        logger.info("Playing playlist: \(tracks.count) tracks")

        let authStatus = await MusicAuthorization.request()
        guard authStatus == .authorized else {
            logger.error("MusicKit authorization denied")
            lastError = "Accès Apple Music refusé"
            isLoading = false
            return
        }

        // Résoudre tous les morceaux depuis le catalogue
        var resolvedTracks: [(song: Song, url: URL, artworkURL: URL?)] = []
        for track in tracks {
            guard let content = Self.parseAppleMusicURL(track.url) else { continue }
            do {
                switch content {
                case .song(let id):
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
                    let response = try await request.response()
                    if let song = response.items.first {
                        resolvedTracks.append((song: song, url: track.url, artworkURL: track.artworkURL))
                    }
                case .album(let id):
                    let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                    let response = try await request.response()
                    if let album = response.items.first {
                        // Récupérer les pistes de l'album
                        let detailRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
                        let detailResponse = try await detailRequest.response()
                        if let detailedAlbum = detailResponse.items.first {
                            player.queue = [detailedAlbum]
                        }
                    }
                case .playlist(let id):
                    let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
                    let response = try await request.response()
                    if let playlist = response.items.first {
                        player.queue = [playlist]
                    }
                }
            } catch {
                logger.warning("Failed to resolve track: \(track.url) - \(error)")
            }
        }

        guard !resolvedTracks.isEmpty else {
            logger.error("No songs resolved from playlist")
            lastError = "Aucun morceau trouvé"
            isLoading = false
            canNavigateTracks = false
            currentPlaylistSignature = nil
            return
        }

        do {
            let songs = resolvedTracks.map(\.song)
            let startSong = requestedStartURL.flatMap { url in
                resolvedTracks.first(where: { $0.url == url })?.song
            } ?? songs.first

            // Workaround MusicKit bug: Queue(for:startingAt:) throws "unexpected start item"
            // even when the item IS in the array. Instead, rotate the array so startSong
            // comes first, then use Queue(for:) without startingAt.
            let orderedSongs: [Song]
            if let start = startSong, let idx = songs.firstIndex(where: { $0.id == start.id }) {
                orderedSongs = Array(songs[idx...]) + Array(songs[..<idx])
            } else {
                orderedSongs = songs
            }
            player.queue = ApplicationMusicPlayer.Queue(for: orderedSongs)
            queuedTrackContextsByID = Dictionary(
                uniqueKeysWithValues: resolvedTracks.map { track in
                    (track.song.id, QueueTrackContext(url: track.url, artworkURL: track.artworkURL))
                }
            )
            try await playWithRetry()

            if let startSong {
                currentTrackTitle = startSong.title
                currentTrackArtist = startSong.artistName
            }
            updateNowPlaying()

            isPlaying = true
            isLoading = false
            startPolling()
            logger.info("Playlist playback started: \(songs.count) songs")
        } catch {
            logger.error("Playlist playback error: \(error)")
            lastError = error.localizedDescription
            isLoading = false
            canNavigateTracks = false
            currentPlaylistSignature = nil
        }
    }

    @MainActor
    func playFromCollection(
        itemURL: URL,
        artworkURL: URL? = nil,
        containerURL: URL?,
        tracks: [(url: URL, artworkURL: URL?)]
    ) async {
        guard !tracks.isEmpty else {
            await play(from: itemURL, artworkURL: artworkURL)
            return
        }

        guard let containerURL else {
            await playPlaylist(tracks: tracks, startAtURL: itemURL)
            return
        }

        lastError = nil
        isLoading = true
        currentArticleURL = itemURL
        currentArtworkURL = artworkURL ?? tracks.first(where: { $0.url == itemURL })?.artworkURL
        canNavigateTracks = tracks.count > 1
        queuedTrackContextsByID = [:]
        currentPlaylistSignature = Self.playlistSignature(for: tracks)

        let authStatus = await MusicAuthorization.request()
        guard authStatus == .authorized else {
            logger.error("MusicKit authorization denied")
            lastError = "Accès Apple Music refusé"
            isLoading = false
            return
        }

        do {
            if let queuePayload = try await makeCollectionQueue(
                containerURL: containerURL,
                startAtURL: itemURL,
                localTracks: tracks
            ) {
                player.queue = queuePayload.queue
                queuedTrackContextsByID = queuePayload.contexts
                canNavigateTracks = queuePayload.canNavigate
                try await playWithRetry()

                // MusicKit startingAt bug workaround: check if wrong track is playing
                let actualEntry = player.queue.currentEntry?.title
                let expectedTitle = queuePayload.title
                if actualEntry != nil && actualEntry != expectedTitle {
                    logger.info("startingAt workaround: got '\(actualEntry!)' expected '\(expectedTitle)' — playing single song")
                    // Resolve the target song and play it directly
                    if let songID = Self.songID(from: itemURL) {
                        let songReq = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
                        if let song = try? await songReq.response().items.first {
                            player.queue = ApplicationMusicPlayer.Queue(for: [song])
                            try await player.play()
                        }
                    }
                }

                currentTrackTitle = queuePayload.title
                currentTrackArtist = queuePayload.artist
                isPlaying = true
                isLoading = false
                startPolling()
                logger.info("Playback started from collection: \(itemURL.absoluteString)")
                return
            }
        } catch {
            logger.warning("Collection playback fallback for \(itemURL.absoluteString): \(error)")
        }

        await playPlaylist(tracks: tracks, startAtURL: itemURL)
    }

    @MainActor
    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
            stopPolling()
            logger.info("Paused")
        } else {
            Task {
                do {
                    try await player.play()
                    isPlaying = true
                    startPolling()
                    logger.info("Resumed")
                } catch {
                    logger.error("Resume error: \(error)")
                    lastError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func skipToNext() async {
        do {
            try await player.skipToNextEntry()
            updateNowPlaying()
            scheduleNowPlayingRefresh()
            logger.info("Skipped to next track")
        } catch {
            logger.error("Skip next error: \(error)")
        }
    }

    @MainActor
    func skipToPrevious() async {
        do {
            try await player.skipToPreviousEntry()
            updateNowPlaying()
            scheduleNowPlayingRefresh()
            logger.info("Skipped to previous track")
        } catch {
            logger.error("Skip previous error: \(error)")
        }
    }

    @MainActor
    private func updateNowPlaying() {
        if let entry = player.queue.currentEntry {
            let entryArtworkURL = entry.artwork?.url(width: 800, height: 800)
            let context: QueueTrackContext?
            if let itemID = entry.item?.id {
                context = queuedTrackContextsByID[itemID]
            } else {
                context = nil
            }

            currentTrackTitle = entry.title
            currentTrackArtist = entry.subtitle

            if let context {
                currentArticleURL = context.url
                currentArtworkURL = context.artworkURL ?? entryArtworkURL
            } else if let entryArtworkURL {
                currentArtworkURL = entryArtworkURL
            }
        }
    }

    @MainActor
    private func scheduleNowPlayingRefresh(delay: Duration = .milliseconds(350)) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            self.updateNowPlaying()
        }
    }

    @MainActor
    func stop() {
        player.stop()
        isPlaying = false
        isLoading = false
        currentTrackTitle = nil
        currentTrackArtist = nil
        currentArticleURL = nil
        currentArtworkURL = nil
        lastError = nil
        canNavigateTracks = false
        currentPlaylistSignature = nil
        stopPolling()
    }

    // MARK: - Play with cold-start retry

    /// Lance la lecture et retry une fois si le player ne démarre pas (bug MusicKit cold start).
    @MainActor
    private func playWithRetry() async throws {
        try await player.play()
        // MusicKit cold start: play() peut réussir sans vraiment démarrer.
        // On vérifie après 350ms et on retry si nécessaire.
        try? await Task.sleep(for: .milliseconds(350))
        if player.state.playbackStatus != .playing {
            logger.info("Cold start retry: player status=\(String(describing: self.player.state.playbackStatus))")
            try await player.play()
        }
    }

    // MARK: - Polling (observe player state)

    private func startPolling() {
        stopPolling()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }

                let status = self.player.state.playbackStatus
                self.isPlaying = (status == .playing)

                let beforeTitle = self.currentTrackTitle
                self.updateNowPlaying()
                if self.currentTrackTitle != beforeTitle {
                    logger.info("[DEBUG-POLL] Track changed: \(beforeTitle ?? "nil") -> \(self.currentTrackTitle ?? "nil"), entry=\(self.player.queue.currentEntry?.title ?? "nil")")
                }

                if status == .stopped || status == .interrupted {
                    self.stopPolling()
                }
            }
        }
    }

    @MainActor
    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - URL Parsing

    enum ParsedContent {
        case song(String)
        case album(String)
        case playlist(String)
    }

    static func parseAppleMusicURL(_ url: URL) -> ParsedContent? {
        // Paramètre ?i= = morceau individuel dans un album
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let trackId = components.queryItems?.first(where: { $0.name == "i" })?.value {
            return .song(trackId)
        }

        let path = url.pathComponents
        guard let lastComponent = path.last, lastComponent != "/" else { return nil }

        if path.contains("song") {
            return .song(lastComponent)
        } else if path.contains("album") {
            return .album(lastComponent)
        } else if path.contains("playlist") {
            return .playlist(lastComponent)
        }

        return nil
    }

    // MARK: - Helpers

    static func isAppleMusicURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "music.apple.com" || host == "itunes.apple.com"
    }

    private func makeCollectionQueue(
        containerURL: URL,
        startAtURL: URL,
        localTracks: [(url: URL, artworkURL: URL?)]
    ) async throws -> (queue: ApplicationMusicPlayer.Queue, contexts: [MusicItemID: QueueTrackContext], title: String, artist: String?, canNavigate: Bool)? {
        let localContextBySongID = Self.localContextBySongID(from: localTracks)
        let startSongID = Self.songID(from: startAtURL)

        guard let parsedContainer = Self.parseAppleMusicURL(containerURL) else {
            return nil
        }

        switch parsedContainer {
        case .playlist(let id):
            let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            guard let playlist = response.items.first else {
                throw MusicKitServiceError.notFound
            }
            let detailedPlaylist = try await playlist.with([.entries])
            guard let entries = detailedPlaylist.entries, let firstEntry = entries.first else {
                return nil
            }

            let startEntry = entries.first(where: { entry in
                if let entrySongID = Self.songID(from: entry.url) {
                    return entrySongID == startSongID
                }
                return entry.item?.id.rawValue == startSongID
            }) ?? firstEntry

            let contexts = Dictionary(
                uniqueKeysWithValues: entries.compactMap { entry in
                    let itemID = entry.item?.id ?? entry.id
                    if let localContext = localContextBySongID[itemID.rawValue] {
                        return (itemID, localContext)
                    }
                    if let url = entry.url {
                        let artworkURL = entry.artwork?.url(width: 800, height: 800)
                        return (itemID, QueueTrackContext(url: url, artworkURL: artworkURL))
                    }
                    return nil
                }
            )

            // Workaround MusicKit bug: Queue(playlist:startingAt:) throws "unexpected start item".
            // Extract songs from entries, rotate so startEntry is first, use Queue(for:) without startingAt.
            let entrySongs: [Song] = entries.compactMap { entry in
                if case .song(let song) = entry.item { return song }
                return nil
            }
            let startSongFromEntry: Song? = entries.first(where: { $0.id == startEntry.id }).flatMap {
                if case .song(let s) = $0.item { return s } else { return nil }
            }
            let orderedEntrySongs: [Song]
            if let start = startSongFromEntry,
               let idx = entrySongs.firstIndex(where: { $0.id == start.id }),
               !entrySongs.isEmpty {
                orderedEntrySongs = Array(entrySongs[idx...]) + Array(entrySongs[..<idx])
            } else {
                orderedEntrySongs = entrySongs
            }
            // Fall back to playlist queue if songs can't be extracted (e.g., music videos)
            let queue: ApplicationMusicPlayer.Queue = orderedEntrySongs.isEmpty
                ? ApplicationMusicPlayer.Queue(playlist: detailedPlaylist, startingAt: startEntry)
                : ApplicationMusicPlayer.Queue(for: orderedEntrySongs)

            return (
                queue: queue,
                contexts: contexts,
                title: startEntry.title,
                artist: startEntry.artistName,
                canNavigate: entries.count > 1
            )

        case .album(let id):
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            guard let album = response.items.first else {
                throw MusicKitServiceError.notFound
            }
            let detailedAlbum = try await album.with([.tracks])
            guard let tracks = detailedAlbum.tracks, let firstTrack = tracks.first else {
                return nil
            }

            let startTrack = tracks.first(where: { track in
                if let trackURL = track.url, let trackSongID = Self.songID(from: trackURL) {
                    return trackSongID == startSongID
                }
                return track.id.rawValue == startSongID
            }) ?? firstTrack

            let contexts = Dictionary(
                uniqueKeysWithValues: tracks.compactMap { track in
                    if let localContext = localContextBySongID[track.id.rawValue] {
                        return (track.id, localContext)
                    }
                    if let url = track.url {
                        let artworkURL = track.artwork?.url(width: 800, height: 800)
                        return (track.id, QueueTrackContext(url: url, artworkURL: artworkURL))
                    }
                    return nil
                }
            )

            return (
                queue: ApplicationMusicPlayer.Queue(album: detailedAlbum, startingAt: startTrack),
                contexts: contexts,
                title: startTrack.title,
                artist: startTrack.artistName,
                canNavigate: tracks.count > 1
            )

        case .song:
            return nil
        }
    }

    private static func songID(from url: URL?) -> String? {
        guard let url, let parsed = parseAppleMusicURL(url) else { return nil }
        if case .song(let id) = parsed {
            return id
        }
        return nil
    }

    private static func localContextBySongID(
        from tracks: [(url: URL, artworkURL: URL?)]
    ) -> [String: QueueTrackContext] {
        Dictionary(
            uniqueKeysWithValues: tracks.compactMap { track in
                guard let id = songID(from: track.url) else { return nil }
                return (id, QueueTrackContext(url: track.url, artworkURL: track.artworkURL))
            }
        )
    }

    private static func playlistSignature(for tracks: [(url: URL, artworkURL: URL?)]) -> String {
        tracks.map { $0.url.absoluteString }.joined(separator: "|")
    }
}

enum MusicKitServiceError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return "Contenu introuvable sur Apple Music"
        }
    }
}
