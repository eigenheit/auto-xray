# Сборка AUTO Xray

Эта страница предназначена для сопровождающего проекта, а не для обычного пользователя.

## Почему Catalina-сборка делается на старом Intel Mac

AUTO Xray должен работать на macOS Catalina 10.15.x. Поэтому само AppleScript-приложение компилируется на проверенном Intel Mac с Catalina. GitHub Actions выполняет только статические проверки на современной macOS и не считается доказательством совместимости с Catalina.

## 1. Получить Xray-core локально

Репозиторий намеренно не хранит бинарник Xray-core.

На Mac, где уже установлен рабочий AUTO Xray 2.3+ или V2RayXS с проверенным core, запустите:

```text
scripts/import-xray-from-installed.command
```

Скрипт принимает только Xray 1.8.4 с ожидаемой SHA-256.

Файл `vendor/xray/xray` исключен из Git через `.gitignore`.

## 2. Собрать Catalina app и локальный DMG

```text
scripts/build-catalina.command
```

Результат появляется на Desktop в папке `AUTO_Xray_<version>_BUILD`.

Там находятся:

- `AUTO Xray.app`
- локальный ad-hoc signed DMG для теста
- ZIP с Catalina-скомпилированным приложением для последующей Developer ID подписи на современном Mac

## 3. Альтернативный Catalina installer

Для fallback-релиза можно упаковать исходники, `assets/dove-icon.png`, helper и проверенный `vendor/xray/xray`, а затем запускать:

```text
scripts/install-catalina.command
```

Этот способ локально собирает приложение на компьютере пользователя.

## 4. Developer ID / notarization

На современном Mac с Developer ID Application:

```text
scripts/setup-notarization.command
```

один раз сохраняет notary credentials в Keychain.

Затем:

```text
scripts/sign-notarize.command /path/to/AUTO_Xray_vX.Y.Z_Catalina_App_for_Signing.zip
```

## Версия

Единственный файл версии проекта:

```text
VERSION
```

Перед новым релизом сначала обновляется он, затем отображаемая версия в `src/AUTO_Xray.applescript`.
