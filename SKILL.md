# Container Environment

You are running inside an isolated Docker container based on Debian Trixie.

User: `ai` (uid 1000), shell: zsh (oh-my-zsh with powerlevel10k).

## Languages & Runtimes

- **Node.js** 24.x (npm, pnpm, yarn, bun, corepack enabled)
- **Go** 1.25.1 (golangci-lint available)
- **Python** 3 (pip, uv, uvx; packages: pandas, openpyxl, markdownify)
- **PHP** 8.1, 8.2, 8.3, 8.4, 8.5 (default: 8.5; Composer installed)

## Key Tools

- **git**, **gh** (GitHub CLI), **git-delta**, **difftastic**
- **ripgrep** (`rg`), **fzf**, **jq**, **yq**, **ast-grep** (`sg`)
- **file**, **tree**, **rsync**, **zip**, **unzip**
- **ImageMagick** (`magick`, `identify`), **exiftool**
- **poppler-utils** (`pdfinfo`, `pdftotext`, `pdftoppm`)
- **tidy**, **html-validate**
- **just** (command runner)
- **shellcheck**
- **sqlite3**, **postgresql-client**, **mysql-client**
- **PHPStan**, **composer-unused**
- **nano** (default `$EDITOR`), **vim**
- **wget**, **curl**, **HTTPie**, **openssh-client**
- **sshfs** (FUSE enabled in Docker Compose; default mount root: `/mnt/sshfs`)

## Browser Testing

Playwright with Chromium is pre-installed from the Node package pinned to **1.58.2**. Python Playwright is pinned to **1.58.0**, the matching PyPI patch available for this minor release. When adding Node Playwright to a project, match the browser install version:

```bash
pnpm -D install playwright@1.58.2
# or
npx playwright@1.58.2 install --with-deps
```

Browsers path: `$PLAYWRIGHT_BROWSERS_PATH` = `/home/ai/.cache/ms-playwright/`
