# Telegram Desktop + AUTO Xray

Для Telegram не нужен отдельный ручной SOCKS-прокси.

Откройте:

**Telegram → Settings → Advanced → Connection type → Proxy settings**

Выберите:

**Use system proxy settings**

После этого:

- когда AUTO Xray включен, Telegram использует AUTO Xray;
- когда AUTO Xray выключен, Telegram использует обычные системные настройки сети.

Если раньше использовался V2RayXS, запись:

```text
SOCKS5 127.0.0.1:1081
```

можно удалить из списка Telegram.

AUTO Xray использует собственный локальный SOCKS:

```text
127.0.0.1:2081
```

но в Telegram вручную его вводить не требуется, если выбран **Use system proxy settings**.
