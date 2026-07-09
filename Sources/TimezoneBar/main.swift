import AppKit
import Combine
import SwiftUI

struct City: Codable, Identifiable, Equatable {
    var id: UUID
    var tzIdentifier: String
    var label: String
    var flag: String
    var workStart: Int
    var workEnd: Int
    var pinned: Bool

    init(
        id: UUID = UUID(),
        tzIdentifier: String,
        label: String,
        flag: String,
        workStart: Int = 9,
        workEnd: Int = 17,
        pinned: Bool = false
    ) {
        self.id = id
        self.tzIdentifier = tzIdentifier
        self.label = label
        self.flag = flag
        self.workStart = workStart
        self.workEnd = workEnd
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tzIdentifier = try container.decode(String.self, forKey: .tzIdentifier)
        label = try container.decode(String.self, forKey: .label)
        flag = try container.decode(String.self, forKey: .flag)
        workStart = try container.decodeIfPresent(Int.self, forKey: .workStart) ?? 9
        workEnd = try container.decodeIfPresent(Int.self, forKey: .workEnd) ?? 17
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

struct Settings: Codable, Equatable {
    enum SortMode: String, Codable, CaseIterable {
        case westToEast
        case manual

        var title: String {
            switch self {
            case .westToEast:
                return "West to east"
            case .manual:
                return "Manual"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            switch value {
            case "westToEast", "West to east":
                self = .westToEast
            case "manual", "Manual":
                self = .manual
            default:
                self = .westToEast
            }
        }
    }

    var use24HourClock = true
    var showSeconds = false
    var showPinnedInMenuBar = false
    var sortMode: SortMode = .westToEast
}

struct CatalogCity: Codable, Identifiable {
    var id: String { "\(label)|\(tzIdentifier)" }
    var label: String
    var tzIdentifier: String
    var country: String
    var flag: String
    var aliases: [String]
}

@MainActor
final class TimezoneStore: ObservableObject {
    static let maximumCityCount = 10

    @Published var cities: [City] {
        didSet {
            persist()
        }
    }

    @Published var settings: Settings {
        didSet {
            persist()
        }
    }

    @Published var now = Date()
    @Published var scrubMinutes: Int? = nil

    let catalog: [CatalogCity]

    private let citiesKey = "TimezoneBar.cities"
    private let settingsKey = "TimezoneBar.settings"
    private static let validWorkHourRange = 0...24

    init() {
        catalog = Self.loadCatalog()
        settings = Self.load(Settings.self, key: settingsKey) ?? Settings()
        cities = Self.validatedCities(Self.load([City].self, key: citiesKey) ?? Self.defaultCities())
    }

    var referenceDate: Date {
        if let scrubMinutes {
            return now.addingTimeInterval(TimeInterval(scrubMinutes * 60))
        }
        return now
    }

    var sortedCities: [City] {
        switch settings.sortMode {
        case .manual:
            return cities
        case .westToEast:
            return cities.sorted { left, right in
                TimeZone(identifier: left.tzIdentifier)?.secondsFromGMT(for: referenceDate) ?? 0 <
                    TimeZone(identifier: right.tzIdentifier)?.secondsFromGMT(for: referenceDate) ?? 0
            }
        }
    }

    var pinnedCity: City? {
        cities.first(where: \.pinned) ?? cities.first
    }

    func tick() {
        now = Date()
    }

    func resetToNow() {
        scrubMinutes = nil
        now = Date()
    }

    func setScrubSteps(_ steps: Double) {
        let snapped = Int(steps.rounded()) * 15
        scrubMinutes = snapped == 0 ? nil : snapped
    }

    func add(_ catalogCity: CatalogCity) {
        guard canAdd(catalogCity) else {
            return
        }
        cities.append(City(tzIdentifier: catalogCity.tzIdentifier, label: catalogCity.label, flag: catalogCity.flag))
    }

    func canAdd(_ catalogCity: CatalogCity) -> Bool {
        cities.count < Self.maximumCityCount &&
            TimeZone(identifier: catalogCity.tzIdentifier) != nil &&
            !cities.contains(where: { $0.label == catalogCity.label && $0.tzIdentifier == catalogCity.tzIdentifier })
    }

    func remove(_ city: City) {
        cities.removeAll { $0.id == city.id }
        if cities.isEmpty {
            cities = Self.defaultCities()
        }
    }

    func setPinned(_ city: City) {
        cities = cities.map { current in
            var copy = current
            copy.pinned = current.id == city.id
            return copy
        }
        settings.showPinnedInMenuBar = true
    }

    func updateWorkHours(for city: City, start: Int, end: Int) {
        guard let index = cities.firstIndex(where: { $0.id == city.id }) else {
            return
        }
        let clampedStart = min(max(start, Self.validWorkHourRange.lowerBound), Self.validWorkHourRange.upperBound - 1)
        let clampedEnd = min(max(end, Self.validWorkHourRange.lowerBound + 1), Self.validWorkHourRange.upperBound)
        cities[index].workStart = min(clampedStart, clampedEnd - 1)
        cities[index].workEnd = max(clampedEnd, clampedStart + 1)
    }

    func moveCities(from offsets: IndexSet, to destination: Int) {
        cities.move(fromOffsets: offsets, toOffset: destination)
        settings.sortMode = .manual
    }

    func moveSortedCities(from offsets: IndexSet, to destination: Int) {
        var reorderedCities = sortedCities
        reorderedCities.move(fromOffsets: offsets, toOffset: destination)
        cities = reorderedCities
        settings.sortMode = .manual
    }

    func results(matching query: String) -> [CatalogCity] {
        guard cities.count < Self.maximumCityCount else {
            return []
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = catalog.filter { candidate in
            !cities.contains(where: { $0.label == candidate.label && $0.tzIdentifier == candidate.tzIdentifier })
        }
        guard !trimmed.isEmpty else {
            return Array(base.prefix(8))
        }
        let needle = trimmed.lowercased()
        return base
            .filter { candidate in
                ([candidate.label, candidate.country, candidate.tzIdentifier] + candidate.aliases)
                    .contains { $0.lowercased().contains(needle) }
            }
            .prefix(8)
            .map { $0 }
    }

    func formattedTime(for city: City, date: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: city.tzIdentifier)
        formatter.dateFormat = settings.use24HourClock
            ? (settings.showSeconds ? "HH:mm:ss" : "HH:mm")
            : (settings.showSeconds ? "h:mm:ss a" : "h:mm a")
        return formatter.string(from: date ?? referenceDate)
    }

    func formattedDayAndTime(for city: City, date: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: city.tzIdentifier)
        formatter.dateFormat = settings.use24HourClock ? "EEE HH:mm" : "EEE h:mm a"
        return formatter.string(from: date ?? referenceDate)
    }

    func dayOffset(for city: City, date: Date? = nil) -> Int {
        let instant = date ?? referenceDate
        let localDay = dayOrdinal(for: instant, timeZone: .current)
        let cityDay = dayOrdinal(for: instant, timeZone: TimeZone(identifier: city.tzIdentifier) ?? .current)
        return cityDay - localDay
    }

    func cityLocalHour(for city: City, at date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: city.tzIdentifier) ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    private func dayOrdinal(for date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        return calendar.ordinality(of: .day, in: .era, for: start) ?? 0
    }

    private func persist() {
        Self.save(Self.validatedCities(cities), key: citiesKey)
        Self.save(settings, key: settingsKey)
    }

    private static func defaultCities() -> [City] {
        [
            City(tzIdentifier: "America/Los_Angeles", label: "San Francisco", flag: "🇺🇸", pinned: true),
            City(tzIdentifier: "America/New_York", label: "New York", flag: "🇺🇸"),
            City(tzIdentifier: "Asia/Tokyo", label: "Tokyo", flag: "🇯🇵"),
            City(tzIdentifier: "Europe/London", label: "London", flag: "🇬🇧"),
            City(tzIdentifier: "Australia/Sydney", label: "Sydney", flag: "🇦🇺")
        ]
    }

    private static func loadCatalog() -> [CatalogCity] {
        guard let url = Bundle.module.url(forResource: "Cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cities = try? JSONDecoder().decode([CatalogCity].self, from: data) else {
            return []
        }
        return cities.filter { TimeZone(identifier: $0.tzIdentifier) != nil }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func validatedCities(_ loadedCities: [City]) -> [City] {
        var sanitized = loadedCities.compactMap { city -> City? in
            guard TimeZone(identifier: city.tzIdentifier) != nil else {
                return nil
            }

            var copy = city
            copy.label = copy.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if copy.label.isEmpty {
                copy.label = city.tzIdentifier
            }
            copy.workStart = min(max(copy.workStart, validWorkHourRange.lowerBound), validWorkHourRange.upperBound - 1)
            copy.workEnd = min(max(copy.workEnd, copy.workStart + 1), validWorkHourRange.upperBound)
            return copy
        }

        if sanitized.isEmpty {
            sanitized = defaultCities()
        }

        if !sanitized.contains(where: \.pinned), sanitized.indices.contains(sanitized.startIndex) {
            sanitized[sanitized.startIndex].pinned = true
        }

        var didKeepPinnedCity = false
        return sanitized.map { city in
            var copy = city
            if copy.pinned, didKeepPinnedCity {
                copy.pinned = false
            } else if copy.pinned {
                didKeepPinnedCity = true
            }
            return copy
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var store: TimezoneStore!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var stopTimerWorkItem: DispatchWorkItem?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        store = TimezoneStore()
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        bindStore()
        startClock()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeZoneChanged),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        stopTimerWorkItem?.cancel()
        timer?.invalidate()
    }

    @MainActor
    func popoverDidShow(_ notification: Notification) {
        startClock()
    }

    @MainActor
    func popoverDidClose(_ notification: Notification) {
        store.resetToNow()
        scheduleClockStopIfIdle()
    }

    @MainActor
    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            startClock()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    @objc private func systemTimeZoneChanged() {
        store.tick()
    }

    @MainActor
    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "TimezoneBar")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)
        updateStatusTitle()
    }

