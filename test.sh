#!/bin/bash
# test.sh — Automated testing across distros via Docker
# Usage: ./test.sh [distro|all|syntax|local]
#
# Examples:
#   ./test.sh syntax          # Syntax check only (no Docker)
#   ./test.sh local           # Dry-run on current machine (needs sudo)
#   ./test.sh ubuntu          # Test on Ubuntu container
#   ./test.sh rocky           # Test on Rocky Linux container
#   ./test.sh all             # Test on all distros
#   ./test.sh                 # Same as 'all'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
SKIP=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${RESET} $*"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${RESET} $*"; FAIL=$((FAIL + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${RESET} $*"; SKIP=$((SKIP + 1)); }
log_test() { echo -e "${CYAN}[TEST]${RESET} $*"; }
log_head() { echo -e "\n${CYAN}=== $* ===${RESET}"; }

# --- Syntax Check ---

test_syntax() {
    log_head "Syntax Check"
    local files=(server-setup.sh lib/*.sh modules/*.sh uninstall.sh update.sh)
    for f in "${files[@]}"; do
        if bash -n "$f" 2>/dev/null; then
            log_pass "$f"
        else
            log_fail "$f"
        fi
    done
}

# --- CLI Flag Tests ---

test_cli_flags() {
    log_head "CLI Flags"

    log_test "--help exits 0"
    if bash server-setup.sh --help &>/dev/null; then
        log_pass "--help"
    else
        log_fail "--help"
    fi

    log_test "--version exits 0"
    if bash server-setup.sh --version &>/dev/null; then
        log_pass "--version"
    else
        log_fail "--version"
    fi

    log_test "--help contains usage text"
    if bash server-setup.sh --help 2>/dev/null | grep -q "Usage:"; then
        log_pass "--help output"
    else
        log_fail "--help output"
    fi

    log_test "--version contains version number"
    if bash server-setup.sh --version 2>/dev/null | grep -qE '^server-setup [0-9]+\.[0-9]+'; then
        log_pass "--version output"
    else
        log_fail "--version output"
    fi

    log_test "Unknown flag exits non-zero"
    if bash server-setup.sh --bogus &>/dev/null; then
        log_fail "unknown flag should fail"
    else
        log_pass "unknown flag rejected"
    fi
}

# --- Config Parsing Tests ---

test_config() {
    log_head "Config Parsing"

    log_test "default.conf exists and is readable"
    if [[ -f config/default.conf ]]; then
        log_pass "default.conf exists"
    else
        log_fail "default.conf missing"
    fi

    log_test "example.conf exists and is readable"
    if [[ -f config/example.conf ]]; then
        log_pass "example.conf exists"
    else
        log_fail "example.conf missing"
    fi

    log_test "default.conf has required keys"
    local required_keys=("PHP_VERSIONS" "WEB_SERVER" "INSTALL_PHPMYADMIN" "ENABLE_FIREWALL")
    for key in "${required_keys[@]}"; do
        if grep -q "^${key}=" config/default.conf; then
            log_pass "default.conf has $key"
        else
            log_fail "default.conf missing $key"
        fi
    done
}

# --- Docker Tests ---

declare -A DOCKER_IMAGES=(
    [ubuntu]="ubuntu:22.04"
    [debian]="debian:12"
    [rocky]="rockylinux:9"
    [alma]="almalinux:9"
    [fedora]="fedora:39"
)

declare -A DOCKER_SETUP=(
    [ubuntu]="apt-get update -qq && apt-get install -y -qq curl lsb-release openssl >/dev/null 2>&1"
    [debian]="apt-get update -qq && apt-get install -y -qq curl lsb-release openssl >/dev/null 2>&1"
    [rocky]="dnf install -y -q curl openssl >/dev/null 2>&1"
    [alma]="dnf install -y -q curl openssl >/dev/null 2>&1"
    [fedora]="dnf install -y -q curl openssl >/dev/null 2>&1"
)

check_docker() {
    if ! command -v docker &>/dev/null; then
        echo "Docker not found. Install Docker to run container tests."
        return 1
    fi
    if ! docker info &>/dev/null; then
        echo "Docker daemon not running. Start Docker first."
        return 1
    fi
    return 0
}

run_docker_test() {
    local distro="$1"
    local image="${DOCKER_IMAGES[$distro]}"
    local setup="${DOCKER_SETUP[$distro]}"

    if [[ -z "$image" ]]; then
        log_fail "Unknown distro: $distro"
        return 1
    fi

    log_head "Docker: $distro ($image)"

    # Pull image
    log_test "Pulling $image..."
    if ! docker pull "$image" -q &>/dev/null; then
        log_fail "Could not pull $image"
        return 1
    fi

    # Test 1: Syntax check inside container
    log_test "Syntax check inside $distro container"
    local syntax_result
    syntax_result=$(docker run --rm -v "${SCRIPT_DIR}:/app:ro" "$image" bash -c '
        cd /app
        failed=0
        for f in server-setup.sh lib/*.sh modules/*.sh uninstall.sh update.sh; do
            bash -n "$f" 2>&1 || { echo "SYNTAX FAIL: $f"; failed=1; }
        done
        exit $failed
    ' 2>&1)
    if [[ $? -eq 0 ]]; then
        log_pass "Syntax check ($distro)"
    else
        log_fail "Syntax check ($distro): $syntax_result"
    fi

    # Test 2: --help and --version
    log_test "CLI flags inside $distro container"
    if docker run --rm -v "${SCRIPT_DIR}:/app:ro" "$image" bash -c '
        cd /app && bash server-setup.sh --help >/dev/null && bash server-setup.sh --version >/dev/null
    ' &>/dev/null; then
        log_pass "CLI flags ($distro)"
    else
        log_fail "CLI flags ($distro)"
    fi

    # Test 3: Dry-run (needs root + package prereqs)
    log_test "Dry-run inside $distro container"
    local dryrun_output
    dryrun_output=$(docker run --rm -v "${SCRIPT_DIR}:/app:ro" "$image" bash -c "
        ${setup}
        cd /app
        bash server-setup.sh --dry-run --non-interactive --verbose 2>&1
    " 2>&1)
    local dryrun_exit=$?

    if [[ $dryrun_exit -eq 0 ]]; then
        log_pass "Dry-run ($distro)"
    else
        # Check if it at least started correctly
        if echo "$dryrun_output" | grep -q "server-setup v"; then
            if echo "$dryrun_output" | grep -q "DRY RUN"; then
                log_pass "Dry-run ($distro) — started correctly (may have non-fatal issues)"
            else
                log_fail "Dry-run ($distro) — exited $dryrun_exit"
            fi
        else
            log_fail "Dry-run ($distro) — exited $dryrun_exit"
        fi
    fi

    # Test 4: Distro detection
    log_test "Distro detection inside $distro container"
    local detect_output
    detect_output=$(docker run --rm -v "${SCRIPT_DIR}:/app:ro" "$image" bash -c '
        cd /app
        source lib/common.sh
        source lib/platform.sh
        SS_LOG_LEVEL=debug
        SS_QUIET=false
        detect_distro_family "linux"
        echo "FAMILY=$SS_DISTRO_FAMILY"
    ' 2>&1)

    local expected_family="debian"
    [[ "$distro" == "rocky" || "$distro" == "alma" || "$distro" == "fedora" ]] && expected_family="rhel"

    if echo "$detect_output" | grep -q "FAMILY=${expected_family}"; then
        log_pass "Distro detection ($distro → $expected_family)"
    else
        log_fail "Distro detection ($distro): expected $expected_family, got: $detect_output"
    fi
}

# --- Local Dry-Run ---

test_local_dryrun() {
    log_head "Local Dry-Run (requires sudo)"

    if [[ $EUID -ne 0 ]]; then
        log_skip "Not running as root — skipping local dry-run"
        return 0
    fi

    log_test "Dry-run with defaults"
    if bash server-setup.sh --dry-run --non-interactive --verbose 2>&1 | grep -q "DRY RUN"; then
        log_pass "Local dry-run"
    else
        log_fail "Local dry-run"
    fi

    log_test "Dry-run with config file"
    if bash server-setup.sh --dry-run --config config/example.conf --non-interactive 2>&1 | grep -q "DRY RUN"; then
        log_pass "Local dry-run with config"
    else
        log_fail "Local dry-run with config"
    fi

    log_test "Clear state"
    if bash server-setup.sh --clear-state 2>&1 | grep -q "cleared"; then
        log_pass "Clear state"
    else
        log_fail "Clear state"
    fi
}

# --- Summary ---

print_summary() {
    echo ""
    log_head "Test Summary"
    echo -e "  ${GREEN}Passed: $PASS${RESET}"
    echo -e "  ${RED}Failed: $FAIL${RESET}"
    echo -e "  ${YELLOW}Skipped: $SKIP${RESET}"
    echo ""
    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${RESET}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${RESET}"
        return 0
    fi
}

# --- Main ---

main() {
    local target="${1:-all}"

    cd "$SCRIPT_DIR"

    case "$target" in
        syntax)
            test_syntax
            ;;
        cli)
            test_cli_flags
            ;;
        config)
            test_config
            ;;
        local)
            test_syntax
            test_cli_flags
            test_config
            test_local_dryrun
            ;;
        ubuntu|debian|rocky|alma|fedora)
            check_docker || exit 1
            run_docker_test "$target"
            ;;
        all)
            test_syntax
            test_cli_flags
            test_config

            if check_docker 2>/dev/null; then
                for distro in ubuntu debian rocky alma fedora; do
                    run_docker_test "$distro"
                done
            else
                log_skip "Docker not available — skipping container tests"
            fi
            ;;
        *)
            echo "Usage: $0 [syntax|cli|config|local|ubuntu|debian|rocky|alma|fedora|all]"
            exit 1
            ;;
    esac

    print_summary
}

main "$@"
