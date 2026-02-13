# server-setup

A modular LAMP/LEMP stack installer for **Ubuntu/Debian**, **RHEL/CentOS/Rocky/AlmaLinux/Fedora**, and **macOS**. Choose between native package installation or **Docker Compose** — with resumable state, secure credential handling, and a full CLI.

## Features

- **Multi-platform**: Ubuntu/Debian (apt), RHEL/CentOS/Rocky/AlmaLinux/Fedora (dnf/yum), and macOS (Homebrew)
- **Docker mode**: Generate a complete Docker Compose stack instead of installing packages on the host
- **Multi-PHP**: Install multiple PHP versions side-by-side with extensions
- **Resumable**: Interrupted? Re-run and it picks up where it left off
- **Secure**: Passwords saved to permission-restricted files, never exposed in process lists
- **Configurable**: Config files, environment variables, or interactive prompts
- **Dry-run mode**: Preview all actions before executing
- **Full lifecycle**: Install, uninstall, update, start, stop, restart

## Quick Start

### Native Install

```bash
git clone https://github.com/ruban-s/server-setup.git
cd server-setup
chmod +x server-setup.sh
sudo ./server-setup.sh
```

The script will interactively ask for PHP versions and web server choice.

### Docker Install

```bash
sudo ./server-setup.sh --docker --non-interactive
```

This generates a complete `docker-compose.yml` stack in `./docker-output/` and starts it.

## Usage

```
sudo ./server-setup.sh [OPTIONS]

Options:
  -c, --config FILE       Load configuration from FILE
  -n, --non-interactive   Run without prompts (uses config/defaults)
  -d, --dry-run           Show what would be done without executing
  -v, --verbose           Enable debug-level logging
  -q, --quiet             Suppress all output except errors
  -u, --uninstall         Uninstall components (reads state file)
      --update            Update installed components
      --clear-state       Clear saved state and start fresh
      --docker            Use Docker Compose instead of native packages
      --start             Start Docker Compose stack
      --stop              Stop Docker Compose stack
      --restart           Restart Docker Compose stack
  -h, --help              Show help message
      --version           Show version
```

## Examples

```bash
# Interactive native install
sudo ./server-setup.sh

# Preview what would happen
sudo ./server-setup.sh --dry-run

# Install from a config file, no prompts
sudo ./server-setup.sh --config config/example.conf --non-interactive

# Use environment variables
PHP_VERSIONS="8.2,8.3" WEB_SERVER="nginx" sudo ./server-setup.sh -n

# Docker install with custom config
sudo ./server-setup.sh --docker --config my-config.conf --non-interactive

# Docker install with extras
INSTALL_REDIS=yes INSTALL_ELASTICSEARCH=yes sudo ./server-setup.sh --docker -n

# Manage Docker stack
sudo ./server-setup.sh --start
sudo ./server-setup.sh --stop
sudo ./server-setup.sh --restart

# Uninstall (works for both native and Docker)
sudo ./server-setup.sh --uninstall

# Update installed components / pull latest images
sudo ./server-setup.sh --update

# Verbose dry-run
sudo ./server-setup.sh --docker --dry-run --verbose --non-interactive
```

## Docker Mode

When you pass `--docker` (or set `INSTALL_METHOD=docker`), the script generates a production-ready Docker Compose setup instead of installing packages on the host.

### What Gets Generated

```
docker-output/
├── docker-compose.yml         # All services with health checks
├── .env                       # Passwords, versions, ports (chmod 600)
├── php/
│   └── Dockerfile.X.Y         # Custom PHP-FPM image per version
├── nginx/
│   └── default.conf           # NGINX config (if nginx selected)
├── apache/
│   └── httpd-vhost.conf       # Apache config (if apache selected)
├── config/
│   └── phpmyadmin.config.inc.php
└── html/
    └── index.php              # Default phpinfo page
```

### Services

| Service | Image | Condition |
|---------|-------|-----------|
| PHP-FPM | Custom build (php:X.Y-fpm) | Always |
| NGINX | nginx:alpine | `WEB_SERVER=nginx` |
| Apache | httpd:alpine | `WEB_SERVER=apache` |
| MariaDB | mariadb:latest | Always |
| phpMyAdmin | phpmyadmin/phpmyadmin | `INSTALL_PHPMYADMIN=yes` |
| Redis | redis:alpine | `INSTALL_REDIS=yes` |
| Elasticsearch | elasticsearch:8 | `INSTALL_ELASTICSEARCH=yes` |
| Node.js | node:X-alpine | `INSTALL_NODEJS=yes` |

### Default Ports

| Service | Port |
|---------|------|
| HTTP | 80 |
| HTTPS | 443 |
| phpMyAdmin | 8080 |
| MariaDB | 3306 |
| Redis | 6379 |
| Elasticsearch | 9200 |
| Node.js | 3000 |

Ports are configurable via the `.env` file after generation.

### Lifecycle Management

```bash
sudo ./server-setup.sh --start     # docker compose up -d
sudo ./server-setup.sh --stop      # docker compose down
sudo ./server-setup.sh --restart   # docker compose restart
sudo ./server-setup.sh --update    # docker compose pull && up -d --build
sudo ./server-setup.sh --uninstall # docker compose down -v + remove files
```

