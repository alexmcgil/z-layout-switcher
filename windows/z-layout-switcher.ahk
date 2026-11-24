#Requires AutoHotkey v2.0
#SingleInstance Force

if A_Args.Length && A_Args[1] = "--self-test" {
    us := DllCall("user32\LoadKeyboardLayoutW", "Str", "00000409", "UInt", 0, "Ptr")
    ru := DllCall("user32\LoadKeyboardLayoutW", "Str", "00000419", "UInt", 0, "Ptr")
    if !us || ConvertText("hello", us, us) != "hello" {
        FileAppend "Keyboard conversion failed`n", "*"
        ExitApp 1
    }
    if !ru || ru = us {
        FileAppend "US conversion OK; Russian layout unavailable`n", "*"
        ExitApp 2
    }
    if ConvertText("ghbdtn", us, ru) != "привет" || ConvertText("руддщ", ru, us) != "hello" {
        FileAppend "US/RU conversion failed`n", "*"
        ExitApp 1
    }
    FileAppend "US/RU conversion OK`n", "*"
    ExitApp
}

#CapsLock::FixSelection()

FixSelection() {
    KeyWait "LWin"
    KeyWait "RWin"
    layouts := KeyboardLayouts()
    if layouts.Length < 2 {
        MsgBox "Install at least two keyboard layouts in Windows settings."
        return
    }

    previous := ClipboardAll()
    converted := false
    try {
        A_Clipboard := ""
        Send "^c"
        if !ClipWait(1)
            return

        input := A_Clipboard
        source := DetectLayout(input, layouts)
        output := ConvertText(input, source, layouts[Mod(IndexOf(layouts, source), layouts.Length) + 1])
        if output = input
            return

        A_Clipboard := output
        converted := true
        if !ClipWait(1)
            throw Error("Could not put converted text on the clipboard")
        Send "^v"
        Sleep 300
    } finally {
        if !converted || A_Clipboard = output
            A_Clipboard := previous
    }
}

KeyboardLayouts() {
    count := DllCall("user32\GetKeyboardLayoutList", "Int", 0, "Ptr", 0, "Int")
    if count < 1
        throw Error("Could not read installed keyboard layouts")
    data := Buffer(count * A_PtrSize)
    count := DllCall("user32\GetKeyboardLayoutList", "Int", count, "Ptr", data, "Int")
    layouts := []
    Loop count
        layouts.Push(NumGet(data, (A_Index - 1) * A_PtrSize, "Ptr"))
    return layouts
}

DetectLayout(input, layouts) {
    scores := []
    for layout in layouts
        scores.Push(0)
    Loop Parse, input {
        char := Ord(A_LoopField)
        found := 0
        for index, layout in layouts {
            if KeyForChar(char, layout) != -1 {
                found += 1
                match := index
            }
        }
        if found = 1
            scores[match] += 1
    }

    best := 0
    bestIndex := 0
    for index, score in scores {
        if score > best {
            best := score
            bestIndex := index
        } else if score = best {
            bestIndex := 0
        }
    }
    if bestIndex
        return layouts[bestIndex]

    thread := DllCall("user32\GetWindowThreadProcessId", "Ptr", DllCall("user32\GetForegroundWindow", "Ptr"), "Ptr", 0, "UInt")
    current := DllCall("user32\GetKeyboardLayout", "UInt", thread, "Ptr")
    if IndexOf(layouts, current)
        return current
    throw Error("Cannot detect the source keyboard layout")
}

ConvertText(input, source, target) {
    output := ""
    Loop Parse, input {
        char := A_LoopField
        key := KeyForChar(Ord(char), source)
        if key = -1 {
            output .= char
            continue
        }

        state := Buffer(256, 0)
        shift := (key >> 8) & 7
        if shift & 1
            NumPut("UChar", 0x80, state, 0x10)
        if shift & 2
            NumPut("UChar", 0x80, state, 0x11)
        if shift & 4
            NumPut("UChar", 0x80, state, 0x12)
        vk := key & 0xff
        scan := DllCall("user32\MapVirtualKeyExW", "UInt", vk, "UInt", 0, "Ptr", source, "UInt")
        targetVk := DllCall("user32\MapVirtualKeyExW", "UInt", scan, "UInt", 3, "Ptr", target, "UInt")
        if !scan || !targetVk {
            output .= char
            continue
        }
        chars := Buffer(16, 0)
        count := DllCall("user32\ToUnicodeEx", "UInt", targetVk, "UInt", scan, "Ptr", state, "Ptr", chars, "Int", 8, "UInt", 4, "Ptr", target, "Int")
        ; shortcut: dead keys and IME sequences stay unchanged, use a layout-specific input method if needed.
        output .= count > 0 ? StrGet(chars, count, "UTF-16") : char
    }
    return output
}

KeyForChar(char, layout) {
    return char > 0xffff ? -1 : DllCall("user32\VkKeyScanExW", "UShort", char, "Ptr", layout, "Short")
}

IndexOf(items, value) {
    for index, item in items {
        if item = value
            return index
    }
    return 0
}
