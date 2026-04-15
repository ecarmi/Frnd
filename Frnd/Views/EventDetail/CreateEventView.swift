import SwiftUI
import MapKit

struct CreateEventView: View {
    let groupId: String?
    var onCreated: ((Event) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    // Form fields
    @State private var title = ""
    @State private var description = ""
    @State private var category: EventCategory = .other
    @State private var startDate = Date()
    @State private var hasEndTime = false
    @State private var endDate = Date().addingTimeInterval(7200)
    @State private var isPaid = false
    @State private var priceText = ""
    @State private var venueName = ""
    @State private var venueAddress = ""
    @State private var hasCapacity = false
    @State private var capacityText = "50"

    // State
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var geocodeError: String?
    @State private var priceError: String?

    private enum Field: Hashable {
        case price
        case capacity
    }

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
                .simultaneousGesture(
                    TapGesture().onEnded {
                        focusedField = nil
                    }
                )
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .foregroundColor(.ember)
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
                        .padding(.leading, 4)
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
                    Text("Price $")
                        .foregroundColor(.textSecondary)
                    TextField("0", text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .price)
                        .foregroundColor(.textPrimary)
                        .onChange(of: priceText) { priceError = nil }
                }
                if let err = priceError {
                    Text(err)
                        .font(.captionSmall)
                        .foregroundColor(.red)
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
                HStack {
                    Text("Max attendees")
                        .foregroundColor(.textPrimary)
                    Spacer()
                    TextField("50", text: $capacityText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .capacity)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.textPrimary)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !venueName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !venueAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func validateFields() -> String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Please enter an event title."
        }
        if venueName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Please enter a venue name."
        }
        if venueAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Please enter the venue address."
        }
        if isPaid {
            if Double(priceText) == nil {
                priceError = "Enter a valid price."
                return "Fix pricing before posting."
            }
        }
        return nil
    }

    // MARK: - Submit

    private func submit() async {
        focusedField = nil
        geocodeError = nil
        errorMessage = nil
        priceError = nil

        if let err = validateFields() {
            errorMessage = err
            return
        }

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
            price_min: isPaid ? Double(priceText) : nil,
            price_max: isPaid ? Double(priceText) : nil,
            capacity: hasCapacity ? (Int(capacityText) ?? 50) : nil,
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
