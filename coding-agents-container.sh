#!/usr/bin/env bash

set -eo pipefail

readonly PROGRAM=${0##*/}
readonly DEFAULT_IMAGE=ghcr.io/selim13/coding-agents:latest
readonly UPDATE_URL=https://raw.githubusercontent.com/selim13/docker-coding-agents/master/coding-agents-container.sh
INVOCATION_DIR=$(pwd -P)
readonly INVOCATION_DIR
: "${HOME:?HOME must be set}"

die() {
    printf '%s: %s\n' "$PROGRAM" "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  $PROGRAM [OPTIONS] COMMAND [ARG...]

Commands:
  codex | claude | opencode
  codex-acp | claude-acp | opencode-acp
  shell                     run zsh
  run COMMAND [ARG...]      run an arbitrary image command
  pull                      pull the configured image
  update | up               replace launcher from master

Options:
  --workspace DIR           mounted workspace root; default: current directory
  -C, --workdir DIR         working directory inside the workspace
  --env FILE                shared launcher/container env file; repeatable
  --volume SOURCE:TARGET    bind path or named volume; repeatable
  --shadow SOURCE:TARGET    exact bind or named-volume shadow; repeatable
  --shadow-all VALUE        recursive BASENAME or ROOT:BASENAME; repeatable
  --fd-binary NAME          fd binary for recursive discovery; default: fd
  --image IMAGE             image override
  --no-x11                  disable automatic X11 integration
  --dry-run                 print the Docker command without running it
  -h, --help
EOF
}

canonical_dir() {
    [ -d "$1" ] || return 1
    (cd -P -- "$1" && pwd -P)
}

canonical_file() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    local dir base
    dir=${1%/*}
    base=${1##*/}
    [ "$dir" != "$1" ] || dir=.
    dir=$(canonical_dir "$dir") || return 1
    printf '%s/%s\n' "${dir%/}" "$base"
}

inside() {
    [ "$1" = / ] || [ "$2" = "$1" ] || [ "${2#"$1"/}" != "$2" ]
}

overlap() {
    inside "$1" "$2" || inside "$2" "$1"
}

