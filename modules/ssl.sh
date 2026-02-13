#!/usr/bin/env bash
# modules/ssl.sh — Let's Encrypt SSL via certbot

install_ssl() {
    local os="$1"

    if step_completed "ssl"; then
        log_info "SSL configuration already completed. Skipping."
        return 0
    fi

    if [[ "${CFG_ENABLE_SSL,,}" != "yes" ]]; then
        log_info "SSL configuration disabled in config. Skipping."
        return 0
    fi

    log_info "=== SSL Configuration (Let's Encrypt) ==="

    # Get domains
    local domains_str="${CFG_SSL_DOMAINS}"
    local email="${CFG_SSL_EMAIL}"

    if [[ -z "$domains_str" ]] && [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
        read -rp "Enter domain(s) for SSL (comma-separated): " domains_str
    fi

    if [[ -z "$domains_str" ]]; then
        log_error "No domains specified for SSL. Skipping."
        return 0
    fi

    if [[ -z "$email" ]] && [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
        read -rp "Enter email for Let's Encrypt notifications: " email
    fi

    # Install certbot
    if [[ "$os" == "linux" ]]; then
        _install_certbot_linux
    else
        _install_certbot_macos
    fi

    # Generate certificates
    local web_server
    web_server=$(load_state "web_server")
    local -a domain_args=()
    IFS=',' read -ra domains <<< "$domains_str"
    for d in "${domains[@]}"; do
        d=$(echo "$d" | xargs)
        domain_args+=("-d" "$d")
    done

    local certbot_plugin
    if [[ "$web_server" == "apache" ]]; then
        certbot_plugin="--apache"
    else
        certbot_plugin="--nginx"
    fi

    local email_arg=""
    if [[ -n "$email" ]]; then
        email_arg="--email $email"
    else
        email_arg="--register-unsafely-without-email"
    fi

    log_info "Requesting SSL certificates for: $domains_str"
    run_cmd certbot $certbot_plugin "${domain_args[@]}" $email_arg --non-interactive --agree-tos --redirect

    # Setup auto-renewal
    if [[ "$os" == "linux" ]]; then
        _setup_renewal_linux
    else
        _setup_renewal_macos
    fi

    save_state "ssl_domains" "$domains_str"
    log_success "SSL certificates installed and auto-renewal configured."
    mark_step_completed "ssl"
}

_install_certbot_linux() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        _install_certbot_rhel
    else
        _install_certbot_debian
    fi
}

_install_certbot_debian() {
    log_info "Installing certbot..."
    if command -v snap &>/dev/null; then
        run_cmd snap install --classic certbot 2>/dev/null || true
        if [[ ! -L /usr/bin/certbot ]]; then
            run_cmd ln -sf /snap/bin/certbot /usr/bin/certbot
        fi
    else
        local web_server
        web_server=$(load_state "web_server")
        local plugin_pkg="python3-certbot-nginx"
        [[ "$web_server" == "apache" ]] && plugin_pkg="python3-certbot-apache"
        pkg_install linux certbot "$plugin_pkg"
    fi
}

_install_certbot_rhel() {
    log_info "Installing certbot..."
    local dnf_cmd
    dnf_cmd=$(_get_dnf_cmd)
    local web_server
    web_server=$(load_state "web_server")

    # Try snap first, then fall back to dnf
    if command -v snap &>/dev/null; then
        run_cmd snap install --classic certbot 2>/dev/null || true
        if [[ ! -L /usr/bin/certbot ]]; then
            run_cmd ln -sf /snap/bin/certbot /usr/bin/certbot
        fi
    else
        local plugin_pkg="python3-certbot-nginx"
        [[ "$web_server" == "apache" ]] && plugin_pkg="python3-certbot-apache"
        pkg_install linux certbot "$plugin_pkg"
    fi
}

_install_certbot_macos() {
    log_info "Installing certbot via Homebrew..."
    pkg_install macos certbot
}

_setup_renewal_linux() {
    if systemctl list-timers 2>/dev/null | grep -q certbot; then
        log_info "Certbot auto-renewal timer already active."
    else
        log_info "Setting up certbot renewal cron..."
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    fi
}

_setup_renewal_macos() {
    local plist_path="/Library/LaunchDaemons/com.servforge.certbot-renew.plist"
    if [[ -f "$plist_path" ]]; then
        log_info "Certbot renewal launchd plist already exists."
        return 0
    fi

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create certbot renewal launchd plist."
        return 0
    fi

    cat > "$plist_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.servforge.certbot-renew</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/certbot</string>
        <string>renew</string>
        <string>--quiet</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
PLIST
    run_cmd launchctl load "$plist_path"
    log_info "Certbot renewal scheduled via launchd."
}
