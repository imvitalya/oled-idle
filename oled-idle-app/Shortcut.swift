import Foundation

/// A physical keyboard key with Carbon modifier flags. Independent of keyboard language.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32?
    var modifiers: UInt32
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12
    static let allowedModifiers = command | shift | option | control
    static let disabled = Shortcut(keyCode: nil, modifiers: 0)
    static let controlOptionCommandB = Shortcut(keyCode: 11, modifiers: control | option | command)
    static let controlOptionCommandO = Shortcut(keyCode: 31, modifiers: control | option | command)
    static let controlOptionB = Shortcut(keyCode: 11, modifiers: control | option)
    static let functionKeys: [UInt32: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",
        98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",
        106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
    private static let names: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",10:"§",11:"B",12:"Q",13:"W",
        14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",
        27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",
        40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",
        65:"Keypad .",67:"Keypad *",69:"Keypad +",71:"Clear",75:"Keypad /",76:"Keypad ↩",78:"Keypad −",
        81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",
        87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",93:"¥",94:"_",
        95:"Keypad ,",102:"英数",104:"かな",114:"Help",115:"↖",116:"⇞",117:"⌦",119:"↘",121:"⇟",
        123:"←",124:"→",125:"↓",126:"↑"
    ]

    init(keyCode: UInt32?, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    enum CodingKeys: String, CodingKey { case keyCode, modifiers }
    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            switch legacy {
            case "controlOptionCommandB": self = .controlOptionCommandB
            case "controlOptionCommandO": self = .controlOptionCommandO
            case "controlOptionB": self = .controlOptionB
            default: self = .disabled
            }
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keyCode = try c.decodeIfPresent(UInt32.self, forKey: .keyCode)
            modifiers = try c.decode(UInt32.self, forKey: .modifiers)
            self = normalized()
        }
    }
    var isDisabled: Bool { keyCode == nil }
    var isValid: Bool {
        guard let key = keyCode, Self.names[key] != nil || Self.functionKeys[key] != nil else { return false }
        return modifiers & (Self.command | Self.control | Self.option) != 0 || Self.functionKeys[key] != nil
    }
    func normalized() -> Shortcut {
        let result = Shortcut(keyCode: keyCode, modifiers: modifiers & Self.allowedModifiers)
        return result.isValid ? result : .disabled
    }
    var title: String {
        guard let key = keyCode else { return "—" }
        return formattedTitle(keyName: Self.functionKeys[key] ?? Self.names[key] ?? "?")
    }
    func localizedTitle(using localizer: Localizer) -> String {
        guard let key = keyCode else { return "—" }
        let name = Self.functionKeys[key] ?? Self.names[key] ?? "?"
        let localized = name.hasPrefix("Keypad ")
            ? localizer.text("Keypad") + String(name.dropFirst(6)) : localizer.text(name)
        return formattedTitle(keyName: localized)
    }
    private func formattedTitle(keyName: String) -> String {
        var parts: [String] = []
        for (flag, label) in [(Self.control,"⌃"),(Self.option,"⌥"),(Self.shift,"⇧"),(Self.command,"⌘")] {
            if modifiers & flag != 0 { parts.append(label) }
        }
        parts.append(keyName)
        return parts.joined(separator: " ")
    }
}
