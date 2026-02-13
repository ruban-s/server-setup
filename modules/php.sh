#!/usr/bin/env bash
# modules/php.sh — Multi-version PHP installation with extensions

install_php() {
    local os="$1"

    if step_completed "php"; then
        log_info "PHP installation already completed. Skipping."
        return 0
    fi

    log_info "=== PHP Installation ==="

    # Get PHP versions
    local php_versions_str
    php_versions_str=$(load_state "php_versions")

    if [[ -z "$php_versions_str" ]]; then
        php_versions_str="$CFG_PHP_VERSIONS"

        if [[ -z "$php_versions_str" ]] && [[ "$SS_NON_INTERACTIVE" != "true" ]]; then
            if [[ "$os" == "linux" ]]; then
                _show_available_php_linux
            else
                _show_available_php_macos
            fi
            read -rp "Enter PHP versions to install (comma-separated): " php_versions_str
        fi

        if [[ -z "$php_versions_str" ]]; then
            log_error "No PHP versions specified."
            exit 1
        fi
    fi

    # Parse and validate versions
    local -a versions=()
    IFS=',' read -ra raw_versions <<< "$php_versions_str"
    for ver in "${raw_versions[@]}"; do
        local clean_ver
        clean_ver=$(sanitize_php_version "$ver") || {
            log_error "Invalid PHP version: '$ver'. Expected format: X.Y (e.g., 8.3)"
            exit 1
        }
        versions+=("$clean_ver")
    done

    # Sort and find highest version
    local -a sorted_versions
    IFS=$'\n' sorted_versions=($(printf '%s\n' "${versions[@]}" | sort -V))
    unset IFS
    local highest_version="${sorted_versions[-1]}"

    # Save to state
    save_state "php_versions" "$(IFS=','; echo "${versions[*]}")"
    save_state "highest_php_version" "$highest_version"

    if [[ "$os" == "linux" ]]; then
        if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            _install_php_rhel "${versions[@]}"
        else
            _install_php_debian "${versions[@]}"
        fi
    else
        _install_php_macos "${versions[@]}"
    fi

    log_success "PHP installed: ${versions[*]} (primary: $highest_version)"
    mark_step_completed "php"
}

_show_available_php_linux() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        _setup_remi_repo
        log_info "Available PHP versions (via Remi):"
        local dnf_cmd
        dnf_cmd=$(_get_dnf_cmd)
        $dnf_cmd module list php 2>/dev/null | grep -oP 'remi-\K[0-9.]+' | sort -Vu | sed 's/^/  /' || true
    else
        if ! step_completed "php_repo"; then
            log_info "Adding PHP repository (ondrej/php)..."
            run_cmd apt-get install -y software-properties-common
            run_cmd add-apt-repository -y ppa:ondrej/php
            run_cmd apt-get update -y
            mark_step_completed "php_repo"
        fi
        log_info "Available PHP versions:"
        apt-cache pkgnames 2>/dev/null | grep -Po '^php[0-9]\.[0-9]+$' | sort -Vu | sed 's/php/  /' || true
    fi
}

_show_available_php_macos() {
    log_info "Available PHP versions:"
    brew search php 2>/dev/null | grep -E '^php(@[0-9.]+)?$' | sed 's/php@/  /' | sed 's/^php$/  (latest)/' || true
}

# --- Debian/Ubuntu ---

_install_php_debian() {
    local versions=("$@")

    # Ensure repo is added
    if ! step_completed "php_repo"; then
        log_info "Adding PHP repository (ondrej/php)..."
        run_cmd apt-get install -y software-properties-common
        run_cmd add-apt-repository -y ppa:ondrej/php
        run_cmd apt-get update -y
        mark_step_completed "php_repo"
    fi

    # Parse extensions
    local -a extensions=()
    IFS=',' read -ra extensions <<< "$CFG_PHP_EXTENSIONS"

    for version in "${versions[@]}"; do
        log_info "Installing PHP $version with extensions..."
        local -a packages=("php${version}")
        for ext in "${extensions[@]}"; do
            ext=$(echo "$ext" | xargs)
            packages+=("php${version}-${ext}")
        done
        run_cmd apt-get install -y "${packages[@]}" || {
            log_error "Failed to install PHP $version."
            exit 1
        }
        log_success "PHP $version installed."
    done
}

# --- RHEL/CentOS/Rocky/Alma/Fedora ---

