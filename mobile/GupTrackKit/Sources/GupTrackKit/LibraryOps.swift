import Foundation

// Between the API's library (ListEntry, WriteOp) and the app's (LibraryEntry, LibraryPatch): how a server entry
// shows, how an edit made on the phone becomes outbox ops, and how a waiting op shows before the server answers
// (the website's list rules, docs/app-api.md §7.2, with automatic dates on as the website's default).

extension ListEntry {
    /// the entry as the screens show it
    func library(_ media: APIMedia, updatedAt: Date) -> LibraryEntry {
        let kind = media.kind
        let t = Title(id: TitleKey(media: media, id: id).titleId, media: kind, name: title,
                      subtitle: alt.isEmpty ? nil : alt.joined(separator: " · "),
                      cover: cover.isEmpty ? nil : URL(string: cover), format: format.isEmpty ? nil : format,
                      total: total, volumes: volumes, runtime: Self.runtime(minutes, kind))
        let shown: ListStatus = rewatch != nil ? .repeating : (ListStatus(rawValue: status.rawValue) ?? .planned)
        return LibraryEntry(title: t, status: shown, progress: progress, volume: readVolumes > 0 ? readVolumes : nil,
                            score: score, repeats: repeats, started: started, finished: finished, notes: notes,
                            favourite: favourite, updatedAt: updatedAt)
    }

    /// "24 min" an episode, "2h 47m" a film; nil for reading lists
    static func runtime(_ minutes: Int, _ kind: MediaKind) -> String? {
        guard minutes > 0, !kind.isReading else { return nil }
        if kind == .movie || minutes >= 90 {
            let h = minutes / 60, m = minutes % 60
            return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
        }
        return "\(minutes) min"
    }

    /// a new entry for a title an op adds to a list
    init(_ meta: TitleMeta, id: String, status: EntryStatus, at: Int64) {
        self.init(id: id, title: meta.title, alt: meta.alt ?? [], cover: meta.cover ?? "", format: meta.format ?? "",
                  status: status, total: meta.total, minutes: meta.minutes ?? 0, volumes: meta.volumes,
                  idMal: meta.idMal, added: at)
    }
}

extension SyncEntry {
    var library: LibraryEntry { entry.library(media, updatedAt: Millis.date(changedAt)) }
}

extension TitleMeta {
    /// what a title page or browse card knows about a title, for adding it
    init(_ t: Title) {
        self.init(title: t.name, alt: nil,
                  cover: t.cover.flatMap { $0.scheme == "https" ? $0.absoluteString : nil },
                  format: t.format, total: t.total, volumes: t.volumes, minutes: nil, idMal: nil)
    }
}

extension WriteOp {
    /// The ops an edit becomes. A single status, count, score or heart change (and a rewatch) uses its own op, so
    /// the server's list rules apply; anything else (the edit sheet) is one `edit` op with the fields as given.
    /// `current` is the entry as the phone shows it now (nil: not on the list); `title` adds one that isn't.
    static func ops(for p: LibraryPatch, key: TitleKey, current: ListEntry?, title: Title?, at: Int64,
                    newId: () -> String = { UUID().uuidString }) -> [WriteOp] {
        func op(_ kind: Kind) -> WriteOp { WriteOp(requestId: newId(), op: kind, media: key.media, id: key.id, at: at) }
        let meta: TitleMeta? = current == nil ? title.map(TitleMeta.init) : nil
        if p.remove == true { return current == nil ? [] : [op(.remove)] }
        var out: [WriteOp] = []
        var rest = p
        if p.status == .repeating {
            var r = op(.rewatch)
            r.progress = p.progress
            out.append(r)
            rest.status = nil
            rest.progress = nil
        }
        let simple = rest.volume == nil && rest.season == nil && rest.repeats == nil && rest.started == nil
            && rest.finished == nil && rest.notes == nil
        if simple {
            var added = current != nil
            if let s = rest.status, let status = EntryStatus(rawValue: s.rawValue) {
                var o = op(.status)
                o.status = status
                if !added { o.meta = meta; added = true }
                out.append(o)
            }
            if let n = rest.progress {
                var o = op(.progress)
                o.progress = max(0, n)
                if !added { o.meta = meta; added = true }
                out.append(o)
            }
            if let s = rest.score {
                var o = op(.score)
                o.score = s < 0 ? nil : min(100, max(1, s))
                out.append(o)
            }
            if let f = rest.favourite {
                var o = op(.favourite)
                o.favourite = f
                out.append(o)
            }
            return out
        }
        var fields: [String: JSONValue] = [:]
        if let s = rest.status, let status = EntryStatus(rawValue: s.rawValue) { fields["status"] = .string(status.rawValue) }
        if let v = rest.progress { fields["progress"] = .int(max(0, v)) }
        if let v = rest.score { fields["score"] = v < 0 ? .null : .int(min(100, max(1, v))) }
        if let v = rest.volume { fields["readVolumes"] = .int(max(0, v)) }
        if let v = rest.repeats { fields["repeats"] = .int(max(0, v)) }
        if let v = rest.started { fields["started"] = v.isEmpty ? .null : .string(v) }
        if let v = rest.finished { fields["finished"] = v.isEmpty ? .null : .string(v) }
        if let v = rest.notes { fields["notes"] = .string(v) }
        if let v = rest.favourite { fields["favourite"] = .bool(v) }
        if current == nil {
            guard let meta else { return out }
            fields["title"] = .string(meta.title)
            if let c = meta.cover { fields["cover"] = .string(c) }
            if let f = meta.format { fields["format"] = .string(f) }
            if let t = meta.total { fields["total"] = .int(t) }
            if let v = meta.volumes { fields["volumes"] = .int(v) }
            if fields["status"] == nil { fields["status"] = .string(EntryStatus.planned.rawValue) }
        }
        if !fields.isEmpty {
            var o = op(.edit)
            o.entry = fields
            out.append(o)
        }
        return out
    }

