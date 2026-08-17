import SwiftUI

@main
struct MIR4DPatentSourceListingApp: App {
    @StateObject private var model = ListingViewModel()

    var body: some Scene {
        WindowGroup("Листинг исходного текста") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1050, minHeight: 760)
        }
    }
}
