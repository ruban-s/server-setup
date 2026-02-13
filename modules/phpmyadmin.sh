#!/usr/bin/env bash
# modules/phpmyadmin.sh — phpMyAdmin installation and web server configuration

install_phpmyadmin() {
    local os="$1"

    if step_completed "phpmyadmin"; then
        log_info "phpMyAdmin installation already completed. Skipping."
        return 0
    fi

    if [[ "${CFG_INSTALL_PHPMYADMIN,,}" != "yes" ]]; then
        log_info "phpMyAdmin installation disabled in config. Skipping."
        return 0
    fi

    log_info "=== phpMyAdmin Installation ==="

    local web_server
    web_server=$(load_state "web_server")
    local highest_version
    highest_version=$(load_state "highest_php_version")

    if [[ "$os" == "linux" ]]; then
        if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
            _install_phpmyadmin_rhel "$web_server" "$highest_version"
        else
            _install_phpmyadmin_debian "$web_server" "$highest_version"
        fi
    else
        _install_phpmyadmin_macos "$web_server"
    fi

    log_success "phpMyAdmin installed and configured."
    mark_step_completed "phpmyadmin"
}

# --- Debian/Ubuntu ---

_install_phpmyadmin_debian() {
    local web_server="$1"
    local highest_version="$2"

    log_info "Installing phpMyAdmin via apt..."
    run_cmd apt-get install -y phpmyadmin

    if [[ "$web_server" == "apache" ]]; then
        _configure_phpmyadmin_apache_debian
    elif [[ "$web_server" == "nginx" ]]; then
        _configure_phpmyadmin_nginx_debian "$highest_version"
    fi
}

_configure_phpmyadmin_apache_debian() {
    log_info "Configuring phpMyAdmin for Apache..."

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write /etc/apache2/conf-available/phpmyadmin.conf"
        return 0
    fi

    cat > /etc/apache2/conf-available/phpmyadmin.conf <<'APACHECONF'
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php

    <IfModule mod_php.c>
        <IfModule mod_mime.c>
            AddType application/x-httpd-php .php
        </IfModule>
        <FilesMatch ".+\.php$">
            SetHandler application/x-httpd-php
        </FilesMatch>

        php_value include_path .
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/etc/phpmyadmin/:/var/lib/phpmyadmin/:/usr/share/php/:/usr/share/javascript/
        php_admin_value mbstring.func_overload 0
    </IfModule>
</Directory>

<Directory /usr/share/phpmyadmin/setup>
    Require all denied
</Directory>

<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>

<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>
APACHECONF

    run_cmd a2enconf phpmyadmin
    service_reload linux apache2
}

