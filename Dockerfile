# syntax=docker/dockerfile:1.25

# https://github.com/anthropics/claude-code/blob/main/.devcontainer/Dockerfile
# https://github.com/openai/codex-universal


FROM debian:trixie-20260623

LABEL org.opencontainers.image.title="coding-agents" \
      org.opencontainers.image.description="Isolated environment for codex, claude and opencode." \
      org.opencontainers.image.authors="Dmitry Seleznev <selim013@gmail.com>" \
      org.opencontainers.image.source="https://github.com/selim13/docker-coding-agents" \
      org.opencontainers.image.url="https://github.com/selim13/docker-coding-agents" \
      org.opencontainers.image.documentation="https://github.com/selim13/docker-coding-agents#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ARG TARGETARCH
ARG TZ
ENV TZ="$TZ"

ARG USERNAME=ai

# Add NodeSource, Docker, and sury.org (PHP) repositories
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg2 lsb-release && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    printf '%s\n' \
      'Types: deb' \
      'URIs: https://download.docker.com/linux/debian' \
      "Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")" \
      'Components: stable' \
      "Architectures: $(dpkg --print-architecture)" \
      'Signed-By: /etc/apt/keyrings/docker.asc' \
      > /etc/apt/sources.list.d/docker.sources && \
    curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb && \
    dpkg -i /tmp/debsuryorg-archive-keyring.deb && \
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' && \
    rm /tmp/debsuryorg-archive-keyring.deb

# Create user (uid/gid 1000)
RUN groupadd --gid 1000 $USERNAME && \
  useradd --uid 1000 --gid $USERNAME --shell /bin/bash --create-home $USERNAME

# Install all packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    7zip \
    aggregate \
    awscli \
    busybox \
    bzip2 \
    default-mysql-client \
    dnsutils \
    docker-ce-cli \
    docker-compose-plugin \
    file \
    fonts-liberation \
    fzf \
    gh \
    git \
    gosu \
    httpie \
    imagemagick \
    iptables \
    ipset \
    iproute2 \
    iputils-ping \
    jq \
    less \
    locales \
    libasound2 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libarchive-tools \
    libimage-exiftool-perl \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libsqlite3-dev \
    libxml2-utils \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxshmfence1 \
    lz4 \
    man-db \
    nano \
    netcat-openbsd \
    nodejs \
    openssh-client \
    pandoc \
    sshfs \
    poppler-utils \
    postgresql-client \
    procps \
    python-is-python3 \
    python3 \
    python3-pip \
    rclone \
    rsync \
    sqlite3 \
    sudo \
    tidy \
    tree \
    unar \
    unzip \
    unrar-free \
    vim \
    wget \
    xauth \
    xclip \
    xmlstarlet \
    xz-utils \
    xsel \
    yamllint \
    yq \
    zip \
    zstd \
    zsh

# renovate: datasource=github-releases depName=hadolint/hadolint extractVersion=^v(?<version>.*)$
ARG HADOLINT_VERSION=2.14.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") hadolint_arch="arm64" ;; \
        "amd64") hadolint_arch="x86_64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${hadolint_arch}" -o /usr/local/bin/hadolint; \
    chmod 0755 /usr/local/bin/hadolint; \
    hadolint --version | grep -F "Haskell Dockerfile Linter ${HADOLINT_VERSION}"

# renovate: datasource=github-releases depName=peak/s5cmd extractVersion=^v(?<version>.*)$
ARG S5CMD_VERSION=2.3.0
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    case "${TARGETARCH}" in \
        "arm64") deb_arch="arm64" ;; \
        "amd64") deb_arch="amd64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    deb="s5cmd_${S5CMD_VERSION}_linux_${deb_arch}.deb"; \
    curl -fsSL "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/${deb}" -o "/tmp/${deb}"; \
    apt-get install -y --no-install-recommends "/tmp/${deb}"; \
    rm "/tmp/${deb}"

# renovate: datasource=github-releases depName=restic/restic extractVersion=^v(?<version>.*)$
ARG RESTIC_VERSION=0.19.1
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") restic_arch="arm64" ;; \
        "amd64") restic_arch="amd64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    archive="restic_${RESTIC_VERSION}_linux_${restic_arch}.bz2"; \
    curl -fsSL "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/${archive}" -o "/tmp/${archive}"; \
    bzip2 -dc "/tmp/${archive}" > /usr/local/bin/restic; \
    chmod 0755 /usr/local/bin/restic; \
    rm "/tmp/${archive}"; \
    restic version | grep -F "restic ${RESTIC_VERSION}"

# Auto-accept first-seen SSH hosts while still rejecting changed host keys.
RUN mkdir -p /etc/ssh/ssh_config.d && \
  printf '%s\n' \
    'Host *' \
    '  StrictHostKeyChecking accept-new' \
    > /etc/ssh/ssh_config.d/90-accept-new-hosts.conf

