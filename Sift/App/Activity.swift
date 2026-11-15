import Foundation

/// One thing Sift is doing, or waiting to do. `AppModel.activities` is the
/// only list of them: the sidebar footer shows every item, the banner shows
/// none (it only asks for decisions). A new background job adds its row
/// here, never a progress bar of its own.
struct Activity: Identifiable, Equatable {
    enum State: Equatable {
        /// Working. `total` nil means the size is not known.
        case running(done: Int, total: Int?)
        /// A site refused; the job waits until this time (see `block`).
        case paused(until: Date)
    }

    let id: String
    let title: String
    let state: State
}

extension AppModel {
    /// Everything running or paused, in a fixed order: sorting first (the
    /// user started it), then the library jobs that run by themselves.
    var activities: [Activity] {
        var out: [Activity] = []
        func run(_ id: String, _ title: String, _ on: Bool, _ p: (done: Int, total: Int)?) {
            guard on else { return }
            out.append(Activity(id: id, title: title, state: .running(done: p?.done ?? 0, total: p.map { $0.total })))
        }
        run("sort", sortingOnDevice ? "Sorting on this Mac" : "Sorting with Claude", isSorting, sortProgress)
        run("discover", "Finding themes with Claude", isDiscovering, nil)
        run("connections", "Finding links that feed two themes", isConnecting, connectProgress)
        run("feeds", "Checking feeds", isFetchingFeeds, feedProgress)
        run("capture", "Saving page text", isCapturing, captureProgress)
        run("youtube", "YouTube transcripts", isTranscribing, transcriptProgress)
        run("reels", "Reel transcripts", isTranscribingReels, reelProgress)
        run("images", "Instagram images", isFetchingInstagramImages, instagramImageProgress)
        run("titles", "YouTube titles", isFetchingVideoTitles, nil)
        run("summaries", "Summaries on this Mac", isSummarizing, summaryProgress)

        let paused: [(key: String, title: String)] = [
            ("youtube", "YouTube transcripts"),
            ("youtube-audio", "YouTube audio"),
            ("reels", "Reel transcripts"),
        ]
        for p in paused {
            if let until = state.blockedUntil[p.key], until > .now, !out.contains(where: { $0.id == p.key }) {
                out.append(Activity(id: p.key + "-paused", title: p.title, state: .paused(until: until)))
            }
        }
        return out
    }
}
