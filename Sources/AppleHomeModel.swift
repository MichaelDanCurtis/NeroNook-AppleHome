import Foundation
import Combine
import HomeKit
import UIKit
import NookPluginSDK

let appleHomePluginID = "cafe.nero.plugin.applehome"
struct AccessoryCard: Identifiable {
    let id: String
    let name: String
    let room: String
    let reachable: Bool
    let readings: [String]
    var display: String { reachable ? readings.first ?? "No current reading" : "Unreachable" }
}
@MainActor final class AppleHomeModel: NSObject, ObservableObject {
    @Published var settingsVisible = false
    @Published var enabled = false
    @Published var ready = false
    @Published var status = "Enable Apple Home access in Settings"
    @Published var notice = ""
    @Published var tab = "Favorites"
    @Published var search = ""
    @Published var selectedRoom = "All rooms"
    @Published var selectedHome = ""
    @Published var homes: [(id: String, name: String)] = []
    @Published var accessories: [AccessoryCard] = []
    @Published var scenes: [(id: String, name: String, count: Int)] = []
    @Published var favorites = Set<String>()
    @Published var reading = false
    private var manager: HMHomeManager?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var lastRefresh = Date.distantPast
    private var generation = UUID()
    private var receivedHomes = false
    private var registeredNotifications = Set<UUID>()
    private var input: PluginLines = .init()
    private var initialAppearance = true
    private var readings = ReadingTracker()
    private var characteristics: [UUID: HMCharacteristic] = [:]
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    private let protocolTest = CommandLine.arguments.contains("--protocol-test")
    private var home: HMHome? { manager?.homes.first { $0.uniqueIdentifier.uuidString == selectedHome } }
    var homeName: String { home?.name ?? "Apple Home" }
    var rooms: [String] { Set(accessories.map(\.room)).sorted() }
    var visibleAccessories: [AccessoryCard] {
        accessories.filter { (tab != "Favorites" || favorites.contains($0.id)) && (tab != "Rooms" || selectedRoom == "All rooms" || selectedRoom == $0.room) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.room.localizedCaseInsensitiveContains(search)) }
    }
    override init() {
        super.init()
        if !protocolTest {
            enabled = UserDefaults.standard.bool(forKey: "homeEnabled")
            selectedHome = UserDefaults.standard.string(forKey: "selectedHome") ?? ""
            favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        }
        if hosted {
            FileHandle.standardInput.readabilityHandler = { [weak self] file in
                let data = file.availableData
                Task { @MainActor in
                    guard let self else { return }
                    guard !data.isEmpty else { exit(0) }
                    do { for message in try self.input.append(data) { self.receive(message) } } catch { exit(1) }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            self.readings.expire(); self.pumpReads()
            self.reading = self.readings.busy
            if self.ready && Date().timeIntervalSince(self.lastRefresh) > 60 { self.refresh() }
            self.rebuild(); self.publish()
        } }
        if enabled && !protocolTest { start() }
    }
    func windowAppeared() {
        guard initialAppearance else { return }; initialAppearance = false
        if hosted { for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) { for window in scene.windows { window.isHidden = true } } }
    }
    func showSettings() { settingsVisible = true; showWindow() }
    func showWindow() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) { for window in scene.windows { window.makeKeyAndVisible() } }
        if let scene = UIApplication.shared.connectedScenes.first { UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil, errorHandler: nil) }
    }
    func start() {
        guard manager == nil, !protocolTest else { return }
        enabled = true; UserDefaults.standard.set(true, forKey: "homeEnabled"); status = "Waiting for Apple Home permission…"
        let manager = HMHomeManager(); self.manager = manager; manager.delegate = self
    }
    func stop() {
        generation = UUID(); ready = false; enabled = false; receivedHomes = false
        for accessory in home?.accessories ?? [] {
            accessory.delegate = nil
            for characteristic in accessory.services.flatMap(\.characteristics) where registeredNotifications.contains(characteristic.uniqueIdentifier) { characteristic.enableNotification(false) { _ in } }
        }
        manager?.delegate = nil; manager = nil; homes = []; accessories = []; scenes = []
        readings.reset(); characteristics = [:]; registeredNotifications = []; reading = false
        UserDefaults.standard.set(false, forKey: "homeEnabled"); status = "Apple Home paused · enable it in Settings"; publish()
    }
    func chooseHome(_ id: String) {
        guard manager?.homes.contains(where: { $0.uniqueIdentifier.uuidString == id }) == true else { return }
        generation = UUID()
        for accessory in home?.accessories ?? [] { accessory.delegate = nil; for c in accessory.services.flatMap(\.characteristics) where registeredNotifications.contains(c.uniqueIdentifier) { c.enableNotification(false) { _ in } } }
        selectedHome = id; selectedRoom = "All rooms"; readings.reset(); characteristics = [:]; registeredNotifications = []
        UserDefaults.standard.set(id, forKey: "selectedHome"); refresh()
    }
    func star(_ id: String) {
        if !favorites.insert(id).inserted { favorites.remove(id) }
        if !protocolTest { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }; publish()
    }
    private func allowed(_ c: HMCharacteristic) -> Bool {
        [HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeCurrentTemperature, HMCharacteristicTypeCurrentRelativeHumidity, HMCharacteristicTypeBatteryLevel, HMCharacteristicTypeContactState, HMCharacteristicTypeMotionDetected, HMCharacteristicTypeCurrentDoorState, HMCharacteristicTypeCurrentLockMechanismState].contains(c.characteristicType) && c.properties.contains(HMCharacteristicPropertyReadable)
    }
    func refresh() {
        guard ready, let home, !readings.busy else { return }; lastRefresh = Date()
        var readable: [HMCharacteristic] = []
        for accessory in home.accessories.prefix(300) {
            accessory.delegate = self
            guard accessory.isReachable else { continue }
            readable += accessory.services.flatMap(\.characteristics).filter(allowed).prefix(16)
        }
        characteristics = Dictionary(readable.map { ($0.uniqueIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        readings.enqueue(readable.map(\.uniqueIdentifier)); pumpReads(); rebuild()
    }
    private func pumpReads() {
        guard ready else { return }; let current = generation
        while let ticket = readings.next() {
            guard let c = characteristics[ticket.characteristic] else { readings.complete(ticket, success: false); continue }
            c.readValue { [weak self] error in Task { @MainActor in
                guard let self, self.generation == current, self.readings.complete(ticket, success: error == nil) else { return }
                self.pumpReads(); self.rebuild()
            } }
            let id = c.uniqueIdentifier
            if c.properties.contains(HMCharacteristicPropertySupportsEventNotification), !registeredNotifications.contains(id) {
                registeredNotifications.insert(id)
                c.enableNotification(true) { [weak self] error in Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    if error != nil { self.registeredNotifications.remove(id) }
                } }
            }
        }
        reading = readings.busy
    }
    private func value(_ c: HMCharacteristic) -> String? {
        guard readings.fresh(c.uniqueIdentifier), let n = c.value as? NSNumber else { return nil }
        switch c.characteristicType {
        case HMCharacteristicTypePowerState: return n.boolValue ? "On" : "Off"
        case HMCharacteristicTypeBrightness: return "Brightness \(n.intValue)%"
        case HMCharacteristicTypeCurrentTemperature: return String(format: "%.1f °C", n.doubleValue)
        case HMCharacteristicTypeCurrentRelativeHumidity: return "Humidity \(n.intValue)%"
        case HMCharacteristicTypeBatteryLevel: return "Battery \(n.intValue)%"
        case HMCharacteristicTypeContactState: return n.intValue == 0 ? "Contact detected" : "Contact not detected"
        case HMCharacteristicTypeMotionDetected: return n.boolValue ? "Motion detected" : "No motion"
        case HMCharacteristicTypeCurrentLockMechanismState: return [0: "Unlocked", 1: "Locked", 2: "Jammed", 3: "Unknown lock state"][n.intValue]
        case HMCharacteristicTypeCurrentDoorState: return [0: "Open", 1: "Closed", 2: "Opening", 3: "Closing", 4: "Stopped"][n.intValue]
        default: return nil
        }
    }
    private func rebuild() {
        guard ready, let home else { return }
        accessories = home.accessories.prefix(300).map { a in
            AccessoryCard(id: a.uniqueIdentifier.uuidString, name: String(a.name.prefix(120)), room: String((a.room?.name ?? "Unassigned").prefix(100)), reachable: a.isReachable, readings: a.services.flatMap(\.characteristics).filter(allowed).compactMap(value))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        scenes = home.actionSets.prefix(300).map { (id: $0.uniqueIdentifier.uuidString, name: String($0.name.prefix(120)), count: $0.actions.count) }.sorted { $0.name < $1.name }
        status = "\(home.name) · \(accessories.count) accessories\(reading ? " · reading…" : "")"
        notice = readings.failed.isEmpty ? "" : "Some readings are unavailable. Refresh to try again."
    }
    private func updateHomes() {
        guard let manager else { return }
        guard manager.authorizationStatus.contains(.authorized) else {
            generation = UUID(); ready = false; accessories = []; homes = []; scenes = []; readings.reset(); characteristics = [:]; reading = false
            status = manager.authorizationStatus.contains(.restricted) ? "Apple Home access is restricted" : "Allow Apple Home access in System Settings"; publish(); return
        }
        homes = manager.homes.map { ($0.uniqueIdentifier.uuidString, String($0.name.prefix(100))) }
        if !homes.contains(where: { $0.id == selectedHome }) {
            generation = UUID(); readings.reset(); characteristics = [:]; registeredNotifications = []; accessories = []; scenes = []
            selectedHome = homes.first?.id ?? ""; UserDefaults.standard.set(selectedHome, forKey: "selectedHome")
        }
        ready = receivedHomes && !selectedHome.isEmpty
        if ready { refresh() } else { status = receivedHomes ? "No homes are available to this Apple account" : "Reading your homes…" }
        publish()
    }
    private func receive(_ m: PluginMessage) {
        guard m.pluginID == appleHomePluginID else { exit(1) }
        if session == nil {
            guard m.type == "hello" else { exit(1) }; session = m.session
            emit("ready", features: ["actions-v1", "panels-v1", "dashboard-v1", "diagrams-v1"])
            send(.init(.register, registration: .init(actions: [.init("read_status", title: "Read Apple Home status", output: .init([.init("connected", .boolean), .init("message", .string)]))], channels: [.init("status", title: "Apple Home status", kind: .state, schema: .init([.init("connected", .boolean), .init("message", .string)]))])))
            publish(); return
        }
        guard m.session == session else { exit(1) }
        if m.type == "action" { switch m.action { case "configure": showSettings(); case "home": showWindow(); case "refresh": refresh(); default: break } }
        if m.type == "bus", let bus = m.bus, bus.operation == .execute {
            let valid = bus.address?.plugin == appleHomePluginID && bus.address?.name == "read_status"
            send(.init(.update, requestID: bus.requestID, update: .init(valid ? .succeeded : .failed, values: valid ? values : [:])))
        }
    }
    var values: [String: PluginValue] { ["connected": .boolean(ready), "message": .string(String(status.prefix(250)))] }
    func publish() {
        guard session != nil else { return }
        let snapshot = PluginSnapshot(title: "Apple Home", status: String(status.prefix(300)), activity: String(status.prefix(100)), actions: [.init("home", "Open home", symbol: "house"), .init("refresh", "Refresh", enabled: ready && !reading, symbol: "arrow.clockwise")], badge: ready ? "Read only" : "Setup needed", panels: ["Favorites", "Rooms", "Scenes"].map { .init($0.lowercased(), $0, diagrams: [diagram(page: $0)]) })
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(appleHomePluginID, "status"), values: values, lifetime: 8))
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: appleHomePluginID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) } catch { exit(1) }
    }
}
extension AppleHomeModel: @preconcurrency HMHomeManagerDelegate, @preconcurrency HMAccessoryDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { guard manager === self.manager else { return }; receivedHomes = true; updateHomes() }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { guard manager === self.manager else { return }; updateHomes() }
    func accessoryDidUpdateReachability(_ accessory: HMAccessory) { rebuild(); if accessory.isReachable { refresh() } }
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        guard ready, home?.accessories.contains(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) == true, allowed(characteristic) else { return }
        readings.event(characteristic.uniqueIdentifier); rebuild()
    }
}
