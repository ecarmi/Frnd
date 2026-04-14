import Foundation
import CoreLocation

// MARK: - Enums

enum EventCategory: String, Codable, CaseIterable {
    case music     = "music"
    case nightlife = "nightlife"
    case foodDrink = "food_drink"
    case arts      = "arts"
    case sports    = "sports"
    case other     = "other"

    var displayName: String {
        switch self {
        case .music:     return "Music"
        case .nightlife: return "Nightlife"
        case .foodDrink: return "Food & Drink"
        case .arts:      return "Arts & Culture"
        case .sports:    return "Sports & Outdoors"
        case .other:     return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .music:     return "🎵"
        case .nightlife: return "🌙"
        case .foodDrink: return "🍻"
        case .arts:      return "🎨"
        case .sports:    return "🏃"
        case .other:     return "✨"
        }
    }
}

enum RSVPStatus: String, Codable {
    case going      = "going"
    case interested = "interested"
    case notGoing   = "not_going"
}

enum FriendshipTier: String, Codable {
    case innerCircle  = "inner_circle"
    case friend       = "friend"
    case connection   = "connection"
}

enum PlanStatus: String, Codable {
    case proposal = "proposal"
    case voting   = "voting"
    case locked   = "locked"
    case live     = "live"
    case archived = "archived"
}

enum PlanMemberStatus: String, Codable {
    case invited  = "invited"
    case going    = "going"
    case maybe    = "maybe"
    case declined = "declined"
}

enum MessageType: String, Codable {
    case text   = "text"
    case image  = "image"
    case system = "system"
}

enum EventType: String, Codable, CaseIterable {
    case study         = "study"
    case social        = "social"
    case sports        = "sports"
    case food          = "food"
    case career        = "career"
    case entertainment = "entertainment"
    case creative      = "creative"
    case wellness      = "wellness"
    case other         = "other"

    var displayName: String {
        switch self {
        case .study:         return "Study"
        case .social:        return "Social"
        case .sports:        return "Sports"
        case .food:          return "Food"
        case .career:        return "Career"
        case .entertainment: return "Entertainment"
        case .creative:      return "Creative"
        case .wellness:      return "Wellness"
        case .other:         return "Other"
        }
    }
}

enum GroupRole: String, Codable {
    case owner  = "owner"
    case admin  = "admin"
    case member = "member"
}

enum ActivityType: String, Codable, CaseIterable {
    case study      = "study"
    case sports     = "sports"
    case social     = "social"
    case food       = "food"
    case creative   = "creative"
    case wellness   = "wellness"
    case other      = "other"

    var displayName: String {
        switch self {
        case .study:    return "Study"
        case .sports:   return "Sports"
        case .social:   return "Social"
        case .food:     return "Food"
        case .creative: return "Creative"
        case .wellness: return "Wellness"
        case .other:    return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .study:    return "📚"
        case .sports:   return "🏃"
        case .social:   return "👋"
        case .food:     return "🍜"
        case .creative: return "🎨"
        case .wellness: return "🧘"
        case .other:    return "✨"
        }
    }
}

enum ActivityStatus: String, Codable {
    case open      = "open"
    case full      = "full"
    case cancelled = "cancelled"
    case completed = "completed"
}

enum CarpoolStatus: String, Codable {
    case open      = "open"
    case full      = "full"
    case cancelled = "cancelled"
    case completed = "completed"
}

// MARK: - User

struct User: Codable, Identifiable {
    let id: String
    let email: String?
    let phone: String?
    let university: String?
    let name: String
    let avatarURL: String?
    let latitude: Double?
    let longitude: Double?
    let onboardingComplete: Bool
    let createdAt: Date

    var tasteProfile: TasteProfile?

    var location: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    enum CodingKeys: String, CodingKey {
        case id, email, phone, university, name
        case avatarURL        = "avatar_url"
        case latitude, longitude
        case onboardingComplete = "onboarding_complete"
        case createdAt        = "created_at"
        case tasteProfile     = "taste_profile"
    }
}

// MARK: - Taste Profile

