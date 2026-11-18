import AppKit

enum MacWeatherMode: String, CaseIterable {
    case snow = "Snow", heavySnow = "Heavy snow", rain = "Rain", sakura = "Sakura"
    case leaves = "Leaves", fireflies = "Fireflies", starfall = "Starfall", off = "Off"
    var isSnow: Bool { self == .snow || self == .heavySnow }
}

enum MacWeatherSchedule: String, CaseIterable {
    case manual = "Manual", random = "Random", season = "Match the season", local = "My weather"
}

@MainActor final class MacWeatherControls: NSObject {
    private let settings: UserDefaults
    private let onChange: () -> Void
    private var nextChange = Date.distantPast
    private var lookup: Task<Void,Never>?
    private var status = ""
    private(set) var mode: MacWeatherMode
    private(set) var schedule: MacWeatherSchedule
    var wind: CGFloat { CGFloat(max(-80,min(80,settings.integer(forKey:"weatherWind")))) }
    var lightning: Bool { settings.bool(forKey:"weatherLightning") }
    private var southern: Bool { settings.bool(forKey:"weatherSouthern") }

    init(settings: UserDefaults, onChange: @escaping () -> Void) {
        self.settings = settings; self.onChange = onChange
        mode = MacWeatherMode(rawValue:settings.string(forKey:"weatherMode") ?? "") ?? .snow
        schedule = MacWeatherSchedule(rawValue:settings.string(forKey:"weatherSchedule") ?? "") ?? .manual
    }

    private func apply(_ effect: MacWeatherMode) {
        guard effect != mode else {return}
        mode = effect; settings.set(effect.rawValue,forKey:"weatherMode"); onChange()
    }
    func choose(_ effect: MacWeatherMode) {
        use(.manual)
        apply(effect)
    }
    private func use(_ value: MacWeatherSchedule) {
        lookup?.cancel();lookup=nil
        schedule=value;settings.set(value.rawValue,forKey:"weatherSchedule")
        nextChange = .distantPast; status=""
    }
    static func seasonal(month:Int, southern:Bool) -> MacWeatherMode {
        let local = southern ? (month+5)%12+1 : month
        switch local {
        case 3...5: return .sakura
        case 6...8: return .fireflies
        case 9...11: return .leaves
        default: return .snow
        }
    }
    func tick(now:Date = Date()) {
        guard schedule != .manual, now >= nextChange else {return}
        switch schedule {
        case .manual: break
        case .random:
            nextChange = now.addingTimeInterval(15*60)
            if let next = MacWeatherMode.allCases.filter({ $0 != .off && $0 != mode }).randomElement() {apply(next)}
        case .season:
            nextChange = now.addingTimeInterval(60*60)
            apply(Self.seasonal(month:Calendar.current.component(.month,from:now),southern:southern))
        case .local:
            nextChange = now.addingTimeInterval(30*60)
            guard let query=settings.string(forKey:"weatherPlace"), !query.isEmpty else{return}
            status="Checking " + query + "…"
            lookup?.cancel()
            lookup=Task { [weak self] in
                do {
                    let match = try await LocalWeather.lookup(query)
                    guard let self=self,!Task.isCancelled,self.schedule == .local else{return}
                    self.status=match.1 + " · " + match.2 + " · Open-Meteo"; self.apply(match.0)
                } catch {
                    guard let self=self,!Task.isCancelled,self.schedule == .local else{return}
                    self.status = (error as? LocalWeather.Problem)?.description ?? "Weather unavailable. Retrying in 30 minutes."
                }
            }
        }
    }

