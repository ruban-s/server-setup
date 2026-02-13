#!/usr/bin/env bash
# modules/firewall.sh — Firewall configuration (ufw/firewalld on Linux, pf on macOS)

install_firewall() {
    local os="$1"

    if step_completed "firewall"; then
        log_info "Firewall configuration already completed. Skipping."
        return 0
    fi

    if [[ "${CFG_ENABLE_FIREWALL,,}" != "yes" ]]; then
        log_info "Firewall configuration disabled in config. Skipping."
        return 0
    fi

    log_info "=== Firewall Configuration ==="

    local -a ports=()
    IFS=',' read -ra ports <<< "${CFG_FIREWALL_PORTS:-22,80,443}"

    if [[ "$os" == "linux" ]]; then
        if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            _configure_firewalld "${ports[@]}"
        else
            _configure_ufw "${ports[@]}"
        fi
    else
        _configure_pf_macos "${ports[@]}"
    fi

    log_success "Firewall configured."
    mark_step_completed "firewall"
}

# --- Debian/Ubuntu: ufw ---

_configure_ufw() {
    local ports=("$@")

    log_info "Installing and configuring ufw..."
    pkg_install linux ufw

    run_cmd ufw --force reset
    run_cmd ufw default deny incoming
    run_cmd ufw default allow outgoing

    for port in "${ports[@]}"; do
        port=$(echo "$port" | xargs)
        log_info "Allowing port $port..."
        run_cmd ufw allow "$port"
    done

    run_cmd ufw --force enable
    log_info "ufw status:"
    ufw status verbose 2>/dev/null || true
}

# --- RHEL/CentOS: firewalld ---

_configure_firewalld() {
    local ports=("$@")

    log_info "Installing and configuring firewalld..."
    pkg_install linux firewalld

    service_start linux firewalld

    for port in "${ports[@]}"; do
        port=$(echo "$port" | xargs)
        log_info "Allowing port ${port}/tcp..."
        run_cmd firewall-cmd --permanent --add-port="${port}/tcp"
    done

    run_cmd firewall-cmd --reload
    log_info "firewalld status:"
    firewall-cmd --list-all 2>/dev/null || true
}

# --- macOS: pf ---

_configure_pf_macos() {
    local ports=("$@")

    log_info "Configuring pf firewall on macOS..."

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure pf with ports: ${ports[*]}"
        return 0
    fi

    local anchor_file="/etc/pf.anchors/server-setup"

    {
        echo "# server-setup firewall rules"
        echo "# Generated on $(date)"
        echo ""
        echo "# Block all incoming by default"
        echo "block in all"
        echo "# Allow loopback"
        echo "pass in on lo0 all"
        echo "# Allow established connections"
        echo "pass out all keep state"
        for port in "${ports[@]}"; do
            port=$(echo "$port" | xargs)
            echo "pass in proto tcp from any to any port $port"
        done
    } > "$anchor_file"

    if ! grep -q "server-setup" /etc/pf.conf 2>/dev/null; then
        echo 'anchor "server-setup"' >> /etc/pf.conf
        echo 'load anchor "server-setup" from "/etc/pf.anchors/server-setup"' >> /etc/pf.conf
    fi

    run_cmd pfctl -f /etc/pf.conf 2>/dev/null || log_warn "Could not reload pf. You may need to enable it manually."
    log_info "pf anchor configured at: $anchor_file"
}
