#!/usr/bin/env -S just --justfile

# vim: set tabstop=4 shiftwidth=4 expandtab :

set shell := ["bash", "-euo", "pipefail", "-c"]

service := "coding-agents"
claude_proxy := "http://10.13.1.35:8014"
codex_proxy := "http://10.13.1.35:8014"
no_proxy := "localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,fc00::/7,fe80::/10,host.docker.internal,.lan,.local,.ru,.su"
timezone := "Asia/Singapore"
locale := "en_SG.UTF-8"

default:
    @just --justfile {{ justfile() }} --list --unsorted

docker-compose args='':
    compose_dir="$(dirname "$(readlink -f "{{ justfile() }}")")"; \
    compose_files=(-f "$compose_dir/docker-compose.yml"); \
    if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then \
        compose_files+=(-f "$compose_dir/docker-compose.x11.yml"); \
    fi; \
    docker compose "${compose_files[@]}" {{ args }}

test:
    echo {{ invocation_directory_native() }}

build:
    just --justfile {{ justfile() }} docker-compose build 

rm:
    just --justfile {{ justfile() }} docker-compose 'rm coding-agents'

run *cmd="":
    just --justfile {{ justfile() }} docker-compose 'run --rm {{ service }} {{ cmd }}'

shell:
    just --justfile {{ justfile() }} run zsh

opencode *args="":
    TARGET_DIR="{{ invocation_directory_native() }}" just --justfile {{ justfile() }} run 'opencode {{ args }}'

opencode-acp:
    TARGET_DIR="{{ invocation_directory_native() }}" just --justfile {{ justfile() }} run 'opencode acp'

claude *args="":
    TARGET_DIR="{{ invocation_directory_native() }}" \
    HTTP_PROXY="{{ claude_proxy }}" \
    HTTPS_PROXY="{{ claude_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} run 'claude {{ args }}'

claude-acp:
    TARGET_DIR="{{ invocation_directory_native() }}" \
    HTTP_PROXY="{{ claude_proxy }}" \
    HTTPS_PROXY="{{ claude_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} docker-compose 'run --rm -T {{ service }} claude-agent-acp'

codex *args="":
    TARGET_DIR="{{ invocation_directory_native() }}" \
    HTTP_PROXY="{{ codex_proxy }}" \
    HTTPS_PROXY="{{ codex_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} run 'codex {{ args }}'

codex-acp:
    TARGET_DIR="{{ invocation_directory_native() }}" \
    HTTP_PROXY="{{ codex_proxy }}" \
    HTTPS_PROXY="{{ codex_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} docker-compose 'run --rm -T {{ service }} codex-acp'

claude-at workdir *args="":
    workspace_dir="{{ invocation_directory_native() }}"; \
    target_dir="$(realpath -m "$workspace_dir/{{ workdir }}")"; \
    case "$target_dir/" in \
        "$workspace_dir"/*) ;; \
        *) echo "claude-at workdir must be inside $workspace_dir: $target_dir" >&2; exit 1 ;; \
    esac; \
    WORKSPACE_DIR="$workspace_dir" \
    TARGET_DIR="$target_dir" \
    HTTP_PROXY="{{ claude_proxy }}" \
    HTTPS_PROXY="{{ claude_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} run 'claude {{ args }}'

codex-at workdir *args="":
    workspace_dir="{{ invocation_directory_native() }}"; \
    target_dir="$(realpath -m "$workspace_dir/{{ workdir }}")"; \
    case "$target_dir/" in \
        "$workspace_dir"/*) ;; \
        *) echo "codex-at workdir must be inside $workspace_dir: $target_dir" >&2; exit 1 ;; \
    esac; \
    WORKSPACE_DIR="$workspace_dir" \
    TARGET_DIR="$target_dir" \
    HTTP_PROXY="{{ codex_proxy }}" \
    HTTPS_PROXY="{{ codex_proxy }}" \
    NO_PROXY="{{ no_proxy }}" \
    TZ="{{ timezone }}" \
    LANG="{{ locale }}" \
    LC_ALL="{{ locale }}" \
    just --justfile {{ justfile() }} run 'codex {{ args }}'
