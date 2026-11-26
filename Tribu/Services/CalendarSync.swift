import EventKit
import UIKit
import Foundation

/// Copie l'agenda de la tribu dans un calendrier « Tribu » de l'iPhone (iCloud si disponible).
///
/// Sens unique : Tribu est la référence. Les événements copiés sont retrouvés grâce à une table
/// gardée sur l'iPhone (identifiant Tribu → identifiant du calendrier).
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()
    private let enabledKey = "tribu.calendarSync"
    private let mapKey = "tribu.calendarSync.map"
    private let calendarKey = "tribu.calendarSync.calendar"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func enable() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isEnabled = granted
            return granted
        } catch {
            isEnabled = false
            return false
        }
    }

    func disable() {
        isEnabled = false
        if let calendar = tribuCalendar(create: false) {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: mapKey)
        UserDefaults.standard.removeObject(forKey: calendarKey)
    }

    private func tribuCalendar(create: Bool) -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Tribu"
        calendar.cgColor = UIColor(red: 0.95, green: 0.39, blue: 0.25, alpha: 1).cgColor
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }
        guard calendar.source != nil else { return nil }
        do {
            try store.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
            return calendar
        } catch {
            return nil
        }
    }

    /// Met le calendrier « Tribu » de l'iPhone à jour avec les événements de la tribu.
    func sync(_ events: [FamilyEvent], people: [Person]) {
        guard isEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = tribuCalendar(create: true) else { return }
        var map = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        let ids = Set(events.map(\.id))

        for (tribuId, ekId) in map where !ids.contains(tribuId) {
            if let event = store.event(withIdentifier: ekId) { try? store.remove(event, span: .futureEvents, commit: false) }
            map[tribuId] = nil
        }

        for event in events {
            let ekEvent = map[event.id].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            ekEvent.calendar = calendar
            ekEvent.title = event.title
            ekEvent.startDate = event.start
            ekEvent.endDate = event.end
            ekEvent.isAllDay = event.allDay
            ekEvent.location = event.location.isEmpty ? nil : event.location
            let names = event.personIds.compactMap { id in people.first { $0.id == id }?.firstName }
            ekEvent.notes = [names.isEmpty ? nil : "Pour : " + names.joined(separator: ", "), event.notes.isEmpty ? nil : event.notes]
                .compactMap { $0 }.joined(separator: "\n")
            ekEvent.recurrenceRules = nil
            if let rule = Self.rule(event.recurrence) { ekEvent.addRecurrenceRule(rule) }
            do {
                try store.save(ekEvent, span: .futureEvents, commit: false)
                map[event.id] = ekEvent.eventIdentifier
            } catch {
                continue
            }
        }
        try? store.commit()
        UserDefaults.standard.set(map, forKey: mapKey)
    }

    private static func rule(_ recurrence: Recurrence) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch recurrence {
        case .none: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }
}
