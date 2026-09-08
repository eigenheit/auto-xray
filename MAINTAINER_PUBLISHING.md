# Чек-лист публикации AUTO Xray на GitHub

Этот файл предназначен владельцу репозитория, а не обычному пользователю.

## Структура репозитория

Рекомендуемый минимум:

```text
README.md
SECURITY.md
THIRD_PARTY_NOTICES.txt
docs/
  INSTALLATION.md
  TROUBLESHOOTING.md
  TELEGRAM.md
assets/
  dove-icon.png
```

README должен оставаться коротким. Технический процесс сборки в него не добавлять.

## Перед первым публичным релизом

1. Выбрать лицензию для собственного кода AUTO Xray.
2. Проверить обязательства по лицензии встроенного Xray-core.
3. Убедиться, что в репозиторий не попали:
   - URL подписки;
   - UUID;
   - HWID конкретного пользователя;
   - Reality keys;
   - логи;
   - персональные пути `/Users/...`.
4. Собрать два пользовательских asset:
   - DMG;
   - альтернативный Catalina Installer ZIP.
5. Проверить оба на отдельном пользовательском профиле.
6. Рассчитать SHA-256.

Пример:

```bash
shasum -a 256 AUTO_Xray_Catalina_Intel_v2.5.dmg
shasum -a 256 AUTO_Xray_Catalina_Installer_v2.5.zip
```

7. Создать `SHA256SUMS.txt`.
8. Загрузить в GitHub Release:
   - DMG
   - Installer ZIP
   - SHA256SUMS.txt
   - при необходимости source archive
9. Вставить текст из `GITHUB_RELEASE_TEXT.md`.
10. Заменить placeholders контрольных сумм на реальные.

## Важная политика по Gatekeeper

В пользовательской документации разрешать только штатные способы macOS:

- Control-click → Open;
- Security & Privacy → Open Anyway.

Не предлагать пользователям глобально отключать Gatekeeper.

Если macOS сообщает, что приложение содержит malware или «will damage your computer», инструкция должна требовать остановить установку, а не обходить блокировку.
