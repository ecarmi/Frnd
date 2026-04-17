import SwiftUI
import Combine
import CoreLocation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var goingEvents: [Event] = []
    @Published var myEvents: [Event] = []
    @Published var isLoading = false
    @Published var isLoadingGoing = false
    @Published var isLoadingMyEvents = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var goingError: String?
    @Published var myEventsError: String?
    @Published var areaLabel = AppConfig.defaultAreaLabel

    private var nextCursor: String?
    private var hasMore = true
    private var locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastResolvedLocation: CLLocation?
    private var storedUserCoordinate: CLLocationCoordinate2D? {
        guard
            let data = UserDefaults.standard.data(forKey: "current_user"),
            let user = try? JSONDecoder().decode(User.self, from: data),
            let latitude = user.latitude,
            let longitude = user.longitude
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var currentLocation: CLLocationCoordinate2D {
        locationManager.location?.coordinate ??
        storedUserCoordinate ??
        AppConfig.defaultCoordinate
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
            let actualCoordinate = locationManager.location?.coordinate ?? storedUserCoordinate
            let response = try await APIService.shared.fetchFeed(
                lat: loc.latitude, lng: loc.longitude,
                cursor: refresh ? nil : nextCursor
            )
            await updateAreaLabel(from: response.events, currentCoordinate: actualCoordinate)
            if refresh {
                events = response.events
            } else {
                events.append(contentsOf: response.events)
            }
            SavedEventsStore.shared.bootstrap(from: response.events)
            nextCursor = response.nextCursor
            hasMore = response.nextCursor != nil
        } catch {
            if isCancellation(error) {
                return
            }
            self.error = error.localizedDescription
        }
    }

    func loadGoingEvents() async {
        guard !isLoadingGoing else { return }
        isLoadingGoing = true
        goingError = nil
        defer { isLoadingGoing = false }

        do {
            goingEvents = try await APIService.shared.fetchGoingEvents()
        } catch {
            if isCancellation(error) {
                return
            }
            goingEvents = []
            goingError = error.localizedDescription
        }
    }

    func loadMyEvents() async {
        guard !isLoadingMyEvents else { return }
        isLoadingMyEvents = true
        myEventsError = nil
        defer { isLoadingMyEvents = false }

        do {
            myEvents = try await APIService.shared.fetchMyCreatedEvents()
        } catch {
            if isCancellation(error) {
                return
            }
            myEvents = []
            myEventsError = error.localizedDescription
        }
    }

    func insertOrUpdateMyEvent(_ event: Event) {
        myEvents.removeAll { $0.id == event.id }
        myEvents.insert(event, at: 0)
    }

    func removeMyEvent(id: String) {
        myEvents.removeAll { $0.id == id }
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

    func rsvp(eventId: String, status: RSVPStatus) async {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return }
        if let activityPostId = events[index].activityPostId {
            let wasJoined = events[index].userRSVPStatus == .going
            events[index].userRSVPStatus = wasJoined ? nil : .going

            do {
                let updatedActivity: ActivityPost
                if wasJoined {
                    try await APIService.shared.leaveActivity(id: activityPostId)
                    updatedActivity = try await APIService.shared.fetchActivity(id: activityPostId)
                } else {
                    updatedActivity = try await APIService.shared.joinActivity(id: activityPostId)
                }

                if let idx = events.firstIndex(where: { $0.id == eventId }) {
                    events[idx].friendsGoing = updatedActivity.participants.compactMap(\.user)
                    events[idx].totalInterested = updatedActivity.participantCount
                    events[idx].userRSVPStatus = updatedActivity.isJoined ? .going : nil
                }
            } catch {
                if let idx = events.firstIndex(where: { $0.id == eventId }) {
                    events[idx].userRSVPStatus = wasJoined ? .going : nil
                }
            }
            return
        }

        let previousStatus = events[index].userRSVPStatus
        events[index].userRSVPStatus = status

        do {
            let rsvp = try await APIService.shared.rsvp(eventId: eventId, status: status)
            if let idx = events.firstIndex(where: { $0.id == eventId }) {
                events[idx].userRSVPStatus = rsvp.status
            }
            if let refreshed = try? await APIService.shared.fetchEvent(id: eventId),
               let idx = events.firstIndex(where: { $0.id == eventId }) {
                events[idx] = refreshed
            }
        } catch {
            if let idx = events.firstIndex(where: { $0.id == eventId }) {
                events[idx].userRSVPStatus = previousStatus
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .networkError(let underlying):
                return isCancellation(underlying)
            default:
                break
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func updateAreaLabel(from events: [Event], currentCoordinate: CLLocationCoordinate2D?) async {
        if let currentCoordinate,
           let resolved = await reverseGeocodeLabel(
                for: CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
           ) {
            areaLabel = resolved
            return
        }

        areaLabel = AppConfig.defaultAreaLabel
    }

    private func reverseGeocodeLabel(for location: CLLocation) async -> String? {
        if let lastResolvedLocation, location.distance(from: lastResolvedLocation) < 250 {
            return areaLabel == AppConfig.defaultAreaLabel ? nil : areaLabel
        }

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return nil
            }

            let parts = [placemark.subLocality, placemark.locality]
                .compactMap { value in
                    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (trimmed?.isEmpty == false) ? trimmed : nil
                }

            guard !parts.isEmpty else {
                return nil
            }

            lastResolvedLocation = location
            return parts.joined(separator: " · ")
        } catch {
            return nil
        }
    }
}
