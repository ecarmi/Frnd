import SwiftUI
import Combine
import CoreLocation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [Event] = []
    @Published var isSearching = false
    @Published var selectedCategory: EventCategory?

    private var searchTask: Task<Void, Never>?

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = []
            return
        }
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            do {
                results = try await APIService.shared.searchEvents(query: query)
            } catch {
                results = Event.mockEvents.filter {
                    $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                }
            }
            isSearching = false
        }
    }

    func filterByCategory(_ category: EventCategory?) {
        selectedCategory = category
    }

    @Published var trending: [Event] = []

    func loadTrending() async {
        do {
            let loc = CLLocationCoordinate2D(latitude: 41.7991, longitude: -87.5876)
            let response = try await APIService.shared.fetchFeed(lat: loc.latitude, lng: loc.longitude)
            trending = response.events
        } catch {
            trending = Event.mockEvents
        }
    }

    var filteredTrending: [Event] {
        if let cat = selectedCategory {
            return trending.filter { $0.category == cat }
        }
        return trending
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showEventDetail: Event?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.textTertiary)
                            TextField(
                                "",
                                text: $viewModel.searchText,
                                prompt: Text("Search events, venues, vibes...").foregroundColor(.textTertiary)
                            )
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)
                            .submitLabel(.search)
                            .onSubmit { viewModel.search() }
                            .onChange(of: viewModel.searchText) { viewModel.search() }

                            if !viewModel.searchText.isEmpty {
                                Button {
                                    viewModel.searchText = ""
                                    viewModel.results = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.textTertiary)
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .background(Color.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.bgBorder))
                        .padding(.horizontal, Spacing.base)

                        if viewModel.searchText.isEmpty {
                            browseContent
                        } else {
                            searchResults
                        }

                        Color.clear.frame(height: 88)
                    }
                    .padding(.top, Spacing.base)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Explore")
                        .font(.headingMedium)
                        .foregroundColor(.textPrimary)
                }
            }
            .task { await viewModel.loadTrending() }
        }
    }

    // MARK: - Browse Content

    private var browseContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Category pills
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionLabel("Browse by Vibe")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        categoryChip(nil, label: "All")
                        ForEach(EventCategory.allCases, id: \.self) { cat in
                            categoryChip(cat, label: "\(cat.emoji) \(cat.displayName)")
                        }
                    }
                    .padding(.horizontal, Spacing.base)
                }
            }

            // Curated collections
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionLabel("Curated for Chicago")
                    .padding(.horizontal, Spacing.base)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(curatedCollections, id: \.title) { col in
                            CuratedCard(collection: col)
                        }
                    }
                    .padding(.horizontal, Spacing.base)
                }
            }

            // Trending events
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionLabel("Trending Now")
                    .padding(.horizontal, Spacing.base)

                ForEach(viewModel.filteredTrending.prefix(4)) { event in
                    Button {
                        showEventDetail = event
                    } label: {
                        SearchResultRow(event: event)
                    }
                    .padding(.horizontal, Spacing.base)
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if viewModel.isSearching {
                HStack {
                    Spacer()
                    ProgressView().tint(.ember)
                    Spacer()
                }
                .padding(.vertical, Spacing.xl)
            } else if viewModel.results.isEmpty {
                VStack(spacing: Spacing.md) {
                    Text("🔍")
                        .font(.system(size: 40))
                    Text("No results for \"\(viewModel.searchText)\"")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Text("\(viewModel.results.count) results")
                    .font(.captionMedium)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, Spacing.base)

                ForEach(viewModel.results) { event in
                    Button {
                        showEventDetail = event
                    } label: {
                        SearchResultRow(event: event)
                    }
                    .padding(.horizontal, Spacing.base)
                }
            }
        }
        .sheet(item: $showEventDetail) { event in
            EventDetailView(event: event)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono)
            .foregroundColor(.textTertiary)
            .textCase(.uppercase)
            .tracking(1.5)
    }

    private func categoryChip(_ category: EventCategory?, label: String) -> some View {
        let isSelected = viewModel.selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.2)) {
                viewModel.filterByCategory(isSelected ? nil : category)
            }
        } label: {
            Text(label)
                .font(.captionMedium)
                .foregroundColor(isSelected ? (category.map { Color.categoryColor(for: $0) } ?? .ember) : .textSecondary)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, 8)
                .background(isSelected ? (category.map { Color.categoryColor(for: $0).opacity(0.15) } ?? Color.ember.opacity(0.15)) : Color.bgRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? (category.map { Color.categoryColor(for: $0) } ?? .ember) : Color.bgBorder))
        }
    }

    private var curatedCollections: [CuratedCollection] {[
        CuratedCollection(title: "Date Night in Hyde Park", subtitle: "Intimate venues, great vibes", emoji: "🥂", color: .rose),
        CuratedCollection(title: "Friday Under $20", subtitle: "Great nights, budget friendly", emoji: "💸", color: .teal),
        CuratedCollection(title: "Live Music This Week", subtitle: "Concerts & jazz nights", emoji: "🎸", color: .ember),
        CuratedCollection(title: "Weekend Brunch Spots", subtitle: "Sun, food, friends", emoji: "☀️", color: .gold),
    ]}
}

// MARK: - Curated Card

private struct CuratedCard: View {
    let collection: CuratedCollection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(collection.emoji)
                .font(.system(size: 32))
            Spacer()
            Text(collection.title)
                .font(.headingSmall)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Text(collection.subtitle)
                .font(.captionMedium)
                .foregroundColor(.textSecondary)
        }
        .frame(width: 160, height: 140)
        .padding(Spacing.base)
        .background(
            LinearGradient(
                colors: [collection.color.opacity(0.25), Color.bgSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(collection.color.opacity(0.3))
        )
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.categoryColor(for: event.category).opacity(0.2))
                    .frame(width: 52, height: 52)
                Text(event.category.emoji)
                    .font(.system(size: 24))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headingSmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.venue.name)
                        .font(.captionMedium)
                        .foregroundColor(.textSecondary)
                    Text("·")
                        .foregroundColor(.textTertiary)
                    Text(event.startTime.relativeEventTime)
                        .font(.captionMedium)
                        .foregroundColor(.ember)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(event.priceDisplay)
                    .font(.captionMedium)
                    .foregroundColor(event.isFree ? .teal : .textSecondary)
                if event.totalInterested > 0 {
                    Text("\(event.totalInterested) interested")
                        .font(.captionSmall)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }
}

struct CuratedCollection {
    let title: String
    let subtitle: String
    let emoji: String
    let color: Color
}
