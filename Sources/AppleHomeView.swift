import SwiftUI
import NookPluginSDK

private let amber = Color(red: 0.97, green: 0.69, blue: 0.31)
struct AppleHomeView: View {
    @ObservedObject var model: AppleHomeModel
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: "house.fill").font(.system(size: 28)).foregroundStyle(amber).padding(14).background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) { Text(model.homeName).font(.title.bold()); Text(model.ready ? "Accessories and scenes · read only" : "Your Apple Home, close at hand").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(!model.ready || model.reading)
                Button { model.settingsVisible = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            HStack {
                Picker("View", selection: $model.tab) { ForEach(["Favorites", "Rooms", "Scenes"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 300)
                if model.tab == "Rooms" { Picker("Room", selection: $model.selectedRoom) { Text("All rooms").tag("All rooms"); ForEach(model.rooms, id: \.self) { Text($0) } }.frame(maxWidth: 190) }
                Spacer()
                TextField("Find an accessory", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 210)
            }
            if !model.ready {
                VStack(spacing: 18) { Image(systemName: "house").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(amber); Text(model.status).font(.title3).multilineTextAlignment(.center); Button("Open Settings") { model.settingsVisible = true }.buttonStyle(.borderedProminent) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        if model.tab == "Scenes" {
                            ForEach(model.scenes.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }, id: \.id) { scene in
                                VStack(alignment: .leading, spacing: 15) { Image(systemName: "sparkles").font(.title2).foregroundStyle(amber); Text(scene.name).font(.headline); Text("\(scene.count) actions").foregroundStyle(.secondary); Text("Scene · read only").font(.caption).foregroundStyle(.secondary) }.cardSurface()
                            }
                        } else {
                            ForEach(model.visibleAccessories) { accessory in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack { Image(systemName: "house.fill").foregroundStyle(amber); Spacer(); Button { model.star(accessory.id) } label: { Image(systemName: model.favorites.contains(accessory.id) ? "star.fill" : "star").foregroundStyle(model.favorites.contains(accessory.id) ? amber : .secondary) }.buttonStyle(.plain) }
                                    Text(accessory.name).font(.headline).lineLimit(2)
                                    Text(accessory.room).font(.caption).foregroundStyle(.secondary)
                                    Text(accessory.display).font(.title3.weight(.medium)).lineLimit(2)
                                    Text(accessory.readings.dropFirst().prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.cardSurface()
                            }
                        }
                    }
                    if model.tab == "Favorites" && model.visibleAccessories.isEmpty { Text("Star accessories in Rooms to keep them here and in your Nook.").foregroundStyle(.secondary).padding(40) }
                    if model.tab == "Scenes" && model.scenes.isEmpty { Text("No scenes are available in this home.").foregroundStyle(.secondary).padding(40) }
                }
            }
            HStack { Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2); Spacer() }
        }.padding(24).background(Color(red: 0.075, green: 0.073, blue: 0.087)).preferredColorScheme(.dark).tint(amber)
        .sheet(isPresented: $model.settingsVisible) {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Apple Home settings").font(.title2.bold()); Spacer(); Button("Done") { model.settingsVisible = false } }
                Label("Apple Home permission", systemImage: "house.fill").font(.headline)
                Text("This independent module uses Apple’s HomeKit permission to read your homes, rooms, accessories and scenes. It does not use Home Assistant or copy another app’s credentials.").foregroundStyle(.secondary)
                if model.enabled { Button("Pause Apple Home access") { model.stop() } }
                else { Button("Enable Apple Home access") { model.start() }.buttonStyle(.borderedProminent) }
                Text(model.status).font(.callout)
                if !model.homes.isEmpty {
                    Picker("Home", selection: Binding(get: { model.selectedHome }, set: { model.chooseHome($0) })) { ForEach(model.homes, id: \.id) { Text($0.name).tag($0.id) } }
                }
                Divider()
                Text("First release: read-only inventory").font(.headline)
                Text("Favorites are local to this plugin. Device controls follow after live inventory is verified. Pausing stops this module’s reads; revoke its Home permission in System Settings to remove system authorization.").foregroundStyle(.secondary)
                if !model.notice.isEmpty { Text(model.notice).font(.caption).foregroundStyle(.orange) }
                Spacer()
            }.padding(28).frame(minWidth: 540, minHeight: 420).presentationDetents([.large]).preferredColorScheme(.dark).tint(amber)
        }
    }
}
private extension View {
    func cardSurface() -> some View { self.padding(20).frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18)) }
}
extension AppleHomeModel {
    func diagram(page: String) -> PluginDiagram {
        var e: [PluginDiagramElement] = []
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fill: String) { e.append(.init(.box, x: x, y: y, w: w, h: h, fill: fill, radius: 16)) }
        func text(_ value: String, _ x: Double, _ y: Double, _ w: Double, _ font: Double = 22, _ color: String = "#F5EEE4") { e.append(.init(.text, x: x, y: y, w: w, h: 45, fill: color, text: String(value.prefix(170)), font: font)) }
        box(0, 0, 960, 540, "#17151A"); text(homeName, 34, 22, 700, 30); text(page.uppercased(), 35, 75, 700, 13, "#BEA991")
        var cards: [(String, String, String)] = []
        if page == "Scenes" { cards = scenes.map { ($0.name, "\($0.count) actions", "Read-only scene") } }
        else if page == "Rooms" { cards = rooms.map { room in (room, "\(accessories.filter { $0.room == room }.count) accessories", "Apple Home room") } }
        else { cards = accessories.filter { favorites.contains($0.id) }.map { ($0.name, $0.display, $0.room) } }
        if cards.isEmpty {
            box(420, 175, 120, 110, "#4B3826")
            e.append(.init(.line, x: 401, y: 187, w: 79, h: -65, stroke: "#F1B45D", weight: 5)); e.append(.init(.line, x: 480, y: 122, w: 79, h: 65, stroke: "#F1B45D", weight: 5))
            box(466, 226, 29, 59, "#17151A"); text(ready ? "Your home, your favorites" : "Your Apple Home, close at hand", 195, 329, 640, 28)
            text(ready ? "Open home to browse accessories and scenes." : "Enable Apple Home access in Settings.", 195, 393, 640, 18, "#BAAEA0")
        } else {
            for (i, card) in cards.prefix(6).enumerated() {
                let x = 32.0 + Double(i % 3) * 304, y = 134.0 + Double(i / 3) * 171
                box(x, y, 285, 153, "#2B2524"); text(String(card.0.prefix(26)), x + 16, y + 9, 252, 21); text(String(card.1.prefix(32)), x + 16, y + 62, 252, 24, "#F1B45D"); text(String(card.2.prefix(38)), x + 16, y + 107, 252, 13, "#BEA991")
            }
            text("Open home to browse · read-only preview", 35, 489, 870, 15, "#BEA991")
        }
        return .init(id: page.lowercased(), title: page, width: 960, height: 540, summary: String((cards.isEmpty ? status : cards.map { "\($0.0): \($0.1)" }.joined(separator: "; ")).prefix(3900)), elements: e)
    }
}
