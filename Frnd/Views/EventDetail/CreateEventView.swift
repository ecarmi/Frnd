import SwiftUI
import MapKit
import UIKit

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
    @State private var capacityText = ""

    // State
    @State private var isSubmitting = false
    @State private var titleError: String?
    @State private var venueNameError: String?
    @State private var venueAddressError: String?
    @State private var geocodeError: String?
    @State private var priceError: String?
    @State private var alertMessage: String?

    private enum Field: Hashable {
        case title
        case description
        case venueName
        case venueAddress
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
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissKeyboard()
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
                    .disabled(isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
            .alert("Can't Post Event", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section("Event Details") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Event Name")
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
                TextField("Event title", text: $title)
                    .focused($focusedField, equals: .title)
                    .foregroundColor(.textPrimary)
                    .onChange(of: title) { titleError = nil }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.captionSmall)
                    .foregroundColor(.textTertiary)
                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Description (optional)")
                            .foregroundColor(.textTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                        .focused($focusedField, equals: .description)
                        .foregroundColor(.textPrimary)
                        .scrollContentBackground(.hidden)
                }
            }
            if let err = titleError {
                Text(err)
                    .font(.captionSmall)
                    .foregroundColor(.red)
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Menu {
                ForEach(EventCategory.allCases, id: \.self) { cat in
                    Button {
                        category = cat
                    } label: {
                        Label(cat.displayName, systemImage: selectedCategorySymbol(for: cat))
                    }
                }
            } label: {
                HStack {
                    Text("Category")
                        .foregroundColor(.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Text(category.emoji)
                        Text(category.displayName)
                            .foregroundColor(.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.captionSmall)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
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
                .focused($focusedField, equals: .venueName)
                .foregroundColor(.textPrimary)
                .onChange(of: venueName) { venueNameError = nil }
            if let err = venueNameError {
                Text(err)
                    .font(.captionSmall)
                    .foregroundColor(.red)
            }
            TextField("Address (street, city, state)", text: $venueAddress)
                .focused($focusedField, equals: .venueAddress)
                .foregroundColor(.textPrimary)
                .onChange(of: venueAddress) { venueAddressError = nil; geocodeError = nil }
            if let err = venueAddressError ?? geocodeError {
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
                    TextField("Optional", text: $capacityText)
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

    private func validateFields() -> String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            titleError = "Please enter an event title."
            return "Please enter an event title."
        }
        if venueName.trimmingCharacters(in: .whitespaces).isEmpty {
            venueNameError = "Please enter a venue name."
            return "Please enter a venue name."
        }
        if venueAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            venueAddressError = "Please enter the venue address."
            return "Please enter the venue address."
        }
        if isPaid {
            if Double(priceText) == nil {
                priceError = "Enter a valid price."
                return "Fix pricing before posting."
            }
        }
        if hasCapacity {
            guard let capacity = Int(capacityText), capacity > 0 else {
                return "Please enter a valid max attendee count."
            }
        }
        return nil
    }

    // MARK: - Submit

    private func submit() async {
        dismissKeyboard()
        titleError = nil
        venueNameError = nil
        venueAddressError = nil
        geocodeError = nil
        priceError = nil

        if let err = validateFields() {
            alertMessage = err
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
            alertMessage = geocodeError
            return
        }

        guard let mapItem = searchResponse.mapItems.first else {
            geocodeError = "Could not determine coordinates for that address."
            alertMessage = geocodeError
            return
        }
        let coord = mapItem.placemark.coordinate

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
            alertMessage = error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func selectedCategorySymbol(for category: EventCategory) -> String {
        switch category {
        case .music: return "music.note"
        case .nightlife: return "moon.stars"
        case .foodDrink: return "fork.knife"
        case .arts: return "paintpalette"
        case .sports: return "figure.run"
        case .speaker: return "mic"
        case .networking: return "person.2"
        case .other: return "sparkles"
        }
    }
}