RUN for locale in en_US.UTF-8 en_SG.UTF-8; do \
      sed -i "s/^# *\(${locale} UTF-8\)/\1/" /etc/locale.gen; \
      grep -qxF "${locale} UTF-8" /etc/locale.gen || echo "${locale} UTF-8" >> /etc/locale.gen; \
    done && \
    locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Ensure user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R $USERNAME:$USERNAME /usr/local/share

# Persist bash history.
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace \
    /mnt/sshfs \
    /home/$USERNAME/.config/opencode \
    /home/$USERNAME/.local/share/opencode \
    /home/$USERNAME/.local/state/opencode \
    /home/$USERNAME/.cache/opencode \
    /home/$USERNAME/.ssh \
    /home/$USERNAME/.claude \
  && chown -R $USERNAME:$USERNAME /workspace \
    /mnt/sshfs \
    /home/$USERNAME/.config \
    /home/$USERNAME/.local \
    /home/$USERNAME/.cache \
    /home/$USERNAME/.ssh \
    /home/$USERNAME/.claude

# Allow the non-root agent user to create SSHFS/FUSE mounts.
RUN if [ -f /etc/fuse.conf ]; then \
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf; \
    grep -qxF user_allow_other /etc/fuse.conf || echo user_allow_other >> /etc/fuse.conf; \
  fi && \
  if getent group fuse >/dev/null; then usermod -aG fuse "$USERNAME"; fi

WORKDIR /workspace

# renovate: datasource=github-releases depName=dandavison/delta
ARG GIT_DELTA_VERSION=0.19.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -o "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# renovate: datasource=github-releases depName=Wilfred/difftastic
ENV DIFFT_VERSION=0.69.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") \
        archive="difft-aarch64-unknown-linux-gnu.tar.gz" ;; \
        "amd64") \
        archive="difft-x86_64-unknown-linux-gnu.tar.gz" ;; \
        *) \
        echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    url="https://github.com/Wilfred/difftastic/releases/download/${DIFFT_VERSION}/${archive}"; \
    tmpdir="$(mktemp -d)"; \
    curl -L "${url}" -o "${tmpdir}/difft.tar.gz"; \
    tar -xzf "${tmpdir}/difft.tar.gz" -C "${tmpdir}"; \
    install -m 0755 "${tmpdir}/difft" /usr/local/bin/difft; \
    rm -rf "${tmpdir}"

# renovate: datasource=github-releases depName=BurntSushi/ripgrep
ENV RIPGREP_VERSION=15.1.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") \
        archive="ripgrep-${RIPGREP_VERSION}-aarch64-unknown-linux-gnu.tar.gz"; \
        dirname="ripgrep-${RIPGREP_VERSION}-aarch64-unknown-linux-gnu" ;; \
        "amd64") \
        archive="ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz"; \
        dirname="ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl" ;; \
        *) \
        echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    url="https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${archive}"; \
    tmpdir="$(mktemp -d)"; \
    curl -L "${url}" -o "${tmpdir}/ripgrep.tar.gz"; \
    tar -xzf "${tmpdir}/ripgrep.tar.gz" -C "${tmpdir}"; \
    install -m 0755 "${tmpdir}/${dirname}/rg" /usr/local/bin/rg; \
    rm -rf "${tmpdir}"

# renovate: datasource=github-releases depName=koalaman/shellcheck extractVersion=^v(?<version>.*)$
ENV SHELLCHECK_VERSION=0.11.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") \
        archive="shellcheck-v${SHELLCHECK_VERSION}.linux.aarch64.tar.gz"; \
        dirname="shellcheck-v${SHELLCHECK_VERSION}" ;; \
        "amd64") \
        archive="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.gz"; \
        dirname="shellcheck-v${SHELLCHECK_VERSION}" ;; \
        *) \
        echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    url="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${archive}"; \
    tmpdir="$(mktemp -d)"; \
    curl -L "${url}" -o "${tmpdir}/shellcheck.tar.gz"; \
    tar -xzf "${tmpdir}/shellcheck.tar.gz" -C "${tmpdir}"; \
    install -m 0755 "${tmpdir}/${dirname}/shellcheck" /usr/local/bin/shellcheck; \
    rm -rf "${tmpdir}"

# renovate: datasource=github-releases depName=casey/just
ENV JUST_VERSION=1.56.0
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") \
        target="aarch64-unknown-linux-musl" ;; \
        "amd64") \
        target="x86_64-unknown-linux-musl" ;; \
        *) \
        echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    archive="just-${JUST_VERSION}-${target}.tar.gz"; \
    url="https://github.com/casey/just/releases/download/${JUST_VERSION}/${archive}"; \
    tmpdir="$(mktemp -d)"; \
    curl -L "${url}" -o "${tmpdir}/just.tar.gz"; \
    tar -xzf "${tmpdir}/just.tar.gz" -C "${tmpdir}"; \
    install -m 0755 "${tmpdir}/just" /usr/local/bin/just; \
    rm -rf "${tmpdir}"

