# Docker Coding Agents

An environment to run coding agents:

- OpenCode
- Claude Code
- Codex

## Quick install

```sh
mkdir -p ~/.local/bin ~/.config
curl -fsSL https://raw.githubusercontent.com/selim13/docker-coding-agents/master/coding-agents-container.sh \
  -o ~/.local/bin/coding-agents-container.sh
chmod +x ~/.local/bin/coding-agents-container.sh
curl -fsSL https://raw.githubusercontent.com/selim13/docker-coding-agents/master/.env.coding-agents.example \
  -o ~/.config/env.coding-agents
```

## Usage

```sh
coding-agents-container.sh codex
```

A new Codex instance will be spawned inside a Docker container, with the
current working directory mounted as its working directory.

By default, the container mounts your Codex, Claude Code, and OpenCode configuration
directories into the container. Use `--volume` or `CODING_AGENTS_VOLUME` to override
the paths.

See `--help` for the invocation options.

## Installed software

- Agents: Codex, Claude Code, OpenCode, and their ACP commands.
- Runtimes: Python, Node.js, Go, PHP, Bun, uv, npm, pnpm, Yarn, pip, and Composer.
- Tools: Git, Docker, Playwright with Chromium, ripgrep, ast-grep, jq, yq, Hadolint, droast, and common
  linters.
- Infrastructure: GitHub and AWS CLIs, s5cmd, rclone, Restic, and database clients.

See the [Dockerfile](Dockerfile) for the complete, versioned list.

## Configuration

The launcher script can be configured with environment variables.
For example, set a binary name for fd: `CODING_AGENTS_FD_BINARY=fdfind`.

Put the variables in either the user's global `~/.config/env.coding-agents`
or the current working directory's `.env.coding-agents`.

Variable values are shell-evaluated, so you can use other
environment variables or execute shell commands there, e.g.:
`CODING_AGENTS_VOLUME=$HOME/.config/gitconfig-llms:/home/ai/.gitconfig`.

Some options, such as volumes, can be repeated with numbered suffixes:

```sh
CODING_AGENTS_VOLUME=$HOME/.config/gitconfig-llms:/home/ai/.gitconfig
CODING_AGENTS_VOLUME_1=$HOME/.cache/ms-playwright:/home/ai/.cache/ms-playwright
CODING_AGENTS_VOLUME_2=$HOME/.cache/uv:/home/ai/.cache/uv
```

All environment variables from the files above will also be passed
to the container. Use them to configure the timezone, proxies, and similar settings.

```sh
TZ=Asia/Singapore
LANG=en_SG.UTF-8
LC_ALL=en_SG.UTF-8
NODE_OPTIONS=--max-old-space-size=4096
```

Some variables can be overridden for each agent type. Currently, these are
`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, and `TZ`:

```sh
CODING_AGENTS_CODEX_HTTP_PROXY=http://10.13.1.35:8014
CODING_AGENTS_CODEX_HTTPS_PROXY=http://10.13.1.35:8014
CODING_AGENTS_CODEX_TZ=Asia/Singapore

CODING_AGENTS_CLAUDE_HTTP_PROXY=http://10.13.1.35:8015
CODING_AGENTS_CLAUDE_HTTPS_PROXY=http://10.13.1.35:8015
CODING_AGENTS_CLAUDE_TZ=Europe/Berlin
```

See `.env.coding-agents.example` for examples.

## AI usage scale

🤖💩 5/5 - pure slop.
