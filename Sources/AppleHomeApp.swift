import SwiftUI
import UIKit

@main struct AppleHomeApp: App {
    @StateObject private var model: AppleHomeModel
    init() {
        // Start the plugin connection even when LaunchServices opens this app hidden.
        // A StateObject's lazy constructor otherwise waits for a visible scene.
        let model = AppleHomeModel()
        _model = StateObject(wrappedValue: model)
    }
    var body: some Scene {
        WindowGroup { AppleHomeView(model: model).frame(minWidth: 760, minHeight: 500).onAppear { model.windowAppeared() } }
    }
}