# renovate: datasource=golang-version depName=go
ENV GO_VERSION=1.26.5
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") goarch="arm64" ;; \
        "amd64") goarch="amd64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

# renovate: datasource=github-releases depName=golangci/golangci-lint extractVersion=^v(?<version>.*)$
ENV GOLANGCI_LINT_VERSION=2.12.2
RUN set -eux; \
    case "${TARGETARCH}" in \
        "arm64") goarch="arm64" ;; \
        "amd64") goarch="amd64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${goarch}.tar.gz" -o /tmp/golangci-lint.tar.gz && \
    tar -xzf /tmp/golangci-lint.tar.gz -C /tmp && \
    install -m 0755 "/tmp/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${goarch}/golangci-lint" /usr/local/bin/golangci-lint && \
    rm -rf /tmp/golangci-lint.tar.gz "/tmp/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${goarch}"

# renovate: datasource=pypi depName=playwright
ARG PLAYWRIGHT_VERSION=1.61.0
# renovate: datasource=pypi depName=markdownify
ARG MARKDOWNIFY_VERSION=1.2.3
# renovate: datasource=pypi depName=openpyxl
ARG OPENPYXL_VERSION=3.1.5
# renovate: datasource=pypi depName=pandas
ARG PANDAS_VERSION=3.0.3
RUN pip install --break-system-packages \
  markdownify==${MARKDOWNIFY_VERSION} \
  openpyxl==${OPENPYXL_VERSION} \
  pandas==${PANDAS_VERSION} \
  playwright==${PLAYWRIGHT_VERSION}

### PHP ###
ARG PHP_VERSIONS="8.5 8.4 8.3 8.2 8.1"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    for v in $PHP_VERSIONS; do \
        apt-get install -y --no-install-recommends \
            php${v}-cli \
            php${v}-common \
            php${v}-mbstring \
            php${v}-xml \
            php${v}-curl \
            php${v}-zip \
            php${v}-mysql \
            php${v}-pgsql \
            php${v}-sqlite3 \
            php${v}-gd \
            php${v}-bcmath \
            php${v}-intl; \
    done && \
    update-alternatives --set php /usr/bin/php${PHP_VERSIONS%% *}

# Composer
# renovate: datasource=github-releases depName=composer/composer
ARG COMPOSER_VERSION=2.10.2
RUN curl -fsSL https://getcomposer.org/installer | php -- --version="${COMPOSER_VERSION}" --install-dir=/usr/local/bin --filename=composer

# Enable corepack for pnpm and yarn
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION=11.11.0
# renovate: datasource=npm depName=@yarnpkg/cli-dist
ARG YARN_VERSION=4.17.1
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable && \
    corepack prepare pnpm@${PNPM_VERSION} --activate && pnpm -v && \
    corepack prepare yarn@${YARN_VERSION} --activate && yarn -v

# Set up non-root user
USER $USERNAME

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV NODE_PATH=$NPM_CONFIG_PREFIX/lib/node_modules
ENV COMPOSER_HOME=/home/$USERNAME/.config/composer
ENV PNPM_HOME=/home/$USERNAME/.local/share/pnpm
ENV CODING_AGENTS_PATH=/usr/local/go/bin:/home/$USERNAME/.local/bin:/home/$USERNAME/.config/composer/vendor/bin:/usr/local/share/npm-global/bin:$PNPM_HOME/bin
ENV PATH=$PATH:$CODING_AGENTS_PATH

RUN printf '%s\n' \
    '' \
    '# Keep login-shell PATH in sync with the Docker image environment.' \
    'if [ -n "${CODING_AGENTS_PATH:-}" ]; then' \
    '  old_ifs="$IFS"' \
    '  IFS=:' \
    '  for path_entry in $CODING_AGENTS_PATH; do' \
    '    case ":$PATH:" in' \
    '      *":$path_entry:"*) ;;' \
    '      *) PATH="$PATH:$path_entry" ;;' \
    '    esac' \
    '  done' \
    '  IFS="$old_ifs"' \
    '  unset old_ifs path_entry' \
    '  export PATH' \
    'fi' \
    >> /home/$USERNAME/.profile

# Pin PNPM's store directory to match the mounted host's one
RUN pnpm config set store-dir /home/ai/.local/share/pnpm/store/v${PNPM_VERSION%%.*} --global

