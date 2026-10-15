# MAX Messenger Agent Skill

**Русский** · [English](README.en.md)

[![Agent Skills](https://img.shields.io/badge/Agent_Skills-SKILL.md-2f6feb)](https://agentskills.io)
[![License](https://img.shields.io/badge/license-Apache--2.0-lightgrey)](LICENSE)

MAX быстро меняется, AI-агентам нужен актуальный контекст, чтобы писать рабочий код.

MAX Messenger Agent Skill — это набор навыков, благодаря которым AI-агенты разрабатывают ботов и мини-приложения
для мессенджера [MAX](https://max.ru):

- Bot API
- Вебхуки
- Библиотеки для настройки сценариев бота на Go и TypeScript
- Библиотека для работы с мини-приложениями MAX Bridge
- Библиотека MAX UI `@maxhub/max-ui`

MAX Messenger Agent Skill работает в Claude Code, Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot, Cline,
Claude Desktop и в любом агенте, который читает формат [Agent Skills](https://agentskills.io).

## Установка MAX Messenger Agent Skill

Установите навыки всем агентам на вашем устройстве из репозитория max-agents-skill:

- В терминале macOS или Linux, в WSL или Git Bash:

  ```bash
  curl -fsSLO https://raw.githubusercontent.com/max-messenger/max-agents-skill/main/install.sh && bash install.sh
  ```

- С помощью пакетного менеджера [skills CLI](https://github.com/vercel-labs/skills):

  ```bash
  npx skills add max-messenger/max-agents-skill -g
  ```

### Процесс установки навыков для агентов

| Агент | Как устанавливаются навыки |
|-------|----------------------------|
| Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot | Скрипт `install.sh` автоматически копирует файлы навыка в общую папку `~/.agents/skills`, которую эти агенты читают сами |
| Claude Code | Скрипт `install.sh` создаёт виртуальный ярлык-указатель (симлинк) в системной папке агента `~/.claude/skills`. Когда агент обращается к этой папке, по ярлыку он сразу находит навык |
| Cline | Скрипт `install.sh` создаёт виртуальный ярлык-указатель (симлинк) в системной папке агента `~/.cline/skills`. Когда агент обращается к этой папке, по ярлыку он сразу находит навык |
| Claude Desktop, Cowork, claude.ai | Скрипт `install.sh` автоматически упаковывает файлы навыка в архив `max-messenger-skill.zip` и помещает его в папку «Загрузки». Пользователь вручную загружает этот архив через [настройки Skills](https://support.claude.com/en/articles/12512180-using-skills-in-claude) |
| Другой агент | Скопируйте папку с навыком в каталог скиллов агента и дайте агенту команду: установи скилл «MAX Messenger» из файла `~/.agents/skills/max-messenger/INSTALL.md` — прочитай инструкции и следуй им без вопросов |

Если агент не находит навык после установки, дайте ему команду:

```
Установи скилл «MAX Messenger» из файла ~/.agents/skills/max-messenger/INSTALL.md — прочитай инструкции и следуй им без вопросов.
```

## Управление и настройка

### Обновление

Для обновления навыка снова запустите скрипт:

```bash
bash install.sh
```

Резервная копия предыдущей версии создастся автоматически и сохранится в папке `~/.cache/agent-skills-backup/`.

### Удаление

Для удаления навыка выполните команду:

```bash
bash install.sh --uninstall
```

### Дополнительные настройки

- Для выбора версии выполните команду:

  ```bash
  bash install.sh --ref v1.0.1
  # По умолчанию устанавливается версия из главной ветки main
  ```

- Для установки из локальной копии выполните команду:

  ```bash
  bash install.sh --local <папка>
  # Используется, если скилл уже лежит у вас на диске.
  # Из клона репозитория GitHub скрипт ставит локальную копию сам, без этого параметра
  ```

- Чтобы скрипт работал только с общей папкой `~/.agents/skills` и не создавал виртуальные ярлыки, выполните команду:

  ```bash
  bash install.sh --no-links
  ```

- Чтобы не создавать `.zip`-архив для Claude-приложений, выполните команду:

  ```bash
  bash install.sh --no-zip
  ```

- Если GitHub недоступен из вашей сети или заблокирован, выполните команду:

  ```bash
  MAX_SKILL_TARBALL_URL=<ссылка на зеркало .tar.gz> bash install.sh
  # Вместо <ссылка на зеркало .tar.gz> укажите адрес альтернативного сайта
  # или локального сервера, где находится архив
  ```

При установке в каталог скиллов попадают только файлы `SKILL.md`, `INSTALL.md` и папка `references/`.

## Примеры запросов к агенту

Скилл активируется, когда агент получает запрос, связанный с MAX:

- «Напиши бота для MAX на Go, который отвечает на /start и показывает inline-клавиатуру»
- «Подними вебхук для бота MAX на TypeScript и проверь секрет»
- «Мини-приложение MAX на React с max-ui: получи номер телефона и проверь initData на бэкенде»
- «Бот падает с x509: certificate signed by unknown authority в Docker — почини»
- «Разбей длинный текст на сообщения MAX с учётом лимита 4000 символов»

## Область применения скилла

- **Bot API** — все методы, включая комментарии, ответы на callback, закрепы, участников и админов;
  загрузка медиа, лимиты, ошибки, датированные изменения платформы
- **TLS** — корневой сертификат Минцифры для Go, Node, Docker, curl, Python
- **Безопасность** — секрет вебхука, `initData`, хэши телефона и контакта; код на Go и TypeScript
- **Библиотеки** — `max-bot-api-client-go` v2, `maxbot`, `@maxhub/max-bot-api`, MAX Bridge (`window.WebApp`), `@maxhub/max-ui`
- **Паттерны разработки** — rate limit, повторные запросы при ошибках, учёт чатов, отложенная отправка,
  разбиение текста, идемпотентность

## Архитектура

### Структура репозитория max-agents-skill

```
max-agents-skill/
├── SKILL.md                     ядро: ограничения, выбор стека, минимальные боты, частые ошибки
├── INSTALL.md                   инструкция по установке для агента
├── install.sh                   установщик
└── references/
    ├── bot-api.md               методы, загрузки, лимиты, ошибки
    ├── objects-and-updates.md   сообщения, вложения, кнопки, типы апдейтов
    ├── formatting.md            поддерживаемые markdown и html
    ├── tls-trust.md             сертификат Минцифры
    ├── webhooks-and-security.md вебхуки, initData, хэши
    ├── go-client.md             официальный Go-клиент
    ├── go-maxbot.md             фреймворк maxbot
    ├── ts-client.md             @maxhub/max-bot-api
    ├── mini-apps-bridge.md      MAX Bridge
    ├── max-ui.md                @maxhub/max-ui
    ├── patterns.md              паттерны
    └── sources.md               источники и версии
```

## Версии и источники

Сверено с официальной документацией и исходниками библиотек **21.09.2026**.

Код компилируется (`go vet`, `tsc --strict`) на следующих версиях:

| Пакет | Версия |
|-------|--------|
| `github.com/max-messenger/max-bot-api-client-go/v2` | v2.4.0 |
| `github.com/max-messenger/maxbot` | v1.1.0 (Go ≥ 1.26) |
| `@maxhub/max-bot-api` | 0.3.1 (Node ≥ 20.19, ESM) |
| `@maxhub/max-ui` | 0.5.0 (React 19.2.8) |

Если скилл расходится с источником или информация устарела, ориентируйтесь на информацию:

- [dev.max.ru/docs-api](https://dev.max.ru/docs-api)
- [MAX Bridge](https://dev.max.ru/docs/webapps/bridge)
- [api-schema](https://github.com/max-messenger/api-schema)
- [Go-клиент](https://github.com/max-messenger/max-bot-api-client-go)
- [maxbot](https://github.com/max-messenger/maxbot)
- [TS-клиент](https://github.com/max-messenger/max-bot-api-client-ts)
- [max-ui](https://github.com/max-messenger/max-ui)

Порядок приоритета источников — в [`references/sources.md`](references/sources.md).

## Лицензия

[Apache-2.0](LICENSE)
