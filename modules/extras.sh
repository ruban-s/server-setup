#!/usr/bin/env bash
# modules/extras.sh — Composer, Redis, Node.js, Elasticsearch

install_extras() {
    local os="$1"

    log_info "=== Optional Extras ==="

    _install_composer "$os"
    _install_redis "$os"
    _install_nodejs "$os"
    _install_elasticsearch "$os"
}

# --- Composer ---

_install_composer() {
    local os="$1"

    if step_completed "composer"; then
        log_info "Composer already installed. Skipping."
        return 0
    fi

    if [[ "${CFG_INSTALL_COMPOSER,,}" != "yes" ]]; then
        log_debug "Composer installation disabled."
        return 0
    fi

    log_info "Installing Composer..."

    if [[ "$os" == "macos" ]]; then
        pkg_install macos composer
    else
        if [[ "$SS_DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would download and install Composer."
        else
            local tmpdir
            tmpdir=$(mktemp -d)
            curl -fsSL https://getcomposer.org/installer -o "${tmpdir}/composer-setup.php"
            php "${tmpdir}/composer-setup.php" --install-dir=/usr/local/bin --filename=composer
            rm -rf "$tmpdir"
        fi
    fi

    log_success "Composer installed."
    mark_step_completed "composer"
}

# --- Redis ---

_install_redis() {
    local os="$1"

    if step_completed "redis"; then
        log_info "Redis already installed. Skipping."
        return 0
    fi

    if [[ "${CFG_INSTALL_REDIS,,}" != "yes" ]]; then
        log_debug "Redis installation disabled."
        return 0
    fi

    log_info "Installing Redis..."

    local redis_pkg
    redis_pkg=$(get_redis_pkg)
    local redis_svc
    redis_svc=$(get_redis_svc)

    if [[ "$os" == "macos" ]]; then
        pkg_install macos redis
        service_start macos redis
    else
        pkg_install linux "$redis_pkg"
        service_start linux "$redis_svc"
    fi

    # Health check
    if [[ "$SS_DRY_RUN" != "true" ]]; then
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            log_success "Redis is running and healthy."
        else
            log_warn "Redis installed but health check failed. Check service status."
        fi
    fi

    mark_step_completed "redis"
}

# --- Node.js ---

_install_nodejs() {
    local os="$1"

    if step_completed "nodejs"; then
        log_info "Node.js already installed. Skipping."
        return 0
    fi

    if [[ "${CFG_INSTALL_NODEJS,,}" != "yes" ]]; then
        log_debug "Node.js installation disabled."
        return 0
    fi

    local version="${CFG_NODEJS_VERSION:-20}"
    log_info "Installing Node.js v${version}..."

    if [[ "$os" == "macos" ]]; then
        pkg_install macos "node@${version}"
        local brew_prefix
        brew_prefix=$(get_brew_prefix)
        local shell_profile
        shell_profile=$(get_shell_profile)
        if ! grep -q "node@${version}" "$shell_profile" 2>/dev/null; then
            echo "export PATH=\"${brew_prefix}/opt/node@${version}/bin:\$PATH\"" >> "$shell_profile"
        fi
    else
        if [[ "$SS_DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would add NodeSource repo and install Node.js v${version}."
        else
            # NodeSource setup script works for both Debian and RHEL families
            curl -fsSL "https://deb.nodesource.com/setup_${version}.x" | bash -
            pkg_install linux nodejs
        fi
    fi

    log_success "Node.js v${version} installed."
    mark_step_completed "nodejs"
}

# --- Elasticsearch ---

_install_elasticsearch() {
    local os="$1"

    if step_completed "elasticsearch"; then
        log_info "Elasticsearch already installed. Skipping."
        return 0
    fi

    if [[ "${CFG_INSTALL_ELASTICSEARCH,,}" != "yes" ]]; then
        log_debug "Elasticsearch installation disabled."
        return 0
    fi

    log_info "Installing Elasticsearch..."

    if [[ "$os" == "macos" ]]; then
        pkg_install macos elasticsearch
        service_start macos elasticsearch
    else
        if [[ "$SS_DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would add Elastic repo and install Elasticsearch."
        else
            if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
                _install_elasticsearch_rhel
            else
                _install_elasticsearch_debian
            fi
        fi
    fi

    # Basic health check
    if [[ "$SS_DRY_RUN" != "true" ]]; then
        sleep 5
        if curl -s http://localhost:9200 &>/dev/null; then
            log_success "Elasticsearch is running."
        else
            log_warn "Elasticsearch installed but may need time to start. Check: curl http://localhost:9200"
        fi
    fi

    mark_step_completed "elasticsearch"
}

_install_elasticsearch_debian() {
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
        > /etc/apt/sources.list.d/elastic-8.x.list
    pkg_update linux
    pkg_install linux elasticsearch
    service_start linux elasticsearch
}

_install_elasticsearch_rhel() {
    local dnf_cmd
    dnf_cmd=$(_get_dnf_cmd)

    # Import GPG key
    rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch 2>/dev/null

    # Add repo
    cat > /etc/yum.repos.d/elasticsearch.repo <<'REPO'
[elasticsearch]
name=Elasticsearch repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
REPO

    pkg_install linux elasticsearch
    service_start linux elasticsearch
}
