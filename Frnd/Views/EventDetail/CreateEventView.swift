import SwiftUI
import MapKit

struct CreateEventView: View {
    let groupId: String?
    var onCreated: ((Event) -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Form fields
    @State private var title = ""
    @State private var description = ""
    @State private var category: EventCategory = .other
    @State private var startDate = Date()
    @State private var hasEndTime = false
    @State private var endDate = Date().addingTimeInterval(7200)
    @State private var isPaid = false
    @State private var priceMin = ""
    @State private var priceMax = ""
    @State private var venueName = ""
    @State private var venueAddress = ""
    @State private var hasCapacity = false
    @State private var capacity = 50

    // State
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var geocodeError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                Form {
                    basicSection
                    categorySection
                    dateSection
                    pricingSection
                    venueSection
                    capacitySection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Post Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        Task { await submit() }
                    }
                    .foregroundColor(.ember)
                    .fontWeight(.semibold)
                    .disabled(!isFormValid || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        }
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section("Event Details") {
            TextField("Event title", text: $title)
                .foregroundColor(.textPrimary)
            ZStack(alignment: .topLeading) {
                if description.isEmpty {
                    Text("Description (optional)")
                        .foregroundColor(.textTertiary)
                        .padding(.top, 8)
                }
                TextEditor(text: $description)
                    .frame(minHeight: 80)
                    .foregroundColor(.textPrimary)
            }
            if let err = errorMessage {
                Text(err)
                    .font(.captionSmall)
                    .foregroundColor(.red)
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $category) {
                ForEach(EventCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .foregroundColor(.textPrimary)
        }
    }

    private var dateSection: some View {
        Section("Date & Time") {
            DatePicker("Start", selection: $startDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .foregroundColor(.textPrimary)
            Toggle("End time", isOn: $hasEndTime)
                .foregroundColor(.textPrimary)
            if hasEndTime {
                DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    .foregroundColor(.textPrimary)
            }
        }
    }

    private var pricingSection: some View {
        Section("Pricing") {
            Toggle("Paid event", isOn: $isPaid)
                .foregroundColor(.textPrimary)
            if isPaid {
                HStack {
                    Text("Min $")
                        .foregroundColor(.textSecondary)
                    TextField("0", text: $priceMin)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.textPrimary)
                }
                HStack {
                    Text("Max $")
                        .foregroundColor(.textSecondary)
                    TextField("0", text: $priceMax)
                        .keyboardType(.decimalPad)
                        .foregroundColor(.textPrimary)
                }
            }
        }
    }

    private var venueSection: some View {
        Section("Venue") {
            TextField("Venue name (e.g. Ida Noyes Hall)", text: $venueName)
                .foregroundColor(.textPrimary)
            TextField("Address (e.g. 1212 E 59th St, Chicago, IL)", text: $venueAddress)
                .foregroundColor(.textPrimary)
            if let err = geocodeError {
                Text(err)
                    .font(.captionSmall)
                    .foregroundColor(.red)
            }
        }
    }

    private var capacitySection: some View {
        Section("Capacity") {
            Toggle("Set capacity limit", isOn: $hasCapacity)
                .foregroundColor(.textPrimary)
            if hasCapacity {
                Stepper("Capacity: \(capacity)", value: $capacity, in: 1...10000, step: 10)
                    .foregroundColor(.textPrimary)
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !venueName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !venueAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Submit

    private func submit() async {
        geocodeError = nil
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        // Geocode address using MKLocalSearch
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = venueAddress
        let searchResponse: MKLocalSearch.Response
        do {
            searchResponse = try await MKLocalSearch(request: searchRequest).start()
        } catch {
            geocodeError = "Address not found. Try a more specific address."
            return
        }

        guard let mapItem = searchResponse.mapItems.first else {
            geocodeError = "Could not determine coordinates for that address."
            return
        }
        let coord = mapItem.location.coordinate

        let body = APIService.CreateEventBody(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            venue: .init(
                name: venueName.trimmingCharacters(in: .whitespaces),
                address: venueAddress.trimmingCharacters(in: .whitespaces),
                latitude: coord.latitude,
                longitude: coord.longitude
            ),
            start_time: startDate,
            end_time: hasEndTime ? endDate : nil,
            price_min: isPaid ? Double(priceMin) : nil,
            price_max: isPaid ? Double(priceMax) : nil,
            capacity: hasCapacity ? capacity : nil,
            category: category,
            tags: [],
            group_id: groupId
        )

        do {
            let event = try await APIService.shared.createEvent(body)
            onCreated?(event)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

