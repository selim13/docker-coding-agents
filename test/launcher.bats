#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    LAUNCHER=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/coding-agents-container.sh
    ORIGINAL_PATH=$PATH
    TEST_HOME=$BATS_TEST_TMPDIR/home
    WORKSPACE=$BATS_TEST_TMPDIR/workspace
    DOCKER_CAPTURE=$BATS_TEST_TMPDIR/docker.args
    mkdir -p "$TEST_HOME" "$WORKSPACE" "$BATS_TEST_TMPDIR/bin"
    ln -s "$BATS_TEST_DIRNAME/fixtures/docker" "$BATS_TEST_TMPDIR/bin/docker"
    export HOME=$TEST_HOME DOCKER_CAPTURE
    PATH=$BATS_TEST_TMPDIR/bin:$ORIGINAL_PATH
    export PATH
    while IFS= read -r name; do unset "$name"; done < <(compgen -A variable CODING_AGENTS_)
    created_x11=0
}

teardown() {
    [ "$created_x11" -eq 0 ] || rmdir /tmp/.X11-unix
}

load_args() {
    docker_args=()
    while IFS= read -r -d '' arg; do docker_args+=("$arg"); done < "$DOCKER_CAPTURE"
}

assert_arg() {
    local wanted=$1 arg
    for arg in "${docker_args[@]}"; do [ "$arg" != "$wanted" ] || return 0; done
    fail "missing Docker argument: $wanted"
}

refute_arg() {
    local unwanted=$1 arg
    for arg in "${docker_args[@]}"; do [ "$arg" != "$unwanted" ] || fail "unexpected Docker argument: $unwanted"; done
}

assert_pair() {
    local first=$1 second=$2 i=0
    while [ "$i" -lt "${#docker_args[@]}" ]; do
        if [ "${docker_args[$i]}" = "$first" ] && [ "${docker_args[$((i + 1))]:-}" = "$second" ]; then return 0; fi
        i=$((i + 1))
    done
    fail "missing Docker argument pair: $first $second"
}

