#!/bin/bash
# modules/vhost.sh — Virtual host creation wizard

create_vhost() {
    local os="$1"

    log_info "=== Virtual Host Creator ==="

    local web_server
    web_server=$(load_state "web_server")
    local highest_version
    highest_version=$(load_state "highest_php_version")

    if [[ -z "$web_server" ]]; then
        log_error "No web server detected. Install a web server first."
        return 1
    fi

    # Gather info
    local domain docroot php_version enable_ssl

    if [[ "$SS_NON_INTERACTIVE" == "true" ]]; then
        log_warn "Virtual host creation requires interactive mode. Skipping."
        return 0
    fi

    read -rp "Domain name (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        log_error "Domain name is required."
        return 1
    fi

    read -rp "Document root [/var/www/${domain}/public]: " docroot
    docroot="${docroot:-/var/www/${domain}/public}"

    read -rp "PHP version [$highest_version]: " php_version
    php_version="${php_version:-$highest_version}"

    read -rp "Enable SSL? (yes/no) [no]: " enable_ssl
    enable_ssl="${enable_ssl:-no}"

    # Create document root
    run_cmd mkdir -p "$docroot"

    if [[ "$web_server" == "nginx" ]]; then
        _create_nginx_vhost "$domain" "$docroot" "$php_version" "$enable_ssl" "$os"
    else
        _create_apache_vhost "$domain" "$docroot" "$php_version" "$enable_ssl" "$os"
    fi

    log_success "Virtual host created for: $domain"
}

# --- NGINX vhost ---

_create_nginx_vhost() {
    local domain="$1" docroot="$2" php_version="$3" enable_ssl="$4" os="$5"

    local sites_dir
    sites_dir=$(get_nginx_sites_dir)
    local conf_file="${sites_dir}/${domain}.conf"

    # Determine PHP-FPM socket path
    local fpm_sock
    fpm_sock=$(_get_fpm_sock "$php_version")

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create NGINX vhost: $conf_file"
        return 0
    fi

    mkdir -p "$sites_dir"

    cat > "$conf_file" <<VHOST
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};
    root ${docroot};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_pass unix:${fpm_sock};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\\.ht {
        deny all;
    }

    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
VHOST

    # Enable site (Debian uses sites-enabled symlinks; RHEL uses conf.d directly)
    if [[ "$SS_DISTRO_FAMILY" == "debian" ]]; then
        ln -sf "$conf_file" "/etc/nginx/sites-enabled/${domain}.conf"
    fi

    if nginx -t 2>/dev/null; then
        service_reload linux nginx
    else
        log_error "NGINX config test failed. Check: $conf_file"
        return 1
    fi

    if [[ "${enable_ssl,,}" == "yes" ]]; then
        log_info "Adding SSL for $domain..."
        run_cmd certbot --nginx -d "$domain" -d "www.${domain}" --non-interactive --agree-tos --redirect
    fi
}

# --- Apache vhost ---

_create_apache_vhost() {
    local domain="$1" docroot="$2" php_version="$3" enable_ssl="$4" os="$5"

    local sites_dir
    sites_dir=$(get_apache_sites_dir)
    local conf_file="${sites_dir}/${domain}.conf"
    local apache_svc
    apache_svc=$(get_apache_svc)

    # Determine PHP-FPM socket path
    local fpm_sock
    fpm_sock=$(_get_fpm_sock "$php_version")

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Apache vhost: $conf_file"
        return 0
    fi

    mkdir -p "$sites_dir"

    cat > "$conf_file" <<VHOST
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${docroot}

    <Directory ${docroot}>
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \\.php\$>
        SetHandler "proxy:unix:${fpm_sock}|fcgi://localhost"
    </FilesMatch>

    ErrorLog /var/log/${apache_svc}/${domain}.error.log
    CustomLog /var/log/${apache_svc}/${domain}.access.log combined
</VirtualHost>
VHOST

    # Enable site (Debian uses a2ensite; RHEL reads from conf.d directly)
    if [[ "$SS_DISTRO_FAMILY" == "debian" ]]; then
        run_cmd a2ensite "${domain}.conf"
    fi

    # Test config
    local test_cmd="apache2ctl"
    [[ "$SS_DISTRO_FAMILY" == "rhel" ]] && test_cmd="apachectl"

    if $test_cmd configtest 2>/dev/null; then
        service_reload linux "$apache_svc"
    else
        log_error "Apache config test failed. Check: $conf_file"
        return 1
    fi

    if [[ "${enable_ssl,,}" == "yes" ]]; then
        log_info "Adding SSL for $domain..."
        run_cmd certbot --apache -d "$domain" -d "www.${domain}" --non-interactive --agree-tos --redirect
    fi
}

# --- Helper: Get PHP-FPM socket path ---

_get_fpm_sock() {
    local php_version="$1"
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        local ver_nodot="${php_version//./}"
        echo "/var/opt/remi/php${ver_nodot}/run/php-fpm/www.sock"
    elif [[ "$SS_DISTRO_FAMILY" == "debian" ]]; then
        echo "/run/php/php${php_version}-fpm.sock"
    else
        # macOS — varies by setup
        local brew_prefix
        brew_prefix=$(get_brew_prefix)
        echo "${brew_prefix}/var/run/php-fpm.sock"
    fi
}