struct TasteProfile: Codable {
    let id: String
    let userId: String
    let genreWeights: [String: Double]
    let categoryAffinities: [String: Double]
    let priceSensitivity: Double     // 0–1, 0 = price insensitive, 1 = very sensitive
    let timePreferences: TimePreferences
    let updatedAt: Date
    let humanReadableSummary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId             = "user_id"
        case genreWeights       = "genre_weights"
        case categoryAffinities = "category_affinities"
        case priceSensitivity   = "price_sensitivity"
        case timePreferences    = "time_preferences"
        case updatedAt          = "updated_at"
        case humanReadableSummary = "human_readable_summary"
    }
}

struct TimePreferences: Codable {
    let weekdayEvening: Double?
    let fridayNight: Double?
    let saturdayNight: Double?
    let sundayAfternoon: Double?

    enum CodingKeys: String, CodingKey {
        case weekdayEvening   = "weekday_evening"
        case fridayNight      = "friday_night"
        case saturdayNight    = "saturday_night"
        case sundayAfternoon  = "sunday_afternoon"
    }
}

// MARK: - Venue

struct Venue: Codable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let googlePlaceId: String?
    let vibeTags: [String]
    let images: [String]
    let claimedByOrganizerId: String?
    let createdAt: Date

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, address
        case googlePlaceId         = "google_place_id"
        case vibeTags              = "vibe_tags"
        case images
        case claimedByOrganizerId  = "claimed_by"
        case createdAt             = "created_at"
    }
}

// MARK: - Event

struct Event: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let venue: Venue
    let startTime: Date
    let endTime: Date?
    let priceMin: Double?
    let priceMax: Double?
    let capacity: Int?
    let category: EventCategory
    let tags: [String]
    let imageURL: String?
    let source: String       // "aggregated" | "organic" | "user_created"
    let creatorId: String?  = nil
    let trendingScore: Double

    // Feed-specific extras (injected by the feed endpoint)
    var friendsGoing: [User]
    var friendsInterested: [User]
    var totalInterested: Int
    var userRSVPStatus: RSVPStatus?
    var aiReasonChip: String?
    var isSaved: Bool

    var priceDisplay: String {
        if let min = priceMin {
            if min == 0 { return "Free" }
            if let max = priceMax, max > min { return "From $\(Int(min))" }
            return "$\(Int(min))"
        }
        return "Free"
    }

    var isFree: Bool { priceMin == nil || priceMin == 0 }

    var distanceText: String? { nil } // populated by client from location

    enum CodingKeys: String, CodingKey {
        case id, title, description, venue
        case startTime    = "start_time"
        case endTime      = "end_time"
        case priceMin     = "price_min"
        case priceMax     = "price_max"
        case capacity, category, tags
        case imageURL     = "image_url"
        case source
        case creatorId     = "creator_id"
        case trendingScore = "trending_score"
        case friendsGoing     = "friends_going"
        case friendsInterested = "friends_interested"
        case totalInterested  = "total_interested"
        case userRSVPStatus   = "user_rsvp_status"
        case aiReasonChip     = "ai_reason_chip"
        case isSaved          = "is_saved"
    }
}

// MARK: - RSVP

struct RSVP: Codable, Identifiable {
    let id: String
    let userId: String
    let eventId: String
    let status: RSVPStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId   = "user_id"
        case eventId  = "event_id"
        case status
        case createdAt = "created_at"
    }
}

// MARK: - Friendship

struct Friendship: Codable, Identifiable {
    let id: String
    let userAId: String
    let userBId: String
    let tier: FriendshipTier
    let createdAt: Date
    var otherUser: User?

    enum CodingKeys: String, CodingKey {
        case id
        case userAId  = "user_a_id"
        case userBId  = "user_b_id"
        case tier
        case createdAt = "created_at"
        case otherUser = "other_user"
    }
}

// MARK: - Plan

struct Plan: Codable, Identifiable {
    let id: String
    let creatorId: String
    var title: String
    var eventOptions: [Event]
    var status: PlanStatus
    var meetingTime: Date?
    var meetingLocation: String?
    var members: [PlanMember]
    var messages: [Message]
    let createdAt: Date
    var selectedEventId: String?

