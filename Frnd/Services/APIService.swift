import Foundation
import Combine

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .unauthorized:        return "Session expired. Please sign in again."
        case .serverError(let c, let m): return "Server error \(c): \(m)"
        case .decodingError(let e): return "Decoding error: \(e)"
        case .networkError(let e): return e.localizedDescription
        case .unknown:             return "An unknown error occurred"
        }
    }
}

// MARK: - API Service

@MainActor
final class APIService: ObservableObject {
    static let shared = APIService()

    // Change to your machine's IP when testing on device, or localhost for simulator
    private let baseURL = "https://frnd-production.up.railway.app"
    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Core Request

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.unknown }

            switch http.statusCode {
            case 200...299:
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw APIError.decodingError(error)
                }
            case 401:
                authToken = nil
                throw APIError.unauthorized
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(http.statusCode, msg)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Auth

    func requestEmailOTP(email: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(
            path: "/auth/email/request",
            method: "POST",
            body: EmailOTPRequest(email: email),
            authenticated: false
        )
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthResponse {
        let resp: AuthResponse = try await request(
            path: "/auth/email/verify",
            method: "POST",
            body: EmailOTPVerify(email: email, code: code),
            authenticated: false
        )
        authToken = resp.accessToken
        return resp
    }

    func logout() {
        authToken = nil
    }

    var isAuthenticated: Bool { authToken != nil }

    // MARK: - Feed

    func fetchFeed(lat: Double, lng: Double, radius: Double = 8, cursor: String? = nil) async throws -> FeedResponse {
        var path = "/feed?lat=\(lat)&lng=\(lng)&radius=\(radius)"
        if let cursor = cursor { path += "&cursor=\(cursor)" }
        return try await request(path: path)
    }

    // MARK: - Events

    func fetchEvent(id: String) async throws -> Event {
        try await request(path: "/events/\(id)")
    }

    func searchEvents(query: String, lat: Double? = nil, lng: Double? = nil) async throws -> [Event] {
        var path = "/events/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        if let lat = lat, let lng = lng { path += "&lat=\(lat)&lng=\(lng)" }
        return try await request(path: path)
    }

    func fetchEventsForMap(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) async throws -> [Event] {
        try await request(path: "/events/map?min_lat=\(minLat)&max_lat=\(maxLat)&min_lng=\(minLng)&max_lng=\(maxLng)")
    }

    // MARK: - RSVPs

    func rsvp(eventId: String, status: RSVPStatus) async throws -> RSVP {
        struct RSVPBody: Encodable { let status: RSVPStatus }
        return try await request(
            path: "/events/\(eventId)/rsvp",
            method: "POST",
            body: RSVPBody(status: status)
        )
    }

    func saveEvent(eventId: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/events/\(eventId)/save", method: "POST")
    }

    func unsaveEvent(eventId: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/events/\(eventId)/save", method: "DELETE")
    }

    func recordSwipe(eventId: String, direction: SwipeDirection) async throws {
        struct SwipeBody: Encodable { let event_id: String; let direction: String }
        struct Empty: Codable {}
        let _: Empty = try await request(
            path: "/feedback/swipe",
            method: "POST",
            body: SwipeBody(event_id: eventId, direction: direction.rawValue)
        )
    }

    // MARK: - Plans

    func fetchMyPlans() async throws -> [Plan] {
        try await request(path: "/plans")
    }

    func fetchPlan(id: String) async throws -> Plan {
        try await request(path: "/plans/\(id)")
    }

    func createPlan(title: String, eventIds: [String], inviteeIds: [String]) async throws -> Plan {
        struct CreatePlanBody: Encodable {
            let title: String
            let event_ids: [String]
            let invitee_ids: [String]
        }
        return try await request(
            path: "/plans",
            method: "POST",
            body: CreatePlanBody(title: title, event_ids: eventIds, invitee_ids: inviteeIds)
        )
    }

    func sendMessage(planId: String, body: String) async throws -> Message {
        struct MsgBody: Encodable { let body: String }
        return try await request(
            path: "/plans/\(planId)/messages",
            method: "POST",
            body: MsgBody(body: body)
        )
    }

    func voteForEvent(planId: String, eventId: String) async throws -> Plan {
        struct VoteBody: Encodable { let event_id: String }
        return try await request(
            path: "/plans/\(planId)/vote",
            method: "POST",
            body: VoteBody(event_id: eventId)
        )
    }

    func inviteToPlan(planId: String, userIds: [String]) async throws -> Plan {
        struct InviteBody: Encodable { let user_ids: [String] }
        return try await request(
            path: "/plans/\(planId)/invite",
            method: "POST",
            body: InviteBody(user_ids: userIds)
        )
    }

    func updatePlanStatus(planId: String, status: PlanStatus) async throws -> Plan {
        struct StatusBody: Encodable { let status: PlanStatus }
        return try await request(
            path: "/plans/\(planId)/status",
            method: "PATCH",
            body: StatusBody(status: status)
        )
    }

    // MARK: - Users / Profile

    func fetchMe() async throws -> User {
        try await request(path: "/users/me")
    }

    func updateProfile(name: String?, vibeTagIds: [String]?) async throws -> User {
        struct UpdateBody: Encodable {
            let name: String?
            let vibe_tag_ids: [String]?
        }
        return try await request(
            path: "/users/me",
            method: "PATCH",
            body: UpdateBody(name: name, vibe_tag_ids: vibeTagIds)
        )
    }

    func fetchFriends() async throws -> [Friendship] {
        try await request(path: "/users/me/friends")
    }

    func fetchSavedEvents() async throws -> [Event] {
        try await request(path: "/users/me/saved")
    }

    func fetchAttendedEvents() async throws -> [Event] {
        try await request(path: "/users/me/attended")
    }

    func completeOnboarding(vibeTagNames: [String]) async throws -> User {
        struct OnboardingBody: Encodable { let vibe_tag_names: [String] }
        return try await request(
            path: "/users/me/onboarding",
            method: "POST",
            body: OnboardingBody(vibe_tag_names: vibeTagNames)
        )
    }

    // MARK: - Groups

    func fetchMyGroups() async throws -> [Group] {
        try await request(path: "/groups")
    }

    func fetchGroup(id: String) async throws -> Group {
        try await request(path: "/groups/\(id)")
    }

    func createGroup(name: String, description: String, isPrivate: Bool) async throws -> Group {
        struct Body: Encodable { let name: String; let description: String; let is_private: Bool }
        return try await request(
            path: "/groups",
            method: "POST",
            body: Body(name: name, description: description, is_private: isPrivate)
        )
    }

    func joinGroup(inviteCode: String) async throws -> Group {
        struct Body: Encodable { let invite_code: String }
        return try await request(
            path: "/groups/join",
            method: "POST",
            body: Body(invite_code: inviteCode)
        )
    }

    func leaveGroup(id: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/groups/\(id)/leave", method: "DELETE")
    }

    // MARK: - Activities (LFG)

    func fetchActivities(groupId: String? = nil) async throws -> [ActivityPost] {
        var path = "/activities"
        if let gid = groupId { path += "?group_id=\(gid)" }
        return try await request(path: path)
    }

    func fetchActivity(id: String) async throws -> ActivityPost {
        try await request(path: "/activities/\(id)")
    }

    func createActivity(
        title: String,
        description: String,
        activityType: ActivityType,
        location: String?,
        latitude: Double?,
        longitude: Double?,
        scheduledTime: Date?,
        maxParticipants: Int?,
        groupId: String?
    ) async throws -> ActivityPost {
        struct Body: Encodable {
            let title: String
            let description: String
            let activity_type: ActivityType
            let location: String?
            let latitude: Double?
            let longitude: Double?
            let scheduled_time: Date?
            let max_participants: Int?
            let group_id: String?
        }
        return try await request(
            path: "/activities",
            method: "POST",
            body: Body(
                title: title, description: description, activity_type: activityType,
                location: location, latitude: latitude, longitude: longitude,
                scheduled_time: scheduledTime, max_participants: maxParticipants, group_id: groupId
            )
        )
    }

    func joinActivity(id: String) async throws -> ActivityPost {
        try await request(path: "/activities/\(id)/join", method: "POST")
    }

    func leaveActivity(id: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/activities/\(id)/leave", method: "DELETE")
    }

    func deleteActivity(id: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/activities/\(id)", method: "DELETE")
    }

    // MARK: - Carpools

    func fetchCarpools(planId: String) async throws -> [Carpool] {
        try await request(path: "/carpools/plan/\(planId)")
    }

    func offerCarpool(
        planId: String,
        departureLocation: String,
        departureLatitude: Double?,
        departureLongitude: Double?,
        departureTime: Date?,
        totalSeats: Int,
        notes: String?
    ) async throws -> Carpool {
        struct Body: Encodable {
            let plan_id: String
            let departure_location: String
            let departure_latitude: Double?
            let departure_longitude: Double?
            let departure_time: Date?
            let total_seats: Int
            let notes: String?
        }
        return try await request(
            path: "/carpools",
            method: "POST",
            body: Body(
                plan_id: planId, departure_location: departureLocation,
                departure_latitude: departureLatitude, departure_longitude: departureLongitude,
                departure_time: departureTime, total_seats: totalSeats, notes: notes
            )
        )
    }

    func requestCarpoolSeat(carpoolId: String) async throws -> Carpool {
        try await request(path: "/carpools/\(carpoolId)/request", method: "POST")
    }

    func updatePassengerStatus(carpoolId: String, passengerUserId: String, status: String) async throws -> Carpool {
        try await request(path: "/carpools/\(carpoolId)/passengers/\(passengerUserId)?status=\(status)", method: "PATCH")
    }

    func leaveCarpool(carpoolId: String) async throws {
        struct Empty: Codable {}
        let _: Empty = try await request(path: "/carpools/\(carpoolId)/leave", method: "DELETE")
    }
}

// MARK: - Swipe Direction

enum SwipeDirection: String {
    case right = "right"   // save
    case left  = "left"    // dismiss
}
