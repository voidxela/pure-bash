# pure.bash - A Bash-native prompt inspired by Pure.
#
# Source this file from an interactive Bash shell:
#   source /path/to/pure.bash
#
# Requires Bash 4.4+ and Git 2.15.2+ for Git integration.

if [[ -z ${BASH_VERSION:-} ]]; then
    return 0 2>/dev/null || exit 0
fi

# Public defaults. Use "set if unset" rather than := so symbols may be
# intentionally set to an empty string.
[[ ${PURE_CMD_MAX_EXEC_TIME+x} ]] || PURE_CMD_MAX_EXEC_TIME=5
[[ ${PURE_GIT_PULL+x} ]] || PURE_GIT_PULL=1
[[ ${PURE_GIT_UNTRACKED_DIRTY+x} ]] || PURE_GIT_UNTRACKED_DIRTY=1
[[ ${PURE_GIT_DELAY_DIRTY_CHECK+x} ]] || PURE_GIT_DELAY_DIRTY_CHECK=1800
[[ ${PURE_PROMPT_SYMBOL+x} ]] || PURE_PROMPT_SYMBOL='❯'
[[ ${PURE_PROMPT_VICMD_SYMBOL+x} ]] || PURE_PROMPT_VICMD_SYMBOL='❮'
[[ ${PURE_SUSPENDED_JOBS_SYMBOL+x} ]] || PURE_SUSPENDED_JOBS_SYMBOL='✦'
[[ ${PURE_GIT_DOWN_ARROW+x} ]] || PURE_GIT_DOWN_ARROW='⇣'
[[ ${PURE_GIT_UP_ARROW+x} ]] || PURE_GIT_UP_ARROW='⇡'
[[ ${PURE_GIT_STASH_SYMBOL+x} ]] || PURE_GIT_STASH_SYMBOL='≡'

# Bash equivalents of Pure's zstyle switches.
[[ ${PURE_GIT+x} ]] || PURE_GIT=1
[[ ${PURE_GIT_STASH+x} ]] || PURE_GIT_STASH=0
[[ ${PURE_GIT_DIRTY_DETAILED+x} ]] || PURE_GIT_DIRTY_DETAILED=0
[[ ${PURE_NODE_VERSION+x} ]] || PURE_NODE_VERSION=0
[[ ${PURE_NODE_VERSION_SYMBOL+x} ]] || PURE_NODE_VERSION_SYMBOL='⬢'
[[ ${PURE_VIRTUALENV+x} ]] || PURE_VIRTUALENV=1
[[ ${PURE_NIX_SHELL+x} ]] || PURE_NIX_SHELL=1
[[ ${PURE_HOST+x} ]] || PURE_HOST=1
[[ ${PURE_TITLE+x} ]] || PURE_TITLE=1
[[ ${PURE_PATH_SEPARATOR_DIM+x} ]] || PURE_PATH_SEPARATOR_DIM=0

# Colors mirror Pure's defaults. Values may be a named ANSI color, 0..255,
# "default", or #RRGGBB.
[[ ${PURE_COLOR_CUSTOM_PREFIX+x} ]] || PURE_COLOR_CUSTOM_PREFIX=242
[[ ${PURE_COLOR_CUSTOM_SUFFIX+x} ]] || PURE_COLOR_CUSTOM_SUFFIX=242
[[ ${PURE_COLOR_EXECUTION_TIME+x} ]] || PURE_COLOR_EXECUTION_TIME=yellow
[[ ${PURE_COLOR_GIT_ARROW+x} ]] || PURE_COLOR_GIT_ARROW=cyan
[[ ${PURE_COLOR_GIT_STASH+x} ]] || PURE_COLOR_GIT_STASH=cyan
[[ ${PURE_COLOR_GIT_BRANCH+x} ]] || PURE_COLOR_GIT_BRANCH=242
[[ ${PURE_COLOR_GIT_BRANCH_CACHED+x} ]] || PURE_COLOR_GIT_BRANCH_CACHED=red
[[ ${PURE_COLOR_GIT_ACTION+x} ]] || PURE_COLOR_GIT_ACTION=yellow
[[ ${PURE_COLOR_GIT_DIRTY+x} ]] || PURE_COLOR_GIT_DIRTY=218
[[ ${PURE_COLOR_HOST+x} ]] || PURE_COLOR_HOST=242
[[ ${PURE_COLOR_NODE_VERSION+x} ]] || PURE_COLOR_NODE_VERSION=green
[[ ${PURE_COLOR_PATH+x} ]] || PURE_COLOR_PATH=blue
[[ ${PURE_COLOR_PROMPT_ERROR+x} ]] || PURE_COLOR_PROMPT_ERROR=red
[[ ${PURE_COLOR_PROMPT_SUCCESS+x} ]] || PURE_COLOR_PROMPT_SUCCESS=magenta
[[ ${PURE_COLOR_PROMPT_CONTINUATION+x} ]] || PURE_COLOR_PROMPT_CONTINUATION=242
[[ ${PURE_COLOR_SUSPENDED_JOBS+x} ]] || PURE_COLOR_SUSPENDED_JOBS=red
[[ ${PURE_COLOR_USER+x} ]] || PURE_COLOR_USER=242
[[ ${PURE_COLOR_USER_ROOT+x} ]] || PURE_COLOR_USER_ROOT=default
[[ ${PURE_COLOR_VIRTUALENV+x} ]] || PURE_COLOR_VIRTUALENV=242