    /// The entry as it shows with this op on top, before the server answers (nil: not on the list).
    func applied(to e: ListEntry?) -> ListEntry? {
        let today = Format.day(Millis.date(at))
        switch op {
        case .remove:
            return nil
        case .status:
            guard let status, var x = e ?? meta.map({ ListEntry($0, id: id, status: status, at: at) }) else { return e }
            x.status = status
            if status == .completed {
                if let t = x.total, t > 0 { x.progress = t }
                if x.finished == nil { x.finished = today }
                if x.rewatch != nil { x.rewatch = nil; x.repeats += 1 }
            }
            if status == .current, x.started == nil { x.started = today }
            return x
        case .progress:
            guard var x = e ?? meta.map({ ListEntry($0, id: id, status: .current, at: at) }) else { return e }
            if let n = progress { x.progress = max(0, x.total.map { min(n, $0) } ?? n) }
            if let p = position { x.position = max(0, p) }
            if x.status == .planned, x.progress > 0 { x.status = .current }
            if x.status == .current, x.started == nil, x.progress > 0 { x.started = today }
            if x.status == .current, let t = x.total, t > 0, x.progress >= t {
                x.status = .completed
                if x.finished == nil || x.rewatch != nil { x.finished = today }
                if x.rewatch != nil { x.rewatch = nil; x.repeats += 1 }
            }
            return x
        case .score:
            guard var x = e else { return nil }
            x.score = score
            return x
        case .favourite:
            guard var x = e, let favourite else { return e }
            x.favourite = favourite
            return x
        case .rewatch:
            guard var x = e, x.status == .completed, x.rewatch == nil else { return e }
            x.rewatch = Rewatch(progress: x.progress, started: x.started, finished: x.finished)
            x.status = .current
            x.progress = progress ?? 0
            x.started = today
            x.finished = nil
            return x
        case .edit:
            let f = entry ?? [:]
            var x: ListEntry
            if let e { x = e } else {
                guard let name = f["title"]?.string, let s = f["status"]?.string.flatMap(EntryStatus.init) else { return nil }
                x = ListEntry(id: id, title: name, status: s, added: at)
            }
            if let v = f["status"]?.string.flatMap(EntryStatus.init) { x.status = v }
            if let v = f["progress"]?.int { x.progress = v }
            if let v = f["score"] { x.score = v.int }
            if let v = f["readVolumes"]?.int { x.readVolumes = v }
            if let v = f["repeats"]?.int { x.repeats = v }
            if let v = f["started"] { x.started = v.string }
            if let v = f["finished"] { x.finished = v.string }
            if let v = f["notes"]?.string { x.notes = v }
            if let v = f["favourite"]?.bool { x.favourite = v }
            if let v = f["position"]?.double { x.position = v }
            if let v = f["total"] { x.total = v.int }
            if let v = f["volumes"] { x.volumes = v.int }
            if let v = f["title"]?.string { x.title = v }
            if let v = f["cover"]?.string { x.cover = v }
            if let v = f["format"]?.string { x.format = v }
            return x
        }
    }
}
