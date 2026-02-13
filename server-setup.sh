#!/bin/bash
# server-setup.sh — Modular LAMP/LEMP stack installer
# Supports Ubuntu/Debian, RHEL/CentOS/Rocky/AlmaLinux/Fedora, and macOS
# Usage: sudo ./server-setup.sh [OPTIONS]
# Run with --help for full usage information.

# Resolve script directory (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/platform.sh"
source "${SCRIPT_DIR}/lib/cli.sh"
source "${SCRIPT_DIR}/lib/config.sh"

# Source modules
source "${SCRIPT_DIR}/modules/php.sh"
source "${SCRIPT_DIR}/modules/webserver.sh"
source "${SCRIPT_DIR}/modules/database.sh"
source "${SCRIPT_DIR}/modules/phpmyadmin.sh"
source "${SCRIPT_DIR}/modules/firewall.sh"
source "${SCRIPT_DIR}/modules/ssl.sh"
source "${SCRIPT_DIR}/modules/extras.sh"
source "${SCRIPT_DIR}/modules/vhost.sh"

# --- Main ---

main() {
    # Parse CLI arguments
    parse_args "$@"

    # Handle --help and --version early (already handled in parse_args via exit)

    # Setup error traps
    setup_traps

    # Detect platform
    local os
    os=$(detect_os)
    local arch
    arch=$(detect_arch)

    # Initialize state directory
    init_state_dir "$os"

    # Handle clear-state early
    if [[ "$SS_ACTION" == "clear-state" ]]; then
        clear_state
        log_success "State cleared. Next run will start fresh."
        exit 0
    fi

    # Load configuration (defaults → config file → env vars)
    init_config "$SCRIPT_DIR"

    log_info "server-setup v${SS_VERSION}"
    log_info "Platform: ${os} (${arch})"
    [[ "$SS_DRY_RUN" == "true" ]] && log_warn "DRY RUN MODE — no changes will be made."

    # Platform-specific prerequisites
    if [[ "$os" == "linux" ]]; then
        check_root
        check_linux_distro  # sets SS_DISTRO_FAMILY
        local distro
        distro=$(detect_distro)
        log_info "Distro: ${distro} (${SS_DISTRO_FAMILY} family)"
        log_info "Updating system packages..."
        pkg_update linux
        pkg_upgrade linux
    else
        check_root
        SS_DISTRO_FAMILY="macos"
        ensure_homebrew
    fi

    # Dispatch action
    case "$SS_ACTION" in
        install)
            _run_install "$os"
            ;;
        uninstall)
            source "${SCRIPT_DIR}/uninstall.sh"
            run_uninstall "$os"
            ;;
        update)
            source "${SCRIPT_DIR}/update.sh"
            run_update "$os"
            ;;
        *)
            log_error "Unknown action: $SS_ACTION"
            exit 1
            ;;
    esac
}

_run_install() {
    local os="$1"

    log_info "Starting installation..."

    # Core stack
    install_php "$os"
    install_webserver "$os"
    install_database "$os"
    install_phpmyadmin "$os"

    # Security
    install_firewall "$os"
    install_ssl "$os"

    # Extras
    install_extras "$os"

    # Summary
    echo ""
    log_success "============================================"
    log_success "  Installation Complete!"
    log_success "============================================"
    echo ""

    local web_server
    web_server=$(load_state "web_server")
    local php_versions
    php_versions=$(load_state "php_versions")
    local highest
    highest=$(load_state "highest_php_version")

    log_info "PHP versions:    $php_versions (primary: $highest)"
    log_info "Web server:      $web_server"
    log_info "Database:        MariaDB"

    if [[ -f "$SS_CREDENTIALS_FILE" ]]; then
        log_info "Credentials:     $SS_CREDENTIALS_FILE"
    fi

    if [[ "${CFG_INSTALL_PHPMYADMIN,,}" == "yes" ]]; then
        log_info "phpMyAdmin:      http://localhost/phpmyadmin"
    fi

    echo ""
    log_warn "Review your credentials file and delete it once noted:"
    log_warn "  cat $SS_CREDENTIALS_FILE"
    echo ""
}

main "$@"
