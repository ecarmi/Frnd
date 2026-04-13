import SwiftUI
import Combine
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var selectedEvent: Event?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876), // Hyde Park
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var isLoading = false

    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let span = region.span
            let center = region.center
            events = try await APIService.shared.fetchEventsForMap(
                minLat: center.latitude - span.latitudeDelta / 2,
                maxLat: center.latitude + span.latitudeDelta / 2,
                minLng: center.longitude - span.longitudeDelta / 2,
                maxLng: center.longitude + span.longitudeDelta / 2
            )
        } catch {
            events = Event.mockEvents
        }
    }
}

struct MapTabView: View {
    @StateObject private var viewModel = MapViewModel()
    @State private var showEventPreview = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map
                Map(initialPosition: .region(viewModel.region)) {
                    UserAnnotation()
                    ForEach(viewModel.events) { event in
                        Annotation("", coordinate: event.venue.location) {
                            EventMapPin(event: event, isSelected: viewModel.selectedEvent?.id == event.id) {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.selectedEvent = event
                                    showEventPreview = true
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea()

                // Time filter bar
                VStack(spacing: 0) {
                    // Filter pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(["Now", "Tonight", "This Weekend", "This Week"], id: \.self) { label in
                                PillView(text: label, color: label == "Now" ? .ember : .textSecondary)
                            }
                            Divider()
                                .frame(width: 1, height: 20)
                                .overlay(Color.bgBorder)
                            ForEach(EventCategory.allCases, id: \.self) { cat in
                                HStack(spacing: 4) {
                                    Text(cat.emoji).font(.captionSmall)
                                    Text(cat.displayName).font(.captionMedium)
                                }
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 5)
                                .background(Color.bgRaised.opacity(0.9))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.bgBorder))
                            }
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.sm)
                    }
                    .background(.ultraThinMaterial)

                    Spacer()

                    // Event preview card (when pin tapped)
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
                ToolbarItem(placement: .topBarLeading) {
                    Text("Map")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            viewModel.region = MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876),
                                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                            )
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(.ember)
                    }
                }
            }
        }
        .task { await viewModel.loadEvents() }
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
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.bgBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            HStack(alignment: .top, spacing: Spacing.md) {
                // Category icon
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
                        .frame(width: 36, height: 36)
                        .background(Color.ember.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(Spacing.base)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .fill(Color.bgSurface.opacity(0.85))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.bgBorder)
        )
        .padding(.horizontal, Spacing.base)
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 4)
        .sheet(isPresented: $showDetail) {
            EventDetailView(event: event)
        }
    }
}