    var pendingInvites: Int {
        members.filter { $0.status == .invited }.count
    }

    var confirmedCount: Int {
        members.filter { $0.status == .going }.count
    }

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId    = "creator_id"
        case title
        case eventOptions = "event_options"
        case status
        case meetingTime  = "meeting_time"
        case meetingLocation = "meeting_location"
        case members, messages
        case createdAt    = "created_at"
        case selectedEventId = "selected_event_id"
    }
}

// MARK: - PlanMember

struct PlanMember: Codable, Identifiable {
    let id: String
    let planId: String
    let userId: String
    var status: PlanMemberStatus
    var user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case planId  = "plan_id"
        case userId  = "user_id"
        case status, user
    }
}

// MARK: - Message

struct Message: Codable, Identifiable {
    let id: String
    let planId: String
    let userId: String
    let body: String
    let type: MessageType
    let createdAt: Date
    var sender: User?

    enum CodingKeys: String, CodingKey {
        case id
        case planId   = "plan_id"
        case userId   = "user_id"
        case body, type
        case createdAt = "created_at"
        case sender
    }
}

// MARK: - Group

struct GroupMember: Codable, Identifiable {
    let id: String
    let groupId: String
    let userId: String
    let role: GroupRole
    let createdAt: Date
    var user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId  = "group_id"
        case userId   = "user_id"
        case role
        case createdAt = "created_at"
        case user
    }
}

struct Group: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let creatorId: String
    let isPrivate: Bool
    let imageURL: String?
    let inviteCode: String?
    let createdAt: Date
    var members: [GroupMember]
    var memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case creatorId  = "creator_id"
        case isPrivate  = "is_private"
        case imageURL   = "image_url"
        case inviteCode = "invite_code"
        case createdAt  = "created_at"
        case members
        case memberCount = "member_count"
    }
}

// MARK: - Activity Post (LFG)

struct ActivityParticipant: Codable, Identifiable {
    let id: String
    let activityId: String
    let userId: String
    let createdAt: Date
    var user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case userId     = "user_id"
        case createdAt  = "created_at"
        case user
    }
}

struct ActivityPost: Codable, Identifiable {
    let id: String
    let creatorId: String
    let title: String
    let description: String
    let activityType: ActivityType
    let location: String?
    let latitude: Double?
    let longitude: Double?
    let scheduledTime: Date?
    let maxParticipants: Int?
    let groupId: String?
    let status: ActivityStatus
    let createdAt: Date
    var creator: User?
    var participants: [ActivityParticipant]
    var participantCount: Int
    var isJoined: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId      = "creator_id"
        case title, description
        case activityType   = "activity_type"
        case location, latitude, longitude
        case scheduledTime  = "scheduled_time"
        case maxParticipants = "max_participants"
        case groupId        = "group_id"
        case status
        case createdAt      = "created_at"
        case creator, participants
        case participantCount = "participant_count"
        case isJoined       = "is_joined"
    }
}

// MARK: - Carpool

struct CarpoolPassenger: Codable, Identifiable {
    let id: String
    let carpoolId: String
    let userId: String
    let status: String   // "pending" | "confirmed" | "rejected"
    let createdAt: Date
    var user: User?

    enum CodingKeys: String, CodingKey {
        case id
        case carpoolId = "carpool_id"
        case userId    = "user_id"
        case status
        case createdAt = "created_at"
        case user
    }
}

struct Carpool: Codable, Identifiable {
    let id: String
    let planId: String
    let driverId: String
    let departureLocation: String
    let departureLatitude: Double?
    let departureLongitude: Double?
    let departureTime: Date?
    let totalSeats: Int
    let notes: String?
    let status: CarpoolStatus
    let createdAt: Date
    var driver: User?
    var passengers: [CarpoolPassenger]
    var seatsAvailable: Int

