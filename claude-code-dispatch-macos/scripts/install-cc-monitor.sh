#!/usr/bin/env bash
# install-cc-monitor.sh - Install CC auto-recovery monitor as launchd agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
AGENT_LABEL="com.openclaw.cc-auto-recover"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
DATA_DIR="${DATA_DIR:-$HOME/.openclaw/workspace/claude-code-dispatch-macos/data}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-60}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check jq
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        log_info "Install with: brew install jq"
        exit 1
    fi

    # Check scripts exist
    if [[ ! -f "${SCRIPT_DIR}/cc-auto-recover.sh" ]]; then
        log_error "Monitor script not found: ${SCRIPT_DIR}/cc-auto-recover.sh"
        exit 1
    fi

    log_info "Prerequisites OK"
}

# Create directories
create_directories() {
    log_info "Creating directories..."

    mkdir -p "${DATA_DIR}/queue"
    mkdir -p "${DATA_DIR}/running"
    mkdir -p "${DATA_DIR}/done"
    mkdir -p "${DATA_DIR}/.budgets"
    mkdir -p "${PROJECT_DIR}/logs"

    log_info "Directories created: $DATA_DIR"
}

# Generate launchd plist
generate_plist() {
    local monitor_script="${SCRIPT_DIR}/cc-auto-recover.sh"
    local log_file="${PROJECT_DIR}/logs/monitor.log"

    cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${monitor_script}</string>
        <string>--data-dir</string>
        <string>${DATA_DIR}</string>
        <string>--interval</string>
        <string>${MONITOR_INTERVAL}</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>DATA_DIR</key>
        <string>${DATA_DIR}</string>
        <key>MONITOR_INTERVAL</key>
        <string>${MONITOR_INTERVAL}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StandardOutPath</key>
    <string>${log_file}</string>

    <key>StandardErrorPath</key>
    <string>${log_file}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>ThrottleInterval</key>
    <integer>60</integer>

    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
</dict>
</plist>
EOF

    log_info "Generated launchd plist: $AGENT_PLIST"
}

# Install the agent
install_agent() {
    log_info "Installing launchd agent..."

    # Stop existing agent if running
    if launchctl list "$AGENT_LABEL" &>/dev/null; then
        log_info "Stopping existing agent..."
        launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    fi

    # Load new agent
    launchctl load "$AGENT_PLIST"

    log_info "Agent installed and started"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    sleep 2

    if launchctl list "$AGENT_LABEL" &>/dev/null; then
        log_info "✓ Agent is running"
    else
        log_error "✗ Agent is not running"
        log_info "Check logs: tail -f ${PROJECT_DIR}/logs/monitor.log"
        exit 1
    fi

    if [[ -d "$DATA_DIR" ]]; then
        log_info "✓ Data directory exists"
    else
        log_error "✗ Data directory missing"
        exit 1
    fi

    log_info "Installation verified successfully"
}

# Print status
print_status() {
    echo ""
    echo "==================================="
    echo "  CC Auto-Recovery Monitor"
    echo "==================================="
    echo ""
    echo "Status:     $(launchctl list "$AGENT_LABEL" &>/dev/null && echo 'Running' || echo 'Stopped')"
    echo "Plist:      $AGENT_PLIST"
    echo "Data Dir:   $DATA_DIR"
    echo "Interval:   ${MONITOR_INTERVAL}s"
    echo "Logs:       ${PROJECT_DIR}/logs/monitor.log"
    echo ""
    echo "Commands:"
    echo "  Start:     launchctl load $AGENT_PLIST"
    echo "  Stop:      launchctl unload $AGENT_PLIST"
    echo "  Restart:   launchctl unload $AGENT_PLIST && launchctl load $AGENT_PLIST"
    echo "  Logs:      tail -f ${PROJECT_DIR}/logs/monitor.log"
    echo ""
}

# Uninstall
uninstall() {
    log_info "Uninstalling CC auto-recovery monitor..."

    if launchctl list "$AGENT_LABEL" &>/dev/null; then
        launchctl unload "$AGENT_PLIST"
        log_info "Agent stopped"
    fi

    if [[ -f "$AGENT_PLIST" ]]; then
        rm "$AGENT_PLIST"
        log_info "Plist removed"
    fi

    log_info "Uninstall complete"
    log_info "Data directory preserved: $DATA_DIR"
}

# Usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Install CC auto-recovery monitor as a launchd agent.

Commands:
    install     Install and start the monitor (default)
    uninstall   Stop and remove the monitor
    status      Show current status
    help        Show this help message

Environment Variables:
    DATA_DIR            Data directory (default: ~/.openclaw/workspace/.../data)
    MONITOR_INTERVAL    Monitoring interval in seconds (default: 60)

Examples:
    # Install with defaults
    $(basename "$0")

    # Install with custom data directory
    DATA_DIR=/custom/path $(basename "$0")

    # Uninstall
    $(basename "$0") uninstall

    # Check status
    $(basename "$0") status
EOF
}

# Main
main() {
    local command="${1:-install}"

    case "$command" in
        install)
            check_prerequisites
            create_directories
            generate_plist
            install_agent
            verify_installation
            print_status
            ;;
        uninstall)
            uninstall
            ;;
        status)
            print_status
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
