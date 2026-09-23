import Foundation
import Combine
import HomeKit
import UIKit
import CryptoKit
import OSLog
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
    @Published var allowedPower = Set<String>()
    @Published var commandBusy = false
    private var command = HomeCommand()
    private var hostCards = false
    private var inlinePower: [String: HomeCommand.Intent] = [:]
    private var inlineStars: [String: String] = [:]
    private var manager: HMHomeManager?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var hostedActivity: NSObjectProtocol?
    private var lastRefresh = Date.distantPast
    private var generation = UUID()
    private var receivedHomes = false
    private var registeredNotifications = Set<UUID>()
    private var input: PluginLines = .init()
    private let applicationChannel = PluginApplicationChannel()
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
        Logger(subsystem: appleHomePluginID, category: "Lifecycle").info("Model started: hosted=\(self.hosted) applicationChannel=\(self.applicationChannel != nil)")
        if !protocolTest {
            allowedPower = Set(UserDefaults.standard.stringArray(forKey: "allowedPower") ?? [])
            enabled = UserDefaults.standard.bool(forKey: "homeEnabled")
            selectedHome = UserDefaults.standard.string(forKey: "selectedHome") ?? ""
            favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        }
        if hosted, let applicationChannel {
            hostedActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Keep the enabled Apple Home module available in NeroNook")
            applicationChannel.start { [weak self] message in
                Task { @MainActor in
                    guard let message else { exit(0) }
                    self?.receive(message)
                }
            }
        } else if hosted {
            FileHandle.standardInput.readabilityHandler = { [weak self] file in
                let data = file.availableData
                Task { @MainActor in
                    guard let self else { return }
                    guard !data.isEmpty else { exit(0) }
                    do { for message in try self.input.append(data) { self.receive(message) } } catch { exit(1) }
                }
            }
        }
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            if self.command.expire() {
                self.commandBusy = false; self.notice = "No confirmation received. The command was not retried. Refresh before trying again."
                self.readings.reset(); self.refresh()
            }
            self.readings.expire(); self.pumpReads()
            self.reading = self.readings.busy
            if self.ready && Date().timeIntervalSince(self.lastRefresh) > 60 { self.refresh() }
            self.rebuild(); self.publish()
        } }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
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
        guard !hosted || applicationChannel != nil else { status = "Update NeroNook to 0.14 or newer to use Apple Home"; return }
        enabled = true; UserDefaults.standard.set(true, forKey: "homeEnabled"); status = "Waiting for Apple Home permission…"
        let manager = HMHomeManager(); self.manager = manager; manager.delegate = self
    }
    func stop() {
        generation = UUID(); command.reset(); commandBusy = false; ready = false; enabled = false; receivedHomes = false
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
        generation = UUID(); command.reset(); commandBusy = false; notice = ""
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
        if !readings.failed.isEmpty && notice.isEmpty { notice = "Some readings are unavailable. Refresh to try again." }
    }
    private func updateHomes() {
        guard let manager else { return }
        guard manager.authorizationStatus.contains(.authorized) else {
            generation = UUID(); command.reset(); commandBusy = false; ready = false; accessories = []; homes = []; scenes = []; readings.reset(); characteristics = [:]; reading = false
            status = manager.authorizationStatus.contains(.restricted) ? "Apple Home access is restricted" : "Allow Apple Home access in System Settings"; publish(); return
        }
        homes = manager.homes.map { ($0.uniqueIdentifier.uuidString, String($0.name.prefix(100))) }
        if !homes.contains(where: { $0.id == selectedHome }) {
            generation = UUID(); command.reset(); commandBusy = false; readings.reset(); characteristics = [:]; registeredNotifications = []; accessories = []; scenes = []
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
            hostCards = m.features?.contains("control-cards-v1") == true
            emit("ready", features: ["actions-v1", "panels-v1", "dashboard-v1", "diagrams-v1", "control-cards-v1"])
            send(.init(.register, registration: .init(actions: [.init("read_status", title: "Read Apple Home status", output: .init([.init("connected", .boolean), .init("message", .string)]))], channels: [.init("status", title: "Apple Home status", kind: .state, schema: .init([.init("connected", .boolean), .init("message", .string)]))])))
            publish(); return
        }
        guard m.session == session else { exit(1) }
        if m.type == "action" { switch m.action { case "configure": showSettings(); case "home": showWindow(); case "refresh": refresh(); default:
            if let action = m.action, let id = inlineStars[action], accessories.contains(where: { $0.id == id }) { star(id) }
            else if let action = m.action, let intent = inlinePower[action] { sendPower(intent) }
        } }
        if m.type == "bus", let bus = m.bus, bus.operation == .execute {
            let valid = bus.address?.plugin == appleHomePluginID && bus.address?.name == "read_status"
            send(.init(.update, requestID: bus.requestID, update: .init(valid ? .succeeded : .failed, values: valid ? values : [:])))
        }
    }
    var values: [String: PluginValue] { ["connected": .boolean(ready), "message": .string(String(status.prefix(250)))] }
    private func cardKey(_ value: String) -> String {
        "item_" + SHA256.hash(data: Data((selectedHome + "|" + value).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    func powerCharacteristic(_ accessoryID: String) -> HMCharacteristic? {
        guard let a = home?.accessories.first(where: { $0.uniqueIdentifier.uuidString == accessoryID }) else { return nil }
        let supported = a.services.filter { [HMServiceTypeLightbulb, HMServiceTypeSwitch, HMServiceTypeOutlet].contains($0.serviceType) }
            .flatMap(\.characteristics).filter { $0.characteristicType == HMCharacteristicTypePowerState && $0.properties.contains(HMCharacteristicPropertyReadable) && $0.properties.contains(HMCharacteristicPropertyWritable) }
        return supported.count == 1 ? supported.first : nil
    }
    func powerState(_ c: HMCharacteristic) -> Bool? { readings.fresh(c.uniqueIdentifier) ? (c.value as? NSNumber)?.boolValue : nil }
    func isPowerAllowed(_ id: String) -> Bool { allowedPower.contains(selectedHome + ":" + id) }
    func setPowerAllowed(_ id: String, _ allowed: Bool) {
        guard powerCharacteristic(id) != nil else { return }
        let key = selectedHome + ":" + id
        if allowed { allowedPower.insert(key) } else { allowedPower.remove(key) }
        UserDefaults.standard.set(Array(allowedPower), forKey: "allowedPower"); publish()
    }
    private func sendPower(_ intent: HomeCommand.Intent) {
        guard ready, !protocolTest, let c = powerCharacteristic(intent.accessory), c.uniqueIdentifier == intent.characteristic,
              let a = home?.accessories.first(where: { $0.uniqueIdentifier.uuidString == intent.accessory }),
              let run = command.begin(intent, currentHome: selectedHome, currentState: powerState(c), reachable: a.isReachable, allowed: isPowerAllowed(intent.accessory)) else { return }
        commandBusy = true; let current = generation; let name = String(a.name.prefix(80)); notice = "Sending \(name) \(intent.desired ? "on" : "off")…"; publish()
        c.writeValue(NSNumber(value: intent.desired)) { [weak self] error in Task { @MainActor in
            guard let self, self.generation == current, self.command.accepts(run) else { return }
            if error != nil {
                self.command.finish(run); self.commandBusy = false; self.readings.reset(); self.notice = "Apple Home could not confirm the command. It was not retried."; self.refresh(); self.publish(); return
            }
            c.readValue { [weak self] error in Task { @MainActor in
                guard let self, self.generation == current, self.command.accepts(run) else { return }
                self.command.finish(run); self.commandBusy = false
                if error == nil, (c.value as? NSNumber)?.boolValue == intent.desired {
                    self.readings.event(c.uniqueIdentifier); self.notice = "\(name) is \(intent.desired ? "on" : "off") · confirmed by Apple Home."
                } else { self.readings.reset(); self.notice = "Command accepted; the resulting state could not be confirmed. It was not retried." }
                self.rebuild(); self.publish()
            } }
        } }
    }
    func publish() {
        guard let session else { return }
        inlinePower = [:]; inlineStars = [:]
        let panels: [PluginPanel] = ["Favorites", "Rooms", "Scenes"].map { page in
            guard hostCards else { return .init(page.lowercased(), page, diagrams: [diagram(page: page)]) }
            if page == "Scenes" {
                return .init("scenes", page, cards: scenes.prefix(48).map { PluginControlCard(cardKey($0.id), title: String($0.name.prefix(80)), value: "\($0.count) actions", detail: "Scene control is not enabled in this version.", symbol: "sparkles") })
            }
            let selected = accessories.filter { page == "Rooms" || favorites.contains($0.id) }
            return .init(page.lowercased(), page, cards: selected.prefix(64).map { a in
                let key = cardKey(a.id); let starID = key + (favorites.contains(a.id) ? "_unstar" : "_star")
                inlineStars[starID] = a.id
                var actions = [PluginAction(starID, favorites.contains(a.id) ? "Unfavorite" : "Favorite", symbol: favorites.contains(a.id) ? "star.fill" : "star")]
                var detail = a.readings.dropFirst().prefix(2).joined(separator: " · ")
                if let c = powerCharacteristic(a.id) {
                    let state = powerState(c); let desired = !(state ?? false); let actionID = key + (desired ? "_on" : "_off")
                    let canSend = ready && a.reachable && state != nil && isPowerAllowed(a.id) && !commandBusy
                    if canSend { inlinePower[actionID] = .init(home: selectedHome, accessory: a.id, characteristic: c.uniqueIdentifier, expected: state!, desired: desired) }
                    actions.insert(.init(actionID, desired ? "Turn on" : "Turn off", enabled: canSend, symbol: "power", confirmation: "Turn \(String(a.name.prefix(80))) \(desired ? "on" : "off") in \(String(a.room.prefix(70)))? Apple Home will check the resulting state."), at: 0)
                    if !isPowerAllowed(a.id) { detail = "Enable this device’s control in Settings." }
                }
                return PluginControlCard(key, title: String(a.name.prefix(80)), subtitle: a.room, value: String(a.display.prefix(100)), detail: String(detail.prefix(300)), symbol: powerCharacteristic(a.id) == nil ? "house.fill" : "power", highlighted: a.reachable && a.display == "On", actions: actions)
            })
        }
        let message = notice.isEmpty ? status : notice
        var snapshot = PluginSnapshot(title: "Apple Home", status: String(message.prefix(300)), activity: String(message.prefix(100)), actions: hostCards ? [.init("refresh", "Refresh", enabled: ready && !reading && !commandBusy, symbol: "arrow.clockwise")] : [.init("home", "Open home", symbol: "house"), .init("refresh", "Refresh", enabled: ready && !reading, symbol: "arrow.clockwise")], badge: commandBusy ? "Working…" : ready ? "Connected" : "Setup needed", panels: panels)
        while ((try? PluginMessage(type: "snapshot", pluginID: appleHomePluginID, session: session, snapshot: snapshot).encoded().count) ?? Int.max) > 120 * 1024 {
            guard let index = snapshot.panels?.indices.max(by: { (snapshot.panels?[$0].cards?.count ?? 0) < (snapshot.panels?[$1].cards?.count ?? 0) }), snapshot.panels?[index].cards?.isEmpty == false else { return }
            snapshot.panels?[index].cards?.removeLast()
        }
        let advertised = Set(snapshot.displayActions.filter(\.enabled).map(\.id))
        inlineStars = inlineStars.filter { advertised.contains($0.key) }; inlinePower = inlinePower.filter { advertised.contains($0.key) }
        guard (try? snapshot.validate()) != nil else { return }
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(appleHomePluginID, "status"), values: values, lifetime: 8))
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do {
            let message = PluginMessage(type: type, pluginID: appleHomePluginID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus)
            if let applicationChannel { try applicationChannel.send(message) }
            else { try FileHandle.standardOutput.write(contentsOf: message.encoded()) }
        } catch { exit(1) }
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