_configure_phpmyadmin_nginx_debian() {
    local highest_version="$1"

    log_info "Configuring phpMyAdmin for NGINX (PHP-FPM $highest_version)..."

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write /etc/nginx/snippets/phpmyadmin.conf"
        return 0
    fi

    mkdir -p /etc/nginx/snippets

    cat > /etc/nginx/snippets/phpmyadmin.conf <<NGINXCONF
location /phpmyadmin {
    root /usr/share/;
    index index.php index.html index.htm;

    location ~ ^/phpmyadmin/(.+\\.php)\$ {
        try_files \$uri =404;
        root /usr/share/;
        fastcgi_pass unix:/run/php/php${highest_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include /etc/nginx/fastcgi_params;
    }

    location ~* ^/phpmyadmin/(.+\\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
        root /usr/share/;
    }
}
NGINXCONF

    # Include snippet in default site config
    local default_conf="/etc/nginx/sites-available/default"
    if [[ -f "$default_conf" ]] && ! grep -q "phpmyadmin.conf" "$default_conf"; then
        awk '/server \{/{c++;if(c==2){sub(/\}/,"    include snippets/phpmyadmin.conf;\n}");c=0}}1' \
            "$default_conf" > "${default_conf}.tmp" && mv "${default_conf}.tmp" "$default_conf"
    fi

    service_reload linux nginx
}

# --- RHEL/CentOS/Rocky/Alma/Fedora ---

_install_phpmyadmin_rhel() {
    local web_server="$1"
    local highest_version="$2"

    # phpMyAdmin is not in standard RHEL repos — download manually
    local pma_dir="/usr/share/phpmyadmin"

    if [[ -d "$pma_dir" ]]; then
        log_info "phpMyAdmin already exists at $pma_dir. Skipping download."
    else
        if [[ "$SS_DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would download and install phpMyAdmin to $pma_dir"
        else
            log_info "Downloading phpMyAdmin (not in RHEL repos)..."
            local tmpdir
            tmpdir=$(mktemp -d)
            curl -fsSL -o "${tmpdir}/phpmyadmin.tar.gz" \
                "https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz"

            if [[ ! -s "${tmpdir}/phpmyadmin.tar.gz" ]]; then
                log_error "phpMyAdmin download failed or is empty."
                rm -rf "$tmpdir"
                exit 1
            fi

            tar -xzf "${tmpdir}/phpmyadmin.tar.gz" -C "$tmpdir"
            mv "${tmpdir}"/phpMyAdmin-* "$pma_dir"
            rm -rf "$tmpdir"

            # Create tmp directory for phpMyAdmin
            mkdir -p "${pma_dir}/tmp"
            chmod 777 "${pma_dir}/tmp"
        fi
    fi

    # Generate config with blowfish secret (skip in dry-run)
    if [[ "$SS_DRY_RUN" != "true" ]]; then
        _generate_phpmyadmin_config "$pma_dir"
    fi

    if [[ "$web_server" == "apache" ]]; then
        _configure_phpmyadmin_apache_rhel "$highest_version"
    elif [[ "$web_server" == "nginx" ]]; then
        _configure_phpmyadmin_nginx_rhel "$highest_version"
    fi
}

_generate_phpmyadmin_config() {
    local pma_dir="$1"
    if [[ ! -f "${pma_dir}/config.inc.php" ]]; then
        local blowfish_secret
        blowfish_secret=$(generate_password)
        cat > "${pma_dir}/config.inc.php" <<PHPCFG
<?php
\$cfg['blowfish_secret'] = '${blowfish_secret}';
\$cfg['Servers'][1]['auth_type'] = 'cookie';
\$cfg['Servers'][1]['host'] = '127.0.0.1';
\$cfg['Servers'][1]['compress'] = false;
\$cfg['Servers'][1]['AllowNoPassword'] = false;
\$cfg['TempDir'] = '$(dirname "$pma_dir")/phpmyadmin/tmp';
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
PHPCFG
        log_info "phpMyAdmin config created with blowfish secret."
    fi
}

_configure_phpmyadmin_apache_rhel() {
    local highest_version="$1"
    local ver_nodot="${highest_version//./}"

    log_info "Configuring phpMyAdmin for Apache (httpd)..."

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write /etc/httpd/conf.d/phpmyadmin.conf"
        return 0
    fi

    cat > /etc/httpd/conf.d/phpmyadmin.conf <<APACHECONF
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    AllowOverride None
    Require all granted

    <FilesMatch "\\.php\$">
        SetHandler "proxy:unix:/var/opt/remi/php${ver_nodot}/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</Directory>

<Directory /usr/share/phpmyadmin/setup>
    Require all denied
</Directory>

<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>

<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>
APACHECONF

    service_reload linux httpd
}

_configure_phpmyadmin_nginx_rhel() {
    local highest_version="$1"
    local ver_nodot="${highest_version//./}"

    log_info "Configuring phpMyAdmin for NGINX (PHP-FPM $highest_version)..."

    if [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would write /etc/nginx/conf.d/phpmyadmin.conf"
        return 0
    fi

    cat > /etc/nginx/conf.d/phpmyadmin.conf <<NGINXCONF
location /phpmyadmin {
    root /usr/share/;
    index index.php index.html index.htm;

    location ~ ^/phpmyadmin/(.+\\.php)\$ {
        try_files \$uri =404;
        root /usr/share/;
        fastcgi_pass unix:/var/opt/remi/php${ver_nodot}/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include /etc/nginx/fastcgi_params;
    }

    location ~* ^/phpmyadmin/(.+\\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
        root /usr/share/;
    }
}
NGINXCONF

    # Include in default server block if using conf.d approach
    service_reload linux nginx
}

# --- macOS ---

_install_phpmyadmin_macos() {
    local web_server="$1"
    local brew_prefix
    brew_prefix=$(get_brew_prefix)
    local web_root="${brew_prefix}/var/www"
    local pma_dir="${web_root}/phpmyadmin"

    if [[ -d "$pma_dir" ]]; then
        log_info "phpMyAdmin already exists at $pma_dir. Skipping download."
    elif [[ "$SS_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download and install phpMyAdmin to $pma_dir"
    else
        log_info "Downloading phpMyAdmin..."
        mkdir -p "$web_root"

        local tmpdir
        tmpdir=$(mktemp -d)
        curl -fsSL -o "${tmpdir}/phpmyadmin.tar.gz" \
            "https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz"

        if [[ ! -s "${tmpdir}/phpmyadmin.tar.gz" ]]; then
            log_error "phpMyAdmin download failed or is empty."
            rm -rf "$tmpdir"
            exit 1
        fi

        tar -xzf "${tmpdir}/phpmyadmin.tar.gz" -C "$tmpdir"
        mv "${tmpdir}"/phpMyAdmin-* "$pma_dir"
        rm -rf "$tmpdir"
    fi

    if [[ "$SS_DRY_RUN" != "true" ]]; then
        _generate_phpmyadmin_config "$pma_dir"
    fi
}
