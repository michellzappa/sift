import Foundation

extension AppModel {
    // MARK: Capture (the library engine, step 1)

    /// Links worth capturing: everything Sift has seen, minus errands, drop,
    /// and links captured already (failed ones retry after a week).
    var linksToCapture: [ArchiveRecord] {
        archive.values.filter { r in
            guard r.theme != Project.errands, r.theme != Project.drop, !Errands.isErrand(r.url) else { return false }
            // TikTok videos wait for their caption (fetchTikTokDetails).
            if TikTokReader.videoID(r.url) != nil, (previews[r.url]?.title ?? "").isEmpty { return false }
            guard let e = library[r.url] else { return true }
            // Videos captured before Sift read their length: read the page again
            // (not when a transcript was appended to the file).
            if e.kind == "video", e.status == "ok", e.duration == nil, e.transcript != true { return true }
            // Posts captured as thin before posts were exempt: redo once.
            if e.status == "thin", Self.isPostURL(r.url) { return true }
            // Failed posts that now have known text (an Instagram caption) retry now.
            if e.status == "failed", Self.isPostURL(r.url), !(previews[r.url]?.text ?? "").isEmpty { return true }
            return e.status == "failed" && Date().timeIntervalSince(e.captured) > 7 * 24 * 3600
        }
    }

    /// Fetches and extracts the text of every link not yet in the library,
    /// four at a time, and writes it as Markdown. Local only: no Claude.
    func captureAll() async {
        guard !Demo.isOn else { return }
        guard !isCapturing else { return }
        let todo = linksToCapture
        guard !todo.isEmpty else { return }
        isCapturing = true
        captureProgress = (0, todo.count)
        defer { isCapturing = false; Library.saveIndex(library); PreviewFetcher.saveCache(previews); scheduleSearchIndex() }
        // Posts (X, Instagram) are captured from the text Sift already has:
        // their pages need a login or JavaScript. An X post without text yet
        // is asked from oEmbed (syndication when on), never from x.com.
        let xSyndication = state.xSyndication
        let jobs: [(ArchiveRecord, Capture?)] = todo.map { r in
            guard Self.isPostURL(r.url) else { return (r, nil) }
            if XClient.statusID(r.url) != nil { return (r, xCapture(for: r.url)) }
            guard let text = previews[r.url]?.text, !text.isEmpty else { return (r, nil) }
            let site = URL(string: r.url)?.host() ?? ""
            return (r, Capture(url: r.url, title: "", author: nil, site: site, published: nil, kind: "post", text: text))
        }
        await withTaskGroup(of: (ArchiveRecord, Capturer.Outcome).self) { group in
            var iterator = jobs.makeIterator()
            func next(_ job: (ArchiveRecord, Capture?)) {
                let (r, known) = job
                group.addTask { (r, await Capturer.capture(r.url, known: known, xSyndication: xSyndication)) }
            }
            for _ in 0..<4 { if let j = iterator.next() { next(j) } }
            for await (r, outcome) in group {
                switch outcome {
                case .captured(let capture):
                    library[r.url] = Library.write(capture, title: r.title, theme: r.theme, source: r.source)
                    // A video's page gives its real title and description.
                    if capture.kind == "video" {
                        var p = previews[r.url] ?? Preview(title: "", text: "", imageURL: nil, site: "youtube.com", fetched: .now)
                        if !capture.title.isEmpty { p.title = capture.title }
                        let body = capture.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                        if !body.isEmpty { p.text = String(body.prefix(400)) }
                        previews[r.url] = p
                    }
                case .gone:
                    library[r.url] = Library.Entry(file: "", captured: .now, words: 0, kind: "page", status: "gone")
                case .failed:
                    // A site that asked to slow down is left for a later run.
                    if await HostGate.shared.isPaused((URL(string: r.url)?.host() ?? "").lowercased()) { break }
                    library[r.url] = Library.Entry(file: "", captured: .now, words: 0, kind: "page", status: "failed")
                }
                captureProgress.done += 1
                if captureProgress.done % 25 == 0 { Library.saveIndex(library) }
                if let j = iterator.next() { next(j) }
            }
        }
        Task { await summarizeLibrary() }
    }

