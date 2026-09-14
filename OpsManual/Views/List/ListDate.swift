import Foundation

/// Mirrors formatListDate in doc-list.tsx: HH:mm today, "2 Mar" this year, "24 Dec 2025" otherwise.
enum ListDate {
    static func format(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            f.dateFormat = "d MMM"
        } else {
            f.dateFormat = "d MMM yyyy"
        }
        return f.string(from: date)
    }
}

/// Matches what the previous build of the app rendered for the reader subtitle,
/// "Updated 13 Sep 2026 at 20:20" — that on-screen output is the reference. The
/// Node CLI is not: the same `toLocaleDateString("en-GB", …)` call in
/// doc-viewer.tsx prints "13 Sept 2026, 20:20" there.
enum ReaderDate {
    static func format(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy 'at' HH:mm"
        return f.string(from: date)
    }
}
