#!/bin/bash
# config.sh — Config file parsing with environment variable overrides

# Config defaults (overridden by file, then by env vars)
CFG_PHP_VERSIONS="${PHP_VERSIONS:-}"
CFG_PHP_EXTENSIONS="${PHP_EXTENSIONS:-}"
CFG_WEB_SERVER="${WEB_SERVER:-}"
CFG_INSTALL_PHPMYADMIN="${INSTALL_PHPMYADMIN:-}"
CFG_ENABLE_SSL="${ENABLE_SSL:-}"
CFG_SSL_EMAIL="${SSL_EMAIL:-}"
CFG_SSL_DOMAINS="${SSL_DOMAINS:-}"
CFG_ENABLE_FIREWALL="${ENABLE_FIREWALL:-}"
CFG_FIREWALL_PORTS="${FIREWALL_PORTS:-}"
CFG_INSTALL_COMPOSER="${INSTALL_COMPOSER:-}"
CFG_INSTALL_REDIS="${INSTALL_REDIS:-}"
CFG_INSTALL_NODEJS="${INSTALL_NODEJS:-}"
CFG_NODEJS_VERSION="${NODEJS_VERSION:-}"
CFG_INSTALL_ELASTICSEARCH="${INSTALL_ELASTICSEARCH:-}"
CFG_INSTALL_METHOD="${INSTALL_METHOD:-}"

load_config_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "Config file not found: $file"
        exit 1
    fi
    log_info "Loading config from: $file"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Remove surrounding quotes
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        case "$key" in
            PHP_VERSIONS)          CFG_PHP_VERSIONS="$value" ;;
            PHP_EXTENSIONS)        CFG_PHP_EXTENSIONS="$value" ;;
            WEB_SERVER)            CFG_WEB_SERVER="$value" ;;
            INSTALL_PHPMYADMIN)    CFG_INSTALL_PHPMYADMIN="$value" ;;
            ENABLE_SSL)            CFG_ENABLE_SSL="$value" ;;
            SSL_EMAIL)             CFG_SSL_EMAIL="$value" ;;
            SSL_DOMAINS)           CFG_SSL_DOMAINS="$value" ;;
            ENABLE_FIREWALL)       CFG_ENABLE_FIREWALL="$value" ;;
            FIREWALL_PORTS)        CFG_FIREWALL_PORTS="$value" ;;
            INSTALL_COMPOSER)      CFG_INSTALL_COMPOSER="$value" ;;
            INSTALL_REDIS)         CFG_INSTALL_REDIS="$value" ;;
            INSTALL_NODEJS)        CFG_INSTALL_NODEJS="$value" ;;
            NODEJS_VERSION)        CFG_NODEJS_VERSION="$value" ;;
            INSTALL_ELASTICSEARCH) CFG_INSTALL_ELASTICSEARCH="$value" ;;
            INSTALL_METHOD)        CFG_INSTALL_METHOD="$value" ;;
            LOG_LEVEL)             SS_LOG_LEVEL="$value" ;;
            *)                     log_debug "Unknown config key: $key" ;;
        esac
    done < "$file"
}

