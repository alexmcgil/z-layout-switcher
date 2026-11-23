# z-layout-switcher

По горячей клавише заменяет выделенный текст так, как если бы он был набран на следующей XKB-раскладке. Работает в Wayland; процесс запускается только на время преобразования. Таблицы символов строятся из XKB, без зашитых пар языков.

## Nix + niri + Home Manager

Добавьте этот flake в `inputs` своего flake и импортируйте модуль. Для локального репозитория:

```nix
inputs.z-layout-switcher.url = "path:/home/alexmcgil/Projects/z-layout-switcher";

home-manager.users.you.imports = [ inputs.z-layout-switcher.homeManagerModules.default ];
```

После публикации можно заменить `path:` на `github:OWNER/z-layout-switcher`. В конфиге `/home/alexmcgil/nixos` импорт модуля удобно добавить в `users/desktop.nix`, где уже определены раскладки niri, и там же установить `programs.z-layout-switcher.enable = true;`.

В конфигурации Home Manager:

```nix
programs.niri.settings.input.keyboard.xkb = {
  layout = "us,ru";
  options = "grp:caps_toggle";
};
programs.z-layout-switcher.enable = true;
```

Модуль берёт раскладки и варианты из настроек niri. Для `grp:caps_toggle` он добавляет биндинг `Super+Caps_Lock`. Для другого XKB-переключателя задайте клавишу явно: `programs.z-layout-switcher.key = "Mod+F8";`. Если конфигурация niri задана вне Home Manager, укажите `programs.z-layout-switcher.layouts = "us,ru";` и `programs.z-layout-switcher.key`.

## Любой Wayland-композитор

Пакет: `inputs.z-layout-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default`. Привяжите команду к горячей клавише композитора:

```text
z-layout-switcher --layouts us,ru --variants , --options grp:caps_toggle
```

Направление определяется по символам выделения. Когда это невозможно (например, выделены только цифры), используется активная раскладка из `niri msg -j keyboard-layouts`; в другом композиторе можно явно передать `--from 0` (индекс начинается с нуля). `--dry-run` читает stdin и печатает результат без вставки.

## Как это работает

Команда читает PRIMARY selection (`wl-paste --primary`), кладёт преобразованный текст в PRIMARY и посылает `Shift+Insert` через `wtype`. Обычный буфер обмена не меняется. Приложение должно поддерживать PRIMARY selection и вставку по `Shift+Insert`; некоторые поля ввода этого не делают. PRIMARY может хранить старое выделение после снятия выделения — перед запуском убедитесь, что нужный текст всё ещё выделен. Проверьте биндинг в живой сессии: XKB-опция переключения раскладки может влиять на `Super+Caps_Lock`.

Для разработки: `direnv allow`, `nix develop` или `nix-shell`. Проверка: `cargo test`, `nix flake check`.
