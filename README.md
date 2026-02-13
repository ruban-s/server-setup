# server-setup

A modular LAMP/LEMP stack installer for **Ubuntu/Debian**, **RHEL/CentOS/Rocky/AlmaLinux/Fedora**, and **macOS**.

Two installation methods:
- **Native** — installs packages directly on the host (apt, dnf/yum, Homebrew)
- **Docker** — generates a Docker Compose stack, nothing installed on the host

---

## Table of Contents

- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Installation Methods](#installation-methods)
  - [Native Install](#native-install)
  - [Docker Install](#docker-install)
- [CLI Reference](#cli-reference)
- [Configuration](#configuration)
  - [Configuration Options](#configuration-options)
  - [How Configuration Works](#how-configuration-works)
- [Managing Your Stack](#managing-your-stack)
  - [Update](#update)
  - [Uninstall](#uninstall)
  - [Docker Lifecycle](#docker-lifecycle)
- [Docker Mode Details](#docker-mode-details)
  - [Generated Files](#generated-files)
  - [Services](#services)
  - [Ports](#ports)
- [Credentials & State](#credentials--state)
- [Supported Platforms](#supported-platforms)
- [Testing](#testing)
- [Project Structure](#project-structure)

---

## Requirements

### Native mode

| Requirement | Details |
|-------------|---------|
| OS | Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux, Fedora, or macOS |
| Shell | `bash` 4.0+ |
| Tools | `curl`, `openssl` |
| Access | Root / sudo (Linux), admin (macOS) |

### Docker mode

| Requirement | Details |
|-------------|---------|
| OS | Any platform that runs Docker |
| Docker | Docker Engine 20.10+ |
| Compose | Docker Compose v2 (`docker compose` plugin) |

---

## Getting Started

```bash
git clone https://github.com/ruban-s/server-setup.git
cd server-setup
chmod +x server-setup.sh
```

Preview what would happen before committing:

```bash
sudo ./server-setup.sh --dry-run
```

---

## Installation Methods

### Native Install

Installs PHP, web server, MariaDB, and extras directly on the host using the system package manager.

**Interactive** (the script asks you questions):

```bash
sudo ./server-setup.sh
```

**Non-interactive** (uses defaults or your config file):

```bash
sudo ./server-setup.sh --non-interactive
```

**With a config file**:

```bash
cp config/example.conf my-config.conf
# Edit my-config.conf to your needs
sudo ./server-setup.sh --config my-config.conf --non-interactive
```

**With environment variables**:

```bash
PHP_VERSIONS="8.2,8.3" WEB_SERVER="apache" sudo ./server-setup.sh -n
```

### Docker Install

Generates a complete `docker-compose.yml` with all services and starts the stack. No packages are installed on the host.

**Quick start with defaults** (NGINX + PHP 8.3 + MariaDB + phpMyAdmin):

```bash
sudo ./server-setup.sh --docker --non-interactive
```

**With extras**:

```bash
INSTALL_REDIS=yes INSTALL_ELASTICSEARCH=yes sudo ./server-setup.sh --docker -n
```

**With a config file**:

```bash
sudo ./server-setup.sh --docker --config my-config.conf --non-interactive
```

**Preview without running**:

```bash
sudo ./server-setup.sh --docker --dry-run --non-interactive
```

After install, your stack is running. Verify with:

```bash
curl http://localhost        # Web server
curl http://localhost:8080   # phpMyAdmin
```

---

## CLI Reference

```
sudo ./server-setup.sh [OPTIONS]
```

### General Options

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show help message and exit |
| `--version` | | Show version and exit |
| `--config FILE` | `-c` | Load configuration from FILE |
| `--non-interactive` | `-n` | Run without prompts, use config/defaults |
| `--dry-run` | `-d` | Preview actions without executing anything |
| `--verbose` | `-v` | Enable debug-level logging |
| `--quiet` | `-q` | Suppress all output except errors |

### Actions

| Flag | Short | Description |
|------|-------|-------------|
| *(default)* | | Install the stack |
| `--uninstall` | `-u` | Remove all installed components |
| `--update` | | Update installed components to latest |
| `--clear-state` | | Clear saved state and start fresh |

### Docker Options

| Flag | Description |
|------|-------------|
| `--docker` | Use Docker Compose instead of native packages |
| `--start` | Start the Docker Compose stack |
| `--stop` | Stop the Docker Compose stack |
| `--restart` | Restart the Docker Compose stack |

---

## Configuration

### Configuration Options

Options can be set in a config file, as environment variables, or through interactive prompts.

#### Installation

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `INSTALL_METHOD` | `native` | `native`, `docker` | Installation method (or use `--docker` flag) |

#### Core Stack

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `PHP_VERSIONS` | `8.3` | e.g. `8.2,8.3` | PHP versions to install (comma-separated) |
| `PHP_EXTENSIONS` | `bcmath,xml,fpm,...` | comma-separated | PHP extensions for each version |
| `WEB_SERVER` | `nginx` | `nginx`, `apache` | Which web server to use |
| `INSTALL_PHPMYADMIN` | `yes` | `yes`, `no` | Install phpMyAdmin web UI for MariaDB |

#### SSL & Security (native mode only)

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `ENABLE_SSL` | `no` | `yes`, `no` | Enable SSL via Let's Encrypt |
| `SSL_EMAIL` | *(empty)* | email address | Email for Let's Encrypt notifications |
| `SSL_DOMAINS` | *(empty)* | e.g. `example.com,www.example.com` | Domains for SSL certificates |
| `ENABLE_FIREWALL` | `yes` | `yes`, `no` | Configure firewall rules |
| `FIREWALL_PORTS` | `22,80,443` | comma-separated | Ports to allow through firewall |

#### Optional Extras

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `INSTALL_COMPOSER` | `yes` | `yes`, `no` | PHP dependency manager |
| `INSTALL_REDIS` | `no` | `yes`, `no` | In-memory data store |
| `INSTALL_NODEJS` | `no` | `yes`, `no` | Node.js runtime |
| `NODEJS_VERSION` | `20` | major version number | Node.js version (e.g. `18`, `20`, `22`) |
| `INSTALL_ELASTICSEARCH` | `no` | `yes`, `no` | Search and analytics engine |

#### Logging

| Option | Default | Values | Description |
|--------|---------|--------|-------------|
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, `debug` | Log verbosity |

### How Configuration Works

Settings are applied in this priority order (highest wins):

```
Environment variables  >  Config file (--config)  >  Defaults (config/default.conf)
```

**Three ways to configure:**

1. **Config file** — copy the template and edit it:
   ```bash
   cp config/example.conf my-config.conf
   sudo ./server-setup.sh --config my-config.conf -n
   ```

2. **Environment variables** — override any option inline:
   ```bash
   PHP_VERSIONS="8.2,8.3" WEB_SERVER="apache" sudo ./server-setup.sh -n
   ```

3. **Interactive prompts** — run without `-n` and the script asks you:
   ```bash
   sudo ./server-setup.sh
   ```

---

## Managing Your Stack

### Update

Updates all installed components to their latest versions.

```bash
# Native: upgrades packages via apt/dnf/brew
sudo ./server-setup.sh --update

# Docker: pulls latest images and rebuilds containers
sudo ./server-setup.sh --update
```

### Uninstall

Removes everything that was installed, guided by the saved state file.

```bash
# Native: removes packages in reverse order, offers database backup
sudo ./server-setup.sh --uninstall

# Docker: stops containers, removes volumes, deletes generated files
sudo ./server-setup.sh --uninstall
```

The script auto-detects whether native or Docker was used. No extra flags needed.

### Docker Lifecycle

Control your Docker Compose stack after installation:

```bash
sudo ./server-setup.sh --start     # Start all containers
sudo ./server-setup.sh --stop      # Stop all containers
sudo ./server-setup.sh --restart   # Restart all containers
```

---

## Docker Mode Details

### Generated Files

When you run with `--docker`, the script creates a `docker-output/` directory:

```
docker-output/
├── docker-compose.yml              # Service definitions with health checks
├── .env                            # Passwords, versions, ports (chmod 600)
├── php/
│   └── Dockerfile.8.3              # Custom PHP-FPM image (one per version)
├── nginx/                          # Only if WEB_SERVER=nginx
│   └── default.conf
├── apache/                         # Only if WEB_SERVER=apache
│   └── httpd-vhost.conf
├── config/
│   └── phpmyadmin.config.inc.php   # Only if INSTALL_PHPMYADMIN=yes
└── html/
    └── index.php                   # Default phpinfo page
```

### Services

All services are conditional based on your configuration:

| Service | Image | When included |
|---------|-------|---------------|
| PHP-FPM | `php:X.Y-fpm` (custom build) | Always (one per PHP version) |
| NGINX | `nginx:alpine` | `WEB_SERVER=nginx` |
| Apache | `httpd:alpine` | `WEB_SERVER=apache` |
| MariaDB | `mariadb:latest` | Always |
| phpMyAdmin | `phpmyadmin/phpmyadmin` | `INSTALL_PHPMYADMIN=yes` |
| Redis | `redis:alpine` | `INSTALL_REDIS=yes` |
| Elasticsearch | `elasticsearch:8` | `INSTALL_ELASTICSEARCH=yes` |
| Node.js | `node:X-alpine` | `INSTALL_NODEJS=yes` |

### Ports

Default port mappings (editable in `docker-output/.env` after generation):

| Service | Host Port | Container Port |
|---------|-----------|----------------|
| HTTP (NGINX/Apache) | 80 | 80 |
| HTTPS | 443 | 443 |
| phpMyAdmin | 8080 | 80 |
| MariaDB | 3306 | 3306 |
| Redis | 6379 | 6379 |
| Elasticsearch | 9200 | 9200 |
| Node.js | 3000 | 3000 |

---

## Credentials & State

### Credentials

Auto-generated passwords are saved to a permission-restricted file (chmod 600):

| Mode | Location |
|------|----------|
| Native (Linux) | `/var/tmp/server-setup/credentials` |
| Native (macOS) | `~/.server-setup/credentials` |
| Docker | Above + `docker-output/.env` |

View your credentials:

```bash
sudo cat /var/tmp/server-setup/credentials   # Linux
cat ~/.server-setup/credentials               # macOS
```

### State

Installation progress is tracked so interrupted installs can resume where they left off:

| Mode | Location |
|------|----------|
| Linux | `/var/tmp/server-setup/state` |
| macOS | `~/.server-setup/state` |

```bash
# Resume an interrupted install — just re-run the same command
sudo ./server-setup.sh --non-interactive

# Start completely fresh
sudo ./server-setup.sh --clear-state
```

---

## Supported Platforms

### Native mode

| Platform | Package Manager | PHP Source | Firewall |
|----------|----------------|------------|----------|
| Ubuntu / Debian | apt | ondrej/php PPA | ufw |
| CentOS / RHEL / Rocky / AlmaLinux | dnf / yum | Remi | firewalld |
| Fedora | dnf | Remi | firewalld |
| macOS | Homebrew | Homebrew | pf |

### Docker mode

Any OS that runs Docker Engine 20.10+ with the Compose v2 plugin — Linux, macOS, Windows (WSL2).

---

## Testing

Run the automated test suite:

```bash
./test.sh              # Run all tests (syntax + CLI + config + Docker CLI + containers)
./test.sh syntax       # Syntax-check all shell scripts
./test.sh cli          # Test CLI flag parsing
./test.sh config       # Validate config files
./test.sh docker       # Test Docker CLI flags
./test.sh local        # All local tests + sudo dry-run
./test.sh ubuntu       # Dry-run in Ubuntu Docker container
./test.sh debian       # Dry-run in Debian Docker container
./test.sh rocky        # Dry-run in Rocky Linux container
./test.sh alma         # Dry-run in AlmaLinux container
./test.sh fedora       # Dry-run in Fedora container
```

---

## Project Structure

```
server-setup/
│
├── server-setup.sh              # Main entry point — sources everything, dispatches actions
│
├── config/
│   ├── default.conf             # Default values for all options
│   └── example.conf             # Documented template — copy and customize
│
├── lib/                         # Core libraries (sourced by server-setup.sh)
│   ├── common.sh                # Logging, error traps, state management, passwords
│   ├── platform.sh              # OS/arch detection, package manager abstraction
│   ├── config.sh                # Config file parsing, env var overrides
│   └── cli.sh                   # CLI argument parsing
│
├── modules/                     # Feature modules (sourced by server-setup.sh)
│   ├── php.sh                   # Multi-version PHP + extensions
│   ├── webserver.sh             # Apache / NGINX installation
│   ├── database.sh              # MariaDB installation + secure setup
│   ├── phpmyadmin.sh            # phpMyAdmin download + web server config
│   ├── ssl.sh                   # Let's Encrypt via certbot
│   ├── firewall.sh              # ufw (Debian) / firewalld (RHEL) / pf (macOS)
│   ├── extras.sh                # Composer, Redis, Node.js, Elasticsearch
│   ├── vhost.sh                 # Virtual host creation wizard
│   └── docker.sh                # Docker Compose generation + lifecycle
│
├── uninstall.sh                 # Reverse-order removal (native + Docker aware)
├── update.sh                    # Component updates (native + Docker aware)
├── test.sh                      # Automated test suite
└── README.md
```

---

## Important Notes

- **Always dry-run first**: `sudo ./server-setup.sh --dry-run` before any real install
- **Back up** existing server configurations before running on a production machine
- **Docker mode** is ideal for development, local testing, and quick prototyping
- **Native mode** is recommended for production servers where you need full OS-level control
- **Credentials** are auto-generated and stored securely — review them after install
