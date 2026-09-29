import MapKit
import SwiftUI

/// Picking a point on the map: crosshair in the center, the point is the map center.
/// Plus address search.
struct PlacePickerMap: View {
    @Binding var coordinate: CLLocationCoordinate2D

    @State private var position: MapCameraPosition
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    init(coordinate: Binding<CLLocationCoordinate2D>) {
        _coordinate = coordinate
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate.wrappedValue,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ZStack {
                MapReader { _ in
                    Map(position: $position)
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .onMapCameraChange(frequency: .onEnd) { context in
                            coordinate = context.region.center
                        }
                }

                // Map center crosshair.
                Image(systemName: "mappin")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                    .shadow(radius: 3)
                    .offset(y: -14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(text: $searchText) {
                    Text("addPlace.addressPrompt", comment: "Search by address")
                }
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }

                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            if !searchResults.isEmpty {
                List(searchResults, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "—").font(.body)
                            if let address = item.placemark.title {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(maxHeight: 180)
            }
        }
    }

    private func search() async {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term

        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = Array(response.mapItems.prefix(8))
        } catch {
            Log.location.debug("Address search returned nothing: \(error.localizedDescription, privacy: .public)")
            searchResults = []
        }
    }

    private func select(_ item: MKMapItem) {
        let target = item.placemark.coordinate
        coordinate = target
        position = .region(MKCoordinateRegion(center: target,
                                              latitudinalMeters: 500,
                                              longitudinalMeters: 500))
        searchResults = []
        searchText = item.name ?? searchText
    }
}