    /// Repairs the library once (1.7.9): X posts captured from x.com's page
    /// kept its no-JavaScript shell ("enable JavaScript", then CSS), and the
    /// on-device model summarized it. Every X post is written again from its
    /// post text (X API or preview); without post text a junk X file is
    /// cleared and the post goes back in the capture queue (oEmbed). Any
    /// other file whose text fails `ShellText` becomes title only. The new
    /// or cleared files have no summary, so the summary is made again where
    /// there is text. Files with a transcript are left alone.
    /// One-time repair for text fetched before `ShellText` existed: feed items
    /// and Today's picks that hold a shell page or a code dump lose that text
    /// (the reader fetches the article again, through the guard).
    func repairFeedText() async {
        let key = "feeds.shellTextV1"
        guard !Demo.isOn, !UserDefaults.standard.bool(forKey: key) else { return }
        let ids = state.feeds.map(\.id)
        let cleared = await Task.detached(priority: .utility) { ids.reduce(0) { $0 + FeedStore.clearJunk($1) } }.value
        if var today = state.today {
            for i in today.picks.indices {
                if let c = today.picks[i].content, ShellText.isJunk(c) { today.picks[i].content = nil }
                if ShellText.isJunk(today.picks[i].summary) { today.picks[i].summary = "" }
            }
            state.today = today
            writeTodayForPhone()
        }
        UserDefaults.standard.set(true, forKey: key)
        if cleared > 0 { refreshFeedCounts() }
    }

    func repairCapturedText() async {
        let key = "library.shellTextV1"
        guard !Demo.isOn, !UserDefaults.standard.bool(forKey: key) else { return }
        let todo = library.filter { !$0.value.file.isEmpty && $0.value.transcript != true }.map(\.key)
        // Read the files off the main actor; only plain values go in and out.
        let checked: [(url: String, junk: Bool)] = await Task.detached(priority: .utility) {
            todo.compactMap { url in
                let isX = XClient.statusID(url) != nil
                let junk = ShellText.isJunk(Library.text(for: url) ?? "")
                return isX || junk ? (url, junk) : nil
            }
        }.value
        for (url, junk) in checked {
            guard let old = library[url] else { continue }
            // A preview made from the shell page is dropped and fetched again.
            if let p = previews[url], ShellText.isJunk(p.text) { previews[url] = nil }
            if XClient.statusID(url) != nil, let c = xCapture(for: url) {
                let r = archive[url]
                library[url] = Library.write(c, title: r?.title ?? "", theme: r?.theme, source: r?.source ?? "x")
            } else if junk {
                Library.clearText(file: old.file)
                if XClient.statusID(url) != nil {
                    // Not captured: the next capture asks oEmbed for the post.
                    library[url] = nil
                } else {
                    var e = old
                    e.status = "failed"; e.words = 0; e.summary = nil; e.captured = .now
                    library[url] = e
                }
            }
        }
        Library.saveIndex(library)
        PreviewFetcher.saveCache(previews)
        UserDefaults.standard.set(true, forKey: key)
        scheduleSearchIndex()
    }

    static func isPostURL(_ url: String) -> Bool {
        if XClient.statusID(url) != nil { return true }
        let host = URL(string: url)?.host()?.lowercased() ?? ""
        return host.hasSuffix("instagram.com") || host.hasSuffix("tiktok.com")
    }

    // MARK: YouTube transcripts

    /// YouTube links without a transcript attempt, newest saves first.
    var videosNeedingTranscript: [ArchiveRecord] {
        guard state.youtubeTranscripts, TranscriptTool.executable != nil, !isBlocked("youtube") || canHearYouTube else { return [] }
        return archive.values
            .filter { TranscriptTool.videoID($0.url) != nil && library[$0.url]?.transcript == nil && !transcriptTried.contains($0.url) }
            .sorted { $0.firstSeen > $1.firstSeen }
    }

    var transcriptCount: Int { library.filter { $0.value.transcript == true && TranscriptTool.videoID($0.key) != nil }.count }

    // MARK: Library jobs

    private func checkDataProblems() {
        let all = SafeStore.problems
        guard all.count > shownProblems else { return }
        dataProblem = all[shownProblems...].joined(separator: "\n\n")
        shownProblems = all.count
    }

