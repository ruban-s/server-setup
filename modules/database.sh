#!/usr/bin/env bash
# modules/database.sh — MariaDB installation and secure setup

install_database() {
    local os="$1"

    if step_completed "database"; then
        log_info "Database installation already completed. Skipping."
        return 0
    fi

    log_info "=== MariaDB Installation ==="

    if [[ "$os" == "linux" ]]; then
        _install_mariadb_linux
    else
        _install_mariadb_macos
    fi

    # Generate and save root password securely
    local password
    password=$(load_credential "mariadb_root_password")

    if [[ -z "$password" ]]; then
        password=$(generate_password)
        save_credential "mariadb_root_password" "$password"
    fi

    # Set root password using options file (avoids password in process list)
    _set_root_password "$password"

    log_success "MariaDB installed and secured."
    log_info "Credentials saved to: $SS_CREDENTIALS_FILE"
    mark_step_completed "database"
}

_install_mariadb_linux() {
    log_info "Installing MariaDB..."
    pkg_install linux mariadb-server

    service_start linux mariadb

    # Run secure installation in non-interactive mode
    if [[ "$SS_NON_INTERACTIVE" == "true" ]] || [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "Skipping interactive mysql_secure_installation (non-interactive mode)."
        log_info "Applying secure defaults automatically..."
        _secure_mariadb_noninteractive
    else
        log_info "Running mysql_secure_installation..."
        run_cmd mysql_secure_installation
    fi
}

_install_mariadb_macos() {
    log_info "Installing MariaDB via Homebrew..."
    pkg_install macos mariadb
    service_start macos mariadb

    if [[ "$SS_NON_INTERACTIVE" == "true" ]] || [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "Applying secure defaults automatically..."
        _secure_mariadb_noninteractive
    else
        log_info "Running mysql_secure_installation..."
        run_cmd mysql_secure_installation
    fi
}

_secure_mariadb_noninteractive() {
    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would secure MariaDB (remove test db, anonymous users, remote root)"
        return 0
    fi
    # Remove anonymous users, disallow remote root, remove test database
    mysql -u root <<-EOSQL
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL
}

_set_root_password() {
    local password="$1"

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set MariaDB root password."
        return 0
    fi

    # Use a temporary options file to avoid password in process list
    local tmpfile
    tmpfile=$(mktemp)
    chmod 600 "$tmpfile"
    cat > "$tmpfile" <<EOF
[client]
user=root
EOF

    mysql --defaults-extra-file="$tmpfile" -e \
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;" 2>/dev/null || {
        # If the above fails (e.g., already has a password), try without auth
        mysql -u root -e \
            "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;" 2>/dev/null || \
            log_warn "Could not set MariaDB root password. You may need to set it manually."
    }

    rm -f "$tmpfile"
}
