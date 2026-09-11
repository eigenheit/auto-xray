<p align="center">
  <img src="assets/dove-icon.png" width="96" alt="AUTO Xray dove icon">
</p>

<h1 align="center">AUTO Xray</h1>

<p align="center">
  Легкий VLESS/Reality-клиент для старых Intel Mac, которым современные клиенты уже не подходят.
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>Русский</strong>
</p>

<p align="center">
  <img alt="Stable release" src="https://img.shields.io/github/v/release/eigenheit/auto-xray?label=stable">
  <img alt="macOS Catalina" src="https://img.shields.io/badge/macOS-Catalina%2010.15-000000?logo=apple&logoColor=white">
  <img alt="Intel x86_64" src="https://img.shields.io/badge/Intel-x86__64-0071C5?logo=intel&logoColor=white">
  <img alt="CI" src="https://github.com/eigenheit/auto-xray/actions/workflows/ci.yml/badge.svg">
</p>

> **AUTO Xray 2.5.20 — Stable**  
> Проверено на реальном Intel Mac `x86_64` с macOS Catalina 10.15.x.

## Скачать

**Текущая стабильная версия: AUTO Xray 2.5.20**

[**Скачать DMG — рекомендуется**](https://github.com/eigenheit/auto-xray/releases/download/v2.5.20/AUTO_Xray_Catalina_v2.5.20.dmg)

Резервный вариант: [ZIP-инсталлятор](https://github.com/eigenheit/auto-xray/releases/download/v2.5.20/AUTO_Xray_Catalina_Installer_v2.5.20.zip) · [SHA256SUMS.txt](https://github.com/eigenheit/auto-xray/releases/download/v2.5.20/SHA256SUMS.txt)

Не скачивайте AUTO Xray с посторонних сайтов и файловых обменников.

## Что умеет

- VLESS + Reality через встроенный **Xray-core 1.8.4**;
- автоматический выбор узлов RF / EU / World;
- ручной выбор конкретного сервера;
- HTTP/HTTPS proxy `127.0.0.1:9001` и SOCKS5 `127.0.0.1:2081`;
- автоматическая настройка системного proxy macOS;
- восстановление после переподключения Wi‑Fi;
- защита от зависших локальных proxy после выключения;
- обновление подписки из меню;
- запуск из строки меню macOS.

AUTO Xray работает как **system proxy client**, а не как TUN VPN.

## Как выглядит

![AUTO Xray в строке меню macOS Catalina](assets/screenshots/menubar.png)

![DMG AUTO Xray на macOS Catalina](assets/screenshots/dmg-installer.png)

Скриншоты сделаны на реальном Intel Mac с macOS Catalina.

## Установка

1. Скачайте `AUTO_Xray_Catalina_v2.5.20.dmg`.
2. Откройте DMG и запустите **Install AUTO Xray.app** через `Control + клик → Open`.
3. Если Catalina сначала показывает только Cancel — нажмите Cancel и повторите открытие.
4. После установки AUTO Xray запускается в состоянии **OFF**.

Полная инструкция: [docs/INSTALLATION.ru.md](docs/INSTALLATION.ru.md)

## Первый запуск

Нажмите 🕊:

1. **Обновить подписку**.
2. Выберите RF / EU / World или ручной сервер.
3. Нажмите **Включить**.

Яркий голубь = ON. Полупрозрачный голубь = OFF.

## Безопасность релиза

- Xray-core проверяется по SHA-256 перед упаковкой;
- каждый релиз содержит SHA256SUMS;
- CI проверяет сборку и установочные пакеты;
- публичные DMG и ZIP не содержат диагностические тестовые инструменты.

## Ограничения

- официальный target: Intel Mac + macOS Catalina 10.15.x;
- Apple Silicon не является целью этого релиза;
- приложение пока не подписано Apple Developer ID и использует штатный Gatekeeper flow;
- приложения, игнорирующие system proxy, могут не использовать AUTO Xray.

Если macOS сообщает о malware или "will damage your computer" — не обходите предупреждение.

## Данные

Настройки:

```text
~/Library/Application Support/AUTO Xray/
```

Логи:

```text
~/Library/Logs/AUTO Xray/
```

## Помощь

- [Установка](docs/INSTALLATION.ru.md)
- [Решение проблем](docs/TROUBLESHOOTING.ru.md)
- [FAQ](docs/FAQ.ru.md)
- [Security](SECURITY.md)

Не публикуйте URL подписки, UUID, Reality keys или HWID в Issues.