    /// Starts every background library job that has work and is not running.
    func startLibraryJobs() {
        // Seen marks from the other devices come in with each round.
        loadSeen()
        // Your Graph first: Today's ranking reads it.
        refreshCreators()
        // A new Today digest at 07:00 and 17:00; feeds not fetched in the last hour.
        refreshToday()
        Task { await fetchFeeds() }
        checkDataProblems()
        // Demo mode: no capture, transcripts, images or summaries.
        guard !Demo.isOn else { return }
        // YouTube videos get their transcript.
        if !isTranscribing, !videosNeedingTranscript.isEmpty { Task { await fetchTranscripts() } }
        // Instagram reels get their speech as text.
        if !isTranscribingReels, !reelsNeedingTranscript.isEmpty { Task { await fetchReelTranscripts() } }
        // Instagram posts get their image.
        if state.instagramImages, !isFetchingInstagramImages, !instagramPostsWithoutImage.isEmpty { Task { await fetchInstagramImages() } }
        // TikTok videos get caption, author and cover from their page.
        if !isFetchingTikTok, !tiktokNeedingDetails.isEmpty { Task { await fetchTikTokDetails() } }
        // YouTube links with no title get one from YouTube's oEmbed.
        if !isFetchingVideoTitles, !videosWithoutTitle.isEmpty { Task { await fetchVideoTitles() } }
        // Who you follow on each network, when an export or handle changed;
        // then one reminder for a stale export (AppModel+Following).
        refreshFollowing()
        checkExportReminders()
        // New links go into the library, after the one-time repair of
        // shell pages (X posts and other no-JavaScript pages).
        Task {
            await repairCapturedText()
            await repairFeedText()
            if state.autoCapture, !isCapturing, !linksToCapture.isEmpty { await captureAll() }
        }
        // Older library entries get their author (Your Graph), once; then
        // Next door reads who your creators link to (at most hourly).
        Task {
            await backfillAuthors()
            await refreshNeighbors()
            // Where your creators publish: one person, many places.
            refreshPeople()
            // Theme dials: end and start the sources Sift tries.
            refreshTrials()
            // Settings > You for the iPhone, once a day.
            await writeProfileForPhone()
        }
        // Meaning on this Mac for links and recent feed items (trails, Today).
        refreshEmbeddings()
        // Saved pages and transcripts get a short summary on this Mac.
        Task { await summarizeLibrary() }
    }

    /// YouTube links that show their URL because the import had no title.
    var videosWithoutTitle: [String] {
        archive.values.filter { r in
            TranscriptTool.videoID(r.url) != nil && !videoTitleTried.contains(r.url)
                && (previews[r.url]?.title ?? "").isEmpty && (r.title.isEmpty || r.title.hasPrefix("http"))
        }
        .sorted { $0.firstSeen > $1.firstSeen }
        .map(\.url)
    }

    /// One oEmbed request a second, newest first.
    func fetchVideoTitles() async {
        guard !Demo.isOn else { return }
        guard !isFetchingVideoTitles else { return }
        let todo = videosWithoutTitle
        guard !todo.isEmpty else { return }
        isFetchingVideoTitles = true
        defer { isFetchingVideoTitles = false; PreviewFetcher.saveCache(previews); recordArchive(); scheduleSearchIndex() }
        for (i, url) in todo.enumerated() {
            videoTitleTried.insert(url)
            guard await HostGate.shared.admit("oembed.youtube") else { return }
            guard let p = await PreviewFetcher.youTube(url) else { continue }
            var merged = previews[url] ?? p
            merged.title = p.title
            if merged.text.isEmpty || merged.text.hasPrefix("In Watch later") || merged.text.hasPrefix("In ") { merged.text = p.text }
            if merged.imageURL == nil { merged.imageURL = p.imageURL }
            merged.failed = false
            previews[url] = merged
            if archive[url] != nil { archive[url]?.title = p.title }
            if i % 25 == 24 { PreviewFetcher.saveCache(previews); ArchiveStore.save(archive) }
        }
    }