_setup_remi_repo() {
    if step_completed "php_repo"; then
        return 0
    fi

    local distro
    distro=$(detect_distro)
    local dnf_cmd
    dnf_cmd=$(_get_dnf_cmd)

    log_info "Adding Remi PHP repository..."

    # Install EPEL first (required by Remi on RHEL-based)
    if [[ "$distro" != "fedora" ]]; then
        run_cmd "$dnf_cmd" install -y epel-release || {
            # For RHEL proper, EPEL needs to be installed from URL
            local version_id
            version_id=$(. /etc/os-release && echo "${VERSION_ID%%.*}")
            run_cmd "$dnf_cmd" install -y \
                "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${version_id}.noarch.rpm" || true
        }
    fi

    # Install Remi repo
    local version_id
    version_id=$(. /etc/os-release && echo "${VERSION_ID%%.*}")

    if [[ "$distro" == "fedora" ]]; then
        run_cmd "$dnf_cmd" install -y \
            "https://rpms.remirepo.net/fedora/remi-release-${version_id}.rpm" || true
    else
        run_cmd "$dnf_cmd" install -y \
            "https://rpms.remirepo.net/enterprise/remi-release-${version_id}.rpm" || true
    fi

    mark_step_completed "php_repo"
}

_install_php_rhel() {
    local versions=("$@")
    local dnf_cmd
    dnf_cmd=$(_get_dnf_cmd)

    _setup_remi_repo

    # Parse extensions
    local -a extensions=()
    IFS=',' read -ra extensions <<< "$CFG_PHP_EXTENSIONS"

    for version in "${versions[@]}"; do
        # Remi parallel packages use format: php83-php-fpm (no dot in version)
        local ver_nodot="${version//./}"
        log_info "Installing PHP $version (remi: php${ver_nodot}) with extensions..."

        local -a packages=("php${ver_nodot}-php")
        for ext in "${extensions[@]}"; do
            ext=$(echo "$ext" | xargs)
            # Map extension names: some differ between Debian and RHEL
            local rhel_ext="$ext"
            case "$ext" in
                mysql) rhel_ext="mysqlnd" ;;
                cgi)   continue ;;  # Not a separate package on RHEL
            esac
            packages+=("php${ver_nodot}-php-${rhel_ext}")
        done

        run_cmd "$dnf_cmd" install -y "${packages[@]}" || {
            log_error "Failed to install PHP $version."
            exit 1
        }

        # Enable and start PHP-FPM for this version
        service_start linux "php${ver_nodot}-php-fpm"

        log_success "PHP $version installed."
    done
}

# --- macOS ---

_install_php_macos() {
    local versions=("$@")
    local brew_prefix
    brew_prefix=$(get_brew_prefix)
    local shell_profile
    shell_profile=$(get_shell_profile)

    for version in "${versions[@]}"; do
        local brew_pkg="php@${version}"
        log_info "Installing PHP $version via Homebrew..."
        run_cmd brew install "$brew_pkg"

        # Add to PATH using proper variable expansion and brew prefix
        local php_bin="${brew_prefix}/opt/${brew_pkg}/bin"
        local php_sbin="${brew_prefix}/opt/${brew_pkg}/sbin"
        if ! grep -q "${brew_pkg}/bin" "$shell_profile" 2>/dev/null; then
            echo "export PATH=\"${php_bin}:\$PATH\"" >> "$shell_profile"
            echo "export PATH=\"${php_sbin}:\$PATH\"" >> "$shell_profile"
        fi
        log_success "PHP $version installed."
    done

    # Install extensions via pecl for macOS
    local -a extensions=()
    IFS=',' read -ra extensions <<< "$CFG_PHP_EXTENSIONS"
    local -a pecl_extensions=()
    for ext in "${extensions[@]}"; do
        ext=$(echo "$ext" | xargs)
        # Skip extensions bundled with PHP or installed via brew
        case "$ext" in
            fpm|cli|cgi|xml|curl|mbstring|zip|gd|mysql|opcache|bz2) continue ;;
            *)  pecl_extensions+=("$ext") ;;
        esac
    done

    if [[ ${#pecl_extensions[@]} -gt 0 ]]; then
        log_info "Installing PHP extensions via pecl..."
        for ext in "${pecl_extensions[@]}"; do
            run_cmd pecl install "$ext" 2>/dev/null || log_warn "Extension '$ext' may already be installed or unavailable via pecl."
        done
    fi

    log_info "Reload your shell or run: source $shell_profile"
}
