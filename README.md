# server-setup

A modular LAMP/LEMP stack installer for **Ubuntu/Debian**, **RHEL/CentOS/Rocky/AlmaLinux/Fedora**, and **macOS**. Installs and configures PHP (multiple versions), Apache or NGINX, MariaDB, phpMyAdmin, and optional extras — with resumable state, secure credential handling, and a full CLI.

## Features

- **Multi-platform**: Ubuntu/Debian (apt), RHEL/CentOS/Rocky/AlmaLinux/Fedora (dnf/yum), and macOS (Homebrew) from a single entry point
- **Multi-PHP**: Install multiple PHP versions with extensions (Linux & macOS)
- **Resumable**: Interrupted? Re-run and it picks up where it left off
- **Secure**: Passwords saved to permission-restricted files, never exposed in process lists
- **Configurable**: Config files, environment variables, or interactive prompts
- **Dry-run mode**: Preview all actions before executing
- **Uninstall & Update**: Full lifecycle management via `--uninstall` and `--update`
- **Optional extras**: Composer, Redis, Node.js, Elasticsearch, SSL (Let's Encrypt), firewall, virtual hosts

## Quick Start

```bash
git clone https://github.com/ruban-s/server-setup.git
cd server-setup
chmod +x server-setup.sh
sudo ./server-setup.sh
```

The script will interactively ask for PHP versions and web server choice.

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
  -h, --help              Show help message
      --version           Show version
```

## Examples

```bash
# Interactive install
sudo ./server-setup.sh

# Preview what would happen
sudo ./server-setup.sh --dry-run

# Install from a config file, no prompts
sudo ./server-setup.sh --config config/example.conf --non-interactive

# Use environment variables
PHP_VERSIONS="8.2,8.3" WEB_SERVER="nginx" sudo ./server-setup.sh -n

# Uninstall everything
sudo ./server-setup.sh --uninstall

# Update installed components
sudo ./server-setup.sh --update

# Verbose logging
sudo ./server-setup.sh --verbose
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
| `PHP_VERSIONS` | `8.3` | Comma-separated PHP versions |
| `PHP_EXTENSIONS` | `bcmath,xml,fpm,...` | Extensions per PHP version |
| `WEB_SERVER` | `nginx` | `apache` or `nginx` |
| `INSTALL_PHPMYADMIN` | `yes` | Install phpMyAdmin |
| `ENABLE_SSL` | `no` | SSL via Let's Encrypt |
| `SSL_EMAIL` | | Email for Let's Encrypt |
| `SSL_DOMAINS` | | Comma-separated domains |
| `ENABLE_FIREWALL` | `yes` | Configure firewall |
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

View credentials:

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
│   ├── config.sh            # Config file parsing
│   └── cli.sh               # CLI argument parsing
├── modules/
│   ├── php.sh               # Multi-version PHP + extensions
│   ├── webserver.sh         # Apache/NGINX install + config
│   ├── database.sh          # MariaDB install + secure setup
│   ├── phpmyadmin.sh        # phpMyAdmin download + config
│   ├── ssl.sh               # Let's Encrypt via certbot
│   ├── firewall.sh          # ufw (Linux) / pf (macOS)
│   ├── extras.sh            # Composer, Redis, Node.js, Elasticsearch
│   └── vhost.sh             # Virtual host creation wizard
├── uninstall.sh             # Component removal
├── update.sh                # Component updates
└── README.md
```

## Supported Platforms

| Platform | Package Manager | PHP Repo | Firewall |
|----------|----------------|----------|----------|
| Ubuntu / Debian | apt | ondrej/php PPA | ufw |
| CentOS / RHEL / Rocky / AlmaLinux | dnf / yum | Remi | firewalld |
| Fedora | dnf | Remi | firewalld |
| macOS | Homebrew | Homebrew | pf |

## Requirements

- **Debian-family Linux**: Ubuntu, Debian, Linux Mint, Pop!_OS, etc. with root access
- **RHEL-family Linux**: CentOS, RHEL, Rocky Linux, AlmaLinux, Fedora, Amazon Linux with root access
- **macOS**: macOS with Homebrew (auto-installed if missing)
- All: `bash` 4.0+, `curl`, `openssl`

## Note

- Always test in a non-production environment first
- Back up existing configurations before running
- Review the dry-run output before a real install: `sudo ./server-setup.sh --dry-run`
