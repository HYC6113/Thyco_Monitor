import AppKit

/// 将物理按键映射为游戏字符，避免中文输入法把候选字当作输入。
/// 字母键受 Shift / Caps Lock 影响；数字和标点只看 Shift，对应美式键盘上的符号。
enum TypeRacingKeyInput {
    static func character(from event: NSEvent) -> Character? {
        let shift = event.modifierFlags.contains(.shift)
        let capsLock = event.modifierFlags.contains(.capsLock)

        switch event.keyCode {
        case 0x00: return letter("a", shift: shift, capsLock: capsLock)
        case 0x01: return letter("s", shift: shift, capsLock: capsLock)
        case 0x02: return letter("d", shift: shift, capsLock: capsLock)
        case 0x03: return letter("f", shift: shift, capsLock: capsLock)
        case 0x04: return letter("h", shift: shift, capsLock: capsLock)
        case 0x05: return letter("g", shift: shift, capsLock: capsLock)
        case 0x06: return letter("z", shift: shift, capsLock: capsLock)
        case 0x07: return letter("x", shift: shift, capsLock: capsLock)
        case 0x08: return letter("c", shift: shift, capsLock: capsLock)
        case 0x09: return letter("v", shift: shift, capsLock: capsLock)
        case 0x0B: return letter("b", shift: shift, capsLock: capsLock)
        case 0x0C: return letter("q", shift: shift, capsLock: capsLock)
        case 0x0D: return letter("w", shift: shift, capsLock: capsLock)
        case 0x0E: return letter("e", shift: shift, capsLock: capsLock)
        case 0x0F: return letter("r", shift: shift, capsLock: capsLock)
        case 0x10: return letter("y", shift: shift, capsLock: capsLock)
        case 0x11: return letter("t", shift: shift, capsLock: capsLock)
        case 0x12: return symbol("1", shifted: "!", shift: shift)
        case 0x13: return symbol("2", shifted: "@", shift: shift)
        case 0x14: return symbol("3", shifted: "#", shift: shift)
        case 0x15: return symbol("4", shifted: "$", shift: shift)
        case 0x16: return symbol("6", shifted: "^", shift: shift)
        case 0x17: return symbol("5", shifted: "%", shift: shift)
        case 0x18: return symbol("=", shifted: "+", shift: shift)
        case 0x19: return symbol("9", shifted: "(", shift: shift)
        case 0x1A: return symbol("7", shifted: "&", shift: shift)
        case 0x1B: return symbol("-", shifted: "_", shift: shift)
        case 0x1C: return symbol("8", shifted: "*", shift: shift)
        case 0x1D: return symbol("0", shifted: ")", shift: shift)
        case 0x1E: return symbol("]", shifted: "}", shift: shift)
        case 0x1F: return letter("o", shift: shift, capsLock: capsLock)
        case 0x20: return letter("u", shift: shift, capsLock: capsLock)
        case 0x21: return symbol("[", shifted: "{", shift: shift)
        case 0x22: return letter("i", shift: shift, capsLock: capsLock)
        case 0x23: return letter("p", shift: shift, capsLock: capsLock)
        case 0x25: return letter("l", shift: shift, capsLock: capsLock)
        case 0x26: return letter("j", shift: shift, capsLock: capsLock)
        case 0x27: return symbol("'", shifted: "\"", shift: shift)
        case 0x28: return letter("k", shift: shift, capsLock: capsLock)
        case 0x29: return symbol(";", shifted: ":", shift: shift)
        case 0x2A: return symbol("\\", shifted: "|", shift: shift)
        case 0x2B: return symbol(",", shifted: "<", shift: shift)
        case 0x2C: return symbol("/", shifted: "?", shift: shift)
        case 0x2D: return letter("n", shift: shift, capsLock: capsLock)
        case 0x2E: return letter("m", shift: shift, capsLock: capsLock)
        case 0x2F: return symbol(".", shifted: ">", shift: shift)
        case 0x31: return " "
        case 0x32: return symbol("`", shifted: "~", shift: shift)
        default:
            return nil
        }
    }

    static func normalizedGameCharacter(from event: NSEvent) -> Character? {
        guard let raw = character(from: event) else { return nil }
        return TypeRacingTextFactory.normalizedInput(raw)
    }

    private static func letter(_ base: Character, shift: Bool, capsLock: Bool) -> Character {
        let upper = shift != capsLock
        if upper, let uppercased = String(base).uppercased().first {
            return uppercased
        }
        return base
    }

    private static func symbol(_ base: Character, shifted: Character, shift: Bool) -> Character {
        shift ? shifted : base
    }
}