## Configuration

Configuration is resolved in order of priority (highest first):

1. **Environment variables** — e.g., `PHP_VERSIONS="8.3" sudo ./server-setup.sh`
2. **Config file** — passed with `--config`
3. **Defaults** — from `config/default.conf`

Copy the example config to get started:

```bash
cp config/example.conf my-config.conf
# Edit my-config.conf, then:
sudo ./server-setup.sh --config my-config.conf --non-interactive
```

### Available Options

| Option | Default | Description |
|--------|---------|-------------|
| `INSTALL_METHOD` | `native` | `native` (system packages) or `docker` (Docker Compose) |
| `PHP_VERSIONS` | `8.3` | Comma-separated PHP versions |
| `PHP_EXTENSIONS` | `bcmath,xml,fpm,...` | Extensions per PHP version |
| `WEB_SERVER` | `nginx` | `apache` or `nginx` |
| `INSTALL_PHPMYADMIN` | `yes` | Install phpMyAdmin |
| `ENABLE_SSL` | `no` | SSL via Let's Encrypt (native mode) |
| `SSL_EMAIL` | | Email for Let's Encrypt |
| `SSL_DOMAINS` | | Comma-separated domains |
| `ENABLE_FIREWALL` | `yes` | Configure firewall (native mode) |
| `FIREWALL_PORTS` | `22,80,443` | Ports to allow |
| `INSTALL_COMPOSER` | `yes` | Install Composer |
| `INSTALL_REDIS` | `no` | Install Redis |
| `INSTALL_NODEJS` | `no` | Install Node.js |
| `NODEJS_VERSION` | `20` | Node.js major version |
| `INSTALL_ELASTICSEARCH` | `no` | Install Elasticsearch |
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, `debug` |

## Credentials

MariaDB root password and other secrets are stored in a permission-restricted file:

- **Linux**: `/var/tmp/server-setup/credentials`
- **macOS**: `~/.server-setup/credentials`
- **Docker mode**: Also written to `docker-output/.env` (chmod 600)

```bash
sudo cat /var/tmp/server-setup/credentials   # Linux
cat ~/.server-setup/credentials               # macOS
```

## State & Resumption

Installation progress is tracked in a state file. If the script is interrupted, re-run it and it will skip completed steps.

- **Linux**: `/var/tmp/server-setup/state`
- **macOS**: `~/.server-setup/state`

To start fresh: `sudo ./server-setup.sh --clear-state`

## Project Structure

```
server-setup/
├── server-setup.sh          # Main entry point
├── config/
│   ├── default.conf         # Default config values
│   └── example.conf         # Documented user config template
├── lib/
│   ├── common.sh            # Logging, traps, validation, state mgmt
│   ├── platform.sh          # OS/arch detection, package wrappers
│   ├── config.sh            # Config file parsing + env overrides
│   └── cli.sh               # CLI argument parsing
├── modules/
│   ├── php.sh               # Multi-version PHP + extensions
│   ├── webserver.sh         # Apache/NGINX install + config
│   ├── database.sh          # MariaDB install + secure setup
│   ├── phpmyadmin.sh        # phpMyAdmin download + config
│   ├── ssl.sh               # Let's Encrypt via certbot
│   ├── firewall.sh          # ufw / firewalld / pf
│   ├── extras.sh            # Composer, Redis, Node.js, Elasticsearch
│   ├── vhost.sh             # Virtual host creation wizard
│   └── docker.sh            # Docker Compose stack generation
├── uninstall.sh             # Component removal (native + Docker)
├── update.sh                # Component updates (native + Docker)
├── test.sh                  # Automated test suite
└── README.md
```

## Testing

```bash
./test.sh syntax     # Syntax check all scripts
./test.sh cli        # CLI flag tests
./test.sh config     # Config file validation
./test.sh docker     # Docker CLI tests
./test.sh local      # All local tests + dry-run (needs sudo)
./test.sh ubuntu     # Test in Ubuntu container
./test.sh rocky      # Test in Rocky Linux container
./test.sh all        # Full suite including all Docker containers
```

## Supported Platforms

| Platform | Package Manager | PHP Repo | Firewall |
|----------|----------------|----------|----------|
| Ubuntu / Debian | apt | ondrej/php PPA | ufw |
| CentOS / RHEL / Rocky / AlmaLinux | dnf / yum | Remi | firewalld |
| Fedora | dnf | Remi | firewalld |
| macOS | Homebrew | Homebrew | pf |

**Docker mode** works on any platform with Docker Engine and the Compose plugin.

## Requirements

**Native mode:**
- Debian-family or RHEL-family Linux with root access, or macOS with Homebrew
- `bash` 4.0+, `curl`, `openssl`

**Docker mode:**
- Docker Engine 20.10+
- Docker Compose v2 (the `docker compose` plugin)

## Notes

- Always test in a non-production environment first
- Back up existing configurations before running
- Review the dry-run output before a real install: `sudo ./server-setup.sh --dry-run`
- Docker mode is ideal for development environments and quick prototyping
- Native mode is recommended for production servers where you need full OS-level control
