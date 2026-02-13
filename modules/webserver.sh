#!/usr/bin/env bash
# modules/webserver.sh — Apache/NGINX installation and configuration

install_webserver() {
    local os="$1"

    if step_completed "webserver"; then
        log_info "Web server installation already completed. Skipping."
        return 0
    fi

    log_info "=== Web Server Installation ==="

    # Get web server choice
    local web_server
    web_server=$(load_state "web_server")

    if [[ -z "$web_server" ]]; then
        web_server="$CFG_WEB_SERVER"

        if [[ -z "$web_server" ]] && [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
            read -rp "Enter the web server to install (apache or nginx): " web_server
        fi

        web_server=$(validate_web_server "${web_server:-nginx}") || {
            log_error "Invalid web server choice: '$web_server'. Must be 'apache' or 'nginx'."
            exit 1
        }
    fi

    save_state "web_server" "$web_server"

    if [[ "$os" == "linux" ]]; then
        _install_webserver_linux "$web_server"
    else
        _install_webserver_macos "$web_server"
    fi

    log_success "Web server '$web_server' installed and started."
    mark_step_completed "webserver"
}

_install_webserver_linux() {
    local web_server="$1"
    local apache_pkg
    apache_pkg=$(get_apache_pkg)
    local apache_svc
    apache_svc=$(get_apache_svc)

    if [[ "$web_server" == "apache" ]]; then
        log_info "Installing Apache ($apache_pkg)..."
        pkg_install linux "$apache_pkg"
        pkg_remove linux nginx || true

        # Enable common modules on RHEL
        if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            # mod_ssl and mod_rewrite are typically needed
            pkg_install linux mod_ssl || true
        fi

        service_start linux "$apache_svc"
    elif [[ "$web_server" == "nginx" ]]; then
        log_info "Installing NGINX..."
        pkg_install linux nginx
        pkg_remove linux "$apache_pkg" || true
        service_start linux nginx
    fi
}

_install_webserver_macos() {
    local web_server="$1"

    if [[ "$web_server" == "apache" ]]; then
        log_info "Installing Apache via Homebrew..."
        pkg_install macos httpd
        service_start macos httpd
    elif [[ "$web_server" == "nginx" ]]; then
        log_info "Installing NGINX via Homebrew..."
        pkg_install macos nginx
        service_start macos nginx
    fi
}