    enum CodingKeys: String, CodingKey {
        case id
        case planId             = "plan_id"
        case driverId           = "driver_id"
        case departureLocation  = "departure_location"
        case departureLatitude  = "departure_latitude"
        case departureLongitude = "departure_longitude"
        case departureTime      = "departure_time"
        case totalSeats         = "total_seats"
        case notes, status
        case createdAt          = "created_at"
        case driver, passengers
        case seatsAvailable     = "seats_available"
    }
}

// MARK: - Feed Response

struct FeedResponse: Codable {
    let events: [Event]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

// MARK: - Auth

struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
        case user
    }
}

struct EmailOTPRequest: Codable {
    let email: String
}

struct EmailOTPVerify: Codable {
    let email: String
    let code: String
}

// MARK: - Vibe Tag (Onboarding)

struct VibeTag: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let category: EventCategory
}

extension VibeTag {
    static let all: [VibeTag] = [
        // Music
        VibeTag(name: "Live Music",  emoji: "🎸", category: .music),
        VibeTag(name: "DJ / Dance",  emoji: "🎧", category: .music),
        VibeTag(name: "Jazz & Soul", emoji: "🎷", category: .music),
        // Going out
        VibeTag(name: "Party",       emoji: "🌙", category: .nightlife),
        VibeTag(name: "Bar Hopping", emoji: "🍻", category: .nightlife),
        VibeTag(name: "Rooftops",    emoji: "🏙️", category: .nightlife),
        // Arts & culture
        VibeTag(name: "Comedy",      emoji: "😂", category: .arts),
        VibeTag(name: "Art & Design",emoji: "🎨", category: .arts),
        VibeTag(name: "Film & Theater", emoji: "🎬", category: .arts),
        // Food & drink
        VibeTag(name: "Brunch",      emoji: "🥂", category: .foodDrink),
        VibeTag(name: "Food Pop-ups",emoji: "🍜", category: .foodDrink),
        // Active
        VibeTag(name: "Sports",      emoji: "🏀", category: .sports),
        VibeTag(name: "Fitness",     emoji: "🏃", category: .sports),
        // Campus
        VibeTag(name: "Study",       emoji: "📚", category: .other),
        VibeTag(name: "Networking",  emoji: "🤝", category: .other),
    ]
}

// Extra init for VibeTag to allow any param order
extension VibeTag {
    init(name: String, category: EventCategory, emoji: String) {
        self.init(name: name, emoji: emoji, category: category)
    }
}

// MARK: - Mock Data

