# z-layout-switcher

**Fix text you have selected** after typing it with the wrong keyboard layout. Select `ghbdtn`, press a shortcut, and the selection is replaced with `привет`.

The Linux version is an on-demand Wayland command. It does not monitor typing or run a background daemon. Character mappings come from XKB, so layout pairs are not hard-coded.

## Windows

Install [AutoHotkey v2](https://www.autohotkey.com/) and at least two keyboard layouts in Windows settings. Run [windows/z-layout-switcher.ahk](windows/z-layout-switcher.ahk) once. Select text in an editable field and press **Win + Caps Lock** to replace it with text from the next installed layout. The script stays in the system tray; exit it from the tray menu to disable the shortcut.

The script detects the source layout from characters unique to one installed layout, falling back to the focused application's active layout when the text is ambiguous. It uses `Ctrl+C` and `Ctrl+V`, so the application must support those shortcuts. It saves and restores the clipboard with AutoHotkey's `ClipboardAll`; a clipboard history manager may still record the temporary converted text. To check US/RU conversion on Windows, run the script with `--self-test` (both layouts must be installed).

## Nix, niri, and Home Manager

Add the flake as an input and import its Home Manager module:

```nix
inputs.z-layout-switcher = {
  url = "github:alexmcgil/z-layout-switcher";
  inputs.nixpkgs.follows = "nixpkgs";
};

home-manager.users.alice.imports = [
  inputs.z-layout-switcher.homeManagerModules.default
];
```

Enable it alongside your niri keyboard settings:

```nix
programs.niri.settings.input.keyboard.xkb = {
  layout = "us,ru";
  options = "grp:caps_toggle";
};
programs.z-layout-switcher.enable = true;
```

The module reads the layouts and variants from the niri settings. With `grp:caps_toggle`, it binds conversion of **selected text** to **Super + Caps Lock**. In niri's config, this key is named `Super+ISO_Next_Group` after XKB processes Caps Lock.

For another shortcut, set `programs.z-layout-switcher.key = "Mod+F8";`. If niri's layout is configured outside Home Manager, also set `programs.z-layout-switcher.layouts = "us,ru";` and specify the shortcut explicitly.

## Other Wayland compositors

The package is available as `inputs.z-layout-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default`. Bind this command in your compositor:

```text
z-layout-switcher --layouts us,ru --options grp:caps_toggle
```

The command detects the source layout from the **selected text** and converts it to the next configured layout. If the text is ambiguous, niri's active layout is used when available. On another compositor, pass `--from 0` to select the first layout explicitly (indices start at zero). Use `--variants` if your XKB layouts have variants. `--dry-run` reads stdin and prints the converted text without replacing a selection.

## Selection and clipboard behavior

The application must expose the **current text selection** through Wayland PRIMARY selection. The command reads that selection, temporarily copies the converted text to the regular clipboard, presses `Ctrl+V` with `wtype`, and restores the previous clipboard contents. Your compositor must support the virtual keyboard protocol used by `wtype`.

Some applications keep an old PRIMARY selection after the highlight disappears. Make sure the text you want to replace is still selected when you press the shortcut. Clipboard restoration keeps one MIME type; if the previous clipboard offered both plain text and HTML, only one is restored. A clipboard history manager may record the temporary converted text.

For development, use `direnv allow`, `nix develop`, or `nix-shell`. Run `cargo test` and `bash tests/clipboard.sh target/debug/z-layout-switcher` after building the binary.
