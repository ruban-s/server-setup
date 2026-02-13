#!/usr/bin/env bash
# common.sh — Logging, traps, validation, password handling, state management

# Strict mode
set -euo pipefail

# Constants
readonly SS_VERSION="2.0.0"
readonly SS_STATE_DIR_LINUX="/var/tmp/servforge"
readonly SS_STATE_DIR_MAC="${HOME}/.servforge"
readonly SS_LOG_FILE="/var/log/servforge.log"
readonly SS_CREDENTIALS_FILE_NAME="credentials"

# Globals (set during init)
SS_STATE_DIR=""
SS_STATE_FILE=""
SS_CREDENTIALS_FILE=""
SS_DRY_RUN="${SS_DRY_RUN:-false}"
SS_LOG_LEVEL="${SS_LOG_LEVEL:-info}"
SS_VERBOSE="${SS_VERBOSE:-false}"
SS_QUIET="${SS_QUIET:-false}"

# --- Logging ---

_log_level_num() {
    case "$1" in
        error) echo 0 ;;
        warn)  echo 1 ;;
        info)  echo 2 ;;
        debug) echo 3 ;;
        *)     echo 2 ;;
    esac
}

_log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local current_level
    current_level=$(_log_level_num "$SS_LOG_LEVEL")
    local msg_level
    msg_level=$(_log_level_num "$level")

    if [[ $msg_level -le $current_level ]]; then
        local color=""
        local prefix=""
        case "$level" in
            error)   color="\033[0;31m"; prefix="ERROR" ;;
            warn)    color="\033[0;33m"; prefix="WARN " ;;
            info)    color="\033[0;36m"; prefix="INFO " ;;
            debug)   color="\033[0;90m"; prefix="DEBUG" ;;
        esac
        local reset="\033[0m"

        # Write to log file (no color)
        if [[ -w "$(dirname "$SS_LOG_FILE")" ]] 2>/dev/null; then
            echo "[$timestamp] [$prefix] $msg" >> "$SS_LOG_FILE" 2>/dev/null || true
        fi

        # Write to stdout (with color) unless quiet
        if [[ "$SS_QUIET" != "true" ]]; then
            echo -e "${color}[$prefix]${reset} $msg"
        fi
    fi
}

log_info()    { _log info "$@"; }
log_warn()    { _log warn "$@"; }
log_error()   { _log error "$@"; }
log_success() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ -w "$(dirname "$SS_LOG_FILE")" ]] 2>/dev/null; then
        echo "[$timestamp] [ OK  ] $*" >> "$SS_LOG_FILE" 2>/dev/null || true
    fi
    if [[ "$SS_QUIET" != "true" ]]; then
        echo -e "\033[0;32m[ OK  ]\033[0m $*"
    fi
}
log_debug()   { _log debug "$@"; }

# --- Dry Run Wrapper ---

run_cmd() {
    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] $*"
        return 0
    fi
    log_debug "Running: $*"
    "$@"
}

# --- Trap Handlers ---

_cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with code $exit_code. State has been saved — re-run to resume."
    fi
}

setup_traps() {
    trap _cleanup EXIT
    trap 'log_error "Interrupted by user."; exit 130' INT
    trap 'log_error "Terminated."; exit 143' TERM
}

# --- State Management ---

init_state_dir() {
    local os="$1"
    if [[ "$os" == "macos" ]]; then
        SS_STATE_DIR="$SS_STATE_DIR_MAC"
    else
        SS_STATE_DIR="$SS_STATE_DIR_LINUX"
    fi
    SS_STATE_FILE="${SS_STATE_DIR}/state"
    SS_CREDENTIALS_FILE="${SS_STATE_DIR}/${SS_CREDENTIALS_FILE_NAME}"
    mkdir -p "$SS_STATE_DIR"
    chmod 700 "$SS_STATE_DIR"
    if [[ ! -f "$SS_STATE_FILE" ]]; then
        touch "$SS_STATE_FILE"
    fi
}

save_state() {
    local key="$1"
    local value="$2"
    # Remove existing key if present, then append
    if [[ -f "$SS_STATE_FILE" ]]; then
        local tmp="${SS_STATE_FILE}.tmp"
        grep -v "^${key}=" "$SS_STATE_FILE" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$SS_STATE_FILE"
    fi
    echo "${key}=${value}" >> "$SS_STATE_FILE"
}

load_state() {
    local key="$1"
    local default="${2:-}"
    if [[ -f "$SS_STATE_FILE" ]]; then
        local val
        val=$(grep "^${key}=" "$SS_STATE_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2-)
        if [[ -n "$val" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

step_completed() {
    local step="$1"
    local val
    val=$(load_state "step_${step}")
    [[ "$val" == "done" ]]
}

mark_step_completed() {
    local step="$1"
    save_state "step_${step}" "done"
    log_debug "Step '$step' marked as completed."
}

clear_state() {
    if [[ -f "$SS_STATE_FILE" ]]; then
        rm -f "$SS_STATE_FILE"
        log_info "State cleared."
    fi
}

# --- Password Handling ---

generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

save_credential() {
    local key="$1"
    local value="$2"
    if [[ ! -f "$SS_CREDENTIALS_FILE" ]]; then
        touch "$SS_CREDENTIALS_FILE"
        chmod 600 "$SS_CREDENTIALS_FILE"
    fi
    # Remove existing key, then append
    local tmp="${SS_CREDENTIALS_FILE}.tmp"
    grep -v "^${key}=" "$SS_CREDENTIALS_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$SS_CREDENTIALS_FILE"
    chmod 600 "$SS_CREDENTIALS_FILE"
    echo "${key}=${value}" >> "$SS_CREDENTIALS_FILE"
    chmod 600 "$SS_CREDENTIALS_FILE"
}

load_credential() {
    local key="$1"
    local default="${2:-}"
    if [[ -f "$SS_CREDENTIALS_FILE" ]]; then
        local val
        val=$(grep "^${key}=" "$SS_CREDENTIALS_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2-)
        if [[ -n "$val" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

# --- Input Validation ---

sanitize_php_version() {
    local ver="$1"
    ver=$(echo "$ver" | xargs)  # trim whitespace
    if [[ "$ver" =~ ^[5-8]\.[0-9]{1,2}$ ]]; then
        echo "$ver"
        return 0
    fi
    return 1
}

validate_web_server() {
    local ws="$1"
    ws="${ws,,}"  # lowercase
    if [[ "$ws" == "apache" || "$ws" == "nginx" ]]; then
        echo "$ws"
        return 0
    fi
    return 1
}

validate_yes_no() {
    local val="$1"
    val="${val,,}"
    if [[ "$val" == "yes" || "$val" == "y" ]]; then
        echo "yes"
    elif [[ "$val" == "no" || "$val" == "n" ]]; then
        echo "no"
    else
        return 1
    fi
}

# --- Service Health ---

check_service_health() {
    local service="$1"
    local os="$2"
    if [[ "$os" == "macos" ]]; then
        brew services list 2>/dev/null | grep -q "${service}.*started"
    else
        systemctl is-active --quiet "$service" 2>/dev/null
    fi
}

# --- Progress ---

spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[0;36m%s\033[0m %s" "${chars:i%${#chars}:1}" "$msg"
        i=$((i + 1))
        sleep 0.1
    done
    printf "\r\033[K"
}
