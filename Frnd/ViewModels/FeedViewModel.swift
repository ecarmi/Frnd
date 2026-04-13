import SwiftUI
import Combine
import CoreLocation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    private var nextCursor: String?
    private var hasMore = true
    private var locationManager = CLLocationManager()

    var currentLocation: CLLocationCoordinate2D {
        locationManager.location?.coordinate ??
        CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876) // Hyde Park default
    }

    func loadFeed(refresh: Bool = false) async {
        guard !isLoading else { return }
        if refresh {
            nextCursor = nil
            hasMore = true
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let loc = currentLocation
            let response = try await APIService.shared.fetchFeed(
                lat: loc.latitude, lng: loc.longitude,
                cursor: refresh ? nil : nextCursor
            )
            if refresh {
                events = response.events
            } else {
                events.append(contentsOf: response.events)
            }
            nextCursor = response.nextCursor
            hasMore = response.nextCursor != nil
        } catch {
            // Use mock data when backend is unavailable
            if events.isEmpty {
                events = Event.mockEvents
            }
            self.error = nil // Silently fall back to mock data
        }
    }

    func loadMoreIfNeeded(currentEvent: Event) async {
        guard let lastId = events.last?.id, currentEvent.id == lastId,
              hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadFeed()
    }

    func swipe(event: Event, direction: SwipeDirection) async {
        // Remove from feed
        events.removeAll { $0.id == event.id }
        // Record feedback
        try? await APIService.shared.recordSwipe(eventId: event.id, direction: direction)
    }

    func toggleSave(eventId: String) {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return }
        events[index].isSaved.toggle()
        let isSaved = events[index].isSaved
        Task {
            try? await isSaved
                ? APIService.shared.saveEvent(eventId: eventId)
                : APIService.shared.unsaveEvent(eventId: eventId)
        }
    }

    func rsvp(eventId: String, status: RSVPStatus) async {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return }
        events[index].userRSVPStatus = status
        do {
            let rsvp = try await APIService.shared.rsvp(eventId: eventId, status: status)
            if let idx = events.firstIndex(where: { $0.id == eventId }) {
                events[idx].userRSVPStatus = rsvp.status
            }
        } catch {}
    }
}
