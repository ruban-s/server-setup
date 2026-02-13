#!/usr/bin/env bash
# update.sh — Update installed components
# Sourced by servforge.sh when --update is passed.

run_update() {
    local os="$1"

    log_info "=== Updating servforge components ==="

    if [[ ! -f "$SS_STATE_FILE" ]]; then
        log_error "No state file found. Nothing to update."
        exit 1
    fi

    # Check if this was a Docker installation
    local install_method
    install_method=$(load_state "install_method")
    if [[ "$install_method" == "docker" ]]; then
        _update_docker
        return
    fi

    # Update system packages first
    log_info "Updating system packages..."
    pkg_update "$os"

    # Update installed components
    local web_server
    web_server=$(load_state "web_server")
    local php_versions
    php_versions=$(load_state "php_versions")

    if step_completed "php" && [[ -n "$php_versions" ]]; then
        log_info "Updating PHP packages..."
        IFS=',' read -ra versions <<< "$php_versions"
        if [[ "$os" == "macos" ]]; then
            for v in "${versions[@]}"; do
                run_cmd brew upgrade "php@${v}" 2>/dev/null || log_debug "php@${v} already up to date."
            done
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            local dnf_cmd
            dnf_cmd=$(_get_dnf_cmd)
            for v in "${versions[@]}"; do
                local ver_nodot="${v//./}"
                run_cmd "$dnf_cmd" upgrade -y "php${ver_nodot}-php*" 2>/dev/null || true
            done
        else
            run_cmd apt-get upgrade -y "php*" 2>/dev/null || true
        fi
    fi

    if step_completed "webserver" && [[ -n "$web_server" ]]; then
        log_info "Updating $web_server..."
        local apache_pkg
        apache_pkg=$(get_apache_pkg)
        local apache_svc
        apache_svc=$(get_apache_svc)

        if [[ "$os" == "macos" ]]; then
            local pkg="nginx"
            [[ "$web_server" == "apache" ]] && pkg="httpd"
            run_cmd brew upgrade "$pkg" 2>/dev/null || log_debug "$pkg already up to date."
        else
            local pkg="nginx"
            [[ "$web_server" == "apache" ]] && pkg="$apache_pkg"
            if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
                local dnf_cmd
                dnf_cmd=$(_get_dnf_cmd)
                run_cmd "$dnf_cmd" upgrade -y "$pkg" 2>/dev/null || true
            else
                run_cmd apt-get upgrade -y "$pkg" 2>/dev/null || true
            fi
        fi

        local svc="nginx"
        [[ "$web_server" == "apache" ]] && svc="$apache_svc"
        [[ "$web_server" == "apache" && "$os" == "macos" ]] && svc="httpd"
        service_restart "$os" "$svc" 2>/dev/null || true
    fi

    if step_completed "database"; then
        log_info "Updating MariaDB..."
        if [[ "$os" == "macos" ]]; then
            run_cmd brew upgrade mariadb 2>/dev/null || log_debug "MariaDB already up to date."
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            local dnf_cmd
            dnf_cmd=$(_get_dnf_cmd)
            run_cmd "$dnf_cmd" upgrade -y mariadb-server 2>/dev/null || true
        else
            run_cmd apt-get upgrade -y mariadb-server 2>/dev/null || true
        fi
        service_restart "$os" mariadb 2>/dev/null || true
    fi

    # Update extras
    if step_completed "composer"; then
        log_info "Updating Composer..."
        if [[ "$os" == "macos" ]]; then
            run_cmd brew upgrade composer 2>/dev/null || true
        else
            run_cmd composer self-update 2>/dev/null || true
        fi
    fi

    if step_completed "redis"; then
        log_info "Updating Redis..."
        local redis_pkg
        redis_pkg=$(get_redis_pkg)
        if [[ "$os" == "macos" ]]; then
            run_cmd brew upgrade redis 2>/dev/null || true
        elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            local dnf_cmd
            dnf_cmd=$(_get_dnf_cmd)
            run_cmd "$dnf_cmd" upgrade -y "$redis_pkg" 2>/dev/null || true
        else
            run_cmd apt-get upgrade -y "$redis_pkg" 2>/dev/null || true
        fi
    fi

    if step_completed "ssl"; then
        log_info "Renewing SSL certificates..."
        run_cmd certbot renew --quiet 2>/dev/null || log_warn "Certificate renewal check failed."
    fi

    # Health checks
    echo ""
    log_info "Service health checks:"
    if step_completed "webserver"; then
        local svc_name="$web_server"
        [[ "$web_server" == "apache" ]] && svc_name=$(get_apache_svc)
        [[ "$web_server" == "apache" && "$os" == "macos" ]] && svc_name="httpd"
        if check_service_health "$svc_name" "$os"; then
            log_success "  $web_server: running"
        else
            log_warn "  $web_server: not running"
        fi
    fi
    if step_completed "database"; then
        if check_service_health "mariadb" "$os"; then
            log_success "  MariaDB: running"
        else
            log_warn "  MariaDB: not running"
        fi
    fi

    echo ""
    log_success "Update complete."
}

_update_docker() {
    local docker_dir
    docker_dir=$(load_state "docker_output_dir")
    if [[ -z "$docker_dir" ]]; then
        docker_dir="${SCRIPT_DIR}/docker-output"
    fi

    if [[ ! -f "${docker_dir}/docker-compose.yml" ]]; then
        log_error "No docker-compose.yml found. Nothing to update."
        exit 1
    fi

    local compose_file="${docker_dir}/docker-compose.yml"
    local env_file="${docker_dir}/.env"

    log_info "Pulling latest Docker images..."
    run_cmd docker compose -f "$compose_file" --env-file "$env_file" pull

    log_info "Recreating containers with updated images..."
    run_cmd docker compose -f "$compose_file" --env-file "$env_file" up -d --build

    if [[ "$SS_DRY_RUN" != "true" ]]; then
        echo ""
        log_info "Service status:"
        docker compose -f "$compose_file" ps 2>/dev/null || true
    fi

    echo ""
    log_success "Docker stack updated."
}
