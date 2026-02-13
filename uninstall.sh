#!/usr/bin/env bash
# uninstall.sh — Clean removal of installed components
# Sourced by server-setup.sh when --uninstall is passed.

run_uninstall() {
    local os="$1"

    log_info "=== Uninstalling server-setup components ==="

    if [[ ! -f "$SS_STATE_FILE" ]]; then
        log_error "No state file found. Nothing to uninstall."
        exit 1
    fi

    # Check if this was a Docker installation
    local install_method
    install_method=$(load_state "install_method")
    if [[ "$install_method" == "docker" ]]; then
        _uninstall_docker
        clear_state
        log_success "Uninstall complete."
        return
    fi

    # Show what's installed
    echo ""
    log_info "Installed components (from state file):"
    local php_versions web_server
    php_versions=$(load_state "php_versions")
    web_server=$(load_state "web_server")

    [[ -n "$php_versions" ]] && log_info "  PHP: $php_versions"
    [[ -n "$web_server" ]]   && log_info "  Web server: $web_server"
    step_completed "database"      && log_info "  MariaDB"
    step_completed "phpmyadmin"    && log_info "  phpMyAdmin"
    step_completed "firewall"      && log_info "  Firewall"
    step_completed "ssl"           && log_info "  SSL (certbot)"
    step_completed "composer"      && log_info "  Composer"
    step_completed "redis"         && log_info "  Redis"
    step_completed "nodejs"        && log_info "  Node.js"
    step_completed "elasticsearch" && log_info "  Elasticsearch"
    echo ""

    if [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
        read -rp "Proceed with uninstall? (yes/no): " confirm
        if [[ "${confirm,,}" != "yes" && "${confirm,,}" != "y" ]]; then
            log_info "Uninstall cancelled."
            exit 0
        fi

        read -rp "Backup databases before removal? (yes/no) [yes]: " backup_db
        backup_db="${backup_db:-yes}"
        if [[ "${backup_db,,}" == "yes" || "${backup_db,,}" == "y" ]]; then
            _backup_databases "$os"
        fi
    fi

    # Remove in reverse order
    _uninstall_extras "$os"
    _uninstall_ssl "$os"
    _uninstall_firewall "$os"
    _uninstall_phpmyadmin "$os"
    _uninstall_database "$os"
    _uninstall_webserver "$os"
    _uninstall_php "$os"

    # Clear state
    clear_state
    log_success "Uninstall complete."
}

_uninstall_docker() {
    local docker_dir
    docker_dir=$(load_state "docker_output_dir")
    if [[ -z "$docker_dir" ]]; then
        docker_dir="${SCRIPT_DIR}/docker-output"
    fi

    log_info "Removing Docker Compose stack..."

    if [[ -f "${docker_dir}/docker-compose.yml" ]]; then
        if [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
            read -rp "This will stop all containers and remove volumes. Proceed? (yes/no): " confirm
            if [[ "${confirm,,}" != "yes" && "${confirm,,}" != "y" ]]; then
                log_info "Uninstall cancelled."
                exit 0
            fi
        fi

        run_cmd docker compose -f "${docker_dir}/docker-compose.yml" down -v --remove-orphans
        run_cmd rm -rf "$docker_dir"
        log_success "Docker stack and generated files removed."
    else
        log_warn "No docker-compose.yml found at ${docker_dir}. Cleaning up state only."
    fi
}

_backup_databases() {
    local os="$1"
    local backup_dir="${HOME}/server-setup-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    log_info "Backing up databases to $backup_dir..."

    local password
    password=$(load_credential "mariadb_root_password")

    if [[ -n "$password" ]]; then
        local tmpfile
        tmpfile=$(mktemp)
        chmod 600 "$tmpfile"
        cat > "$tmpfile" <<EOF
[client]
user=root
password=${password}
EOF
        mysqldump --defaults-extra-file="$tmpfile" --all-databases > "${backup_dir}/all-databases.sql" 2>/dev/null && \
            log_success "Database backup saved to: ${backup_dir}/all-databases.sql" || \
            log_warn "Database backup failed. You may need to back up manually."
        rm -f "$tmpfile"
    else
        mysqldump -u root --all-databases > "${backup_dir}/all-databases.sql" 2>/dev/null || \
            log_warn "Database backup failed. You may need to back up manually."
    fi
}

_uninstall_extras() {
    local os="$1"
    if step_completed "elasticsearch"; then
        log_info "Removing Elasticsearch..."
        if [[ "$os" == "macos" ]]; then
            pkg_remove macos elasticsearch
        else
            service_stop linux elasticsearch
            pkg_remove linux elasticsearch
        fi
    fi
    if step_completed "nodejs"; then
        log_info "Removing Node.js..."
        local version="${CFG_NODEJS_VERSION:-20}"
        if [[ "$os" == "macos" ]]; then
            pkg_remove macos "node@${version}"
        else
            pkg_remove linux nodejs
        fi
    fi
    if step_completed "redis"; then
        log_info "Removing Redis..."
        local redis_pkg
        redis_pkg=$(get_redis_pkg)
        local redis_svc
        redis_svc=$(get_redis_svc)
        if [[ "$os" == "macos" ]]; then
            service_stop macos redis
            pkg_remove macos redis
        else
            service_stop linux "$redis_svc"
            pkg_remove linux "$redis_pkg"
        fi
    fi
    if step_completed "composer"; then
        log_info "Removing Composer..."
        if [[ "$os" == "macos" ]]; then
            pkg_remove macos composer
        else
            rm -f /usr/local/bin/composer
        fi
    fi
}

_uninstall_ssl() {
    local os="$1"
    if step_completed "ssl"; then
        log_info "Removing certbot..."
        if [[ "$os" == "macos" ]]; then
            pkg_remove macos certbot
            rm -f /Library/LaunchDaemons/com.server-setup.certbot-renew.plist
        else
            snap remove certbot 2>/dev/null || pkg_remove linux certbot
        fi
    fi
}

_uninstall_firewall() {
    local os="$1"
    if step_completed "firewall"; then
        log_info "Resetting firewall..."
        if [[ "$os" == "macos" ]]; then
            rm -f /etc/pf.anchors/server-setup
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            # Reset firewalld to defaults
            run_cmd firewall-cmd --reload 2>/dev/null || true
        else
            run_cmd ufw --force disable 2>/dev/null || true
        fi
    fi
}

_uninstall_phpmyadmin() {
    local os="$1"
    if step_completed "phpmyadmin"; then
        log_info "Removing phpMyAdmin..."
        if [[ "$os" == "macos" ]]; then
            local brew_prefix
            brew_prefix=$(get_brew_prefix)
            rm -rf "${brew_prefix}/var/www/phpmyadmin"
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            rm -rf /usr/share/phpmyadmin
            rm -f /etc/httpd/conf.d/phpmyadmin.conf
            rm -f /etc/nginx/conf.d/phpmyadmin.conf
        else
            pkg_remove linux phpmyadmin
            rm -f /etc/apache2/conf-available/phpmyadmin.conf
            rm -f /etc/nginx/snippets/phpmyadmin.conf
        fi
    fi
}

_uninstall_database() {
    local os="$1"
    if step_completed "database"; then
        log_info "Removing MariaDB..."
        if [[ "$os" == "macos" ]]; then
            service_stop macos mariadb
            pkg_remove macos mariadb
        else
            service_stop linux mariadb
            pkg_remove linux mariadb-server
        fi
    fi
}

_uninstall_webserver() {
    local os="$1"
    local web_server
    web_server=$(load_state "web_server")
    if step_completed "webserver" && [[ -n "$web_server" ]]; then
        log_info "Removing $web_server..."
        if [[ "$os" == "macos" ]]; then
            local pkg="nginx"
            [[ "$web_server" == "apache" ]] && pkg="httpd"
            service_stop macos "$pkg"
            pkg_remove macos "$pkg"
        else
            local apache_pkg
            apache_pkg=$(get_apache_pkg)
            local pkg="nginx"
            [[ "$web_server" == "apache" ]] && pkg="$apache_pkg"
            local svc="nginx"
            [[ "$web_server" == "apache" ]] && svc=$(get_apache_svc)
            service_stop linux "$svc"
            pkg_remove linux "$pkg"
        fi
    fi
}

_uninstall_php() {
    local os="$1"
    if step_completed "php"; then
        local php_versions
        php_versions=$(load_state "php_versions")
        log_info "Removing PHP ($php_versions)..."
        IFS=',' read -ra versions <<< "$php_versions"
        if [[ "$os" == "macos" ]]; then
            for v in "${versions[@]}"; do
                pkg_remove macos "php@${v}"
            done
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            for v in "${versions[@]}"; do
                local ver_nodot="${v//./}"
                pkg_remove linux "php${ver_nodot}-php*" || true
            done
        else
            for v in "${versions[@]}"; do
                pkg_remove linux "php${v}*" || true
            done
        fi
    fi
}