    /// Jobs also restart on their own, every 15 minutes, so a job that
    /// stopped (a site asked to slow down) resumes without a reload.
    func startLibraryWorker() {
        guard !Demo.isOn else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                self?.startLibraryJobs()
            }
        }
    }

    /// A service that refused Sift waits before the next try: 1 hour, then
    /// 2, 4, 8, 16 and at most 24. The wait survives a relaunch, so a
    /// relaunch never hits a service that is still blocking.
    func isBlocked(_ job: String) -> Bool { (state.blockedUntil[job] ?? .distantPast) > .now }

    func block(_ job: String) {
        let hours = min(24, max(1, (state.backoffHours[job] ?? 0.5) * 2))
        state.backoffHours[job] = hours
        state.blockedUntil[job] = Date().addingTimeInterval(hours * 3600)
    }

    func unblock(_ job: String) {
        if state.backoffHours[job] != nil { state.backoffHours[job] = nil }
        if state.blockedUntil[job] != nil { state.blockedUntil[job] = nil }
    }

    /// One video at a time, paced by HostGate; stops when YouTube throttles.
    func fetchTranscripts() async {
        guard !Demo.isOn else { return }
        guard !isTranscribing else { return }
        let todo = videosNeedingTranscript
        guard !todo.isEmpty else { return }
        isTranscribing = true
        transcriptProgress = (0, todo.count)
        defer { isTranscribing = false; Library.saveIndex(library); scheduleSearchIndex() }
        for r in todo {
            guard state.youtubeTranscripts, let id = TranscriptTool.videoID(r.url) else { break }
            transcriptTried.insert(r.url)
            // Captions first; when YouTube refuses them, the audio.
            var outcome = TranscriptTool.Outcome.throttled
            if !isBlocked("youtube") {
                outcome = await TranscriptTool.fetch(id)
                if case .throttled = outcome { block("youtube") }
            }
            switch outcome {
            case .transcript(let text):
                unblock("youtube")
                library[r.url] = Library.addTranscript(text, to: r, existing: library[r.url])
            case .none:
                var e = library[r.url] ?? Library.Entry(file: "", captured: .now, words: 0, kind: "video", status: "failed")
                e.transcript = false
                library[r.url] = e
            case .throttled:
                switch await hear(r) {
                case .some(let text?):
                    library[r.url] = Library.addTranscript(text, to: r, existing: library[r.url], heard: true)
                case .some(nil):
                    var e = library[r.url] ?? Library.Entry(file: "", captured: .now, words: 0, kind: "video", status: "failed")
                    e.transcript = false
                    library[r.url] = e
                case nil:
                    // Neither captions nor audio now: the video goes back in the queue.
                    transcriptTried.remove(r.url)
                    return
                }
            }
            transcriptProgress.done += 1
            if transcriptProgress.done % 10 == 0 { Library.saveIndex(library) }
        }
    }

    /// Whether the audio route can run: yt-dlp is installed, the switch is
    /// on and YouTube is not refusing audio either.
    var canHearYouTube: Bool { state.youtubeAudio && ReelTool.executable != nil && !isBlocked("youtube-audio") }

    /// Transcribes a video's audio on this Mac. nil: try again later (route
    /// unavailable or refused); .some(nil): tried, no text (no speech, too
    /// long, a language this Mac cannot do on device).
    private func hear(_ r: ArchiveRecord) async -> String?? {
        guard canHearYouTube, await ReelSpeech.authorize() else { return nil }
        // Very long videos (over 90 minutes) are left to captions.
        if let seconds = library[r.url]?.duration, seconds > 90 * 60 { return .some(nil) }
        switch await ReelTool.audio(for: r.url, gate: ReelTool.youTubeGate) {
        case .throttled:
            block("youtube-audio")
            return nil
        case .none:
            return .some(nil)
        case .audio(let file):
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            unblock("youtube-audio")
            let text = await ReelSpeech.transcribe(file, hint: previews[r.url]?.title ?? r.title, onDeviceOnly: true)
            return .some(text.flatMap { $0.count > 200 ? $0 : nil })
        }
    }

    func installTranscriptTool() async {
        guard !Demo.isOn else { return }
        transcriptToolMessage = "Installing…"
        transcriptToolMessage = await TranscriptTool.install() ?? "Installed."
        if TranscriptTool.executable != nil, !isTranscribing { Task { await fetchTranscripts() } }
    }

    // MARK: Instagram reel transcripts

    /// Reels without a transcript attempt, newest saves first.
    var reelsNeedingTranscript: [ArchiveRecord] {
        guard state.reelTranscripts, ReelTool.executable != nil else { return [] }
        return archive.values
            .filter { ReelTool.isShortVideo($0.url) && !isBlocked(ReelTool.job(for: $0.url).block)
                && library[$0.url]?.transcript == nil && !reelTried.contains($0.url) }
            .sorted { $0.firstSeen > $1.firstSeen }
    }

    var reelCount: Int { archive.keys.filter(ReelTool.isShortVideo).count }
    var reelTranscriptCount: Int { library.filter { $0.value.transcript == true && ReelTool.isShortVideo($0.key) }.count }

    /// One reel at a time: audio through yt-dlp, text through macOS speech
    /// recognition. Stops when Instagram throttles or speech is not allowed.
    func fetchReelTranscripts() async {
        guard !Demo.isOn else { return }
        guard !isTranscribingReels else { return }
        let todo = reelsNeedingTranscript
        guard !todo.isEmpty else { return }
        guard await ReelSpeech.authorize() else {
            reelToolMessage = "Speech Recognition is off for Sift in System Settings > Privacy & Security."
            return
        }
        isTranscribingReels = true
        reelProgress = (0, todo.count)
        defer { isTranscribingReels = false; Library.saveIndex(library); scheduleSearchIndex() }
        for r in todo {
            guard state.reelTranscripts else { break }
            let job = ReelTool.job(for: r.url)
            // One platform refusing does not stop the other.
            if isBlocked(job.block) { continue }
            reelTried.insert(r.url)
            var text: String?
            switch await ReelTool.audio(for: r.url, gate: job.gate) {
            case .throttled:
                reelTried.remove(r.url)
                block(job.block)
                reelProgress.done += 1
                continue
            case .none: text = nil
            case .audio(let file):
                text = await ReelSpeech.transcribe(file, hint: Library.text(for: r.url) ?? r.title)
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
            if let text, text.count > 20 {
                unblock(job.block)
                library[r.url] = Library.addTranscript(text, to: r, existing: library[r.url])
            } else {
                var e = library[r.url] ?? Library.Entry(file: "", captured: .now, words: 0, kind: "post", status: "failed")
                e.transcript = false
                library[r.url] = e
            }
            reelProgress.done += 1
            if reelProgress.done % 10 == 0 { Library.saveIndex(library) }
        }
    }

    func installReelTool() async {
        guard !Demo.isOn else { return }
        reelToolMessage = "Installing…"
        reelToolMessage = await ReelTool.install() ?? "Installed."
        if ReelTool.executable != nil, !isTranscribingReels { Task { await fetchReelTranscripts() } }
    }

    // MARK: Instagram images

    /// Instagram links (any source) whose preview has no image yet.
    var instagramPostsWithoutImage: [String] {
        let urls = Set(tabs.map(\.url)).union(archive.keys)
        return urls.filter { u in
            guard u.contains("instagram.com/"), !instagramImageTried.contains(u) else { return false }
            return previews[u]?.imageURL == nil
        }.sorted()
    }

    /// One post at a time, with a pause between posts, to stay polite.
    func fetchInstagramImages() async {
        guard !Demo.isOn else { return }
        guard !isFetchingInstagramImages else { return }
        let todo = instagramPostsWithoutImage
        guard !todo.isEmpty else { return }
        isFetchingInstagramImages = true
        instagramImageProgress = (0, todo.count)
        defer { isFetchingInstagramImages = false; PreviewFetcher.saveCache(previews) }
        let fetcher = InstagramImageFetcher()
        for url in todo {
            guard state.instagramImages else { break }
            instagramImageTried.insert(url)
            if let image = await fetcher.image(for: url) {
                var p = previews[url] ?? Preview(title: "", text: "", imageURL: nil, site: "instagram.com", fetched: .now)
                p.imageURL = image
                previews[url] = p
            }
            instagramImageProgress.done += 1
            if instagramImageProgress.done % 10 == 0 { PreviewFetcher.saveCache(previews) }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    var instagramImageCount: Int {
        previews.filter { $0.key.contains("instagram.com/") && ($0.value.imageURL?.hasPrefix("file:") ?? false) }.count
    }

    /// Forgets failed captures so the next run tries them again.
    func retryFailedCaptures() async {
        guard !Demo.isOn else { return }
        for (url, e) in library where e.status == "failed" { library[url] = nil }
        Library.saveIndex(library)
        await captureAll()
    }

    var capturedCount: Int { library.values.filter { $0.status != "failed" }.count }
}
