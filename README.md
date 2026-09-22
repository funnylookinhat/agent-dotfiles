# agent-dotfiles

Version-controlled configuration and skills for AI coding agents — currently Claude Code. Keeps
settings and custom skills in one place so they can be installed on any machine with a single
command.

## Structure

```
claude/                           # Maps to ~/.claude/
├── settings.json                 # Claude Code settings and enabled plugins
└── skills/                       # Custom skills loaded by Claude Code
    ├── creating-jira-tickets/    # Draft and create Jira tickets via Atlassian MCP
    ├── gold-star-demerit/        # Track gold stars and demerits across sessions
    └── refining-jira-tickets/    # Review and improve existing Jira tickets

claude-json/                      # Selected keys from ~/.claude.json
└── mcp-servers.json              # User-scope MCP server definitions
```

Each skill directory contains a `SKILL.md` that defines the skill's behavior, and optionally a
`references/` subdirectory with supporting documents the skill loads at runtime.

## Requirements

- [Claude Code](https://claude.ai/code) — the `claude` CLI
- [jq](https://jqlang.org) — used by `install.sh` to parse plugin names from `settings.json`
- [Node.js](https://nodejs.org) (v18+) and npm — used for the formatting toolchain

## Getting started

### 1. Clone the repo

```sh
git clone https://github.com/funnylookinhat/agent-dotfiles.git
cd agent-dotfiles
```

### 2. Install npm dependencies

```sh
npm install
```

Installs [Prettier](https://prettier.io) for markdown formatting and
[Lefthook](https://github.com/evilmartians/lefthook) for the pre-commit hook.

### 3. Install Claude config

```sh
./install.sh
```

Copies `claude/` into `~/.claude/`, installs any plugins listed under `enabledPlugins` in
`settings.json`, and registers the MCP servers from `claude-json/mcp-servers.json` via the Claude
CLI. Servers that are already configured are left alone.

MCP servers still need to be authenticated once per machine with `/mcp` inside Claude Code — only
their definitions are version-controlled, never their credentials.

## Syncing changes

### Backing up from ~/.claude

After editing skills or settings directly in Claude Code, pull those changes back into the repo:

```sh
./backup.sh
```

Copies `~/.claude/settings.json` and `~/.claude/skills/` into the `claude/` tree, extracts the MCP
server definitions from `~/.claude.json` into `claude-json/mcp-servers.json`, and auto-formats all
markdown so the pre-commit hook passes cleanly.

### What is backed up from ~/.claude.json

MCP servers are configured in `~/.claude.json` rather than `settings.json`, so `backup.sh` reads
that file too — but it extracts only the `mcpServers` key. Because it builds the output from that
one key rather than filtering keys out, nothing else in the file can leak into the repo as Claude
Code adds new state over time.

Everything else in `~/.claude.json` is deliberately left out:

- `projects` — per-project session IDs, costs, token counts and absolute paths. It also holds
  `hasTrustDialogAccepted`, and restoring that would pre-trust directories on a new machine.
- `oauthAccount`, `userID`, `machineID` — account and machine identity, repopulated on login.
- `cachedGrowthBookFeatures`, `cachedExperimentData`, `modelAccessCache` and friends — server-side
  caches that churn constantly and mean nothing on another machine.
- `githubRepoPaths`, `skillUsage`, `pluginUsage`, `tipsHistory` and the various `*SeenCount` flags —
  local path mappings, usage telemetry and dismissed-UI state.

The MCP servers listed by `claude mcp list` under `claude.ai <name>` are not in `~/.claude.json` at
all; they sync from your claude.ai account on login. Servers prefixed `plugin:` come from installed
plugins. Neither needs backing up here.

## Development

### Adding a skill

Create a directory under `claude/skills/<skill-name>/` containing at minimum a `SKILL.md`. Add a
`references/` subdirectory for any supporting documents the skill should be able to load.

### Formatting

All markdown files are formatted with Prettier. The pre-commit hook enforces this automatically
after `npm install`.

```sh
npm run format      # Check formatting
npm run format-fix  # Fix formatting
```