# renovate: datasource=github-releases depName=composer-unused/composer-unused
ENV COMPOSER_UNUSED_VERSION=0.9.6
RUN mkdir -p /home/$USERNAME/.local/bin && \
    curl -fsSL "https://github.com/composer-unused/composer-unused/releases/download/${COMPOSER_UNUSED_VERSION}/composer-unused.phar" -o /home/$USERNAME/.local/bin/composer-unused && \
    chmod 0755 /home/$USERNAME/.local/bin/composer-unused

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano
ENV COLORTERM=truecolor

# Default powerline10k theme
# renovate: datasource=github-releases depName=deluan/zsh-in-docker extractVersion=^v(?<version>.*)$
ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# renovate: datasource=docker depName=ghcr.io/astral-sh/uv
ARG UV_VERSION=0.11.28
# renovate: datasource=docker depName=oven/bun
ARG BUN_VERSION=1.3.14
COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /uvx /bin/
COPY --from=oven/bun:${BUN_VERSION} /usr/local/bin/bun /usr/local/bin/bun
# Reduce the verbosity of uv - impacts performance of stdout buffering
ENV UV_NO_PROGRESS=1

# Configure playwright
ENV PLAYWRIGHT_BROWSERS_PATH="/home/$USERNAME/.cache/ms-playwright/"
ARG INSTALL_CHROME=true
RUN mkdir -p /home/$USERNAME/.config/google-chrome/Crashpad
RUN PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install -g playwright@${PLAYWRIGHT_VERSION}
RUN if [ "$INSTALL_CHROME" = "true" ]; then \
    python3 -m playwright install chromium; \
  fi

ENV REBUILD_HERE=1
# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION=1.17.18
# renovate: datasource=npm depName=@openai/codex
ARG CODEX_VERSION=0.144.1
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.206
# renovate: datasource=npm depName=@ast-grep/cli
ARG AST_GREP_CLI_VERSION=0.44.1
# renovate: datasource=npm depName=html-validate
ARG HTML_VALIDATE_VERSION=11.5.5
# renovate: datasource=npm depName=mcpdoc
ARG MCPDOC_VERSION=0.0.1
# renovate: datasource=npm depName=sentry
ARG SENTRY_VERSION=0.38.0
RUN npm install -g \
    opencode-ai@${OPENCODE_VERSION} \
    @openai/codex@${CODEX_VERSION} \
    @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    @ast-grep/cli@${AST_GREP_CLI_VERSION} \
    html-validate@${HTML_VALIDATE_VERSION} \
    mcpdoc@${MCPDOC_VERSION} \
    sentry@${SENTRY_VERSION}

# RUN claude install

USER root

RUN mkdir -p /etc/coding-agents /etc/codex /etc/claude-code && \
  if [ -d "$PLAYWRIGHT_BROWSERS_PATH" ]; then \
    playwright_chrome_path="$(find "$PLAYWRIGHT_BROWSERS_PATH" -type f -path '*/chrome-linux/chrome' -print | sort | tail -n 1)"; \
  fi && \
  playwright_chrome_path="${playwright_chrome_path:-not installed}" && \
  printf '%s\n' \
    'You are running inside an isolated Docker container based on Debian Trixie:' \
    "- default user: ${USERNAME} (uid/gid 1000)" \
    '' \
    '## Key Tools' \
    "- agents: codex ${CODEX_VERSION}, claude-code ${CLAUDE_CODE_VERSION}, opencode ${OPENCODE_VERSION}" \
    '- search/edit: rg, ast-grep, jq, yq, xmlstarlet, difft, delta' \
    '- runtimes: python3, node, go, php, composer, uv, uvx, bun' \
    '- package managers: npm, pnpm, yarn, pip, composer' \
    '- validation: hadolint, shellcheck, yamllint, html-validate' \
    '- infra/storage: docker, docker compose, gh, aws, s5cmd, rclone, restic' \
    '' \
    "- node CLIs: pnpm ${PNPM_VERSION}, yarn ${YARN_VERSION}, bun ${BUN_VERSION}" \
    "- python packages: playwright ${PLAYWRIGHT_VERSION}, pandas ${PANDAS_VERSION}, openpyxl ${OPENPYXL_VERSION}, markdownify ${MARKDOWNIFY_VERSION}" \
    "- browser automation: Playwright Python and npm are pinned together; Chromium is installed by python3 -m playwright install chromium" \
    "- Playwright browsers path: /home/${USERNAME}/.cache/ms-playwright/" \
    "- Playwright Chromium executable: ${playwright_chrome_path}; use it and do not reinstall Chrome or Playwright browsers unless explicitly requested" \
    "- shell/editor: zsh, nano" \
    > /etc/coding-agents/context.md && \
  { \
    printf '%s\n' 'developer_instructions = """'; \
    cat /etc/coding-agents/context.md; \
    printf '%s\n' '"""'; \
  } > /etc/codex/managed_config.toml && \
  cp /etc/coding-agents/context.md /etc/claude-code/CLAUDE.md