    @MainActor
    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: RootView(store: store))
    }

    @MainActor
    private func bindStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusTitle()
                    self?.scheduleClockStopIfIdle()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func updateStatusTitle() {
        guard let button = statusItem.button else {
            return
        }
        if store.settings.showPinnedInMenuBar, let city = store.pinnedCity {
            let shortLabel = city.label
                .split(separator: " ")
                .first
                .map(String.init) ?? city.label
            button.title = " \(shortLabel) \(store.formattedTime(for: city))"
        } else {
            button.title = ""
        }
    }

    @MainActor
    private func startClock() {
        stopTimerWorkItem?.cancel()
        guard timer == nil else {
            return
        }
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(clockFired),
            userInfo: nil,
            repeats: true
        )
    }

    @MainActor
    @objc private func clockFired() {
        store.tick()
    }

    @MainActor
    private func scheduleClockStopIfIdle() {
        stopTimerWorkItem?.cancel()
        guard !popover.isShown, !store.settings.showPinnedInMenuBar else {
            return
        }
        let item = DispatchWorkItem { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.stopTimerWorkItem = nil
        }
        stopTimerWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }
}

struct RootView: View {
    @ObservedObject var store: TimezoneStore
    @State private var selectedTab = 0
    @State private var isAddingCity = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if isAddingCity {
                AddCityView(store: store) {
                    isAddingCity = false
                }
            } else {
                if selectedTab == 0 {
                    CityListView(store: store)
                } else {
                    AlignmentGridView(store: store)
                }

                Divider()
                scrubber
            }
        }
        .frame(width: store.settings.showSeconds ? 392 : 360, height: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isAddingCity {
                Text("Add city")
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Picker("", selection: $selectedTab) {
                    Text("List").tag(0)
                    Text("Align").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Spacer()
            if isAddingCity {
                Button {
                    isAddingCity = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Close")
            } else {
                Button {
                    isAddingCity = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Add city")
            }

            Menu {
                Toggle("Pinned time in menu bar", isOn: $store.settings.showPinnedInMenuBar)
                Toggle("24-hour clock", isOn: $store.settings.use24HourClock)
                Toggle("Show seconds", isOn: $store.settings.showSeconds)
                Picker("Sort", selection: $store.settings.sortMode) {
                    ForEach(Settings.SortMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Divider()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Settings")
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "minus")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                PlainScrubberSlider(
                    value: Binding(
                        get: { Double((store.scrubMinutes ?? 0) / 15) },
                        set: { store.setScrubSteps($0) }
                    ),
                    in: -96...96,
                    step: 1
                )
                .frame(minWidth: 240)
                Button {
                    store.resetToNow()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(store.scrubMinutes == nil)
                .keyboardShortcut("0", modifiers: .command)
                .help("Reset to now")
            }
            Text(scrubLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var scrubLabel: String {
        guard let minutes = store.scrubMinutes else {
            return "Now"
        }
        let hours = abs(minutes) / 60
        let remainder = abs(minutes) % 60
        let sign = minutes > 0 ? "+" : "-"
        return "\(sign)\(hours)h \(remainder)m from now"
    }
}

struct PlainScrubberSlider: NSViewRepresentable {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double

    init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double) {
        _value = value
        self.bounds = bounds
        self.step = step
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: bounds.lowerBound,
            maxValue: bounds.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.sliderType = .linear
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.minValue = bounds.lowerBound
        slider.maxValue = bounds.upperBound
        slider.numberOfTickMarks = 0
        slider.doubleValue = value
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: PlainScrubberSlider

        init(_ parent: PlainScrubberSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = (sender.doubleValue / parent.step).rounded() * parent.step
        }
    }
}

struct CityListView: View {
    @ObservedObject var store: TimezoneStore

    var body: some View {
        List {
            ForEach(store.sortedCities) { city in
                CityRow(store: store, city: city)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.remove(city)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            store.setPinned(city)
                        } label: {
                            Label("Pin", systemImage: "pin.fill")
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Set as pinned") {
                            store.setPinned(city)
                        }
                        Button(role: .destructive) {
                            store.remove(city)
                        } label: {
                            Text("Remove")
                        }
                    }
            }
            .onMove { offsets, destination in
                store.moveSortedCities(from: offsets, to: destination)
            }
        }
        .listStyle(.plain)
    }
}

struct CityRow: View {
    @ObservedObject var store: TimezoneStore
    let city: City

    var body: some View {
        HStack(spacing: 8) {
            Text(store.formattedTime(for: city))
                .font(.system(.title3, design: .monospaced))
                .frame(width: store.settings.showSeconds ? 100 : 66, alignment: .leading)
            Text(city.flag)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(city.label)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if city.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(city.tzIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
            Spacer()
            if store.dayOffset(for: city) != 0 {
                Text(dayOffsetText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            Menu {
                Button {
                    store.setPinned(city)
                } label: {
                    Label("Set as pinned", systemImage: "pin.fill")
                }
                Button(role: .destructive) {
                    store.remove(city)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("City options")
        }
        .padding(.vertical, 6)
    }

    private var dayOffsetText: String {
        let offset = store.dayOffset(for: city)
        return offset > 0 ? "+\(offset)" : "\(offset)"
    }
}

struct AlignmentGridView: View {
    @ObservedObject var store: TimezoneStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hourLegend
            ForEach(store.sortedCities) { city in
                CityGridRow(store: store, city: city)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(store.sortedCities) { city in
                    HStack(spacing: 8) {
                        Text(city.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(width: 92, alignment: .leading)
                        Text(store.formattedDayAndTime(for: city))
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var hourLegend: some View {
        HStack {
            Text("")
                .frame(width: 78)
            ForEach([0, 3, 6, 9, 12, 15, 18, 21, 24], id: \.self) { hour in
                Text("\(hour)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

}

struct CityGridRow: View {
    @ObservedObject var store: TimezoneStore
    let city: City

    var body: some View {
        HStack(spacing: 8) {
            Text(city.label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let cellWidth = size.width / 48
                        for index in 0..<48 {
                            let date = dateForCell(index)
                            let hour = store.cityLocalHour(for: city, at: date)
                            let rect = CGRect(
                                x: Double(index) * cellWidth,
                                y: 0,
                                width: cellWidth - 1,
                                height: size.height
                            )
                            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color(for: hour)))
                        }
                    }
                    .onTapGesture { location in
                        let clamped = min(max(location.x / max(proxy.size.width, 1), 0), 1)
                        let minutes = Int((clamped * 24 * 60 / 15).rounded()) * 15
                        store.scrubMinutes = minutesFromLocalStart(minutes)
                    }

                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2)
                        .offset(x: cursorX(width: proxy.size.width))
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func color(for hour: Double) -> Color {
        if hour >= Double(city.workStart), hour < Double(city.workEnd) {
            return Color.green.opacity(0.62)
        }
        if (hour >= 7 && hour < Double(city.workStart)) || (hour >= Double(city.workEnd) && hour < 22) {
            return Color.yellow.opacity(0.58)
        }
        return Color.gray.opacity(0.28)
    }

    private func localStartOfDay() -> Date {
        Calendar.current.startOfDay(for: store.referenceDate)
    }

    private func dateForCell(_ index: Int) -> Date {
        localStartOfDay().addingTimeInterval(TimeInterval(index * 30 * 60))
    }

    private func cursorX(width: Double) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: store.referenceDate)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return min(max(minutes / (24 * 60) * width, 0), width - 2)
    }

    private func minutesFromLocalStart(_ minutes: Int) -> Int {
        let target = Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60))
        return Int((target.timeIntervalSince(Date()) / 60 / 15).rounded()) * 15
    }
}

struct AddCityView: View {
    @ObservedObject var store: TimezoneStore
    let onDismiss: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search city, country, or alias", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(12)

            List(store.results(matching: query)) { result in
                Button {
                    store.add(result)
                    onDismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text(result.flag)
                            .frame(width: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.label)
                                .font(.body.weight(.semibold))
                            Text("\(result.country) · \(result.tzIdentifier)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            HStack {
                Text("\(store.cities.count)/\(TimezoneStore.maximumCityCount) cities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .frame(height: 44)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onDismiss()
            } label: {
                Label("Close Add City", systemImage: "xmark")
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
