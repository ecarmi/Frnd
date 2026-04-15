import Foundation
import Combine

@MainActor
final class SavedEventsStore: ObservableObject {
    static let shared = SavedEventsStore()

    @Published private(set) var savedEvents: [Event] = []
    @Published private(set) var savedEventIDs: Set<String> = []

    private init() {}

    func isSaved(_ event: Event) -> Bool {
        savedEventIDs.contains(event.id) || event.isSaved
    }

    func bootstrap(from events: [Event]) {
        for event in events where event.isSaved {
            upsertSavedEvent(event)
        }
    }

    func replaceSavedEvents(_ events: [Event]) {
        let normalized = events.map { event in
            var updated = event
            updated.isSaved = true
            return updated
        }
        savedEvents = normalized
        savedEventIDs = Set(normalized.map(\.id))
    }

    func toggle(event: Event) async throws {
        let wasSaved = isSaved(event)
        setSaved(event: event, isSaved: !wasSaved)

        do {
            if wasSaved {
                try await APIService.shared.unsaveEvent(eventId: event.id)
            } else {
                try await APIService.shared.saveEvent(eventId: event.id)
            }
        } catch {
            setSaved(event: event, isSaved: wasSaved)
            throw error
        }
    }

    func setSaved(event: Event, isSaved: Bool) {
        if isSaved {
            upsertSavedEvent(event)
        } else {
            savedEventIDs.remove(event.id)
            savedEvents.removeAll { $0.id == event.id }
        }
    }

    private func upsertSavedEvent(_ event: Event) {
        var updated = event
        updated.isSaved = true

        savedEventIDs.insert(updated.id)
        savedEvents.removeAll { $0.id == updated.id }
        savedEvents.insert(updated, at: 0)
    }
}
