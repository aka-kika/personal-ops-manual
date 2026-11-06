import Foundation

/// How often Drift checks by itself, set in Settings with the same kind of slider as
/// mcpock's "Check servers": stops left to right, Manual at the right end.
/// Opening Drift and "Check now" always check right away.
enum DriftInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneHour = 3600
    case fourHours = 14400
    case twelveHours = 43200
    case oneDay = 86400
    case oneWeek = 604800
    case manual = 0

    /// Once a day (Kika, 2026-11-06: "once an hour is a lot, once a day is ok").
    static let `default` = DriftInterval.oneDay

    var id: Int { rawValue }

    /// Stop label, also the value shown beside the slider; short like mcpock's.
    var title: String {
        switch self {
        case .oneHour: "1 h"
        case .fourHours: "4 h"
        case .twelveHours: "12 h"
        case .oneDay: "1 day"
        case .oneWeek: "1 week"
        case .manual: "Manual"
        }
    }

    /// nil = no automatic check.
    var seconds: TimeInterval? { rawValue == 0 ? nil : TimeInterval(rawValue) }

    var sliderIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func nearest(toSliderPosition position: Double) -> DriftInterval {
        let index = Int(position.rounded())
        return allCases[min(max(index, 0), allCases.count - 1)]
    }

    /// Keyboard and VoiceOver: a small step moves one whole stop that way.
    static func stepped(from current: DriftInterval, toward position: Double) -> DriftInterval {
        let index = Double(current.sliderIndex)
        let delta = position - index
        if abs(delta) >= 1 { return nearest(toSliderPosition: position) }
        if delta > 0 { return nearest(toSliderPosition: index + 1) }
        if delta < 0 { return nearest(toSliderPosition: index - 1) }
        return current
    }

    /// A stored value: a known stop as is, 0 as Manual, anything else to the nearest automatic stop.
    static func fromStored(_ seconds: Int) -> DriftInterval {
        if let exact = DriftInterval(rawValue: seconds) { return exact }
        guard seconds > 0 else { return .default }
        return allCases.filter { $0 != .manual }
            .min { abs($0.rawValue - seconds) < abs($1.rawValue - seconds) } ?? .default
    }

    /// Whether a check is due now, given the last one.
    func isDue(lastChecked: Date?, now: Date = Date()) -> Bool {
        guard let seconds else { return false }
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= seconds
    }
}