apply_defaults() {
    local defaults_file="$1"
    if [[ -f "$defaults_file" ]]; then
        # Only load defaults for values not already set
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            case "$key" in
                PHP_VERSIONS)          [[ -z "$CFG_PHP_VERSIONS" ]]          && CFG_PHP_VERSIONS="$value" ;;
                PHP_EXTENSIONS)        [[ -z "$CFG_PHP_EXTENSIONS" ]]        && CFG_PHP_EXTENSIONS="$value" ;;
                WEB_SERVER)            [[ -z "$CFG_WEB_SERVER" ]]            && CFG_WEB_SERVER="$value" ;;
                INSTALL_PHPMYADMIN)    [[ -z "$CFG_INSTALL_PHPMYADMIN" ]]    && CFG_INSTALL_PHPMYADMIN="$value" ;;
                ENABLE_SSL)            [[ -z "$CFG_ENABLE_SSL" ]]            && CFG_ENABLE_SSL="$value" ;;
                SSL_EMAIL)             [[ -z "$CFG_SSL_EMAIL" ]]             && CFG_SSL_EMAIL="$value" ;;
                SSL_DOMAINS)           [[ -z "$CFG_SSL_DOMAINS" ]]           && CFG_SSL_DOMAINS="$value" ;;
                ENABLE_FIREWALL)       [[ -z "$CFG_ENABLE_FIREWALL" ]]       && CFG_ENABLE_FIREWALL="$value" ;;
                FIREWALL_PORTS)        [[ -z "$CFG_FIREWALL_PORTS" ]]        && CFG_FIREWALL_PORTS="$value" ;;
                INSTALL_COMPOSER)      [[ -z "$CFG_INSTALL_COMPOSER" ]]      && CFG_INSTALL_COMPOSER="$value" ;;
                INSTALL_REDIS)         [[ -z "$CFG_INSTALL_REDIS" ]]         && CFG_INSTALL_REDIS="$value" ;;
                INSTALL_NODEJS)        [[ -z "$CFG_INSTALL_NODEJS" ]]        && CFG_INSTALL_NODEJS="$value" ;;
                NODEJS_VERSION)        [[ -z "$CFG_NODEJS_VERSION" ]]        && CFG_NODEJS_VERSION="$value" ;;
                INSTALL_ELASTICSEARCH) [[ -z "$CFG_INSTALL_ELASTICSEARCH" ]] && CFG_INSTALL_ELASTICSEARCH="$value" ;;
                INSTALL_METHOD)        [[ -z "$CFG_INSTALL_METHOD" ]]        && CFG_INSTALL_METHOD="$value" ;;
                LOG_LEVEL)             : ;; # already handled
            esac
        done < "$defaults_file"
    fi
}

# Apply environment variable overrides (env vars take highest priority)
apply_env_overrides() {
    [[ -n "${PHP_VERSIONS:-}" ]]          && CFG_PHP_VERSIONS="$PHP_VERSIONS"          || true
    [[ -n "${PHP_EXTENSIONS:-}" ]]        && CFG_PHP_EXTENSIONS="$PHP_EXTENSIONS"        || true
    [[ -n "${WEB_SERVER:-}" ]]            && CFG_WEB_SERVER="$WEB_SERVER"                || true
    [[ -n "${INSTALL_PHPMYADMIN:-}" ]]    && CFG_INSTALL_PHPMYADMIN="$INSTALL_PHPMYADMIN" || true
    [[ -n "${ENABLE_SSL:-}" ]]            && CFG_ENABLE_SSL="$ENABLE_SSL"                || true
    [[ -n "${SSL_EMAIL:-}" ]]             && CFG_SSL_EMAIL="$SSL_EMAIL"                  || true
    [[ -n "${SSL_DOMAINS:-}" ]]           && CFG_SSL_DOMAINS="$SSL_DOMAINS"              || true
    [[ -n "${ENABLE_FIREWALL:-}" ]]       && CFG_ENABLE_FIREWALL="$ENABLE_FIREWALL"      || true
    [[ -n "${FIREWALL_PORTS:-}" ]]        && CFG_FIREWALL_PORTS="$FIREWALL_PORTS"        || true
    [[ -n "${INSTALL_COMPOSER:-}" ]]      && CFG_INSTALL_COMPOSER="$INSTALL_COMPOSER"    || true
    [[ -n "${INSTALL_REDIS:-}" ]]         && CFG_INSTALL_REDIS="$INSTALL_REDIS"          || true
    [[ -n "${INSTALL_NODEJS:-}" ]]        && CFG_INSTALL_NODEJS="$INSTALL_NODEJS"        || true
    [[ -n "${NODEJS_VERSION:-}" ]]        && CFG_NODEJS_VERSION="$NODEJS_VERSION"        || true
    [[ -n "${INSTALL_ELASTICSEARCH:-}" ]] && CFG_INSTALL_ELASTICSEARCH="$INSTALL_ELASTICSEARCH" || true
    [[ -n "${INSTALL_METHOD:-}" ]]        && CFG_INSTALL_METHOD="$INSTALL_METHOD"              || true
}

init_config() {
    local script_dir="$1"
    local defaults_file="${script_dir}/config/default.conf"

    # 1. Load defaults
    apply_defaults "$defaults_file"

    # 2. Load user config file (if specified)
    if [[ -n "$SS_CONFIG_FILE" ]]; then
        load_config_file "$SS_CONFIG_FILE"
    fi

    # 3. Environment variables override everything
    apply_env_overrides
}
