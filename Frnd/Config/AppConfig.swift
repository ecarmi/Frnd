import CoreLocation
import MapKit

enum AppConfig {
    static let apiBaseURL = "https://frnd-production.up.railway.app"

    static let defaultCoordinate = CLLocationCoordinate2D(
        latitude: 41.7991,
        longitude: -87.5876
    )

    static let defaultMapSpan = MKCoordinateSpan(
        latitudeDelta: 0.08,
        longitudeDelta: 0.08
    )

    static let defaultAreaLabel = "Near You"
    static let launchCampusLabel = "Campus Email Required"
    static let launchCampusDescription = "Sign in with an approved school email to join your campus community."
    static let allowedEmailDomains = ["uchicago.edu"]

    static let curatedCollections: [CuratedCollection] = [
        CuratedCollection(title: "Date Night Nearby", subtitle: "Intimate venues, great vibes", emoji: "🥂", color: .rose),
        CuratedCollection(title: "Friday Under $20", subtitle: "Great nights, budget friendly", emoji: "💸", color: .teal),
        CuratedCollection(title: "Live Music This Week", subtitle: "Concerts and local shows", emoji: "🎸", color: .ember),
        CuratedCollection(title: "Weekend Brunch Spots", subtitle: "Easy plans with friends", emoji: "☀️", color: .gold),
    ]
}