mount_value() {
    MOUNT_VALUE=$1
    case "$MOUNT_VALUE" in
        *[,\"]*)
            MOUNT_VALUE=${MOUNT_VALUE//\"/\"\"}
            MOUNT_VALUE=\"$MOUNT_VALUE\"
            ;;
    esac
}

# Canonicalize a path whose final components may not exist. The existing
# ancestor is resolved physically; the missing tail is normalized lexically.
canonical_maybe_missing() {
    local path=$1 parent tail='' component i
    case "$path" in
        /*) ;;
        *) path=$INVOCATION_DIR/$path ;;
    esac
    parent=$path
    while [ ! -d "$parent" ]; do
        [ "$parent" != / ] || return 1
        component=${parent##*/}
        tail=$component${tail:+/$tail}
        parent=${parent%/*}
        [ -n "$parent" ] || parent=/
    done
    parent=$(canonical_dir "$parent") || return 1
    path=${parent%/}${tail:+/$tail}

    local old_ifs=$IFS
    local -a parts=() normalized=()
    IFS=/
    read -r -a parts <<< "$path"
    IFS=$old_ifs
    for component in "${parts[@]}"; do
        case "$component" in
            ''|.) ;;
            ..)
                i=${#normalized[@]}
                [ "$i" -eq 0 ] || unset 'normalized[i-1]'
                ;;
            *) normalized+=("$component") ;;
        esac
    done
    path=
    for component in "${normalized[@]}"; do path=$path/$component; done
    printf '%s\n' "${path:-/}"
}

add_unique() {
    local value=$1 existing
    shift
    for existing in "$@"; do [ "$existing" != "$value" ] || return 1; done
    return 0
}

print_command() {
    local arg first=1
    for arg in "$@"; do
        if [ "$first" -eq 1 ]; then
            first=0
        else
            case "$arg" in --*) printf ' \\\n  ' ;; *) printf ' ' ;; esac
        fi
        printf '%q' "$arg"
    done
    printf '\n'
}

# Capture inherited launcher variables before creating any similarly named
# shell variables. compgen is available in Bash 3.2 and preserves empty values.
inherited_keys=()
inherited_values=()
while IFS= read -r inherited_name; do
    case "$inherited_name" in
        CODING_AGENTS_*)
            inherited_keys+=("$inherited_name")
            inherited_values+=("${!inherited_name}")
            ;;
    esac
done < <(compgen -v)

valid_numbered_key() {
    local key=$1 base suffix number
    for base in CODING_AGENTS_ENV CODING_AGENTS_VOLUME CODING_AGENTS_SHADOW CODING_AGENTS_SHADOW_ALL; do
        case "$key" in
            "$base") return 0 ;;
            "$base"_*)
                suffix=${key#"$base"_}
                case "$suffix" in ''|*[!0-9]*) continue ;; esac
                number=$suffix
                while [ "${number#0}" != "$number" ]; do number=${number#0}; done
                [ -n "$number" ] || number=0
                [ "$number" -gt 0 ] || continue
                return 0
                ;;
        esac
    done
    return 1
}

known_key() {
    case "$1" in
        CODING_AGENTS_WORKSPACE|CODING_AGENTS_WORKDIR|CODING_AGENTS_FD_BINARY|CODING_AGENTS_IMAGE|CODING_AGENTS_NO_X11|CODING_AGENTS_DRY_RUN) return 0 ;;
        CODING_AGENTS_CODEX_HTTP_PROXY|CODING_AGENTS_CODEX_HTTPS_PROXY|CODING_AGENTS_CODEX_NO_PROXY|CODING_AGENTS_CODEX_TZ) return 0 ;;
        CODING_AGENTS_CLAUDE_HTTP_PROXY|CODING_AGENTS_CLAUDE_HTTPS_PROXY|CODING_AGENTS_CLAUDE_NO_PROXY|CODING_AGENTS_CLAUDE_TZ) return 0 ;;
        CODING_AGENTS_OPENCODE_HTTP_PROXY|CODING_AGENTS_OPENCODE_HTTPS_PROXY|CODING_AGENTS_OPENCODE_NO_PROXY|CODING_AGENTS_OPENCODE_TZ) return 0 ;;
    esac
    valid_numbered_key "$1"
}

for inherited_name in "${inherited_keys[@]}"; do
    known_key "$inherited_name" || die "unknown inherited launcher variable: $inherited_name"
done

inherited_get() {
    local wanted=$1 i
    FOUND=0
    VALUE=
    i=0
    while [ "$i" -lt "${#inherited_keys[@]}" ]; do
        if [ "${inherited_keys[$i]}" = "$wanted" ]; then
            FOUND=1
            VALUE=${inherited_values[$i]}
            return
        fi
        i=$((i + 1))
    done
}

inherited_repeat() {
    local base=$1 i key suffix number j
    REPEAT_VALUES=()
    repeat_numbers=()
    repeat_values=()
    inherited_get "$base"
    [ "$FOUND" -eq 0 ] || REPEAT_VALUES+=("$VALUE")
    i=0
    while [ "$i" -lt "${#inherited_keys[@]}" ]; do
        key=${inherited_keys[$i]}
        case "$key" in
            "$base"_*)
                suffix=${key#"$base"_}
                case "$suffix" in ''|*[!0-9]*) i=$((i + 1)); continue ;; esac
                number=$suffix
                while [ "${number#0}" != "$number" ]; do number=${number#0}; done
                [ -n "$number" ] || number=0
                if [ "$number" -le 0 ]; then i=$((i + 1)); continue; fi
                j=${#repeat_numbers[@]}
                while [ "$j" -gt 0 ] && [ "${repeat_numbers[$((j - 1))]}" -gt "$number" ]; do
                    repeat_numbers[j]=${repeat_numbers[j-1]}
                    repeat_values[j]=${repeat_values[j-1]}
                    j=$((j - 1))
                done
                repeat_numbers[j]=$number
                repeat_values[j]=${inherited_values[i]}
                ;;
        esac
        i=$((i + 1))
    done
    for VALUE in "${repeat_values[@]}"; do REPEAT_VALUES+=("$VALUE"); done
}

cli_env_files=()
cli_volumes=()
cli_shadows=()
cli_shadow_all=()
cli_workspace_set=0
cli_workdir_set=0
cli_fd_binary_set=0
cli_image_set=0
cli_no_x11_set=0
cli_dry_run_set=0
cli_workspace=
cli_workdir=
cli_fd_binary=
cli_image=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace|-C|--workdir|--env|--volume|--shadow|--shadow-all|--fd-binary|--image)
            option=$1
            [ "$#" -ge 2 ] || die "$option requires a value"
            value=$2
            shift 2
            case "$option" in
                --workspace) cli_workspace_set=1; cli_workspace=$value ;;
                -C|--workdir) cli_workdir_set=1; cli_workdir=$value ;;
                --env) cli_env_files+=("$value") ;;
                --volume) cli_volumes+=("$value") ;;
                --shadow) cli_shadows+=("$value") ;;
                --shadow-all) cli_shadow_all+=("$value") ;;
                --fd-binary) cli_fd_binary_set=1; cli_fd_binary=$value ;;
                --image) cli_image_set=1; cli_image=$value ;;
            esac
            ;;
        --no-x11) cli_no_x11_set=1; shift ;;
        --dry-run) cli_dry_run_set=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) die "unknown option: $1" ;;
        *) break ;;
    esac
done
[ "$#" -gt 0 ] || { usage >&2; exit 1; }
command_name=$1
shift
command_args=("$@")

case "$command_name" in
    update|up)
        [ "${#command_args[@]}" -eq 0 ] || die "$command_name does not accept arguments"
        launcher=$(canonical_file "$0") || die "launcher is not a readable regular file: $0"
        temporary=$(mktemp "$launcher.XXXXXX") || die "cannot create launcher update beside: $launcher"
        trap 'rm -f -- "$temporary"' EXIT
        curl -fsSL "$UPDATE_URL" -o "$temporary"
        bash -n "$temporary"
        chmod 0755 "$temporary"
        mv -- "$temporary" "$launcher"
        printf 'To update image, use pull.\n'
        exit 0
        ;;
esac

selected_env_files=()
if [ "${#cli_env_files[@]}" -gt 0 ]; then
    selected_env_files=("${cli_env_files[@]}")
else
    inherited_repeat CODING_AGENTS_ENV
    if [ "${#REPEAT_VALUES[@]}" -gt 0 ]; then
        selected_env_files=("${REPEAT_VALUES[@]}")
    else
        for value in "$HOME/.config/env.coding-agents" "$INVOCATION_DIR/.env.coding-agents"; do
            [ ! -e "$value" ] || selected_env_files+=("$value")
        done
    fi
fi

env_files=()
for value in "${selected_env_files[@]}"; do
    case "$value" in /*) path=$value ;; *) path=$INVOCATION_DIR/$value ;; esac
    path=$(canonical_file "$path") || die "environment file is not a readable regular file: $value"
    add_unique "$path" "${env_files[@]}" && env_files+=("$path")
done

cfg_workspace_set=0
cfg_workdir_set=0
cfg_fd_binary_set=0
cfg_image_set=0
cfg_no_x11_set=0
cfg_dry_run_set=0
cfg_workspace=
cfg_workdir=
cfg_fd_binary=
cfg_image=
cfg_no_x11=
cfg_dry_run=
cfg_volumes=()
cfg_shadows=()
cfg_shadow_all=()
agent_keys=()
agent_values=()
evaluated_env_keys=()
evaluated_env_values=()

set_agent_value() {
    local key=$1 value=$2 i=0
    while [ "$i" -lt "${#agent_keys[@]}" ]; do
        if [ "${agent_keys[$i]}" = "$key" ]; then
            agent_values[i]=$value
            return
        fi
        i=$((i + 1))
    done
    agent_keys+=("$key")
    agent_values+=("$value")
}

set_evaluated_env() {
    local key=$1 value=$2 i=0
    while [ "$i" -lt "${#evaluated_env_keys[@]}" ]; do
        if [ "${evaluated_env_keys[$i]}" = "$key" ]; then
            evaluated_env_values[i]=$value
            return
        fi
        i=$((i + 1))
    done
    evaluated_env_keys+=("$key")
    evaluated_env_values+=("$value")
}

evaluate_value() {
    local expression=$1 name i=0
    while [ "$i" -lt "${#evaluated_env_keys[@]}" ]; do
        name=${evaluated_env_keys[$i]}
        local "$name"
        printf -v "$name" '%s' "${evaluated_env_values[$i]}"
        i=$((i + 1))
    done
    EVALUATED_VALUE=
    eval "EVALUATED_VALUE=$expression"
}

file_repeat() {
    local base=$1 i key suffix number j
    REPEAT_VALUES=()
    repeat_numbers=()
    repeat_values=()
    i=0
    while [ "$i" -lt "${#file_keys[@]}" ]; do
        key=${file_keys[$i]}
        if [ "$key" = "$base" ]; then
            REPEAT_VALUES+=("${file_values[$i]}")
        else
            case "$key" in
                "$base"_*)
                    suffix=${key#"$base"_}
                    case "$suffix" in ''|*[!0-9]*) i=$((i + 1)); continue ;; esac
                    number=$suffix
                    while [ "${number#0}" != "$number" ]; do number=${number#0}; done
                    [ -n "$number" ] || number=0
                    if [ "$number" -le 0 ]; then i=$((i + 1)); continue; fi
                    j=${#repeat_numbers[@]}
                    while [ "$j" -gt 0 ] && [ "${repeat_numbers[$((j - 1))]}" -gt "$number" ]; do
                        repeat_numbers[j]=${repeat_numbers[j-1]}
                        repeat_values[j]=${repeat_values[j-1]}
                        j=$((j - 1))
                    done
                    repeat_numbers[j]=$number
                    repeat_values[j]=${file_values[i]}
                    ;;
            esac
        fi
        i=$((i + 1))
    done
    for VALUE in "${repeat_values[@]}"; do REPEAT_VALUES+=("$VALUE"); done
}

for file in "${env_files[@]}"; do
    file_keys=()
    file_values=()
    line_number=0
    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        case "$line" in *[![:space:]]*) ;; *) continue ;; esac
        case "$line" in '#'*|[[:space:]]*'#'*) continue ;; esac
        case "$line" in *=*) ;; *) die "$file:$line_number: expected KEY=value" ;; esac
        key=${line%%=*}
        expression=${line#*=}
        case "$key" in ''|[0-9]*|*[!A-Za-z0-9_]*) die "$file:$line_number: invalid key: $key" ;; esac
        for seen in "${file_keys[@]}"; do
            [ "$seen" != "$key" ] || die "$file:$line_number: duplicate key: $key"
        done
        case "$key" in
            CODING_AGENTS_ENV|CODING_AGENTS_ENV_*) die "$file:$line_number: config files cannot select config files" ;;
            CODING_AGENTS_*) known_key "$key" || die "$file:$line_number: unknown launcher key: $key" ;;
        esac
        evaluate_value "$expression"
        value=$EVALUATED_VALUE
        file_keys+=("$key")
        file_values+=("$value")
        set_evaluated_env "$key" "$value"
    done < "$file"

    i=0
    while [ "$i" -lt "${#file_keys[@]}" ]; do
        key=${file_keys[$i]}
        value=${file_values[$i]}
        case "$key" in
            CODING_AGENTS_WORKSPACE) cfg_workspace_set=1; cfg_workspace=$value ;;
            CODING_AGENTS_WORKDIR) cfg_workdir_set=1; cfg_workdir=$value ;;
            CODING_AGENTS_FD_BINARY) cfg_fd_binary_set=1; cfg_fd_binary=$value ;;
            CODING_AGENTS_IMAGE) cfg_image_set=1; cfg_image=$value ;;
            CODING_AGENTS_NO_X11) cfg_no_x11_set=1; cfg_no_x11=$value ;;
            CODING_AGENTS_DRY_RUN) cfg_dry_run_set=1; cfg_dry_run=$value ;;
            CODING_AGENTS_CODEX_*|CODING_AGENTS_CLAUDE_*|CODING_AGENTS_OPENCODE_*) set_agent_value "$key" "$value" ;;
        esac
        i=$((i + 1))
    done
    file_repeat CODING_AGENTS_VOLUME
    cfg_volumes+=("${REPEAT_VALUES[@]}")
    file_repeat CODING_AGENTS_SHADOW
    cfg_shadows+=("${REPEAT_VALUES[@]}")
    file_repeat CODING_AGENTS_SHADOW_ALL
    cfg_shadow_all+=("${REPEAT_VALUES[@]}")
done

workspace_value=$INVOCATION_DIR
workdir_value=
fd_binary=fd
image=$DEFAULT_IMAGE
no_x11=0
dry_run=0
[ "$cfg_workspace_set" -eq 0 ] || workspace_value=$cfg_workspace
[ "$cfg_workdir_set" -eq 0 ] || workdir_value=$cfg_workdir
[ "$cfg_fd_binary_set" -eq 0 ] || fd_binary=$cfg_fd_binary
[ "$cfg_image_set" -eq 0 ] || image=$cfg_image
[ "$cfg_no_x11_set" -eq 0 ] || no_x11=$cfg_no_x11
[ "$cfg_dry_run_set" -eq 0 ] || dry_run=$cfg_dry_run

for key in CODING_AGENTS_WORKSPACE CODING_AGENTS_WORKDIR CODING_AGENTS_FD_BINARY CODING_AGENTS_IMAGE CODING_AGENTS_NO_X11 CODING_AGENTS_DRY_RUN; do
    inherited_get "$key"
    [ "$FOUND" -eq 0 ] || case "$key" in
        CODING_AGENTS_WORKSPACE) workspace_value=$VALUE ;;
        CODING_AGENTS_WORKDIR) workdir_value=$VALUE ;;
        CODING_AGENTS_FD_BINARY) fd_binary=$VALUE ;;
        CODING_AGENTS_IMAGE) image=$VALUE ;;
        CODING_AGENTS_NO_X11) no_x11=$VALUE ;;
        CODING_AGENTS_DRY_RUN) dry_run=$VALUE ;;
    esac
done
[ "$cli_workspace_set" -eq 0 ] || workspace_value=$cli_workspace
[ "$cli_workdir_set" -eq 0 ] || workdir_value=$cli_workdir
[ "$cli_fd_binary_set" -eq 0 ] || fd_binary=$cli_fd_binary
[ "$cli_image_set" -eq 0 ] || image=$cli_image
[ "$cli_no_x11_set" -eq 0 ] || no_x11=1
[ "$cli_dry_run_set" -eq 0 ] || dry_run=1
[ -n "$fd_binary" ] || die "fd binary must not be empty"
[ -n "$image" ] || die "image must not be empty"
case "$no_x11" in 0|1) ;; *) die "CODING_AGENTS_NO_X11 must be 0 or 1" ;; esac
case "$dry_run" in 0|1) ;; *) die "CODING_AGENTS_DRY_RUN must be 0 or 1" ;; esac

if [ "$command_name" = pull ]; then
    [ "${#command_args[@]}" -eq 0 ] || die "pull does not accept arguments"
    docker_command=(docker pull "$image")
    if [ "$dry_run" -eq 1 ]; then print_command "${docker_command[@]}"; exit 0; fi
    printf 'To update launcher, use update.\n'
    exec "${docker_command[@]}"
fi

volumes=("${cfg_volumes[@]}")
inherited_repeat CODING_AGENTS_VOLUME
volumes+=("${REPEAT_VALUES[@]}" "${cli_volumes[@]}")
shadows=("${cfg_shadows[@]}")
inherited_repeat CODING_AGENTS_SHADOW
shadows+=("${REPEAT_VALUES[@]}" "${cli_shadows[@]}")
shadow_all=("${cfg_shadow_all[@]}")
inherited_repeat CODING_AGENTS_SHADOW_ALL
shadow_all+=("${REPEAT_VALUES[@]}" "${cli_shadow_all[@]}")

deduped=()
for value in "${volumes[@]}"; do add_unique "$value" "${deduped[@]}" && deduped+=("$value"); done
volumes=("${deduped[@]}")
deduped=()
for value in "${shadows[@]}"; do add_unique "$value" "${deduped[@]}" && deduped+=("$value"); done
shadows=("${deduped[@]}")
deduped=()
for value in "${shadow_all[@]}"; do add_unique "$value" "${deduped[@]}" && deduped+=("$value"); done
shadow_all=("${deduped[@]}")

case "$workspace_value" in /*) ;; *) workspace_value=$INVOCATION_DIR/$workspace_value ;; esac
workspace=$(canonical_dir "$workspace_value") || die "workspace is not an existing directory: $workspace_value"
if [ -z "$workdir_value" ]; then
    workdir=$workspace
else
    case "$workdir_value" in /*) ;; *) workdir_value=$workspace/$workdir_value ;; esac
    workdir=$(canonical_dir "$workdir_value") || die "workdir is not an existing directory: $workdir_value"
    inside "$workspace" "$workdir" || die "workdir must be inside workspace: $workdir"
fi

case "$command_name" in
    codex) agent=CODEX; image_command=(codex "${command_args[@]}") ;;
    claude) agent=CLAUDE; image_command=(claude "${command_args[@]}") ;;
    opencode) agent=OPENCODE; image_command=(opencode "${command_args[@]}") ;;
    codex-acp) agent=CODEX; image_command=(codex-acp "${command_args[@]}") ;;
    claude-acp) agent=CLAUDE; image_command=(claude-agent-acp "${command_args[@]}") ;;
    opencode-acp) agent=OPENCODE; image_command=(opencode acp "${command_args[@]}") ;;
    shell) agent=; image_command=(zsh "${command_args[@]}") ;;
    run)
        [ "${#command_args[@]}" -gt 0 ] || die "run requires a command"
        agent=
        image_command=("${command_args[@]}")
        ;;
    *) die "unknown command: $command_name" ;;
esac

managed_destinations=()
managed_sources=()
managed_mounts=()
named_roots=()
bind_sources=()
prune_roots=()

add_bind_source() {
    local source=$1 existing
    for existing in "${bind_sources[@]}"; do [ "$existing" != "$source" ] || return; done
    bind_sources+=("$source")
    inside "$workspace" "$source" && prune_roots+=("$source")
    return 0
}

add_managed() {
    local destination=$1 source_id=$2 mount=$3 named=$4 i=0
    while [ "$i" -lt "${#managed_destinations[@]}" ]; do
        if [ "${managed_destinations[$i]}" = "$destination" ]; then
            [ "${managed_sources[$i]}" = "$source_id" ] && return
            die "multiple mount sources target $destination"
        fi
        i=$((i + 1))
    done
    managed_destinations+=("$destination")
    managed_sources+=("$source_id")
    managed_mounts+=("$mount")
    [ "$named" -eq 0 ] || named_roots+=("$destination")
}

resolve_target() {
    local target=$1
    case "$target" in /*) ;; *) target=$workspace/$target ;; esac
    RESOLVED_TARGET=$(canonical_dir "$target") || die "shadow target is not an existing directory: $target"
    inside "$workspace" "$RESOLVED_TARGET" || die "shadow target must be inside workspace: $RESOLVED_TARGET"
}

for value in "${shadows[@]}"; do
    case "$value" in *:*) ;; *) die "--shadow requires SOURCE:TARGET: $value" ;; esac
    source=${value%%:*}
    target=${value#*:}
    [ -n "$source" ] && [ -n "$target" ] || die "--shadow requires nonempty SOURCE and TARGET: $value"
    resolve_target "$target"
    if [ "${source#*/}" != "$source" ]; then
        case "$source" in /*|./*) ;; *) die "relative bind shadow sources must begin with ./: $source" ;; esac
        bind_source=$(canonical_maybe_missing "$source") || die "cannot resolve bind source: $source"
        [ ! -e "$bind_source" ] || [ -d "$bind_source" ] || die "bind shadow source is not a directory: $bind_source"
        overlap "$bind_source" "$RESOLVED_TARGET" && die "bind source and target overlap: $bind_source and $RESOLVED_TARGET"
        add_bind_source "$bind_source"
        mount_value "$bind_source"; mount_source=$MOUNT_VALUE
        mount_value "$RESOLVED_TARGET"; mount_target=$MOUNT_VALUE
        add_managed "$RESOLVED_TARGET" "bind:$bind_source" "type=bind,src=$mount_source,dst=$mount_target" 0
    else
        mount_value "$source"; mount_source=$MOUNT_VALUE
        mount_value "$RESOLVED_TARGET"; mount_target=$MOUNT_VALUE
        add_managed "$RESOLVED_TARGET" "volume:$source" "type=volume,src=$mount_source,dst=$mount_target,volume-nocopy" 1
    fi
done

recursive_kinds=()
recursive_roots=()
recursive_basenames=()
for value in "${shadow_all[@]}"; do
    case "$value" in
        *:*)
            root=${value%%:*}
            basename=${value#*:}
            [ -n "$root" ] && [ -n "$basename" ] || die "--shadow-all requires ROOT:BASENAME"
            case "$root" in /*|./*) ;; *) die "relative recursive bind roots must begin with ./: $root" ;; esac
            root=$(canonical_maybe_missing "$root") || die "cannot resolve recursive bind root: $root"
            [ ! -e "$root" ] || [ -d "$root" ] || die "recursive bind root is not a directory: $root"
            recursive_kinds+=(bind)
            recursive_roots+=("$root")
            add_bind_source "$root"
            ;;
        *)
            basename=$value
            [ -n "$basename" ] || die "--shadow-all basename must not be empty"
            recursive_kinds+=(volume)
            recursive_roots+=("")
            ;;
    esac
    case "$basename" in */*|.|..) die "--shadow-all matches one directory basename: $basename" ;; esac
    recursive_basenames+=("$basename")
done

workspace_cksum=$(printf '%s' "$workspace" | cksum)
workspace_cksum=${workspace_cksum%% *}
i=0
while [ "$i" -lt "${#recursive_kinds[@]}" ]; do
    kind=${recursive_kinds[$i]}
    root=${recursive_roots[$i]}
    basename=${recursive_basenames[$i]}
    if command -v "$fd_binary" >/dev/null 2>&1; then
        discovery_command=("$fd_binary" --hidden --no-ignore --case-sensitive --type d --glob --prune --print0 --exclude .git)
        for value in "${prune_roots[@]}"; do
            [ -d "$value" ] || continue
            if [ "$value" = "$workspace" ]; then relative=/; else relative=/${value#"$workspace"/}; fi
            discovery_command+=(--exclude "$relative")
        done
        discovery_command+=(-- "$basename" "$workspace")
    else
        discovery_command=(find "$workspace" "(" -type d -name .git)
        for value in "${prune_roots[@]}"; do
            [ -d "$value" ] || continue
            discovery_command+=(-o -type d -path "$value")
        done
        discovery_command+=(")" -prune -o "(" -type d -name "$basename" -print0 -prune ")")
    fi
    discovery_complete=0
    while IFS= read -r -d '' target; do
        if [ -z "$target" ]; then discovery_complete=1; continue; fi
        resolve_target "$target"
        if [ "$RESOLVED_TARGET" = "$workspace" ]; then relative=.; else relative=${RESOLVED_TARGET#"$workspace"/}; fi
        if [ "$kind" = bind ]; then
            bind_source=$(canonical_maybe_missing "$root/$relative") || die "cannot resolve recursive bind source"
            overlap "$bind_source" "$RESOLVED_TARGET" && die "bind source and target overlap: $bind_source and $RESOLVED_TARGET"
            add_bind_source "$bind_source"
            mount_value "$bind_source"; mount_source=$MOUNT_VALUE
            mount_value "$RESOLVED_TARGET"; mount_target=$MOUNT_VALUE
            add_managed "$RESOLVED_TARGET" "bind:$bind_source" "type=bind,src=$mount_source,dst=$mount_target" 0
        else
            target_cksum=$(printf '%s' "$relative" | cksum)
            target_cksum=${target_cksum%% *}
            readable=$(printf '%s' "$relative" | tr -c 'A-Za-z0-9_.-' '-')
            volume=coding-agents-shadow-$workspace_cksum-$readable-$target_cksum
            mount_value "$RESOLVED_TARGET"; mount_target=$MOUNT_VALUE
            add_managed "$RESOLVED_TARGET" "volume:$volume" "type=volume,src=$volume,dst=$mount_target,volume-nocopy" 1
        fi
    done < <("${discovery_command[@]}" && printf '\0')
    [ "$discovery_complete" -eq 1 ] || die "recursive shadow discovery failed"
    i=$((i + 1))
done

volume_destinations=()
volume_sources=()
docker_volumes=()
for spec in "${volumes[@]}"; do
    case "$spec" in *:*) ;; *) die "--volume requires SOURCE:TARGET: $spec" ;; esac
    source=${spec%%:*}
    destination=${spec#*:}
    [ -n "$source" ] && [ -n "$destination" ] || die "--volume requires nonempty SOURCE and TARGET: $spec"
    case "$destination" in /*) ;; *) die "volume target must be absolute: $destination" ;; esac
    case "$destination" in *:*) die "--volume accepts SOURCE:TARGET without extra options: $spec" ;; esac

    named=1
    if [ "${source#*/}" != "$source" ]; then
        named=0
        case "$source" in /*|./*) ;; *) die "relative volume sources must begin with ./: $source" ;; esac
        source=$(canonical_maybe_missing "$source") || die "cannot resolve volume source: $source"
        [ -e "$source" ] || die "volume bind source does not exist: $source"
    fi
    normalized_volume=$source:$destination
    duplicate=0
    i=0
    while [ "$i" -lt "${#volume_destinations[@]}" ]; do
        if [ "${volume_destinations[$i]}" = "$destination" ]; then
            [ "${volume_sources[$i]}" = "$source" ] || die "multiple volume sources target $destination"
            duplicate=1
        fi
        i=$((i + 1))
    done
    [ "$duplicate" -eq 1 ] && continue
    for target in "${managed_destinations[@]}"; do
        [ "$destination" != "$target" ] || die "volume duplicates managed target: $target"
    done
    volume_destinations+=("$destination")
    volume_sources+=("$source")
    docker_volumes+=("$normalized_volume")
    [ "$named" -eq 0 ] || named_roots+=("$destination")
done

if [ "$dry_run" -eq 0 ]; then
    for source in "${bind_sources[@]}"; do [ -d "$source" ] || mkdir -p -- "$source"; done
fi

docker_args=(run --rm --interactive --network host --user root)
case "$command_name" in
    *-acp) ;;
    *) [ ! -t 0 ] || [ ! -t 1 ] || docker_args+=(--tty) ;;
esac
mount_value "$workspace"; mount_workspace=$MOUNT_VALUE
docker_args+=(--mount "type=bind,src=$mount_workspace,dst=$mount_workspace" --workdir "$workdir")

fixed_sources=(
    "$HOME/.config/opencode"
    "$HOME/.config/opencode"
    "$HOME/.local/share/opencode"
    "$HOME/.local/share/opencode"
    "$HOME/.local/state/opencode"
    "$HOME/.local/state/opencode"
    "$HOME/.claude.json"
    "$HOME/.claude"
    "$HOME/.claude"
    "$HOME/.codex"
    "$HOME/.codex"
)
fixed_destinations=(
    /home/ai/.config/opencode
    "$HOME/.config/opencode"
    /home/ai/.local/share/opencode
    "$HOME/.local/share/opencode"
    /home/ai/.local/state/opencode
    "$HOME/.local/state/opencode"
    /home/ai/.claude.json
    /home/ai/.claude
    "$HOME/.claude"
    /home/ai/.codex
    "$HOME/.codex"
)
fixed_mount_destinations=()
i=0
while [ "$i" -lt "${#fixed_sources[@]}" ]; do
    destination=${fixed_destinations[$i]}
    overridden=0
    for target in "${volume_destinations[@]}" "${fixed_mount_destinations[@]}"; do
        [ "$target" != "$destination" ] || overridden=1
    done
    if [ "$overridden" -eq 0 ] && [ -e "${fixed_sources[$i]}" ]; then
        docker_args+=(--volume "${fixed_sources[$i]}:$destination")
        fixed_mount_destinations+=("$destination")
    fi
    i=$((i + 1))
done
for spec in "${docker_volumes[@]}"; do docker_args+=(--volume "$spec"); done
for spec in "${managed_mounts[@]}"; do docker_args+=(--mount "$spec"); done
for file in "${env_files[@]}"; do docker_args+=(--env-file "$file"); done
for ((i = 0; i < ${#evaluated_env_keys[@]}; i++)); do
    case "${evaluated_env_keys[$i]}" in CODING_AGENTS_*) continue ;; esac
    docker_args+=(--env "${evaluated_env_keys[$i]}=${evaluated_env_values[$i]}")
done

for key in HERDR_SOCKET_PATH HERDR_PANE_ID; do
    if printenv "$key" >/dev/null 2>&1; then docker_args+=(--env "$key=${!key}"); fi
done

if [ -n "$agent" ]; then
    for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY TZ; do
        key=CODING_AGENTS_${agent}_${variable}
        value=
        found=0
        i=0
        while [ "$i" -lt "${#agent_keys[@]}" ]; do
            if [ "${agent_keys[$i]}" = "$key" ]; then found=1; value=${agent_values[$i]}; break; fi
            i=$((i + 1))
        done
        inherited_get "$key"
        [ "$FOUND" -eq 0 ] || { found=1; value=$VALUE; }
        [ "$found" -eq 0 ] || docker_args+=(--env "$variable=$value")
    done
fi

if [ "$no_x11" -eq 0 ] && [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
    authority=${XAUTHORITY:-$HOME/.Xauthority}
    if [ -f "$authority" ] && [ -r "$authority" ]; then
        authority=$(canonical_file "$authority")
        mount_value "$authority"; mount_authority=$MOUNT_VALUE
        docker_args+=(
            --mount "type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,readonly"
            --mount "type=bind,src=$mount_authority,dst=/tmp/.host.Xauthority,readonly"
            --env "DISPLAY=$DISPLAY"
            --env XAUTHORITY=/home/ai/.Xauthority
        )
    fi
fi

bootstrap=$(cat <<'BOOTSTRAP'
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone 2>/dev/null || true
fi
if [ -n "${DISPLAY:-}" ] && [ -f /tmp/.host.Xauthority ] && [ -r /tmp/.host.Xauthority ]; then
    rm -f /home/ai/.Xauthority
    touch /home/ai/.Xauthority
    export_xauth() {
        xauth -f /tmp/.host.Xauthority nlist "$1" 2>/dev/null \
            | sed 's/^..../ffff/' \
            | xauth -f /home/ai/.Xauthority nmerge - 2>/dev/null
    }
    export_xauth "$DISPLAY" || true
    if ! xauth -f /home/ai/.Xauthority list 2>/dev/null | grep -q .; then export_xauth "" || true; fi
    chown ai:ai /home/ai/.Xauthority
    chmod 600 /home/ai/.Xauthority
fi
count=$1
shift
while [ "$count" -gt 0 ]; do
    chown ai:ai "$1"
    shift
    count=$((count - 1))
done
[ "$#" -gt 0 ] || set -- zsh
exec gosu ai "$@"
BOOTSTRAP
)

docker_command=(docker "${docker_args[@]}" --entrypoint /bin/sh "$image" -c "$bootstrap" -- "${#named_roots[@]}" "${named_roots[@]}" "${image_command[@]}")
if [ "$dry_run" -eq 1 ]; then print_command "${docker_command[@]}"; exit 0; fi
exec "${docker_command[@]}"
