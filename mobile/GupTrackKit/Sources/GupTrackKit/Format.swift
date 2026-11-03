import Foundation

/// The app's clock and time zone. The demo (and its screenshots) runs on Tue Nov 3, 2026, 9:41 AM in New York, the
/// day the mockups were drawn for; the real app uses the phone's.
enum Clock {
    static var fixed: Date?
    static var fixedZone: TimeZone?

    static var now: Date { fixed ?? Date() }
    static var zone: TimeZone { fixedZone ?? .current }

    /// 2026-11-03 09:41 in America/New_York
    static let demoNow = Date(timeIntervalSince1970: 1_793_716_860)
    static let demoZone = TimeZone(identifier: "America/New_York")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
}

/// Words and numbers the way the website writes them.
enum Format {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Clock.zone
        f.dateFormat = format
        return f
    }

    /// 2775 -> "2,775"
    static func grouped(_ n: Int) -> String {
        let neg = n < 0
        var s = String(abs(n))
        var out = ""
        while s.count > 3 {
            out = "," + s.suffix(3) + out
            s = String(s.dropLast(3))
        }
        return (neg ? "-" : "") + s + out
    }

    /// 1234567 -> "1.2M", 48869 -> "48.9K", 999 -> "999"
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return trim(Double(n) / 1_000_000) + "M" }
        if n >= 1_000 { return trim(Double(n) / 1_000) + "K" }
        return String(n)
    }

    /// one decimal, without a trailing ".0"
    static func trim(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// a 0-100 score out of 10: 85 -> "8.5", 90 -> "9"
    static func score10(_ v: Int) -> String { trim(Double(v) / 10) }

    /// "8.6" from an average out of 10
    static func average(_ v: Double) -> String { String(format: "%.1f", v) }

    /// "2026-11-03" in the app's time zone
    static func day(_ d: Date) -> String { formatter("yyyy-MM-dd").string(from: d) }

    /// "2026-11-03" -> a date at noon that day (nil when it isn't one)
    static func parseDay(_ s: String) -> Date? {
        formatter("yyyy-MM-dd HH:mm").date(from: s + " 12:00")
    }

    /// "Nov 3, 2026"
    static func longDay(_ d: Date) -> String { formatter("MMM d, yyyy").string(from: d) }

    /// "Sep 2024"
    static func monthYear(_ d: Date) -> String { formatter("MMM yyyy").string(from: d) }

    /// "Nov 3"
    static func shortDay(_ d: Date) -> String { formatter("MMM d").string(from: d) }

    /// "Fri 3:00 AM"
    static func weekdayTime(_ d: Date) -> String { formatter("EEE h:mm a").string(from: d) }

    /// "3:00 AM"
    static func time(_ d: Date) -> String { formatter("h:mm a").string(from: d) }

    /// "Fri"
    static func weekday(_ d: Date) -> String { formatter("EEE").string(from: d) }

    /// whole days from now's day to d's day (0 today, 1 tomorrow, -1 yesterday)
    static func dayOffset(_ d: Date, now: Date = Clock.now) -> Int {
        let c = Clock.calendar
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: d)).day ?? 0
    }

    /// "in 3 days", "tomorrow", "today", "in 5h"
    static func until(_ d: Date, now: Date = Clock.now) -> String {
        let secs = d.timeIntervalSince(now)
        if secs <= 0 { return "aired" }
        if secs < 3600 { return "in \(max(1, Int(secs / 60)))m" }
        let days = dayOffset(d, now: now)
        if days == 0 { return "in \(Int(secs / 3600))h" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }

    /// "now", "5m", "2h", "3d", "Oct 12" (activity, messages, notifications)
    static func ago(_ d: Date, now: Date = Clock.now) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400))d" }
        return shortDay(d)
    }

    /// "5 min ago", "2 hours ago", "yesterday", "3 days ago", "Oct 12"
    static func agoLong(_ d: Date, now: Date = Clock.now) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { let h = Int(s / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        let days = -dayOffset(d, now: now)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        return shortDay(d)
    }

    /// minutes -> "45.3 days" style figures: 65_232 min -> 45.3
    static func days(minutes: Int) -> String { trim(Double(minutes) / 1440) }

    /// "Ep 7 · Fri 3:00 AM · in 3 days"
    static func airing(_ a: Airing, media: MediaKind = .anime, now: Date = Clock.now) -> String {
        "\(media.unitShort) \(a.episode) · \(weekdayTime(a.at)) · \(until(a.at, now: now))"
    }
}

extension Collection {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}
