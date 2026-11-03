import AppKit

struct DisplayInfo: Identifiable {
    let id: String
    let name: String
    let detail: String
    let screen: NSScreen

    static func connected() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            let id = CFUUIDCreateString(nil, uuid) as String
            let size = "\(CGDisplayPixelsWide(number.uint32Value)) × \(CGDisplayPixelsHigh(number.uint32Value))"
            let position = "x: \(Int(screen.frame.minX)), y: \(Int(screen.frame.minY))"
            return DisplayInfo(id: id, name: screen.localizedName, detail: "\(size) · \(position)", screen: screen)
        }.sorted { a, b in
            a.screen.frame.minY == b.screen.frame.minY ? a.screen.frame.minX < b.screen.frame.minX : a.screen.frame.minY > b.screen.frame.minY
        }
    }
}
