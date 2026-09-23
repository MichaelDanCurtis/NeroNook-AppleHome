import SwiftUI
import UIKit

@main struct AppleHomeApp: App {
    @StateObject private var model = AppleHomeModel()
    var body: some Scene {
        WindowGroup { AppleHomeView(model: model).frame(minWidth: 760, minHeight: 500).onAppear { model.windowAppeared() } }
    }
}