extension Event {
    static let mockEvents: [Event] = [
        Event(
            id: "1",
            title: "Jazz at the Promontory",
            description: "An intimate evening of live jazz featuring the Marcus Miller Quartet. Known for their electric blend of soul and bebop, this is a night you won't forget.",
            venue: Venue(
                id: "v1", name: "The Promontory", latitude: 41.7999, longitude: -87.5882,
                address: "5311 S Lake Park Ave, Chicago, IL", googlePlaceId: nil,
                vibeTags: ["Intimate", "Live Music", "Craft Cocktails"],
                images: [], claimedByOrganizerId: nil, createdAt: Date()
            ),
            startTime: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!,
            endTime: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()),
            priceMin: 15, priceMax: 25,
            capacity: 200, category: .music,
            tags: ["Jazz", "Live Music", "Hyde Park"],
            imageURL: nil, source: "organic", trendingScore: 0.87,
            friendsGoing: [
                User(id: "u2", email: nil, phone: nil, university: nil, name: "Alex Chen", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
                User(id: "u3", email: nil, phone: nil, university: nil, name: "Jordan Kim", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
            ],
            friendsInterested: [],
            totalInterested: 47,
            userRSVPStatus: nil,
            aiReasonChip: "Because you liked Jazz events",
            isSaved: false
        ),
        Event(
            id: "2",
            title: "Neon Dreams: Electronic Night",
            description: "Three floors, six DJs, one unforgettable Saturday. Featuring local residents alongside international acts across techno, house, and bass music.",
            venue: Venue(
                id: "v2", name: "Smartbar", latitude: 41.9478, longitude: -87.6538,
                address: "3730 N Clark St, Chicago, IL", googlePlaceId: nil,
                vibeTags: ["Late Night", "Dance", "Electronic"],
                images: [], claimedByOrganizerId: nil, createdAt: Date()
            ),
            startTime: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!,
            endTime: Calendar.current.date(byAdding: .hour, value: 8, to: Date()),
            priceMin: 20, priceMax: 30,
            capacity: 500, category: .nightlife,
            tags: ["Electronic", "Techno", "Late Night"],
            imageURL: nil, source: "organic", trendingScore: 0.92,
            friendsGoing: [
                User(id: "u4", email: nil, phone: nil, university: nil, name: "Sam Rivera", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
            ],
            friendsInterested: [],
            totalInterested: 112,
            userRSVPStatus: nil,
            aiReasonChip: "Trending in Wrigleyville",
            isSaved: true
        ),
        Event(
            id: "3",
            title: "Hyde Park Art Walk",
            description: "A self-guided walking tour through 20+ local galleries and studios in Hyde Park. Free wine, live demos, and artist talks throughout the evening.",
            venue: Venue(
                id: "v3", name: "Hyde Park Art Center", latitude: 41.8014, longitude: -87.5979,
                address: "5020 S Cornell Ave, Chicago, IL", googlePlaceId: nil,
                vibeTags: ["Artsy", "Social", "Free"],
                images: [], claimedByOrganizerId: nil, createdAt: Date()
            ),
            startTime: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!,
            endTime: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()),
            priceMin: 0, priceMax: nil,
            capacity: nil, category: .arts,
            tags: ["Art", "Free", "Hyde Park", "Social"],
            imageURL: nil, source: "aggregated", trendingScore: 0.75,
            friendsGoing: [],
            friendsInterested: [],
            totalInterested: 89,
            userRSVPStatus: nil,
            aiReasonChip: "Something different — you haven't tried art walks",
            isSaved: false
        ),
        Event(
            id: "4",
            title: "Sunday Bottomless Brunch",
            description: "2-hour bottomless mimosas and bloody marys with a full brunch menu. Live DJ from noon. Reservations strongly recommended.",
            venue: Venue(
                id: "v4", name: "Avec", latitude: 41.8848, longitude: -87.6500,
                address: "615 W Randolph St, Chicago, IL", googlePlaceId: nil,
                vibeTags: ["Brunch", "Lively", "West Loop"],
                images: [], claimedByOrganizerId: nil, createdAt: Date()
            ),
            startTime: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)!,
            endTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 2, to: Date())!),
            priceMin: 35, priceMax: nil,
            capacity: 80, category: .foodDrink,
            tags: ["Brunch", "Bottomless", "West Loop"],
            imageURL: nil, source: "organic", trendingScore: 0.68,
            friendsGoing: [
                User(id: "u5", email: nil, phone: nil, university: nil, name: "Maya Johnson", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
                User(id: "u6", email: nil, phone: nil, university: nil, name: "Tyler Brooks", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
                User(id: "u7", email: nil, phone: nil, university: nil, name: "Priya Nair", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date()),
            ],
            friendsInterested: [],
            totalInterested: 34,
            userRSVPStatus: .interested,
            aiReasonChip: "Alex, Maya + 3 friends going",
            isSaved: false
        ),
    ]
}

extension Plan {
    static let mockPlans: [Plan] = [
        Plan(
            id: "p1",
            creatorId: "me",
            title: "Saturday Night",
            eventOptions: [Event.mockEvents[0], Event.mockEvents[1]],
            status: .voting,
            meetingTime: nil,
            meetingLocation: nil,
            members: [
                PlanMember(id: "pm1", planId: "p1", userId: "me", status: .going),
                PlanMember(id: "pm2", planId: "p1", userId: "u2", status: .going,
                           user: User(id: "u2", email: nil, phone: nil, university: nil, name: "Alex Chen", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date())),
                PlanMember(id: "pm3", planId: "p1", userId: "u3", status: .invited,
                           user: User(id: "u3", email: nil, phone: nil, university: nil, name: "Jordan Kim", avatarURL: nil, latitude: nil, longitude: nil, onboardingComplete: true, createdAt: Date())),
            ],
            messages: [],
            createdAt: Date()
        ),
    ]
}