__PURE_VERSION='0.1.0'
__PURE_SESSION_ID=$$
__PURE_CACHE_DIR=${PURE_BASH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pure-bash}
__PURE_CACHE_FILE="$__PURE_CACHE_DIR/session-${__PURE_SESSION_ID}.cache"
__PURE_WORKER_PID=
__PURE_WORKER_PWD=
__PURE_WORKER_BRANCH=
__PURE_SETUP_DONE=${__PURE_SETUP_DONE:-0}

__pure_sanitize() {
    local value=$1
    value=${value//$'\033'/}
    value=${value//$'\007'/}
    value=${value//$'\r'/?}
    value=${value//$'\n'/?}
    value=${value//$'\t'/ }
    printf '%s' "$value"
}

__pure_color_code() {
    local value=${1:-default}
    local code

    case $value in
        black) code=30 ;;
        red) code=31 ;;
        green) code=32 ;;
        yellow) code=33 ;;
        blue) code=34 ;;
        magenta) code=35 ;;
        cyan) code=36 ;;
        white) code=37 ;;
        default) code=39 ;;
        *)
            if [[ $value =~ ^[0-9]+$ ]] && (( value >= 0 && value <= 255 )); then
                code="38;5;$value"
            elif [[ $value =~ ^#[[:xdigit:]]{6}$ ]]; then
                local hex=${value#\#}
                local r=$((16#${hex:0:2}))
                local g=$((16#${hex:2:2}))
                local b=$((16#${hex:4:2}))
                code="38;2;$r;$g;$b"
            else
                code=39
            fi
            ;;
    esac

    printf '%s' "$code"
}

__pure_color_prompt() {
    local code
    code=$(__pure_color_code "$1")
    printf '\\[\033[%sm\\]' "$code"
}

__pure_color_plain() {
    local code
    code=$(__pure_color_code "$1")
    printf '\033[%sm' "$code"
}

__pure_reset_prompt_color() {
    printf '\\[\033[0m\\]'
}

__pure_human_time() {
    local total_seconds=${1:-0}
    local days=$((total_seconds / 86400))
    local hours=$((total_seconds / 3600 % 24))
    local minutes=$((total_seconds / 60 % 60))
    local seconds=$((total_seconds % 60))
    local human=

    (( days > 0 )) && human+="${days}d "
    (( hours > 0 )) && human+="${hours}h "
    (( minutes > 0 )) && human+="${minutes}m "
    human+="${seconds}s"
    printf '%s' "$human"
}

__pure_display_path() {
    local path=$PWD
    if [[ $path == "$HOME" ]]; then
        path='~'
    elif [[ $path == "$HOME/"* ]]; then
        path="~/${path#"$HOME/"}"
    fi
    __pure_sanitize "$path"
}

__pure_is_inside_container() {
    [[ ${container:-} == lxc || ${container:-} == oci || ${container:-} == podman ]] && return 0
    [[ -r /run/host/container-manager ]] && return 0
    [[ -r /run/.containerenv ]] && return 0
    [[ -r /.dockerenv ]] && return 0
    [[ -r /var/run/secrets/kubernetes.io/serviceaccount/token ]] && return 0
    if [[ -r /proc/1/cgroup ]]; then
        local cgroup
        cgroup=$(< /proc/1/cgroup)
        [[ $cgroup == *lxc* || $cgroup == *docker* || $cgroup == *containerd* ]] && return 0
    fi
    return 1
}

__pure_set_remote_identity() {
    __PURE_SHOW_IDENTITY=0
    __PURE_USER_COLOR=$PURE_COLOR_USER

    if [[ -n ${SSH_CONNECTION:-${SSH_CLIENT:-}} ]]; then
        __PURE_SHOW_IDENTITY=1
    elif [[ -z ${CODESPACES:-} ]] && __pure_is_inside_container; then
        __PURE_SHOW_IDENTITY=1
    fi

    if (( EUID == 0 )); then
        __PURE_SHOW_IDENTITY=1
        __PURE_USER_COLOR=$PURE_COLOR_USER_ROOT
    fi
}

__pure_git_context() {
    __PURE_GIT_TOP=
    __PURE_GIT_DIR=
    __PURE_GIT_BRANCH=
    __PURE_GIT_ACTION=

    (( PURE_GIT )) || return 1
    command -v git >/dev/null 2>&1 || return 1

    local -a info=()
    mapfile -t info < <(command git rev-parse --show-toplevel --absolute-git-dir --abbrev-ref HEAD 2>/dev/null)
    (( ${#info[@]} >= 3 )) || return 1

    __PURE_GIT_TOP=${info[0]}
    __PURE_GIT_DIR=${info[1]}
    __PURE_GIT_BRANCH=${info[2]}

    if [[ $__PURE_GIT_BRANCH == HEAD ]]; then
        __PURE_GIT_BRANCH=$(command git rev-parse --short HEAD 2>/dev/null) || __PURE_GIT_BRANCH=HEAD
    fi

    if [[ -d $__PURE_GIT_DIR/rebase-merge ]]; then
        if [[ -f $__PURE_GIT_DIR/rebase-merge/interactive ]]; then
            __PURE_GIT_ACTION='rebase-i'
        else
            __PURE_GIT_ACTION='rebase'
        fi
    elif [[ -d $__PURE_GIT_DIR/rebase-apply ]]; then
        __PURE_GIT_ACTION='rebase'
    elif [[ -f $__PURE_GIT_DIR/MERGE_HEAD ]]; then
        __PURE_GIT_ACTION='merge'
    elif [[ -f $__PURE_GIT_DIR/CHERRY_PICK_HEAD ]]; then
        __PURE_GIT_ACTION='cherry-pick'
    elif [[ -f $__PURE_GIT_DIR/REVERT_HEAD ]]; then
        __PURE_GIT_ACTION='revert'
    elif [[ -f $__PURE_GIT_DIR/BISECT_LOG ]]; then
        __PURE_GIT_ACTION='bisect'
    fi

    __PURE_GIT_BRANCH=$(__pure_sanitize "$__PURE_GIT_BRANCH")
    __PURE_GIT_ACTION=$(__pure_sanitize "$__PURE_GIT_ACTION")
    return 0
}

__pure_git_dirty() {
    local detailed=${1:-0}
    local untracked=${2:-1}
    local status=

    export GIT_OPTIONAL_LOCKS=0

    if (( ! detailed )); then
        if (( ! untracked )); then
            command git diff --no-ext-diff --quiet --exit-code || { printf '*'; return 0; }
            command git diff --no-ext-diff --cached --quiet --exit-code || { printf '*'; return 0; }
            return 0
        fi
        status=$(command git status --porcelain --untracked-files=normal 2>/dev/null)
        [[ -n $status ]] && printf '*'
        return 0
    fi

    local untracked_mode=normal
    (( untracked )) || untracked_mode=no
    status=$(command git status --porcelain --untracked-files="$untracked_mode" 2>/dev/null)
    [[ -z $status ]] && return 0

    local has_unstaged=0 has_staged=0 has_untracked=0 line x y
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        x=${line:0:1}
        y=${line:1:1}
        [[ $line == '??'* ]] && has_untracked=1
        [[ $y == [MTDUA] ]] && has_unstaged=1
        [[ $x == [MTADRCU] ]] && has_staged=1
        (( has_unstaged && has_staged && has_untracked )) && break
    done <<< "$status"

    (( has_unstaged )) && printf '*'
    (( has_staged )) && printf '+'
    (( has_untracked )) && printf '?'
}

__pure_git_arrows_for_ref() {
    local ref=${1:-'@{u}'}
    local counts left right arrows=
    counts=$(command git rev-list --left-right --count "HEAD...$ref" 2>/dev/null) || return 1
    read -r left right <<< "$counts"
    (( right > 0 )) && arrows+=$PURE_GIT_DOWN_ARROW
    (( left > 0 )) && arrows+=$PURE_GIT_UP_ARROW
    printf '%s' "$arrows"
}

__pure_write_cache() {
    local cwd=$1 branch=$2 dirty=$3 arrows=$4 stash=$5 slow=$6 checked=$7
    local temp="${__PURE_CACHE_FILE}.tmp.${BASHPID}.${RANDOM}"
    mkdir -p "$__PURE_CACHE_DIR" 2>/dev/null || return 1
    {
        printf '%s\0' "$cwd" "$branch" "$dirty" "$arrows" "$stash" "$slow" "$checked"
    } > "$temp" || return 1
    command mv -f -- "$temp" "$__PURE_CACHE_FILE" 2>/dev/null
}

__pure_read_cache() {
    __PURE_CACHE_PWD=
    __PURE_CACHE_BRANCH=
    __PURE_CACHE_DIRTY=
    __PURE_CACHE_ARROWS=
    __PURE_CACHE_STASH=
    __PURE_CACHE_SLOW=0
    __PURE_CACHE_CHECKED=0

    [[ -r $__PURE_CACHE_FILE ]] || return 1
    local -a fields=()
    mapfile -d '' -t fields < "$__PURE_CACHE_FILE" 2>/dev/null || return 1
    (( ${#fields[@]} >= 7 )) || return 1

    __PURE_CACHE_PWD=${fields[0]}
    __PURE_CACHE_BRANCH=${fields[1]}
    __PURE_CACHE_DIRTY=${fields[2]}
    __PURE_CACHE_ARROWS=${fields[3]}
    __PURE_CACHE_STASH=${fields[4]}
    __PURE_CACHE_SLOW=${fields[5]:-0}
    __PURE_CACHE_CHECKED=${fields[6]:-0}
}

__pure_fetch_upstream_arrows() {
    local branch=$1
    [[ $branch == HEAD ]] && return 1

    local remote merge_ref temp_ref arrows
    remote=$(command git config --get "branch.${branch}.remote" 2>/dev/null) || return 1
    merge_ref=$(command git config --get "branch.${branch}.merge" 2>/dev/null) || return 1
    [[ -n $remote && -n $merge_ref ]] || return 1

    temp_ref="refs/pure-bash/${__PURE_SESSION_ID}/upstream"

    # Best-effort cleanup even if the background worker is interrupted after
    # fetch creates the temporary ref. This function normally runs in a
    # command-substitution subshell, so the EXIT trap is isolated.
    trap 'command git update-ref -d "$temp_ref" >/dev/null 2>&1 || true' EXIT HUP INT TERM

    GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    GPG_TTY= \
    command git -c gc.auto=0 -c fetch.prune=false fetch \
        --quiet --no-tags --no-write-fetch-head --recurse-submodules=no \
        "$remote" "+${merge_ref}:${temp_ref}" >/dev/null 2>&1 || return 1

    arrows=$(__pure_git_arrows_for_ref "$temp_ref") || arrows=
    command git update-ref -d "$temp_ref" >/dev/null 2>&1 || true
    trap - EXIT HUP INT TERM
    printf '%s' "$arrows"
}

__pure_git_worker() {
    local cwd=$1 branch=$2 do_dirty=$3 old_dirty=$4 old_slow=$5 old_checked=$6
    local dirty=$old_dirty slow=$old_slow checked=$old_checked arrows= stash=

    cd -- "$cwd" 2>/dev/null || return 0

    arrows=$(__pure_git_arrows_for_ref '@{u}') || arrows=

    if (( do_dirty )); then
        local started=$SECONDS
        dirty=$(__pure_git_dirty "$PURE_GIT_DIRTY_DETAILED" "$PURE_GIT_UNTRACKED_DIRTY")
        local duration=$((SECONDS - started))
        checked=$SECONDS
        if (( duration > 5 )); then
            slow=1
        else
            slow=0
        fi
    fi

    if (( PURE_GIT_STASH )) && [[ -n $PURE_GIT_STASH_SYMBOL ]]; then
        local stash_count
        stash_count=$(command git rev-list --walk-reflogs --count refs/stash 2>/dev/null) || stash_count=0
        (( stash_count > 0 )) && stash=$PURE_GIT_STASH_SYMBOL
    fi

    __pure_write_cache "$cwd" "$branch" "$dirty" "$arrows" "$stash" "$slow" "$checked"

    # Pure fetches in the background to make arrows reflect the remote. In Bash,
    # use a temporary private ref so prompt refreshes do not rewrite the user's
    # normal remote-tracking refs while a foreground Git command may be running.
    if (( PURE_GIT_PULL )) && [[ $cwd != "$HOME" ]]; then
        local fresh_arrows
        fresh_arrows=$(__pure_fetch_upstream_arrows "$branch") || return 0
        __pure_write_cache "$cwd" "$branch" "$dirty" "$fresh_arrows" "$stash" "$slow" "$checked"
    fi
}

__pure_stop_worker_if_stale() {
    [[ -n $__PURE_WORKER_PID ]] || return 0
    if kill -0 "$__PURE_WORKER_PID" 2>/dev/null; then
        if [[ $__PURE_WORKER_PWD != "$PWD" || $__PURE_WORKER_BRANCH != "$__PURE_GIT_BRANCH" ]]; then
            kill "$__PURE_WORKER_PID" 2>/dev/null || true
            __PURE_WORKER_PID=
        fi
    else
        __PURE_WORKER_PID=
    fi
}

__pure_start_git_worker() {
    (( PURE_GIT )) || return 0
    [[ -n $__PURE_GIT_TOP ]] || return 0

    __pure_stop_worker_if_stale
    if [[ -n $__PURE_WORKER_PID ]] && kill -0 "$__PURE_WORKER_PID" 2>/dev/null; then
        return 0
    fi

    local do_dirty=1 old_dirty= old_slow=0 old_checked=0
    if [[ $__PURE_CACHE_PWD == "$PWD" && $__PURE_CACHE_BRANCH == "$__PURE_GIT_BRANCH" ]]; then
        old_dirty=$__PURE_CACHE_DIRTY
        old_slow=${__PURE_CACHE_SLOW:-0}
        old_checked=${__PURE_CACHE_CHECKED:-0}
        if (( old_slow )) && (( SECONDS - old_checked <= PURE_GIT_DELAY_DIRTY_CHECK )); then
            do_dirty=0
        fi
    fi

    __pure_git_worker "$PWD" "$__PURE_GIT_BRANCH" "$do_dirty" "$old_dirty" "$old_slow" "$old_checked" \
        </dev/null >/dev/null 2>&1 &
    __PURE_WORKER_PID=$!
    __PURE_WORKER_PWD=$PWD
    __PURE_WORKER_BRANCH=$__PURE_GIT_BRANCH
    disown "$__PURE_WORKER_PID" 2>/dev/null || true
}

__pure_node_version() {
    (( PURE_NODE_VERSION )) || return 0
    command -v node >/dev/null 2>&1 || return 0

    local dir=$PWD
    while :; do
        if [[ -f $dir/package.json ]]; then
            local version
            version=$(command node --version 2>/dev/null) || return 0
            version=${version#v}
            version=${version%%.*}
            printf '%s%s' "$PURE_NODE_VERSION_SYMBOL" "$(__pure_sanitize "$version")"
            return 0
        fi
        [[ $dir == / ]] && break
        dir=${dir%/*}
        [[ -n $dir ]] || dir=/
    done
}

__pure_environment_name() {
    (( PURE_VIRTUALENV )) || {
        if (( PURE_NIX_SHELL )) && [[ -n ${IN_NIX_SHELL:-} ]]; then
            __pure_sanitize "${name:-nix-shell}"
        fi
        return 0
    }

    if [[ -n ${CONDA_DEFAULT_ENV:-} && ${CONDA_DEFAULT_ENV##*/} != base ]]; then
        __pure_sanitize "${CONDA_DEFAULT_ENV##*/}"
        return 0
    fi

    if [[ -n ${VIRTUAL_ENV:-} ]]; then
        if [[ -n ${VIRTUAL_ENV_PROMPT:-} ]]; then
            __pure_sanitize "$VIRTUAL_ENV_PROMPT"
        else
            __pure_sanitize "${VIRTUAL_ENV##*/}"
        fi
        return 0
    fi

    if (( PURE_NIX_SHELL )) && [[ -n ${IN_NIX_SHELL:-} ]]; then
        __pure_sanitize "${name:-nix-shell}"
    fi
}

__pure_set_title() {
    (( PURE_TITLE )) || return 0
    [[ -n ${INSIDE_EMACS:-} || -n ${EMACS:-} ]] && return 0
    [[ ${TTY:-} == /dev/ttyS[0-9]* ]] && return 0

    local title=$(__pure_display_path)
    if (( __PURE_SHOW_IDENTITY )) && (( PURE_HOST )); then
        title="${HOSTNAME%%.*} ${title}"
    fi
    printf '\033]0;%s\007' "$title"
}

__pure_build_path_prompt() {
    local path_color=$1 reset=$2
    __PURE_RENDER_PATH=$(__pure_display_path)

    if (( ! PURE_PATH_SEPARATOR_DIM )); then
        PS1+="$path_color"'${__PURE_RENDER_PATH}'"$reset"
        return 0
    fi

    local dim_on='\[\033[2m\]'
    local dim_off='\[\033[22m\]'
    local p=$__PURE_RENDER_PATH
    local -a parts=()
    __PURE_RENDER_PATH_PARTS=()

    PS1+="$path_color"
    if [[ $p == /* ]]; then
        PS1+='/'
        p=${p#/}
        [[ -z $p ]] && { PS1+="$reset"; return 0; }
    fi

    IFS='/' read -r -a parts <<< "$p"
    local i
    for ((i = 0; i < ${#parts[@]}; i++)); do
        __PURE_RENDER_PATH_PARTS[i]=${parts[i]}
        (( i > 0 )) && PS1+="${dim_on}/${dim_off}"
        PS1+='${__PURE_RENDER_PATH_PARTS['"$i"']}'
    done
    PS1+="$reset"
}

__pure_build_prompt() {
    local last_status=$1 elapsed=$2
    local reset c_prefix c_suffix c_jobs c_user c_host c_path c_branch c_branch_cached
    local c_dirty c_action c_arrow c_stash c_node c_time c_venv c_success c_error c_cont

    reset=$(__pure_reset_prompt_color)
    c_prefix=$(__pure_color_prompt "$PURE_COLOR_CUSTOM_PREFIX")
    c_suffix=$(__pure_color_prompt "$PURE_COLOR_CUSTOM_SUFFIX")
    c_jobs=$(__pure_color_prompt "$PURE_COLOR_SUSPENDED_JOBS")
    c_user=$(__pure_color_prompt "$__PURE_USER_COLOR")
    c_host=$(__pure_color_prompt "$PURE_COLOR_HOST")
    c_path=$(__pure_color_prompt "$PURE_COLOR_PATH")
    c_branch=$(__pure_color_prompt "$PURE_COLOR_GIT_BRANCH")
    c_branch_cached=$(__pure_color_prompt "$PURE_COLOR_GIT_BRANCH_CACHED")
    c_dirty=$(__pure_color_prompt "$PURE_COLOR_GIT_DIRTY")
    c_action=$(__pure_color_prompt "$PURE_COLOR_GIT_ACTION")
    c_arrow=$(__pure_color_prompt "$PURE_COLOR_GIT_ARROW")
    c_stash=$(__pure_color_prompt "$PURE_COLOR_GIT_STASH")
    c_node=$(__pure_color_prompt "$PURE_COLOR_NODE_VERSION")
    c_time=$(__pure_color_prompt "$PURE_COLOR_EXECUTION_TIME")
    c_venv=$(__pure_color_prompt "$PURE_COLOR_VIRTUALENV")
    c_success=$(__pure_color_prompt "$PURE_COLOR_PROMPT_SUCCESS")
    c_error=$(__pure_color_prompt "$PURE_COLOR_PROMPT_ERROR")
    c_cont=$(__pure_color_prompt "$PURE_COLOR_PROMPT_CONTINUATION")

    PURE_BASH_CUSTOM_PREFIX=
    PURE_BASH_CUSTOM_SUFFIX=
    if declare -F pure_bash_precustom >/dev/null 2>&1; then
        pure_bash_precustom
    fi

    __PURE_RENDER_PREFIX=$(__pure_sanitize "${PURE_BASH_CUSTOM_PREFIX:-}")
    __PURE_RENDER_SUFFIX=$(__pure_sanitize "${PURE_BASH_CUSTOM_SUFFIX:-}")
    __PURE_RENDER_JOBS=
    if [[ -n $PURE_SUSPENDED_JOBS_SYMBOL && -n $(jobs -s -p 2>/dev/null) ]]; then
        __PURE_RENDER_JOBS=$PURE_SUSPENDED_JOBS_SYMBOL
    fi

    __PURE_RENDER_USER=${USER:-${LOGNAME:-user}}
    __PURE_RENDER_USER=$(__pure_sanitize "$__PURE_RENDER_USER")
    __PURE_RENDER_HOST=${HOSTNAME%%.*}
    __PURE_RENDER_HOST=$(__pure_sanitize "$__PURE_RENDER_HOST")
    __PURE_RENDER_BRANCH=$__PURE_GIT_BRANCH
    __PURE_RENDER_DIRTY=
    __PURE_RENDER_ACTION=$__PURE_GIT_ACTION
    __PURE_RENDER_ARROWS=
    __PURE_RENDER_STASH=
    __PURE_RENDER_NODE=$(__pure_node_version)
    __PURE_RENDER_TIME=
    __PURE_RENDER_ENV=$(__pure_environment_name)
    __PURE_RENDER_PROMPT=$PURE_PROMPT_SYMBOL

    local branch_color=$c_branch
    if [[ $__PURE_CACHE_PWD == "$PWD" && $__PURE_CACHE_BRANCH == "$__PURE_GIT_BRANCH" ]]; then
        __PURE_RENDER_DIRTY=$__PURE_CACHE_DIRTY
        __PURE_RENDER_ARROWS=$__PURE_CACHE_ARROWS
        __PURE_RENDER_STASH=$__PURE_CACHE_STASH
        (( ${__PURE_CACHE_SLOW:-0} )) && branch_color=$c_branch_cached
    fi

    if [[ -n $elapsed ]] && (( elapsed > PURE_CMD_MAX_EXEC_TIME )); then
        __PURE_RENDER_TIME=$(__pure_human_time "$elapsed")
    fi

    # Pure's spacious two-line layout.
    PS1='\n'
    if [[ -n $__PURE_RENDER_PREFIX ]]; then
        PS1+="$c_prefix"'${__PURE_RENDER_PREFIX}'"$reset "
    fi
    if [[ -n $__PURE_RENDER_JOBS ]]; then
        PS1+="$c_jobs"'${__PURE_RENDER_JOBS}'"$reset "
    fi
    if (( __PURE_SHOW_IDENTITY )); then
        PS1+="$c_user"'${__PURE_RENDER_USER}'"$reset"
        if (( PURE_HOST )); then
            PS1+="$c_host@"'${__PURE_RENDER_HOST}'"$reset"
        fi
        PS1+=' '
    fi

    __pure_build_path_prompt "$c_path" "$reset"

    if [[ -n $__PURE_RENDER_BRANCH ]]; then
        PS1+=" $branch_color"'${__PURE_RENDER_BRANCH}'
        [[ -n $__PURE_RENDER_DIRTY ]] && PS1+="$c_dirty"'${__PURE_RENDER_DIRTY}'
        PS1+="$reset"
    fi
    [[ -n $__PURE_RENDER_ACTION ]] && PS1+=" $c_action"'${__PURE_RENDER_ACTION}'"$reset"
    [[ -n $__PURE_RENDER_ARROWS ]] && PS1+=" $c_arrow"'${__PURE_RENDER_ARROWS}'"$reset"
    [[ -n $__PURE_RENDER_STASH ]] && PS1+=" $c_stash"'${__PURE_RENDER_STASH}'"$reset"
    [[ -n $__PURE_RENDER_NODE ]] && PS1+=" $c_node"'${__PURE_RENDER_NODE}'"$reset"
    [[ -n $__PURE_RENDER_TIME ]] && PS1+=" $c_time"'${__PURE_RENDER_TIME}'"$reset"
    [[ -n $__PURE_RENDER_SUFFIX ]] && PS1+=" $c_suffix"'${__PURE_RENDER_SUFFIX}'"$reset"

    PS1+='\n'
    [[ -n $__PURE_RENDER_ENV ]] && PS1+="$c_venv"'${__PURE_RENDER_ENV}'"$reset "
    if (( last_status == 0 )); then
        PS1+="$c_success"'${__PURE_RENDER_PROMPT}'"$reset "
    else
        PS1+="$c_error"'${__PURE_RENDER_PROMPT}'"$reset "
    fi

    PS2="$c_cont…$reset $c_success"'${__PURE_RENDER_PROMPT}'"$reset "
}

__pure_capture_status() {
    __PURE_LAST_STATUS=$?
    return "$__PURE_LAST_STATUS"
}

__pure_prompt_command() {
    local last_status=${__PURE_LAST_STATUS:-$?}
    unset __PURE_LAST_STATUS
    local elapsed=

    if [[ ${__PURE_CMD_START+x} ]]; then
        elapsed=$((SECONDS - __PURE_CMD_START))
        unset __PURE_CMD_START
    fi

    __pure_set_remote_identity
    __pure_git_context || true
    __pure_read_cache || true
    __pure_stop_worker_if_stale
    __pure_build_prompt "$last_status" "$elapsed"
    __pure_set_title
    __pure_start_git_worker

    # Keep Python/Conda prompt mutators from adding duplicate env names.
    export CONDA_CHANGEPS1=no
    export PYENV_VIRTUALENV_DISABLE_PROMPT=1
    export VIRTUAL_ENV_DISABLE_PROMPT=1

    return 0
}

pure_bash_preview() {
    local reset=$'\033[0m'
    local prefix jobs user host path branch dirty action arrows stash node time suffix env ok err cont
    prefix=$(__pure_color_plain "$PURE_COLOR_CUSTOM_PREFIX")
    jobs=$(__pure_color_plain "$PURE_COLOR_SUSPENDED_JOBS")
    user=$(__pure_color_plain "$PURE_COLOR_USER")
    host=$(__pure_color_plain "$PURE_COLOR_HOST")
    path=$(__pure_color_plain "$PURE_COLOR_PATH")
    branch=$(__pure_color_plain "$PURE_COLOR_GIT_BRANCH")
    dirty=$(__pure_color_plain "$PURE_COLOR_GIT_DIRTY")
    action=$(__pure_color_plain "$PURE_COLOR_GIT_ACTION")
    arrows=$(__pure_color_plain "$PURE_COLOR_GIT_ARROW")
    stash=$(__pure_color_plain "$PURE_COLOR_GIT_STASH")
    node=$(__pure_color_plain "$PURE_COLOR_NODE_VERSION")
    time=$(__pure_color_plain "$PURE_COLOR_EXECUTION_TIME")
    suffix=$(__pure_color_plain "$PURE_COLOR_CUSTOM_SUFFIX")
    env=$(__pure_color_plain "$PURE_COLOR_VIRTUALENV")
    ok=$(__pure_color_plain "$PURE_COLOR_PROMPT_SUCCESS")
    err=$(__pure_color_plain "$PURE_COLOR_PROMPT_ERROR")
    cont=$(__pure_color_plain "$PURE_COLOR_PROMPT_CONTINUATION")

    printf '\n%sprefix%s %s%s%s %szaphod%s%s@heartofgold%s %s~/dev/pure%s %smain%s%s*%s %srebase-i%s %s%s%s%s %s%s%s %s%s22%s %s42s%s %ssuffix%s\n' \
        "$prefix" "$reset" "$jobs" "$PURE_SUSPENDED_JOBS_SYMBOL" "$reset" \
        "$user" "$reset" "$host" "$reset" "$path" "$reset" "$branch" "$reset" \
        "$dirty" "$reset" "$action" "$reset" "$arrows" "$PURE_GIT_DOWN_ARROW" "$PURE_GIT_UP_ARROW" "$reset" \
        "$stash" "$PURE_GIT_STASH_SYMBOL" "$reset" "$node" "$PURE_NODE_VERSION_SYMBOL" "$reset" \
        "$time" "$reset" "$suffix" "$reset"
    printf '%svenv%s %s%s%s\n\n%serror%s %s%s%s\n\n%s…%s %s%s%s\n' \
        "$env" "$reset" "$ok" "$PURE_PROMPT_SYMBOL" "$reset" \
        "$err" "$reset" "$err" "$PURE_PROMPT_SYMBOL" "$reset" \
        "$cont" "$reset" "$ok" "$PURE_PROMPT_SYMBOL" "$reset"
}

pure_bash_system_report() {
    printf '%s\n' \
        "Pure Bash: $__PURE_VERSION" \
        "Bash: $BASH_VERSION" \
        "Git: $(command git --version 2>/dev/null || printf unavailable)" \
        "TERM: ${TERM:-unknown}" \
        "Terminal: ${TERM_PROGRAM:-unknown} ${TERM_PROGRAM_VERSION:-}" \
        "Tmux: $([[ -n ${TMUX:-} ]] && printf yes || printf no)" \
        "Git integration: $PURE_GIT" \
        "Async auto-fetch: $PURE_GIT_PULL"
}

pure_bash_setup() {
    (( __PURE_SETUP_DONE )) && return 0

    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
        printf 'pure.bash requires Bash 4.4 or newer (found %s).\n' "$BASH_VERSION" >&2
        return 1
    fi

    __PURE_SETUP_DONE=1
    __PURE_ORIGINAL_PS1=${PS1-}
    __PURE_ORIGINAL_PS2=${PS2-}
    __PURE_ORIGINAL_PS0=${PS0-}

    # PS0 is expanded exactly once after Bash reads a complete command and before
    # execution. A zero-length substring lets us stamp SECONDS without printing
    # anything and without installing a DEBUG trap.
    PS0='${PS1:$((__PURE_CMD_START=SECONDS,0)):0}'"${PS0-}"

    local prompt_decl
    prompt_decl=$(declare -p PROMPT_COMMAND 2>/dev/null || true)
    if [[ $prompt_decl == 'declare -a '* ]]; then
        local item found=0
        for item in "${PROMPT_COMMAND[@]}"; do
            [[ $item == __pure_prompt_command ]] && found=1
        done
        (( found )) || PROMPT_COMMAND=(__pure_capture_status "${PROMPT_COMMAND[@]}" __pure_prompt_command)
    else
        if [[ ${PROMPT_COMMAND:-} != *'__pure_prompt_command'* ]]; then
            PROMPT_COMMAND="__pure_capture_status${PROMPT_COMMAND:+;${PROMPT_COMMAND}};__pure_prompt_command"
        fi
    fi

    __pure_set_remote_identity
    return 0
}

if [[ ${PURE_BASH_NO_SETUP:-0} != 1 && $- == *i* ]]; then
    pure_bash_setup
fi