    private func row(_ title:String,_ action:Selector?,in menu:NSMenu)->NSMenuItem {
        let item = NSMenuItem(title:title,action:action,keyEquivalent:"")
        item.target=self;menu.addItem(item);return item
    }
    private func child(_ title:String,in parent:NSMenu)->NSMenu {
        let menu=NSMenu(title:title)
        let item=NSMenuItem(title:title,action:nil,keyEquivalent:"")
        item.submenu=menu; parent.addItem(item); return menu
    }
    func append(to parent:NSMenu) {
        let weather=child("Weather",in:parent)
        for effect in MacWeatherMode.allCases {
            let entry=row(effect.rawValue,#selector(setMode(_:)),in:weather)
            entry.representedObject=effect.rawValue;entry.state=effect == mode ? .on:.off
        }
        weather.addItem(.separator())
        let windMenu=child("Wind",in:weather)
        for value in stride(from:-80,through:80,by:10) {
            let label=value==0 ? "Calm" : (value<0 ? "← " : "→ ")+String(abs(value))
            let entry=row(label,#selector(setWind(_:)),in:windMenu)
            entry.tag=value;entry.state=CGFloat(value)==wind ? .on:.off
        }
        let flash=row("Lightning in rain",#selector(toggleLightning),in:weather)
        flash.state=lightning ? .on:.off
        let schedules=child("Weather schedule",in:weather)
        for option in MacWeatherSchedule.allCases {
            let entry=row(option.rawValue+(option == .local ? "…" : ""),#selector(setSchedule(_:)),in:schedules)
            entry.representedObject=option.rawValue;entry.state=schedule==option ? .on:.off
        }
        schedules.addItem(.separator())
        let hemisphere=row("Southern hemisphere seasons",#selector(toggleHemisphere),in:schedules)
        hemisphere.state=southern ? .on:.off
        if !status.isEmpty { weather.addItem(.separator());row(status,nil,in:weather).isEnabled=false }
    }
    @objc private func setMode(_ item:NSMenuItem) {
        if let raw=item.representedObject as? String,let effect=MacWeatherMode(rawValue:raw) {choose(effect)}
    }
    @objc private func setWind(_ item:NSMenuItem) {settings.set(item.tag,forKey:"weatherWind");onChange()}
    @objc private func toggleLightning() {settings.set(!lightning,forKey:"weatherLightning");onChange()}
    @objc private func toggleHemisphere() {settings.set(!southern,forKey:"weatherSouthern");if schedule == .season {nextChange = .distantPast;tick()}}
    @objc private func setSchedule(_ item:NSMenuItem) {
        guard let raw=item.representedObject as? String,let choice=MacWeatherSchedule(rawValue:raw) else{return}
        if choice == .local {
            let prompt=NSAlert();prompt.messageText="Match your weather"
            prompt.informativeText="Enter a city or coordinates to look up its current weather with Open-Meteo."
            let field=NSTextField(frame:NSRect(x:0,y:0,width:280,height:24))
            field.placeholderString="City or latitude, longitude"
            field.stringValue=settings.string(forKey:"weatherPlace") ?? ""
            field.setAccessibilityLabel("City or coordinates")
            prompt.accessoryView=field;prompt.addButton(withTitle:"Use weather");prompt.addButton(withTitle:"Cancel")
            prompt.window.initialFirstResponder=field
            NSApp.activate(ignoringOtherApps:true)
            guard prompt.runModal() == .alertFirstButtonReturn else{return}
            let text=String(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120))
            guard !text.isEmpty else{return}
            settings.set(text,forKey:"weatherPlace")
        }
        use(choice);tick()
    }
}

enum LocalWeather {
    enum Problem: Error {
        case noCity, unavailable
        var description:String {
            self == .noCity ? "City not found. Choose My weather to change it." : "Weather unavailable. Retrying in 30 minutes."
        }
    }
    struct Place: Decodable {
        let name:String
        let latitude, longitude:Double
        let country_code:String?
    }
    private struct Search:Decodable {let results:[Place]?}
    private struct Forecast:Decodable {
        struct Current:Decodable {let weather_code:Int}
        let current:Current
    }
    static func effect(code:Int)->(MacWeatherMode,String)? {
        switch code {
        case 75,86: return (.heavySnow,"Heavy snow")
        case 71,73,77,85: return (.snow,"Snow")
        case 51...67,80...82,95...99: return (.rain,"Rain or showers")
        case 0...3,45,48: return (.off,code>=45 ? "Fog" : code>=2 ? "Clouds" : "Clear skies")
        default: return nil
        }
    }
    private static func read<T:Decodable>(_ type:T.Type, url:String, query:[URLQueryItem]) async throws -> T {
        var parts=URLComponents(string:url)!
        parts.queryItems=query
        guard let endpoint=parts.url else{throw Problem.unavailable}
        var request=URLRequest(url:endpoint);request.timeoutInterval=8
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count<=65536 else{throw Problem.unavailable}
        return try JSONDecoder().decode(type,from:data)
    }
    static func coordinates(_ text:String)->(Double,Double)? {
        let pair=text.components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces)}
        guard pair.count==2,let lat=Double(pair[0]),let lon=Double(pair[1]),
              (-90...90).contains(lat),(-180...180).contains(lon) else{return nil}
        return (lat,lon)
    }
    static func lookup(_ query:String) async throws -> (MacWeatherMode,String,String) {
        let lat,lon:Double, label:String
        if let point=coordinates(query) {(lat,lon)=point;label=query}
        else {
            let search=try await read(Search.self,url:"https://geocoding-api.open-meteo.com/v1/search",query:[
                URLQueryItem(name:"name",value:query),URLQueryItem(name:"count",value:"1"),URLQueryItem(name:"language",value:"en")])
            guard let place=search.results?.first else{throw Problem.noCity}
            lat=place.latitude;lon=place.longitude;label=place.name+(place.country_code.map{", "+$0} ?? "")
        }
        try Task.checkCancellation()
        let forecast=try await read(Forecast.self,url:"https://api.open-meteo.com/v1/forecast",query:[
            URLQueryItem(name:"latitude",value:String(lat)),URLQueryItem(name:"longitude",value:String(lon)),
            URLQueryItem(name:"current",value:"weather_code"),URLQueryItem(name:"forecast_days",value:"1")])
        guard let result=effect(code:forecast.current.weather_code) else{throw Problem.unavailable}
        return (result.0,label,result.1)
    }
}
