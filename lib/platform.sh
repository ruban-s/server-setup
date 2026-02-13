#!/usr/bin/env bash
# platform.sh — OS/arch detection, distro family, and package manager wrappers

# Global set during init
SS_DISTRO_FAMILY=""  # debian | rhel | macos

detect_os() {
    local uname_s
    uname_s=$(uname -s)
    case "$uname_s" in
        Linux)  echo "linux" ;;
        Darwin) echo "macos" ;;
        *)      log_error "Unsupported OS: $uname_s"; exit 1 ;;
    esac
}

detect_arch() {
    local uname_m
    uname_m=$(uname -m)
    case "$uname_m" in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "arm64" ;;
        arm64)   echo "arm64" ;;
        *)       log_warn "Unknown architecture: $uname_m"; echo "$uname_m" ;;
    esac
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${ID,,}"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

detect_distro_family() {
    local os="$1"
    if [[ "$os" == "macos" ]]; then
        SS_DISTRO_FAMILY="macos"
        return
    fi

    local distro
    distro=$(detect_distro)
    case "$distro" in
        ubuntu|debian|linuxmint|pop|elementary|zorin|kali)
            SS_DISTRO_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|fedora|ol|amzn)
            SS_DISTRO_FAMILY="rhel"
            ;;
        *)
            # Try ID_LIKE from os-release as fallback
            if [[ -f /etc/os-release ]]; then
                # shellcheck source=/dev/null
                . /etc/os-release
                local id_like="${ID_LIKE,,}"
                if [[ "$id_like" == *"debian"* || "$id_like" == *"ubuntu"* ]]; then
                    SS_DISTRO_FAMILY="debian"
                elif [[ "$id_like" == *"rhel"* || "$id_like" == *"centos"* || "$id_like" == *"fedora"* ]]; then
                    SS_DISTRO_FAMILY="rhel"
                else
                    log_error "Unsupported Linux distribution: $distro (ID_LIKE: ${id_like:-none})"
                    log_error "Supported: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora, and derivatives."
                    exit 1
                fi
            else
                log_error "Unsupported Linux distribution: $distro"
                exit 1
            fi
            ;;
    esac
    log_debug "Distro family: $SS_DISTRO_FAMILY (distro: $distro)"
}

get_brew_prefix() {
    if command -v brew &>/dev/null; then
        brew --prefix
    elif [[ -d "/opt/homebrew" ]]; then
        echo "/opt/homebrew"
    else
        echo "/usr/local"
    fi
}

get_shell_profile() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        bash) echo "${HOME}/.bash_profile" ;;
        *)    echo "${HOME}/.profile" ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

check_linux_distro() {
    detect_distro_family "linux"
    # detect_distro_family exits on unsupported distro
}

ensure_homebrew() {
    if ! command -v brew &>/dev/null; then
        log_info "Homebrew not found. Installing..."
        run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        log_info "Updating Homebrew..."
        run_cmd brew update
    fi
}

# --- Package Manager Detection ---

_get_dnf_cmd() {
    if command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    else
        log_error "Neither dnf nor yum found on this system."
        exit 1
    fi
}

# --- Package Manager Wrappers ---

pkg_update() {
    local os="$1"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew update
    elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        local dnf_cmd
        dnf_cmd=$(_get_dnf_cmd)
        run_cmd "$dnf_cmd" makecache -y
    else
        run_cmd apt-get update -y
    fi
}

pkg_upgrade() {
    local os="$1"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew upgrade
    elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        local dnf_cmd
        dnf_cmd=$(_get_dnf_cmd)
        run_cmd "$dnf_cmd" upgrade -y
    else
        run_cmd apt-get upgrade -y
    fi
}

pkg_install() {
    local os="$1"; shift
    local packages=("$@")
    if [[ ${#packages[@]} -eq 0 ]]; then return 0; fi

    if [[ "$os" == "macos" ]]; then
        for pkg in "${packages[@]}"; do
            if brew list "$pkg" &>/dev/null; then
                log_debug "$pkg already installed, skipping."
            else
                run_cmd brew install "$pkg"
            fi
        done
    elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        local dnf_cmd
        dnf_cmd=$(_get_dnf_cmd)
        run_cmd "$dnf_cmd" install -y "${packages[@]}"
    else
        run_cmd apt-get install -y "${packages[@]}"
    fi
}

pkg_remove() {
    local os="$1"; shift
    local packages=("$@")
    if [[ ${#packages[@]} -eq 0 ]]; then return 0; fi

    if [[ "$os" == "macos" ]]; then
        for pkg in "${packages[@]}"; do
            if brew list "$pkg" &>/dev/null; then
                run_cmd brew uninstall "$pkg"
            fi
        done
    elif [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        local dnf_cmd
        dnf_cmd=$(_get_dnf_cmd)
        run_cmd "$dnf_cmd" remove -y "${packages[@]}" || true
    else
        run_cmd apt-get remove -y "${packages[@]}" || true
    fi
}

service_start() {
    local os="$1"
    local service="$2"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew services start "$service"
    else
        run_cmd systemctl start "$service"
        run_cmd systemctl enable "$service"
    fi
}

service_stop() {
    local os="$1"
    local service="$2"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew services stop "$service"
    else
        run_cmd systemctl stop "$service"
    fi
}

service_restart() {
    local os="$1"
    local service="$2"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew services restart "$service"
    else
        run_cmd systemctl restart "$service"
    fi
}

service_reload() {
    local os="$1"
    local service="$2"
    if [[ "$os" == "macos" ]]; then
        run_cmd brew services restart "$service"
    else
        run_cmd systemctl reload "$service"
    fi
}

# --- Distro-Aware Package Name Helpers ---

# Get the correct Apache package name
get_apache_pkg() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "httpd"
    elif [[ "$SS_DISTRO_FAMILY" == "macos" ]]; then
        echo "httpd"
    else
        echo "apache2"
    fi
}

# Get the correct Apache service name
get_apache_svc() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "httpd"
    elif [[ "$SS_DISTRO_FAMILY" == "macos" ]]; then
        echo "httpd"
    else
        echo "apache2"
    fi
}

# Get the correct Redis package name
get_redis_pkg() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "redis"
    elif [[ "$SS_DISTRO_FAMILY" == "macos" ]]; then
        echo "redis"
    else
        echo "redis-server"
    fi
}

# Get the correct Redis service name
get_redis_svc() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "redis"
    elif [[ "$SS_DISTRO_FAMILY" == "macos" ]]; then
        echo "redis"
    else
        echo "redis-server"
    fi
}

# Get Apache config directory for sites/vhosts
get_apache_sites_dir() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "/etc/httpd/conf.d"
    else
        echo "/etc/apache2/sites-available"
    fi
}

# Get NGINX sites directory
get_nginx_sites_dir() {
    if [[ "$SS_DISTRO_FAMILY" == "rhel" ]]; then
        echo "/etc/nginx/conf.d"
    else
        echo "/etc/nginx/sites-available"
    fi
}