assert_tail() {
    local count=$1 start i=0
    shift
    [ "$count" -eq "$#" ] || fail "assert_tail count does not match its expected arguments"
    start=$((${#docker_args[@]} - count))
    [ "$start" -ge 0 ] || fail "Docker argument list is shorter than expected tail"
    while [ "$i" -lt "$count" ]; do
        [ "${docker_args[$((start + i))]}" = "$1" ] || fail "unexpected Docker tail at $i: ${docker_args[$((start + i))]} != $1"
        shift
        i=$((i + 1))
    done
}

volume_args() {
    volumes=()
    local i=0
    while [ "$i" -lt "${#docker_args[@]}" ]; do
        [ "${docker_args[$i]}" != --volume ] || volumes+=("${docker_args[$((i + 1))]}")
        i=$((i + 1))
    done
}

@test "plain agent preserves arguments and base Docker contract" {
    run "$LAUNCHER" --workspace "$WORKSPACE" codex --full-auto "two words"
    assert_success
    load_args
    assert_tail 3 codex --full-auto "two words"
    assert_arg run
    assert_arg --rm
    assert_arg --interactive
    assert_pair --network host
    assert_pair --workdir "$WORKSPACE"
    refute_arg --tty
}

@test "all command routes have the fixed image command" {
    local route
    for route in \
        'claude|claude' \
        'dsh|dsh' \
        'opencode|opencode' \
        'codex-acp|codex-acp' \
        'claude-acp|claude-agent-acp' \
        'opencode-acp|opencode acp' \
        'shell|zsh' \
        'run|printf ok'; do
        IFS='|' read -r launcher_command expected <<< "$route"
        read -r -a expected_args <<< "$expected"
        if [ "$launcher_command" = run ]; then
            run "$LAUNCHER" --workspace "$WORKSPACE" run printf ok
        else
            run "$LAUNCHER" --workspace "$WORKSPACE" "$launcher_command"
        fi
        assert_success
        load_args
        assert_tail "${#expected_args[@]}" "${expected_args[@]}"
        case "$launcher_command" in *-acp) refute_arg --tty ;; esac
    done
}

@test "nested workdir remains inside the same-path workspace mount" {
    mkdir -p "$WORKSPACE/projects/client"
    run "$LAUNCHER" --workspace "$WORKSPACE" -C projects/client codex
    assert_success
    load_args
    assert_pair --mount "type=bind,src=$WORKSPACE,dst=$WORKSPACE"
    assert_pair --workdir "$WORKSPACE/projects/client"
}

@test "workspace commas are CSV-quoted in Docker mount values" {
    comma_workspace=$BATS_TEST_TMPDIR/work,space
    mkdir -p "$comma_workspace"
    run "$LAUNCHER" --workspace "$comma_workspace" codex
    assert_success
    load_args
    assert_pair --mount "type=bind,src=\"$comma_workspace\",dst=\"$comma_workspace\""
}

@test "default config files load user then project and later scalar wins" {
    mkdir -p "$HOME/.config"
    printf 'CODING_AGENTS_IMAGE=user-image\nFROM_USER=1\n' > "$HOME/.config/env.coding-agents"
    printf 'CODING_AGENTS_IMAGE=project-image\nFROM_PROJECT=1\n' > "$WORKSPACE/.env.coding-agents"
    cd "$WORKSPACE"
    run "$LAUNCHER" codex
    assert_success
    load_args
    assert_pair --env-file "$HOME/.config/env.coding-agents"
    assert_pair --env-file "$WORKSPACE/.env.coding-agents"
    assert_arg project-image
}

@test "selected env files replace defaults and reach Docker unchanged" {
    mkdir -p "$HOME/.config"
    printf 'CODING_AGENTS_IMAGE=wrong\n' > "$HOME/.config/env.coding-agents"
    printf 'CODING_AGENTS_IMAGE=selected\n' > "$WORKSPACE/selected.env"
    cd "$WORKSPACE"
    run "$LAUNCHER" --env selected.env codex
    assert_success
    load_args
    assert_pair --env-file "$WORKSPACE/selected.env"
    refute_arg "$HOME/.config/env.coding-agents"
    assert_arg selected
}

@test "numbered repeatables use numeric order with gaps" {
    printf '%s\n' \
        'CODING_AGENTS_VOLUME_10=ten:/ten' \
        'CODING_AGENTS_VOLUME_2=two:/two' \
        'CODING_AGENTS_VOLUME=base:/base' \
        'CODING_AGENTS_VOLUME_4=four:/four' \
        'CODING_AGENTS_VOLUME_1=one:/one' > "$WORKSPACE/config.env"
    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" codex
    assert_success
    load_args
    volume_args
    count=${#volumes[@]}
    [ "${volumes[$((count - 5))]}" = base:/base ]
    [ "${volumes[$((count - 4))]}" = one:/one ]
    [ "${volumes[$((count - 3))]}" = two:/two ]
    [ "${volumes[$((count - 2))]}" = four:/four ]
    [ "${volumes[$((count - 1))]}" = ten:/ten ]
}

@test "CLI scalar wins over inherited environment and config" {
    printf 'CODING_AGENTS_IMAGE=file-image\n' > "$WORKSPACE/config.env"
    CODING_AGENTS_IMAGE=env-image run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" --image cli-image codex
    assert_success
    load_args
    assert_arg cli-image
    refute_arg env-image
    refute_arg file-image
}

@test "config values use shell evaluation and reach Docker evaluated" {
    marker=$BATS_TEST_TMPDIR/evaluated
    mkdir "$HOME/shared"
    touch "$HOME/gitconfig"
    # Expressions must stay literal for the config loader.
    # shellcheck disable=SC2016
    printf '\n  # comment\nEXPANDED=${HOME}/expanded\nCHAINED="${EXPANDED}/child"\nQUOTED="two words"\nCOMMAND=$(touch %s; printf command-value)\nCODING_AGENTS_VOLUME=${HOME}/gitconfig:/home/ai/.gitconfig\nCODING_AGENTS_VOLUME_1=${HOME}/shared:/shared\n' "$marker" > "$WORKSPACE/config.env"
    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" codex
    assert_success
    [ -e "$marker" ]
    load_args
    assert_pair --env "EXPANDED=$HOME/expanded"
    assert_pair --env "CHAINED=$HOME/expanded/child"
    assert_pair --env 'QUOTED=two words'
    assert_pair --env 'COMMAND=command-value'
    assert_pair --volume "$HOME/gitconfig:/home/ai/.gitconfig"
    assert_pair --volume "$HOME/shared:/shared"
    refute_arg "CODING_AGENTS_VOLUME=$HOME/gitconfig:/home/ai/.gitconfig"
}

@test "malformed duplicate recursive and unknown launcher keys fail before Docker" {
    local value
    for value in 'BARE' 'A=1
A=2' 'CODING_AGENTS_ENV=again' 'CODING_AGENTS_UNKNOWN=1'; do
        printf '%b\n' "$value" > "$WORKSPACE/bad.env"
        rm -f "$DOCKER_CAPTURE"
        run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/bad.env" codex
        assert_failure
        [ ! -e "$DOCKER_CAPTURE" ]
    done
}

@test "per-agent file override applies only to its agent and inherited wins" {
    printf 'CODING_AGENTS_CODEX_HTTP_PROXY=file-proxy\nCODING_AGENTS_CODEX_TZ=UTC\nCODING_AGENTS_DSH_HTTP_PROXY=dsh-proxy\n' > "$WORKSPACE/config.env"
    CODING_AGENTS_CODEX_HTTP_PROXY=env-proxy run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" codex
    assert_success
    load_args
    assert_pair --env HTTP_PROXY=env-proxy
    assert_pair --env TZ=UTC

    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" dsh
    assert_success
    load_args
    assert_pair --env HTTP_PROXY=dsh-proxy

    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" claude
    assert_success
    load_args
    refute_arg HTTP_PROXY=file-proxy
    refute_arg TZ=UTC
}

@test "simple named and bind volumes reach Docker" {
    spec=cache:/cache
    bind_source=$BATS_TEST_TMPDIR/shared
    mkdir "$bind_source"
    run "$LAUNCHER" --workspace "$WORKSPACE" --volume "$spec" --volume "$bind_source:/shared" codex
    assert_success
    load_args
    assert_pair --volume "$spec"
    assert_pair --volume "$bind_source:/shared"

    rm -f "$DOCKER_CAPTURE"
    run "$LAUNCHER" --workspace "$WORKSPACE" --volume "$BATS_TEST_TMPDIR/missing:/missing" codex
    assert_failure
    [ ! -e "$DOCKER_CAPTURE" ]
}

@test "explicit named and bind shadows mount the target" {
    mkdir -p "$WORKSPACE/node_modules" "$WORKSPACE/vendor"
    bind_root=$BATS_TEST_TMPDIR/shadows/vendor
    run "$LAUNCHER" --workspace "$WORKSPACE" \
        --shadow modules:node_modules \
        --shadow "$bind_root:$WORKSPACE/vendor" codex
    assert_success
    [ -d "$bind_root" ]
    load_args
    assert_pair --mount "type=volume,src=modules,dst=$WORKSPACE/node_modules,volume-nocopy"
    assert_pair --mount "type=bind,src=$bind_root,dst=$WORKSPACE/vendor"
    assert_tail 3 1 "$WORKSPACE/node_modules" codex
}

@test "recursive named shadows select outermost matches and are stable" {
    mkdir -p "$WORKSPACE/node_modules/pkg/node_modules" "$WORKSPACE/projects/client/node_modules"
    printf 'CODING_AGENTS_FD_BINARY=missing-fd\nCODING_AGENTS_SHADOW_ALL=node_modules\n' > "$WORKSPACE/config.env"
    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" codex
    assert_success
    first=$(tr '\0' '\n' < "$DOCKER_CAPTURE" | grep 'type=volume,src=coding-agents-shadow-' | sort)
    [ "$(printf '%s\n' "$first" | grep -c .)" -eq 2 ]
    [[ "$first" == *"dst=$WORKSPACE/node_modules,"* ]]
    [[ "$first" == *"dst=$WORKSPACE/projects/client/node_modules,"* ]]
    [[ "$first" != *"pkg/node_modules"* ]]
    CODING_AGENTS_FD_BINARY=missing-fd CODING_AGENTS_SHADOW_ALL=node_modules run "$LAUNCHER" --workspace "$WORKSPACE" codex
    assert_success
    second=$(tr '\0' '\n' < "$DOCKER_CAPTURE" | grep 'type=volume,src=coding-agents-shadow-' | sort)
    [ "$first" = "$second" ]
}

@test "recursive shadows use configured fd binary and CLI overrides its environment" {
    mkdir -p "$WORKSPACE/node_modules/pkg/node_modules" "$WORKSPACE/projects/client/node_modules"
    storage=$WORKSPACE/.cache/coding-agents
    mkdir -p "$storage/nested/node_modules"
    fake_fd=$BATS_TEST_TMPDIR/bin/fdfind-test
    ln -s "$BATS_TEST_DIRNAME/fixtures/fd" "$fake_fd"
    export FD_CAPTURE=$BATS_TEST_TMPDIR/fd.args

    CODING_AGENTS_FD_BINARY=missing-fd run "$LAUNCHER" --workspace "$WORKSPACE" \
        --fd-binary fdfind-test --shadow-all "$storage:node_modules" codex
    assert_success
    [ -s "$FD_CAPTURE" ]
    fd_args=$(tr '\0' '\n' < "$FD_CAPTURE")
    [[ "$fd_args" == *"--prune"* ]]
    [[ "$fd_args" == *"--exclude"* ]]
    [[ "$fd_args" == *"/.cache/coding-agents"* ]]
    [[ "$fd_args" == *"node_modules"* ]]
    load_args
    mounts=$(tr '\0' '\n' < "$DOCKER_CAPTURE" | grep "type=bind,src=$storage" | sort)
    [ "$(printf '%s\n' "$mounts" | grep -c .)" -eq 2 ]
    [[ "$mounts" != *"nested/node_modules"* ]]
}

@test "recursive bind shadows mirror relative targets and prune storage" {
    mkdir -p "$WORKSPACE/node_modules" "$WORKSPACE/projects/client/node_modules"
    root=$WORKSPACE/.agent-shadowing
    mkdir -p "$root/ignored/node_modules"
    run "$LAUNCHER" --workspace "$WORKSPACE" --shadow-all "$root:node_modules" codex
    assert_success
    [ -d "$root/node_modules" ]
    [ -d "$root/projects/client/node_modules" ]
    load_args
    assert_pair --mount "type=bind,src=$root/node_modules,dst=$WORKSPACE/node_modules"
    assert_pair --mount "type=bind,src=$root/projects/client/node_modules,dst=$WORKSPACE/projects/client/node_modules"
    refute_arg "type=bind,src=$root/.agent-shadowing/ignored/node_modules,dst=$root/ignored/node_modules"
}

@test "destination conflicts and path traversal fail before Docker" {
    mkdir -p "$WORKSPACE/node_modules" "$BATS_TEST_TMPDIR/outside"
    run "$LAUNCHER" --workspace "$WORKSPACE" --shadow one:node_modules --shadow two:node_modules codex
    assert_failure
    [ ! -e "$DOCKER_CAPTURE" ]
    run "$LAUNCHER" --workspace "$WORKSPACE" -C "$BATS_TEST_TMPDIR/outside" codex
    assert_failure
    [ ! -e "$DOCKER_CAPTURE" ]
    run "$LAUNCHER" --workspace "$WORKSPACE" --shadow one:"$BATS_TEST_TMPDIR/outside" codex
    assert_failure
    [ ! -e "$DOCKER_CAPTURE" ]
}

@test "volume cannot duplicate a managed destination" {
    mkdir -p "$WORKSPACE/node_modules" "$BATS_TEST_TMPDIR/other"
    run "$LAUNCHER" --workspace "$WORKSPACE" \
        --shadow modules:node_modules \
        --volume "$BATS_TEST_TMPDIR/other:$WORKSPACE/node_modules" codex
    assert_failure
    [ ! -e "$DOCKER_CAPTURE" ]
}

@test "missing optional fixed mounts are skipped and not created" {
    run "$LAUNCHER" --workspace "$WORKSPACE" codex
    assert_success
    [ ! -e "$HOME/.claude.json" ]
    [ ! -e "$HOME/.config/gitconfig-llms" ]
    load_args
    refute_arg "$HOME/.claude.json:/home/ai/.claude.json"
}

@test "only agent state is mounted by default and volumes override it" {
    mkdir -p "$HOME/.config/opencode" "$HOME/.codex" "$HOME/.dsh" "$HOME/.agents" "$HOME/.cache/uv"
    run "$LAUNCHER" --workspace "$WORKSPACE" codex
    assert_success
    load_args
    assert_pair --volume "$HOME/.config/opencode:/home/ai/.config/opencode"
    assert_pair --volume "$HOME/.config/opencode:$HOME/.config/opencode"
    assert_pair --volume "$HOME/.codex:/home/ai/.codex"
    assert_pair --volume "$HOME/.dsh:/home/ai/.dsh"
    assert_pair --volume "$HOME/.dsh:$HOME/.dsh"
    assert_pair --volume "$HOME/.agents:/home/ai/.agents"
    assert_pair --volume "$HOME/.agents:$HOME/.agents"
    refute_arg "$HOME/.cache/uv:/home/ai/.cache/uv"

    printf 'CODING_AGENTS_VOLUME=other-dsh:/home/ai/.dsh\n' > "$WORKSPACE/config.env"
    run "$LAUNCHER" --workspace "$WORKSPACE" --env "$WORKSPACE/config.env" codex
    assert_success
    load_args
    assert_pair --volume other-dsh:/home/ai/.dsh
    refute_arg "$HOME/.dsh:/home/ai/.dsh"
}

@test "X11 requires display socket and authority and no-x11 wins" {
    if [ ! -d /tmp/.X11-unix ]; then mkdir /tmp/.X11-unix; created_x11=1; fi
    authority=$BATS_TEST_TMPDIR/Xauthority
    : > "$authority"
    DISPLAY=:9 XAUTHORITY=$authority run "$LAUNCHER" --workspace "$WORKSPACE" codex
    assert_success
    load_args
    assert_pair --env DISPLAY=:9
    assert_pair --env XAUTHORITY=/home/ai/.Xauthority

    DISPLAY=:9 XAUTHORITY=$authority run "$LAUNCHER" --workspace "$WORKSPACE" --no-x11 codex
    assert_success
    load_args
    refute_arg DISPLAY=:9
}

@test "pull reaches fake Docker with selected image" {
    run "$LAUNCHER" --image test-image pull
    assert_success
    load_args
    [ "${#docker_args[@]}" -eq 2 ]
    [ "${docker_args[0]}" = pull ]
    [ "${docker_args[1]}" = test-image ]
    assert_output 'To update launcher, use update.'
}

@test "update aliases replace the invoked launcher from master" {
    local command copy replacement
    replacement=$BATS_TEST_TMPDIR/replacement
    printf '#!/usr/bin/env bash\nprintf updated\n' > "$replacement"
    for command in update up; do
        copy=$BATS_TEST_TMPDIR/launcher-$command
        cp "$LAUNCHER" "$copy"
        curl() {
            [ "$1" = -fsSL ]
            [ "$2" = https://raw.githubusercontent.com/selim13/docker-coding-agents/master/coding-agents-container.sh ]
            [ "$3" = -o ]
            cp "$replacement" "$4"
        }
        export -f curl
        export replacement
        run "$copy" "$command"
        assert_success
        assert_output 'To update image, use pull.'
        cmp "$replacement" "$copy"
        [ -x "$copy" ]
    done
}

@test "dry-run prints a reusable command without Docker or filesystem changes" {
    source=$BATS_TEST_TMPDIR/not-created
    mkdir -p "$WORKSPACE/node_modules"
    rm -f "$DOCKER_CAPTURE"
    run "$LAUNCHER" --workspace "$WORKSPACE" --shadow "$source:node_modules" --dry-run codex "two words"
    assert_success
    assert_output --partial $'docker run \\\n  --rm \\\n  --interactive \\\n  --network host'
    assert_output --partial $'\n  --mount '
    assert_output --partial $'\n  --workdir '
    assert_output --partial 'two\ words'
    [ ! -e "$DOCKER_CAPTURE" ]
    [ ! -e "$source" ]

    run "$LAUNCHER" --image test-image --dry-run pull
    assert_success
    assert_output 'docker pull test-image'
    [ ! -e "$DOCKER_CAPTURE" ]
}
