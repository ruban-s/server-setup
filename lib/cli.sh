#!/usr/bin/env bash
# cli.sh — CLI argument parsing

SS_CONFIG_FILE=""
SS_NON_INTERACTIVE="${SS_NON_INTERACTIVE:-false}"
SS_ACTION="install"  # install | uninstall | update | start | stop | restart

show_help() {
    cat <<'HELP'
Usage: servforge.sh [OPTIONS]

A modular LAMP/LEMP stack installer for Ubuntu/Debian, RHEL/CentOS/Rocky/Fedora, and macOS.

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
  -h, --help              Show this help message
      --version           Show version information

Examples:
  sudo ./servforge.sh                          Interactive install
  sudo ./servforge.sh --dry-run                Preview actions
  sudo ./servforge.sh -c config/example.conf   Install from config
  sudo ./servforge.sh --non-interactive         Use defaults
  sudo ./servforge.sh --uninstall               Remove components
  sudo ./servforge.sh --update                  Update components

Docker:
  sudo ./servforge.sh --docker --non-interactive   Docker install
  sudo ./servforge.sh --start                      Start stack
  sudo ./servforge.sh --stop                       Stop stack
  sudo ./servforge.sh --restart                    Restart stack

Configuration:
  Place a config file at config/default.conf or pass one with -c.
  Environment variables override config file values.
  Set INSTALL_METHOD=docker or use --docker flag for Docker mode.
  See config/example.conf for all available options.

HELP
}

show_version() {
    echo "servforge ${SS_VERSION}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                SS_CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--non-interactive)
                SS_NON_INTERACTIVE="true"
                shift
                ;;
            -d|--dry-run)
                SS_DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                SS_VERBOSE="true"
                SS_LOG_LEVEL="debug"
                shift
                ;;
            -q|--quiet)
                SS_QUIET="true"
                shift
                ;;
            -u|--uninstall)
                SS_ACTION="uninstall"
                shift
                ;;
            --update)
                SS_ACTION="update"
                shift
                ;;
            --docker)
                CFG_INSTALL_METHOD="docker"
                shift
                ;;
            --start)
                SS_ACTION="start"
                shift
                ;;
            --stop)
                SS_ACTION="stop"
                shift
                ;;
            --restart)
                SS_ACTION="restart"
                shift
                ;;
            --clear-state)
                SS_ACTION="clear-state"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run with --help for usage information."
                exit 1
                ;;
        esac
    done
}
