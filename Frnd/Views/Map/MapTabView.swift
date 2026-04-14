import SwiftUI
import Combine
import MapKit
import CoreLocation

// MARK: - Location Manager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func requestLocation() { manager.requestLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - ViewModel

@MainActor
final class MapViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var selectedEvent: Event?
    @Published var isLoading = false
    @Published var selectedCategory: EventCategory?
    @Published var selectedTimeFilter: String = "All"

    let timeFilters = ["All", "Now", "Tonight", "This Weekend"]

    var filteredEvents: [Event] {
        var result = events
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if selectedTimeFilter != "All" {
            let now = Date()
            let calendar = Calendar.current
            result = result.filter { event in
                switch selectedTimeFilter {
                case "Now":
                    let end = event.endTime ?? event.startTime.addingTimeInterval(3600)
                    return event.startTime <= now && end >= now
                case "Tonight":
                    let startOfTomorrow = calendar.startOfDay(for: now.addingTimeInterval(86400))
                    return event.startTime >= now && event.startTime < startOfTomorrow
                case "This Weekend":
                    let weekday = calendar.component(.weekday, from: now)
                    let daysUntilFri = (6 - weekday + 7) % 7
                    let friday = calendar.startOfDay(for: now.addingTimeInterval(Double(daysUntilFri) * 86400))
                    let monday = friday.addingTimeInterval(3 * 86400)
                    return event.startTime >= friday && event.startTime < monday
                default:
                    return true
                }
            }
        }
        return result
    }

    func loadEvents(region: MKCoordinateRegion) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let span = region.span
        let center = region.center
        do {
            events = try await APIService.shared.fetchEventsForMap(
                minLat: center.latitude  - span.latitudeDelta  / 2,
                maxLat: center.latitude  + span.latitudeDelta  / 2,
                minLng: center.longitude - span.longitudeDelta / 2,
                maxLng: center.longitude + span.longitudeDelta / 2
            )
        } catch {
            if events.isEmpty { events = Event.mockEvents }
        }
    }
}

// MARK: - View

struct MapTabView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    ))
    @State private var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @State private var showEventPreview = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(viewModel.filteredEvents) { event in
                        Annotation("", coordinate: event.venue.location) {
                            EventMapPin(
                                event: event,
                                isSelected: viewModel.selectedEvent?.id == event.id
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.selectedEvent = event
                                    showEventPreview = true
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { context in
                    currentRegion = context.region
                    loadTask?.cancel()
                    loadTask = Task { await viewModel.loadEvents(region: context.region) }
                }

                VStack(spacing: 0) {
                    // Filter bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            // Time filters
                            ForEach(viewModel.timeFilters, id: \.self) { label in
                                let isSelected = viewModel.selectedTimeFilter == label
                                Button {
                                    withAnimation(.spring(response: 0.2)) {
                                        viewModel.selectedTimeFilter = label
                                    }
                                } label: {
                                    Text(label)
                                        .font(.captionMedium)
                                        .foregroundColor(isSelected ? .white : .textSecondary)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.ember : Color.bgRaised.opacity(0.9))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.bgBorder))
                                }
                            }

                            Divider()
                                .frame(width: 1, height: 20)
                                .overlay(Color.bgBorder)

                            // Category filters
                            ForEach(EventCategory.allCases, id: \.self) { cat in
                                let isSelected = viewModel.selectedCategory == cat
                                Button {
                                    withAnimation(.spring(response: 0.2)) {
                                        viewModel.selectedCategory = isSelected ? nil : cat
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(cat.emoji).font(.captionSmall)
                                        Text(cat.displayName).font(.captionMedium)
                                    }
                                    .foregroundColor(isSelected ? Color.categoryColor(for: cat) : .textSecondary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.categoryColor(for: cat).opacity(0.15) : Color.bgRaised.opacity(0.9))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(isSelected ? Color.categoryColor(for: cat) : Color.bgBorder))
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.sm)
                    }
                    .background(.ultraThinMaterial)

                    Spacer()

                    if viewModel.isLoading && viewModel.events.isEmpty {
                        ProgressView()
                            .tint(.ember)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(.bottom, Spacing.xl)
                    }

                    if showEventPreview, let event = viewModel.selectedEvent {
                        MapEventPreview(event: event) {
                            withAnimation { showEventPreview = false }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Color.clear.frame(height: 88)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Map")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let coord = locationManager.userLocation
                            ?? CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876)
                        withAnimation {
                            position = .region(MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                            ))
                        }
                    } label: {
                        Image(systemName: locationManager.userLocation != nil ? "location.fill" : "location")
                            .foregroundColor(.ember)
                    }
                }
            }
            .task {
                // Center on user location if available
                if let loc = locationManager.userLocation {
                    position = .region(MKCoordinateRegion(
                        center: loc,
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                    ))
                }
                await viewModel.loadEvents(region: currentRegion)
            }
            .onChange(of: locationManager.userLocation?.latitude) {
                guard let loc = locationManager.userLocation else { return }
                position = .region(MKCoordinateRegion(
                    center: loc,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                ))
            }
        }
    }
}

// MARK: - Event Map Pin

struct EventMapPin: View {
    let event: Event
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPulsing = false

    private var isLiveNow: Bool {
        let now = Date()
        return event.startTime <= now && (event.endTime ?? event.startTime.addingTimeInterval(3600)) >= now
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isLiveNow {
                    Circle()
                        .fill(Color.ember.opacity(0.3))
                        .frame(width: isSelected ? 52 : 44, height: isSelected ? 52 : 44)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
                }
                Circle()
                    .fill(isSelected ? Color.ember : Color.bgSurface)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .overlay(Circle().strokeBorder(isSelected ? Color.white : Color.ember, lineWidth: isSelected ? 2 : 1.5))
                Text(event.category.emoji)
                    .font(.system(size: isSelected ? 20 : 16))
            }
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .onAppear { isPulsing = isLiveNow }
    }
}

// MARK: - Map Event Preview

struct MapEventPreview: View {
    let event: Event
    let onDismiss: () -> Void
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.bgBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.categoryColor(for: event.category).opacity(0.2))
                        .frame(width: 56, height: 56)
                    Text(event.category.emoji)
                        .font(.system(size: 28))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.headingSmall)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        PillView(text: event.startTime.relativeEventTime, color: .ember)
                        PillView(text: event.priceDisplay, color: event.isFree ? .teal : .textSecondary)
                    }
                    Text(event.venue.name)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Button { showDetail = true } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ember)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.ember.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(Spacing.base)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).fill(Color.bgSurface.opacity(0.85)))
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Color.bgBorder))
        .padding(.horizontal, Spacing.base)
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 4)
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height > 40 { onDismiss() }
        })
        .sheet(isPresented: $showDetail) {
            EventDetailView(event: event)
        }
    }
}
