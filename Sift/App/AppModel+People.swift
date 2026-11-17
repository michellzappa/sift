import Foundation

/// People (Feeds/People.swift): finding a person's places, following them
/// everywhere at once, and which feeds belong to one person.
extension AppModel {
    /// The places Sift starts from: every followed site, newsletter, Bluesky
    /// and Mastodon feed, and the sites of the top writers in Your Graph.
    func peopleSeeds() -> [String: (profile: Place, name: String)] {
        var out: [String: (Place, String)] = [:]
        for f in offeredFeeds where f.enabled {
            if let p = People.profile(of: f), ["site", "substack", "bluesky"].contains(p.platform) { out[p.id] = (p, f.title) }
        }
        for c in creators.prefix(300) where c.id.hasPrefix("site:") {
            let host = String(c.id.dropFirst(5))
            let p = Place(platform: host.hasSuffix(".substack.com") ? "substack" : "site", url: "https://\(host)", handle: host)
            if out[p.id] == nil { out[p.id] = (p, c.name) }
        }
        return out
    }

    /// One round: up to `People.perRound` seeds not checked in two weeks,
    /// at most once an hour, then the merge.
    func refreshPeople(force: Bool = false) {
        guard !Demo.isOn, !isFindingPeople else { return }
        if people.isEmpty, !peopleFile.checked.isEmpty { mergePeople() }
        if !force, let last = peopleRound, Date().timeIntervalSince(last) < 3600 { return }
        peopleRound = Date()
        let seeds = peopleSeeds()
        let checked = peopleFile.checked
        let due = seeds.values.filter { s in
            guard let c = checked[s.profile.id] else { return true }
            return force || Date().timeIntervalSince(c.at) > People.recheckDays * 86_400
        }.prefix(People.perRound).map { ($0.profile, $0.name) }
        isFindingPeople = !due.isEmpty
        Task { [weak self] in
            var results: [String: People.Seed] = [:]
            for (p, name) in due { results[p.id] = await People.check(p, name: name) }
            guard let self else { return }
            for (k, v) in results { self.peopleFile.checked[k] = v }
            self.mergePeople()
            People.save(self.peopleFile)
            self.isFindingPeople = false
        }
    }

    /// People from every seed checked so far, minus the ones the user split.
    func mergePeople() {
        var seeds: [String: Place] = [:]
        for (id, s) in peopleSeeds() { seeds[id] = s.profile }
        // Seeds no longer followed still count while their check holds.
        for id in peopleFile.checked.keys where seeds[id] == nil {
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { seeds[id] = Place(platform: parts[0], url: parts[0] == "bluesky" ? "https://bsky.app/profile/\(parts[1].dropFirst())" : "https://\(parts[1])", handle: parts[1]) }
        }
        let hidden = Set(peopleFile.hidden)
        people = People.merge(peopleFile.checked, seeds: seeds).filter { !hidden.contains($0.id) }
        writeCreatorsForPhone()
    }

    /// The followed feed for a profile, if any.
    func followedFeed(for p: Place) -> Feed? {
        state.feeds.first { People.matches($0, p) }
    }

    /// Person id per followed feed, for Today (one post across platforms
    /// shows once; a person does not vouch for themselves in "Linked by").
    var personOfFeed: [String: String] {
        var out: [String: String] = [:]
        for person in people {
            for p in person.profiles { if let f = followedFeed(for: p) { out[f.id] = person.id } }
        }
        return out
    }

    /// Follows one place.
    func followProfile(_ p: Place) async -> Bool {
        guard !Demo.isOn, let input = p.followInput, followedFeed(for: p) == nil else { return false }
        guard let found = await FeedProviders.resolve(input).first else { return false }
        if !state.feeds.contains(where: { $0.url == found.url }) { addFeed(found) }
        if let i = state.feeds.firstIndex(where: { $0.url == found.url }) { state.feeds[i].place = p.id }
        return true
    }

    /// Follows every place of a person that has a feed and is not followed yet.
    func followPerson(_ person: Person) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        Task {
            var added = 0
            for p in person.profiles where p.hasFeed && followedFeed(for: p) == nil {
                if await followProfile(p) { added += 1 }
            }
            note(added == 0 ? "No new feeds for \(person.name)" : "Following \(person.name) in \(added) more place\(added == 1 ? "" : "s")")
            refreshCreators()
            refreshFeedCounts()
            refreshToday()
        }
    }

    /// "Not one person": the group goes away and stays away.
    func splitPerson(_ person: Person) {
        peopleFile.hidden.append(person.id)
        People.save(peopleFile)
        mergePeople()
    }

    /// The person a creator in Your Graph belongs to.
    func person(forCreator c: Creator) -> Person? {
        let key: String
        if c.id.hasPrefix("site:") { key = "site:" + c.id.dropFirst(5) }
        else if c.id.hasPrefix("youtube:") { return people.first { $0.profiles.contains { $0.platform == "youtube" && $0.handle.lowercased().filter(\.isLetter) == c.name.lowercased().filter(\.isLetter) } } }
        else { return nil }
        return people.first { $0.profiles.contains { $0.id == key } }
    }
}
