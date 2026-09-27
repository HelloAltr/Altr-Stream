#!/usr/bin/env bash
# ==============================================================================
# Altr Stream — macOS Setup Utility
# ==============================================================================
# Application-grade Terminal Setup Utility powered by Charmbracelet Gum.
#
# Double-click this file in Finder or execute it in Terminal.
# CLI fallback is automatically preserved for headless execution and CI.

set -eo pipefail

ALTR_VERSION="0.13.5-alpha"
ALTR_IMAGE="ghcr.io/helloaltr/altr-stream:${ALTR_VERSION}"

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin"

DEFAULT_INSTALL_DIR="$HOME/.altr-stream"
CONFIG_FILE="${ALTR_STREAM_CONFIG_FILE:-$HOME/.altr-stream-config}"

# Pinned Gum version and official release checksums
GUM_PINNED_VERSION="2.0.2"
GUM_DARWIN_ARM64_SHA="4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890"
GUM_DARWIN_X86_64_SHA="5374966c7c7199ea879fcaa525ddc6d447a098d3d35496e430a9a1ef38d30485"

GUM_BIN="${GUM_BIN:-}"

# ------------------------------------------------------------------------------
# Terminal & Signal Cleanup
# ------------------------------------------------------------------------------
on_signal() {
    printf "\033[?25h" >&2 2>/dev/null || true
    exit 0
}
trap on_signal INT TERM
trap 'printf "\033[?25h" >&2 2>/dev/null || true' EXIT

# ------------------------------------------------------------------------------
# Gum Dependency Resolution
# ------------------------------------------------------------------------------
resolve_gum() {
    # 0. Explicit environment override
    if [ -n "$GUM_BIN" ] && [ -x "$GUM_BIN" ]; then
        return 0
    fi

    # 1. Bundled next to script (e.g. within release zip: Altr-Stream_macOS_Installer.command + bin/gum)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    if [ -x "$script_dir/bin/gum" ]; then
        GUM_BIN="$script_dir/bin/gum"
        return 0
    fi

    # 2. System PATH
    if command -v gum >/dev/null 2>&1; then
        GUM_BIN="$(command -v gum)"
        return 0
    fi

    # 3. User local cache
    local cache_bin="$HOME/.altr-stream/bin/gum"
    if [ -x "$cache_bin" ]; then
        GUM_BIN="$cache_bin"
        return 0
    fi

    # 4. Verified download from official Charmbracelet GitHub release
    local arch_type asset_name expected_sha
    arch_type="$(uname -m)"
    case "$arch_type" in
        arm64|aarch64)
            asset_name="gum_${GUM_PINNED_VERSION}_Darwin_arm64.tar.gz"
            expected_sha="$GUM_DARWIN_ARM64_SHA"
            ;;
        x86_64)
            asset_name="gum_${GUM_PINNED_VERSION}_Darwin_x86_64.tar.gz"
            expected_sha="$GUM_DARWIN_X86_64_SHA"
            ;;
        *)
            echo "ERROR: Unsupported macOS architecture '$arch_type' for Gum." >&2
            return 1
            ;;
    esac

    local download_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_PINNED_VERSION}/${asset_name}"
    local tmp_dir
    tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'altr-gum')"
    local archive_path="$tmp_dir/$asset_name"

    echo "Preparing Altr Stream Setup UI (fetching Gum v${GUM_PINNED_VERSION})..." >&2
    if ! curl -fsSL "$download_url" -o "$archive_path"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    # Compute and verify SHA-256
    local actual_sha=""
    if command -v shasum >/dev/null 2>&1; then
        actual_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
        actual_sha="$(sha256sum "$archive_path" | awk '{print $1}')"
    fi

    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "ERROR: Gum binary verification failed! Checksum mismatch." >&2
        echo "Expected: $expected_sha" >&2
        echo "Actual:   $actual_sha" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    mkdir -p "$(dirname "$cache_bin")"
    tar -xzf "$archive_path" -C "$tmp_dir"
    local extracted_gum
    extracted_gum="$(find "$tmp_dir" -type f -name gum | head -n 1)"
    if [ -n "$extracted_gum" ] && [ -f "$extracted_gum" ]; then
        cp "$extracted_gum" "$cache_bin"
        chmod +x "$cache_bin"
        rm -rf "$tmp_dir"
        GUM_BIN="$cache_bin"
        return 0
    fi

    rm -rf "$tmp_dir"
    return 1
}

# ------------------------------------------------------------------------------
# Terminal Dimension & Visual Centering
# ------------------------------------------------------------------------------
MIN_TERM_COLS=100
MIN_TERM_LINES=30

get_term_dimensions() {
    local cols="" lines=""
    local stty_out
    stty_out="$(stty size 2>/dev/null || true)"
    if [ -n "$stty_out" ]; then
        lines="${stty_out%% *}"
        cols="${stty_out##* }"
    fi
    if [ -z "$cols" ] || [ "$cols" -le 0 ] 2>/dev/null; then
        cols="$(tput cols 2>/dev/null || true)"
    fi
    if [ -z "$lines" ] || [ "$lines" -le 0 ] 2>/dev/null; then
        lines="$(tput lines 2>/dev/null || true)"
    fi
    if [ -z "$cols" ] || [ "$cols" -le 0 ] 2>/dev/null; then
        cols="${COLUMNS:-80}"
    fi
    if [ -z "$lines" ] || [ "$lines" -le 0 ] 2>/dev/null; then
        lines="${LINES:-24}"
    fi
    echo "$cols $lines"
}

get_layout_padding() {
    local card_width="${1:-68}"
    local est_height="${2:-20}"
    local dims cols lines
    dims="$(get_term_dimensions)"
    cols="${dims%% *}"
    lines="${dims##* }"

    local left_pad=$(( (cols - card_width) / 2 ))
    if [ "$left_pad" -lt 0 ]; then left_pad=0; fi

    local top_pad=$(( (lines - est_height) / 2 ))
    if [ "$top_pad" -lt 0 ]; then top_pad=0; fi

    echo "$left_pad $top_pad"
}

check_terminal_size() {
    # Only enforce when attached to an interactive terminal with Gum
    if [ ! -t 0 ] || [ -z "$GUM_BIN" ]; then
        return 0
    fi

    local dims cols lines
    dims="$(get_term_dimensions)"
    cols="${dims%% *}"
    lines="${dims##* }"

    if [ "$cols" -ge "$MIN_TERM_COLS" ] && [ "$lines" -ge "$MIN_TERM_LINES" ]; then
        return 0
    fi

    while [ "$cols" -lt "$MIN_TERM_COLS" ] || [ "$lines" -lt "$MIN_TERM_LINES" ]; do
        clear 2>/dev/null || printf "\033[H\033[2J"
        local card_w=60
        local l_pad=$(( (cols - card_w) / 2 ))
        if [ "$l_pad" -lt 0 ]; then l_pad=0; fi
        local t_pad=$(( (lines - 14) / 2 ))
        if [ "$t_pad" -lt 0 ]; then t_pad=0; fi
        local i=0
        while [ $i -lt "$t_pad" ]; do
            echo ""
            i=$((i + 1))
        done
        "$GUM_BIN" style \
            --margin "0 0 0 $l_pad" \
            --border double \
            --border-foreground 214 \
            --padding "1 2" \
            --width "$card_w" \
            --align center \
            --bold \
            "ALTR STREAM" \
            "Setup & Management Utility" \
            "" \
            "⚠ Terminal window is too small." \
            "" \
            "Current:  ${cols} × ${lines}" \
            "Required: ${MIN_TERM_COLS} × ${MIN_TERM_LINES}" \
            "" \
            "Please resize the terminal window." 2>/dev/null || {
                printf "\n  ALTR STREAM\n  Setup & Management Utility\n\n  Terminal window is too small.\n  Current: %s × %s\n  Required: %s × %s\n\n  Please resize the terminal window.\n" "$cols" "$lines" "$MIN_TERM_COLS" "$MIN_TERM_LINES"
            }
        sleep 0.5
        dims="$(get_term_dimensions)"
        cols="${dims%% *}"
        lines="${dims##* }"
    done
    clear 2>/dev/null || printf "\033[H\033[2J"
    return 0
}

render_screen_top() {
    local est_height="${1:-20}"
    clear 2>/dev/null || printf "\033[H\033[2J"
    check_terminal_size
    local pad
    pad="$(get_layout_padding 68 "$est_height")"
    local top_pad="${pad##* }"
    if [ "$top_pad" -gt 0 ]; then
        local i=0
        while [ $i -lt "$top_pad" ]; do
            echo ""
            i=$((i + 1))
        done
    fi
}

get_viewport_sel_pad() {
    local left_pad
    if [ -n "${1:-}" ]; then
        left_pad="$1"
    else
        local pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"
    fi
    local sel_pad=$((left_pad + 2))
    if [ "$sel_pad" -lt 0 ]; then sel_pad=0; fi
    echo "$sel_pad"
}

gum_choose() {
    if [ -z "$GUM_BIN" ]; then return 1; fi
    local sel_pad
    if [ -n "${left_pad:-}" ]; then
        sel_pad=$((left_pad + 2))
    else
        sel_pad="$(get_viewport_sel_pad)"
    fi
    if [ "$sel_pad" -lt 0 ]; then sel_pad=0; fi
    "$GUM_BIN" choose --padding="0 0 0 $sel_pad" "$@"
}

gum_confirm() {
    if [ -z "$GUM_BIN" ]; then return 1; fi
    local sel_pad
    if [ -n "${left_pad:-}" ]; then
        sel_pad=$((left_pad + 2))
    else
        sel_pad="$(get_viewport_sel_pad)"
    fi
    if [ "$sel_pad" -lt 0 ]; then sel_pad=0; fi
    "$GUM_BIN" confirm --padding="0 0 0 $sel_pad" "$@"
}

gum_input() {
    if [ -z "$GUM_BIN" ]; then return 1; fi
    local sel_pad
    if [ -n "${left_pad:-}" ]; then
        sel_pad=$((left_pad + 2))
    else
        sel_pad="$(get_viewport_sel_pad)"
    fi
    if [ "$sel_pad" -lt 0 ]; then sel_pad=0; fi
    "$GUM_BIN" input --padding="0 0 0 $sel_pad" "$@"
}

# ------------------------------------------------------------------------------
# Directory Management
# ------------------------------------------------------------------------------
get_install_dir() {
    if [ -n "${1:-}" ]; then
        echo "$1"
    elif [ -n "${ALTR_STREAM_HOME:-}" ]; then
        echo "$ALTR_STREAM_HOME"
    elif [ -f "$CONFIG_FILE" ]; then
        local saved_dir
        saved_dir="$(cat "$CONFIG_FILE" 2>/dev/null | tr -d '\n\r' || true)"
        if [ -n "$saved_dir" ] && [ -d "$saved_dir" ] && [ -f "$saved_dir/docker-compose.yml" ]; then
            case "$saved_dir" in
                */pytest*|*/tmp/*|*/private/var/folders/*|/tmp/*|/var/tmp/*|*\\AppData\\Local\\Temp\\*)
                    echo "$DEFAULT_INSTALL_DIR"
                    ;;
                *)
                    echo "$saved_dir"
                    ;;
            esac
            return
        fi
        echo "$DEFAULT_INSTALL_DIR"
    else
        echo "$DEFAULT_INSTALL_DIR"
    fi
}

save_install_dir() {
    local target="$1"
    # Never leak pytest or temporary paths into the default production config file
    case "$target" in
        */pytest*|*/tmp/*|*/private/var/folders/*|/tmp/*|/var/tmp/*|*\\AppData\\Local\\Temp\\*)
            if [ -n "${ALTR_STREAM_CONFIG_FILE:-}" ]; then
                echo "$target" > "$CONFIG_FILE" 2>/dev/null || true
            fi
            ;;
        *)
            echo "$target" > "$CONFIG_FILE" 2>/dev/null || true
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Docker Prerequisites
# ------------------------------------------------------------------------------
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo ""
    fi
}

check_docker() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

check_compose() {
    [ -n "$(get_compose_cmd)" ]
}

get_docker_status_text() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Missing"
    elif ! docker info >/dev/null 2>&1; then
        echo "Stopped"
    elif [ -z "$(get_compose_cmd)" ]; then
        echo "No Compose"
    else
        echo "Running"
    fi
}

get_web_port() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then dir="$(get_install_dir)"; fi
    local port="8000"
    if [ -f "$dir/.env" ]; then
        local p
        p="$(grep -E '^ALTR_STREAM_PORT=' "$dir/.env" 2>/dev/null | cut -d '=' -f 2 | tr -d ' "\r\n' || true)"
        if [ -n "$p" ]; then
            port="$p"
        fi
    fi
    echo "$port"
}

get_web_url() {
    local dir="${1:-}"
    local port
    port="$(get_web_port "$dir")"
    echo "http://localhost:${port}"
}

launch_browser() {
    local url="$1"
    if command -v open >/dev/null 2>&1; then
        open "$url" 2>/dev/null || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" 2>/dev/null || true
    fi
}

get_altr_status_text() {
    local dir="${1:-$(get_install_dir)}"
    local web_url
    web_url="$(get_web_url "$dir")"
    if [ ! -d "$dir" ] || [ ! -f "$dir/docker-compose.yml" ]; then
        echo "Not Installed"
        return
    fi
    if curl -sf "$web_url/api/v1/health" >/dev/null 2>&1; then
        echo "Running"
        return
    fi
    local compose_cmd
    compose_cmd="$(get_compose_cmd)"
    if [ -n "$compose_cmd" ] && $compose_cmd -f "$dir/docker-compose.yml" ps --status running 2>/dev/null | grep -q "altr-stream"; then
        echo "Running"
        return
    fi
    if command -v docker >/dev/null 2>&1 && [ "$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)" = "running" ]; then
        echo "Running"
        return
    fi
    if [ -n "$compose_cmd" ] && $compose_cmd -f "$dir/docker-compose.yml" ps -a 2>/dev/null | grep -q "altr-stream"; then
        echo "Stopped"
        return
    fi
    if command -v docker >/dev/null 2>&1 && docker inspect altr-stream >/dev/null 2>&1; then
        echo "Stopped"
        return
    fi
    echo "Not Installed"
}

verify_installation() {
    local target_dir="$1"
    local web_url
    web_url="$(get_web_url "$target_dir")"

    if [ ! -d "$target_dir" ]; then
        return 1
    fi
    if [ ! -f "$target_dir/docker-compose.yml" ] || [ ! -f "$target_dir/.env" ]; then
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    if ! docker inspect altr-stream >/dev/null 2>&1; then
        return 1
    fi

    local cstatus cmounts cimage
    cstatus="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
    if [ "$cstatus" != "running" ]; then
        return 1
    fi

    cimage="$(docker inspect -f '{{.Config.Image}}' altr-stream 2>/dev/null || true)"
    if ! echo "$cimage" | grep -qi "altr-stream"; then
        return 1
    fi

    cmounts="$(docker inspect -f '{{range .Mounts}}{{.Name}}{{.Source}} -> {{.Destination}} {{end}}' altr-stream 2>/dev/null || true)"
    if ! echo "$cmounts" | grep -q "altr_stream_data"; then
        return 1
    fi

    if ! curl -sf "$web_url/api/v1/health" >/dev/null 2>&1 && ! curl -sf "$web_url/api/health" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Manifest Generation
# ------------------------------------------------------------------------------
write_runtime_files() {
    local install_dir="$1"
    mkdir -p "$install_dir"
    mkdir -p "$install_dir/data/updates"

    cat << 'EOF' > "$install_dir/docker-compose.yml"
services:
  altr-stream:
    image: ghcr.io/helloaltr/altr-stream:0.13.5-alpha
    container_name: altr-stream
    restart: unless-stopped
    ports:
      - "${ALTR_STREAM_PORT:-8000}:8000"
    volumes:
      - altr_stream_data:/app/data
      - ./data/updates:/app/data/updates
    environment:
      - ALTR_STREAM_HOST=0.0.0.0
      - ALTR_STREAM_PORT=8000
      - ALTR_STREAM_DATA_DIR=/app/data
      - ALTR_STREAM_DEBUG=${ALTR_STREAM_DEBUG:-false}
      - ALTR_STREAM_LOG_LEVEL=${ALTR_STREAM_LOG_LEVEL:-INFO}
      - ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC=${ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC:-5.0}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

volumes:
  altr_stream_data:
    name: altr_stream_data
EOF

    if [ ! -f "$install_dir/.env" ]; then
        cat << 'EOF' > "$install_dir/.env"
# Altr Stream Environment Configuration
ALTR_STREAM_PORT=8000
ALTR_STREAM_LOG_LEVEL=INFO
ALTR_STREAM_DEBUG=false
ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC=5.0
EOF
    fi
}

# ------------------------------------------------------------------------------
# Screen: Docker Prerequisite Error
# ------------------------------------------------------------------------------
show_docker_error_screen() {
    local is_stopped="$1"

    if [ -z "$GUM_BIN" ] || [ ! -t 0 ]; then
        return 1
    fi

    render_screen_top 22
    local pad left_pad
    pad="$(get_layout_padding 68 22)"
    left_pad="${pad%% *}"

    if [ "$is_stopped" = true ]; then
        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            --bold \
            "Docker Daemon Stopped" "" \
            "✗ Docker daemon is not running or accessible." \
            "Altr Stream requires a responsive Docker engine." \
            "Please launch Docker Desktop and verify the status icon is running."
    else
        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            --bold \
            "Docker Required" "" \
            "✗ Docker Desktop was not found on this system." \
            "Docker and Docker Compose are required to run Altr Stream." \
            "Please download Docker Desktop from https://www.docker.com/products/docker-desktop/"
    fi

    local choice
    choice="$(gum_choose \
        --cursor="❯ " \
        --cursor.foreground="48" \
        --header="Select an action:" \
        "Start Docker Desktop" \
        "Open Docker Download / Documentation" \
        "Retry Detection" \
        "Back to Main Menu")"

    case "$choice" in
        "Start Docker Desktop")
            open -a "Docker" 2>/dev/null || open -a "Docker Desktop" 2>/dev/null || true
            sleep 3
            if check_docker; then return 0; fi
            ;;
        "Open Docker Download / Documentation")
            open "https://www.docker.com/products/docker-desktop/" 2>/dev/null || true
            ;;
        "Retry Detection")
            if check_docker; then return 0; fi
            ;;
        *)
            return 1
            ;;
    esac
    return 1
}

# ------------------------------------------------------------------------------
# Screen: Main Menu
# ------------------------------------------------------------------------------
show_main_menu() {
    while true; do
        render_screen_top 22
        local pad left_pad
        pad="$(get_layout_padding 68 22)"
        left_pad="${pad%% *}"

        local docker_stat altr_stat current_dir
        docker_stat="$(get_docker_status_text)"
        altr_stat="$(get_altr_status_text)"
        current_dir="$(get_install_dir)"

        local inner_w=62
        local h1="ALTR STREAM"
        local h2="Setup & Management Utility"
        local h3="v${ALTR_VERSION}"
        local pad1=$(( (inner_w - ${#h1}) / 2 ))
        local pad2=$(( (inner_w - ${#h2}) / 2 ))
        local pad3=$(( (inner_w - ${#h3}) / 2 ))
        local sp1="" sp2="" sp3=""
        local i=0
        while [ $i -lt "$pad1" ]; do sp1=" $sp1"; i=$((i + 1)); done
        i=0
        while [ $i -lt "$pad2" ]; do sp2=" $sp2"; i=$((i + 1)); done
        i=0
        while [ $i -lt "$pad3" ]; do sp3=" $sp3"; i=$((i + 1)); done

        # 1. Unified Application Viewport Container Card
        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 39 \
            --padding "1 2" \
            --width 68 \
            --bold \
            "${sp1}${h1}" \
            "${sp2}${h2}" \
            "${sp3}${h3}" \
            "" \
            "  Docker Engine:  $docker_stat" \
            "  Altr Container: $altr_stat" \
            "  Install Path:   $current_dir"

        # 2. Interactive Selection (Aligned inside Centered Viewport)
        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="Select an operation:" \
            "Install Altr Stream" \
            "Uninstall Altr Stream" \
            "Repair Installation" \
            "Installation Status" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Install Altr Stream")
                workflow_install
                ;;
            "Uninstall Altr Stream")
                workflow_uninstall
                ;;
            "Repair Installation")
                workflow_repair
                ;;
            "Installation Status")
                workflow_status
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                exit 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Workflow 1 Helpers: Container Conflict & Inspection
# ------------------------------------------------------------------------------
check_container_conflict() {
    local target_dir="$1"
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    if ! docker inspect altr-stream >/dev/null 2>&1; then
        return 1
    fi
    local cworkdir
    cworkdir="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>/dev/null || true)"
    if [ -z "$cworkdir" ] || [ "$cworkdir" != "$target_dir" ]; then
        return 0
    fi
    return 1
}

show_existing_container_details() {
    local target_container="${1:-altr-stream}"
    local return_label="${2:-Back to Conflict Menu}"

    if ! docker inspect "$target_container" >/dev/null 2>&1; then
        "$GUM_BIN" style --foreground 196 "Container '$target_container' does not exist."
        gum_choose --cursor="❯ " "$return_label" || true
        return 0
    fi

    local cid cname cstatus chealth cimage ccreated cports cproject cworkdir cmounts clabels cversion
    cid="$(docker inspect -f '{{.Id}}' "$target_container" 2>/dev/null || true)"
    cname="$(docker inspect -f '{{.Name}}' "$target_container" 2>/dev/null | sed 's|^/||')"
    cstatus="$(docker inspect -f '{{.State.Status}}' "$target_container" 2>/dev/null || true)"
    chealth="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$target_container" 2>/dev/null || true)"
    cimage="$(docker inspect -f '{{.Config.Image}}' "$target_container" 2>/dev/null || true)"
    ccreated="$(docker inspect -f '{{.Created}}' "$target_container" 2>/dev/null || true)"
    cports="$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' "$target_container" 2>/dev/null || true)"
    cproject="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$target_container" 2>/dev/null || true)"
    cworkdir="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$target_container" 2>/dev/null || true)"
    cmounts="$(docker inspect -f '{{range .Mounts}}{{.Name}}{{.Source}} -> {{.Destination}} ({{.Type}}) {{end}}' "$target_container" 2>/dev/null || true)"
    cversion="$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$target_container" 2>/dev/null || true)"
    if [ -z "$cversion" ]; then
        cversion="$(echo "$cimage" | grep -o ':[^:]*$' | tr -d ':' || true)"
    fi

    local classification
    if echo "$cimage" | grep -qi "altr-stream"; then
        classification="✓ Identified as an Altr Stream container"
    else
        classification="⚠ Notice: This container does NOT appear to belong to Altr Stream."
    fi

    render_screen_top 26
    local pad left_pad
    pad="$(get_layout_padding 68 26)"
    left_pad="${pad%% *}"

    "$GUM_BIN" style \
        --margin "0 0 0 $left_pad" \
        --border rounded \
        --border-foreground 39 \
        --padding "1 2" \
        --width 68 \
        --align center \
        --bold \
        "CONTAINER DETAILS" "" \
        "${cname}"

    "$GUM_BIN" style \
        --margin "0 0 0 $left_pad" \
        --border rounded \
        --border-foreground 240 \
        --padding "0 2" \
        --width 68 \
        "Container Attributes:" "" \
        "  Name:           ${cname}" \
        "  ID:             ${cid:0:12} (${cid})" \
        "  Status:         ${cstatus}" \
        "  Health State:   ${chealth}" \
        "  Image:          ${cimage}" \
        "  Version:        ${cversion:-Unknown}" \
        "  Created:        ${ccreated}" \
        "  Ports:          ${cports:-None}" \
        "  Compose Proj:   ${cproject:-None}" \
        "  Working Dir:    ${cworkdir:-None}" \
        "  Mounts:         ${cmounts:-None}" "" \
        "Classification:" \
        "  ${classification}"

    gum_choose --cursor="❯ " --cursor.foreground="48" "$return_label" || true
}

handle_remove_existing_container() {
    local target_dir="$1"
    local cid cname
    cid="$(docker inspect -f '{{.Id}}' altr-stream 2>/dev/null || true)"
    cname="$(docker inspect -f '{{.Name}}' altr-stream 2>/dev/null | sed 's|^/||')"

    render_screen_top 20
    local pad left_pad
    pad="$(get_layout_padding 68 20)"
    left_pad="${pad%% *}"

    "$GUM_BIN" style \
        --margin "0 0 0 $left_pad" \
        --border rounded \
        --border-foreground 214 \
        --padding "1 2" \
        --width 68 \
        "⚠ EXISTING CONTAINER" "" \
        "A container named \"altr-stream\" already exists." "" \
        "Removing it may affect an existing Altr Stream" \
        "installation." "" \
        "Container: ${cname:-altr-stream}" \
        "ID:        ${cid:0:12}"

    local choice
    choice="$(gum_choose \
        --cursor="❯ " \
        --cursor.foreground="48" \
        --header="Proceed?" \
        "Cancel" \
        "Remove Container" || echo "Cancel")"

    if [ "$choice" != "Remove Container" ]; then
        return 1
    fi

    # Explicit confirmation
    render_screen_top 20
    "$GUM_BIN" style \
        --margin "0 0 0 $left_pad" \
        --border rounded \
        --border-foreground 196 \
        --padding "1 2" \
        --width 68 \
        "CONFIRM CONTAINER REMOVAL" "" \
        "Are you sure you want to remove container \"altr-stream\"?" "" \
        "This removes ONLY the container. Persistent data stored in" \
        "the named volume \"altr_stream_data\" will NOT be deleted."

    local confirm
    confirm="$(gum_choose \
        --cursor="❯ " \
        --cursor.foreground="48" \
        --header="Are you sure?" \
        "Cancel" \
        "Confirm Removal" || echo "Cancel")"

    if [ "$confirm" != "Confirm Removal" ]; then
        return 1
    fi

    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Removing conflicting container altr-stream..." -- docker rm -f altr-stream || true
    else
        docker rm -f altr-stream >/dev/null 2>&1 || true
    fi

    return 0
}

handle_use_existing_container() {
    local target_dir="$1"

    if ! docker inspect altr-stream >/dev/null 2>&1; then
        "$GUM_BIN" style --foreground 196 "Container 'altr-stream' no longer exists."
        sleep 1
        return 1
    fi

    local cid cname cstatus cimage cworkdir
    cid="$(docker inspect -f '{{.Id}}' altr-stream 2>/dev/null || true)"
    cname="$(docker inspect -f '{{.Name}}' altr-stream 2>/dev/null | sed 's|^/||')"
    cstatus="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
    cimage="$(docker inspect -f '{{.Config.Image}}' altr-stream 2>/dev/null || true)"
    cworkdir="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>/dev/null || true)"

    # Verify image is Altr Stream
    if ! echo "$cimage" | grep -qi "altr-stream"; then
        render_screen_top 20
        local pad left_pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            "INCOMPATIBLE CONTAINER" "" \
            "The existing container does not appear to be an Altr Stream image." "" \
            "Image: ${cimage}"
        local subchoice
        subchoice="$(gum_choose --cursor="❯ " --cursor.foreground="48" "Back to Conflict Menu" "View Container Details" || echo "Back to Conflict Menu")"
        if [ "$subchoice" = "View Container Details" ]; then
            show_existing_container_details "altr-stream" "Back to Conflict Menu"
        fi
        return 1
    fi

    # If container is stopped, offer to start it
    if [ "$cstatus" != "running" ]; then
        render_screen_top 20
        local pad left_pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 214 \
            --padding "1 2" \
            --width 68 \
            "CONTAINER STOPPED" "" \
            "The existing Altr Stream container is currently stopped." "" \
            "Status: ${cstatus}"

        local start_choice
        start_choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="Would you like to start it now?" \
            "Start Container & Verify Health" \
            "Back to Conflict Menu" || echo "Back to Conflict Menu")"

        if [ "$start_choice" != "Start Container & Verify Health" ]; then
            return 1
        fi

        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            "$GUM_BIN" spin --spinner dot --title "Starting container altr-stream..." -- docker start altr-stream || true
        else
            docker start altr-stream >/dev/null 2>&1 || true
        fi
    fi

    # Verify health endpoint
    local healthy=false
    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Verifying container health..." -- bash -c "
            attempt=0
            while [ \$attempt -lt 20 ]; do
                attempt=\$((attempt + 1))
                if curl -sf http://localhost:8000/api/v1/health >/dev/null 2>&1; then
                    exit 0
                fi
                sleep 1
            done
            exit 1
        " && healthy=true || healthy=false
    else
        local attempt=0
        while [ $attempt -lt 20 ]; do
            attempt=$((attempt + 1))
            if curl -sf http://localhost:8000/api/v1/health >/dev/null 2>&1; then
                healthy=true
                break
            fi
            sleep 1
        done
    fi

    if [ "$healthy" != true ]; then
        render_screen_top 20
        local pad left_pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            "HEALTH CHECK FAILED" "" \
            "The existing container could not be verified." "" \
            "Health check at http://localhost:8000/api/v1/health did not respond."

        local fail_choice
        fail_choice="$(gum_choose --cursor="❯ " --cursor.foreground="48" "Back to Conflict Menu" "View Container Details" || echo "Back to Conflict Menu")"
        if [ "$fail_choice" = "View Container Details" ]; then
            show_existing_container_details "altr-stream" "Back to Conflict Menu"
        fi
        return 1
    fi

    # Application reports valid version
    local health_resp version_str
    health_resp="$(curl -sf http://localhost:8000/api/v1/health 2>/dev/null || true)"
    version_str="$(echo "$health_resp" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || true)"
    if [ -z "$version_str" ]; then
        version_str="${ALTR_VERSION}"
    fi

    # Show confirmation summary as specified in prompt:
    while true; do
        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border double \
            --border-foreground 48 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "EXISTING ALTR STREAM FOUND"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 240 \
            --padding "0 2" \
            --width 68 \
            "Container:" \
            "  altr-stream" "" \
            "Status:" \
            "  Running / Healthy" "" \
            "Version:" \
            "  v${version_str#v}" "" \
            "Web Interface:" \
            "  http://localhost:8000" "" \
            "This existing installation can be used."

        local use_choice
        use_choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            "Use Existing Installation" \
            "View Container Details" \
            "Back" || echo "Back")"

        case "$use_choice" in
            "Use Existing Installation")
                local active_dir
                if [ -n "$cworkdir" ] && [ -d "$cworkdir" ] && [ -f "$cworkdir/docker-compose.yml" ]; then
                    active_dir="$cworkdir"
                else
                    active_dir="$target_dir"
                    write_runtime_files "$active_dir"
                fi
                save_install_dir "$active_dir"
                export ALTR_STREAM_HOME="$active_dir"

                show_install_success_screen "$active_dir"
                return 0
                ;;
            "View Container Details")
                show_existing_container_details "altr-stream" "Back"
                ;;
            "Back"|*)
                return 1
                ;;
        esac
    done
}

show_conflict_menu() {
    local target_dir="$1"

    while true; do
        if ! docker inspect altr-stream >/dev/null 2>&1; then
            workflow_install "$target_dir"
            return 0
        fi

        local cid cname cstatus cimage cworkdir
        cid="$(docker inspect -f '{{.Id}}' altr-stream 2>/dev/null || true)"
        cname="$(docker inspect -f '{{.Name}}' altr-stream 2>/dev/null | sed 's|^/||')"
        cstatus="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
        cimage="$(docker inspect -f '{{.Config.Image}}' altr-stream 2>/dev/null || true)"
        cworkdir="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>/dev/null || true)"

        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 214 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "⚠ EXISTING CONTAINER DETECTED" "" \
            "A container named \"altr-stream\" already exists in Docker."

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 240 \
            --padding "0 2" \
            --width 68 \
            "Existing Container Info:" "" \
            "  Name:     ${cname:-altr-stream}" \
            "  ID:       ${cid:0:12}" \
            "  Status:   ${cstatus}" \
            "  Image:    ${cimage}" \
            "  Path:     ${cworkdir:-Unknown / Not set}"

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Use Existing Altr Stream Container" \
            "Remove Existing Container" \
            "View Container Details" \
            "Retry Installation" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Use Existing Altr Stream Container")
                if handle_use_existing_container "$target_dir"; then
                    return 0
                fi
                ;;
            "Remove Existing Container")
                if handle_remove_existing_container "$target_dir"; then
                    workflow_install "$target_dir"
                    return 0
                fi
                ;;
            "View Container Details")
                show_existing_container_details "altr-stream" "Back to Conflict Menu"
                ;;
            "Retry Installation")
                if check_container_conflict "$target_dir"; then
                    clear 2>/dev/null || true
                    "$GUM_BIN" style \
                        --border rounded \
                        --border-foreground 214 \
                        --padding "0 2" \
                        --width 64 \
                        "⚠ Container \"altr-stream\" still exists." \
                        "Please resolve the conflict before retrying installation."
                    sleep 1.5
                else
                    workflow_install "$target_dir"
                    return 0
                fi
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

workflow_install() {
    local target_dir="${1:-}"
    if [ -z "$target_dir" ]; then
        target_dir="$(get_install_dir)"
    fi

    # Verify Docker Prerequisites
    if ! check_docker; then
        if [ ! -t 0 ]; then
            echo "ERROR: Docker engine is not running or accessible."
            exit 1
        fi
        if ! command -v docker >/dev/null 2>&1; then
            if ! show_docker_error_screen false; then return 1; fi
        else
            if ! show_docker_error_screen true; then return 1; fi
        fi
    fi

    # Verify Docker Compose
    if ! check_compose; then
        if [ ! -t 0 ]; then
            echo "ERROR: Docker Compose plugin was not found. Please ensure docker compose is installed."
            exit 1
        fi
        "$GUM_BIN" style \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 64 \
            --bold \
            "Docker Compose Required" "" \
            "✗ Docker Compose plugin was not found." \
            "Docker Compose v2 is required to manage Altr Stream."
        gum_confirm "Press Enter to return" || true
        return 1
    fi

    # Interactive Install Screen
    if [ -t 0 ] && [ -z "${1:-}" ] && [ -n "$GUM_BIN" ]; then
        while true; do
            render_screen_top 20
            local pad left_pad
            pad="$(get_layout_padding 68 20)"
            left_pad="${pad%% *}"

            "$GUM_BIN" style \
                --margin "0 0 0 $left_pad" \
                --border rounded \
                --border-foreground 39 \
                --padding "1 2" \
                --width 68 \
                "Install Altr Stream" "" \
                "Target Version:        v${ALTR_VERSION}" \
                "Installation Path:     ${target_dir}" "" \
                "Prerequisites:" \
                "  ✓ Docker installed" \
                "  ✓ Docker daemon running & responsive" \
                "  ✓ Docker Compose available"

            local action
            action="$(gum_choose \
                --cursor="❯ " \
                --cursor.foreground="48" \
                --header="Ready to proceed:" \
                "Install Altr Stream" \
                "Change Installation Path" \
                "Back to Main Menu")"

            case "$action" in
                "Install Altr Stream")
                    break
                    ;;
                "Change Installation Path")
                    local new_path
                    new_path="$(gum_input --placeholder "Enter custom installation path" --value "$target_dir" --width 50)"
                    if [ -n "$new_path" ]; then
                        target_dir="$(mkdir -p "$new_path" && cd "$new_path" && pwd)"
                        save_install_dir "$target_dir"
                        export ALTR_STREAM_HOME="$target_dir"
                    fi
                    ;;
                *)
                    return 0
                    ;;
            esac
        done
    fi

    target_dir="$(mkdir -p "$target_dir" && cd "$target_dir" && pwd)"
    save_install_dir "$target_dir"
    export ALTR_STREAM_HOME="$target_dir"

    # Pre-creation conflict detection
    if check_container_conflict "$target_dir"; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            show_conflict_menu "$target_dir"
            return 0
        else
            local cid cname cstatus cimage
            cid="$(docker inspect -f '{{.Id}}' altr-stream 2>/dev/null || true)"
            cname="$(docker inspect -f '{{.Name}}' altr-stream 2>/dev/null | sed 's|^/||')"
            cstatus="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
            cimage="$(docker inspect -f '{{.Config.Image}}' altr-stream 2>/dev/null || true)"
            echo "ERROR: A container named \"altr-stream\" already exists in Docker." >&2
            echo "  Container: ${cname:-altr-stream}" >&2
            echo "  ID:        ${cid:0:12}" >&2
            echo "  Status:    ${cstatus}" >&2
            echo "  Image:     ${cimage}" >&2
            echo "Cannot proceed with installation while a conflicting container exists." >&2
            echo "Resolve the conflict or run interactively to use or remove the existing container." >&2
            exit 1
        fi
    fi

    local compose_cmd
    compose_cmd="$(get_compose_cmd)"
    local web_url
    web_url="$(get_web_url "$target_dir")"

    local failed_stage=""
    local failed_reason=""
    local failed_technical=""

    # Stage 1: Preparing installation & runtime configuration
    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Preparing runtime configuration files..." -- sleep 0.4
    fi
    write_runtime_files "$target_dir"

    # Stage 2: Preparing persistent storage
    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Preparing persistent storage volume (altr_stream_data)..." -- sleep 0.3
    fi
    docker volume create altr_stream_data >/dev/null 2>&1 || true

    # Stage 3: Pulling image
    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Pulling Altr Stream image (${ALTR_IMAGE})..." -- $compose_cmd -f "$target_dir/docker-compose.yml" pull || true
    else
        $compose_cmd -f "$target_dir/docker-compose.yml" pull 2>/dev/null || true
    fi

    # Stage 4: Starting container
    local start_failed=false
    local docker_start_log="$target_dir/.docker_start.log"
    rm -f "$docker_start_log" 2>/dev/null || true

    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Starting Altr Stream container..." -- bash -c "
            $compose_cmd -f \"$target_dir/docker-compose.yml\" up -d >\"$docker_start_log\" 2>&1
        " || start_failed=true
    else
        if ! $compose_cmd -f "$target_dir/docker-compose.yml" up -d >"$docker_start_log" 2>&1; then
            start_failed=true
        fi
    fi

    if [ "$start_failed" = true ]; then
        failed_stage="Starting Altr Stream container"
        if [ -f "$docker_start_log" ]; then
            failed_technical="$(cat "$docker_start_log")"
        fi
        if echo "$failed_technical" | grep -qi "Conflict.*container name.*already in use"; then
            failed_reason="Container name \"altr-stream\" is already in use."
        elif echo "$failed_technical" | grep -qi -E "port is already allocated|bind: address already in use"; then
            failed_reason="Port 8000 is already in use by another application."
        elif [ -n "$failed_technical" ]; then
            local first_line
            first_line="$(echo "$failed_technical" | grep -v '^[[:space:]]*$' | head -n 1)"
            failed_reason="${first_line:-docker compose up -d encountered an error}"
        else
            failed_reason="docker compose up -d encountered an error"
        fi
    fi

    # Stage 5: Waiting for health check
    if [ -z "$failed_stage" ]; then
        local healthy=false
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            "$GUM_BIN" spin --spinner dot --title "Waiting for Altr Stream health check..." -- bash -c "
                attempt=0
                while [ \$attempt -lt 30 ]; do
                    attempt=\$((attempt + 1))
                    if curl -sf \"${web_url}/api/v1/health\" >/dev/null 2>&1; then
                        exit 0
                    fi
                    sleep 1
                done
                exit 1
            " && healthy=true || healthy=false
        else
            local max_attempts=30
            local attempt=0
            while [ $attempt -lt $max_attempts ]; do
                attempt=$((attempt + 1))
                if curl -sf "$web_url/api/v1/health" >/dev/null 2>&1; then
                    healthy=true
                    break
                fi
                sleep 1
            done
        fi

        if [ "$healthy" != true ]; then
            failed_stage="Waiting for Altr Stream health check"
            failed_reason="Health check timed out after waiting for ${web_url}/api/v1/health"
        fi
    fi

    # Verification and persistent screen transition
    if [ -z "$failed_stage" ] && verify_installation "$target_dir"; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            show_install_success_screen "$target_dir"
            return 0
        else
            echo "Altr Stream is installed and running at ${web_url}"
            return 0
        fi
    else
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            show_install_failure_screen "$target_dir" "${failed_stage:-Health Verification}" "${failed_reason:-Altr Stream failed health verification}" "${failed_technical}"
            return 0
        else
            echo "ERROR: Installation verification failed at stage: ${failed_stage:-Health Verification}"
            echo "Reason: ${failed_reason:-Altr Stream failed health verification}"
            if [ -n "$failed_technical" ]; then
                echo "Technical Details: $failed_technical"
            fi
            echo "Inspect container logs: cd \"$target_dir\" && $compose_cmd logs altr-stream"
            exit 1
        fi
    fi
}

show_install_success_screen() {
    local target_dir="$1"
    local web_url
    web_url="$(get_web_url "$target_dir")"

    while true; do
        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border double \
            --border-foreground 48 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✓ INSTALLATION COMPLETE" "" \
            "ALTR STREAM" "v${ALTR_VERSION}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 240 \
            --padding "0 2" \
            --width 68 \
            "Installation Summary:" "" \
            "  ✓ Docker Engine       Running" \
            "  ✓ Altr Stream         Running" \
            "  ✓ Container           Healthy" \
            "  ✓ Version             v${ALTR_VERSION}" \
            "  ✓ Installation Path   ${target_dir}" \
            "  ✓ Persistent Data     Enabled (altr_stream_data)" \
            "  ✓ Web Interface       ${web_url}"

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Launch Altr Stream" \
            "Open Web Interface" \
            "Installation Status" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Launch Altr Stream"|"Open Web Interface")
                launch_browser "$web_url"
                show_running_screen "$target_dir" "$web_url"
                return 0
                ;;
            "Installation Status")
                workflow_status "$target_dir"
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

show_running_screen() {
    local target_dir="$1"
    local web_url="$2"

    while true; do
        render_screen_top 22
        local pad left_pad
        pad="$(get_layout_padding 68 22)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border double \
            --border-foreground 48 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✓ ALTR STREAM IS RUNNING" "" \
            "Web Interface:" \
            "${web_url}" "" \
            "The interface has been opened in your default browser."

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Open Altr Stream Again" \
            "Installation Status" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Open Altr Stream Again")
                launch_browser "$web_url"
                ;;
            "Installation Status")
                workflow_status "$target_dir"
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

show_install_failure_screen() {
    local target_dir="$1"
    local stage="$2"
    local reason="$3"
    local technical="${4:-}"
    local compose_cmd
    compose_cmd="$(get_compose_cmd)"

    while true; do
        render_screen_top 26
        local pad left_pad
        pad="$(get_layout_padding 68 26)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border double \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✕ INSTALLATION FAILED" "" \
            "Altr Stream could not be started successfully."

        local docker_stat altr_stat
        docker_stat="$(get_docker_status_text)"
        altr_stat="$(get_altr_status_text "$target_dir")"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "0 2" \
            --width 68 \
            "Failure Diagnostics:" "" \
            "  Stage:          ${stage:-Installation Verification}" \
            "  Reason:         ${reason:-Container failed health checks}" \
            $([ -n "$technical" ] && echo "  Technical:      ${technical}") "" \
            "Current State:" \
            "  Docker Engine:  ${docker_stat}" \
            "  Container:      ${altr_stat}" \
            "  Path:           ${target_dir}"

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Retry Installation" \
            "View Installation Status" \
            "View Container Logs" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Retry Installation")
                workflow_install "$target_dir"
                return 0
                ;;
            "View Installation Status")
                workflow_status "$target_dir"
                ;;
            "View Container Logs")
                local has_container=false
                if [ -n "$compose_cmd" ] && [ -f "$target_dir/docker-compose.yml" ]; then
                    local cid_proj
                    cid_proj="$($compose_cmd -f "$target_dir/docker-compose.yml" ps -q altr-stream 2>/dev/null || true)"
                    if [ -n "$cid_proj" ]; then
                        has_container=true
                    fi
                fi

                if [ "$has_container" = false ] || [ "$stage" = "Starting Altr Stream container" ]; then
                    clear 2>/dev/null || true
                    "$GUM_BIN" style \
                        --border rounded \
                        --border-foreground 214 \
                        --padding "1 2" \
                        --width 64 \
                        --align center \
                        --bold \
                        "CONTAINER LOGS"

                    local cid_conf="" cname_conf="" cstate_conf=""
                    if command -v docker >/dev/null 2>&1 && docker inspect altr-stream >/dev/null 2>&1; then
                        cid_conf="$(docker inspect -f '{{.Id}}' altr-stream 2>/dev/null || true)"
                        cname_conf="$(docker inspect -f '{{.Name}}' altr-stream 2>/dev/null | sed 's|^/||')"
                        cstate_conf="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
                    fi

                    local conflict_details=""
                    if [ -n "$cid_conf" ]; then
                        conflict_details="Conflicting container:
  Name:  ${cname_conf:-altr-stream}
  ID:    ${cid_conf:0:12}
  State: ${cstate_conf}"
                    fi

                    "$GUM_BIN" style \
                        --border rounded \
                        --border-foreground 240 \
                        --padding "0 2" \
                        --width 64 \
                        "No logs are available for the new container because Docker failed" \
                        "before the container could be created." "" \
                        "Docker reported:" \
                        "  ${technical:-${reason}}" "" \
                        ${conflict_details:+"$conflict_details"}

                    local log_action
                    log_action="$(gum_choose \
                        --cursor="❯ " \
                        --cursor.foreground="48" \
                        "View Container Details" \
                        "Back to Failure Menu" || echo "Back to Failure Menu")"

                    if [ "$log_action" = "View Container Details" ]; then
                        show_existing_container_details "altr-stream" "Back to Failure Menu"
                    fi
                else
                    clear 2>/dev/null || true
                    echo "--- Container Logs (last 30 lines) ---"
                    local logs_output
                    logs_output="$($compose_cmd -f "$target_dir/docker-compose.yml" logs --tail 30 altr-stream 2>&1 || true)"
                    if [ -n "$logs_output" ]; then
                        echo "$logs_output"
                    else
                        echo "(No log output recorded yet)"
                    fi
                    echo "--------------------------------------"
                    gum_choose --cursor="❯ " "Return to Failure Menu" || true
                fi
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Workflow 2: Uninstall
# ------------------------------------------------------------------------------
workflow_uninstall() {
    local target_dir="${1:-}"
    if [ -z "$target_dir" ]; then
        target_dir="$(get_install_dir)"
    fi

    if [ ! -d "$target_dir" ] || [ ! -f "$target_dir/docker-compose.yml" ]; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            render_screen_top 18
            local pad left_pad
            pad="$(get_layout_padding 68 18)"
            left_pad="${pad%% *}"

            "$GUM_BIN" style \
                --margin "0 0 0 $left_pad" \
                --border rounded \
                --border-foreground 214 \
                --padding "1 2" \
                --width 68 \
                "Uninstall Altr Stream" "" \
                "No active Altr Stream installation detected at:" \
                "${target_dir}"
            gum_confirm "Press Enter to return..." || true
        else
            echo "No Altr Stream installation detected at ${target_dir}"
        fi
        return
    fi

    local compose_cmd
    compose_cmd="$(get_compose_cmd)"
    local keep_data=true

    if [ -t 0 ] && [ -z "${1:-}" ] && [ -n "$GUM_BIN" ]; then
        render_screen_top 20
        local pad left_pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 214 \
            --padding "1 2" \
            --width 68 \
            "Uninstall Altr Stream" "" \
            "Installed Version: v${ALTR_VERSION}" \
            "Location:          ${target_dir}"

        local data_choice
        data_choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What should happen to your application data?" \
            "Keep application data (Recommended - preserves database, models, data sources)" \
            "Delete application data permanently (Destroys named volume altr_stream_data)" \
            "Cancel")"

        case "$data_choice" in
            "Keep application data"*)
                keep_data=true
                ;;
            "Delete application data"*)
                keep_data=false
                ;;
            *)
                return 0
                ;;
        esac
    else
        local piped_choice=""
        read -r piped_choice || true
        if [ "$piped_choice" = "2" ]; then
            keep_data=false
        fi
    fi

    local delete_confirmed=false
    if [ "$keep_data" = false ]; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            render_screen_top 22
            local pad left_pad
            pad="$(get_layout_padding 68 22)"
            left_pad="${pad%% *}"

            "$GUM_BIN" style \
                --margin "0 0 0 $left_pad" \
                --border double \
                --border-foreground 196 \
                --padding "1 2" \
                --width 68 \
                --bold \
                "⚠ DESTRUCTIVE DATA DELETION" "" \
                "All application state, connections, and volume 'altr_stream_data' will be ERASED." \
                "This action cannot be undone." "" \
                "To confirm permanent destruction, type:" \
                "DELETE ALTR STREAM DATA"

            local conf_str
            conf_str="$(gum_input --placeholder "Type confirmation here" --prompt "Confirmation: " --width 50)"
            if [ "$conf_str" = "DELETE ALTR STREAM DATA" ]; then
                delete_confirmed=true
            else
                "$GUM_BIN" style --foreground 214 "Confirmation text did not match. Application data will be preserved."
                delete_confirmed=false
            fi
        else
            echo "To confirm destructive deletion, type: DELETE ALTR STREAM DATA"
            read -r conf_str || true
            if [ "$conf_str" = "DELETE ALTR STREAM DATA" ]; then
                delete_confirmed=true
            else
                echo "Confirmation text did not match. Application data will be preserved."
                delete_confirmed=false
            fi
        fi
    fi

    if [ -n "$compose_cmd" ]; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            "$GUM_BIN" spin --spinner dot --title "Stopping container and removing deployment..." -- \
                $compose_cmd -f "$target_dir/docker-compose.yml" down 2>/dev/null || true
        else
            $compose_cmd -f "$target_dir/docker-compose.yml" down 2>/dev/null || true
        fi
    fi

    rm -f "$target_dir/docker-compose.yml"
    rm -f "$target_dir/.env"
    rm -rf "$target_dir/data/updates"

    if [ "$delete_confirmed" = true ]; then
        docker volume rm -f altr_stream_data 2>/dev/null || true
    fi

    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        render_screen_top 20
        local pad left_pad
        pad="$(get_layout_padding 68 20)"
        left_pad="${pad%% *}"

        local vol_stat="PRESERVED"
        [ "$delete_confirmed" = true ] && vol_stat="DELETED"
        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 48 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✓ UNINSTALLED" "" \
            "Altr Stream deployment files removed." \
            "Named Volume 'altr_stream_data': ${vol_stat}"
        gum_confirm "Press Enter to return..." || true
    else
        echo "Uninstall complete. Volume: $([ "$delete_confirmed" = true ] && echo "DELETED" || echo "PRESERVED")"
    fi
}

# ------------------------------------------------------------------------------
# Workflow 3: Repair
# ------------------------------------------------------------------------------
workflow_repair() {
    local target_dir="${1:-}"
    if [ -z "$target_dir" ]; then
        target_dir="$(get_install_dir)"
    fi
    local compose_cmd
    compose_cmd="$(get_compose_cmd)"
    local web_url
    web_url="$(get_web_url "$target_dir")"

    local has_dir=false
    local has_compose=false
    local daemon_ok=false
    local container_ok=false
    local health_ok=false

    [ -d "$target_dir" ] && has_dir=true
    [ -f "$target_dir/docker-compose.yml" ] && has_compose=true
    check_docker && daemon_ok=true

    if command -v docker >/dev/null 2>&1 && docker inspect altr-stream >/dev/null 2>&1; then
        local inspect_status
        inspect_status="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
        if [ "$inspect_status" = "running" ]; then
            container_ok=true
        fi
    fi
    if curl -sf "${web_url}/api/v1/health" >/dev/null 2>&1 || curl -sf "${web_url}/api/health" >/dev/null 2>&1; then
        health_ok=true
    fi

    if [ -t 0 ] && [ -z "${1:-}" ] && [ -n "$GUM_BIN" ]; then
        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 39 \
            --padding "1 2" \
            --width 68 \
            "Repair Altr Stream" "" \
            "Diagnostic Checks:" \
            "$([ "$has_dir" = true ] && echo "  ✓ Directory exists" || echo "  ✗ Directory missing")" \
            "$([ "$has_compose" = true ] && echo "  ✓ docker-compose.yml present" || echo "  ✗ docker-compose.yml missing")" \
            "$([ "$daemon_ok" = true ] && echo "  ✓ Docker engine responsive" || echo "  ✗ Docker daemon unreachable")" \
            "$([ "$container_ok" = true ] && echo "  ✓ Container active" || echo "  ⚠ Container stopped or missing")" \
            "$([ "$health_ok" = true ] && echo "  ✓ Healthcheck responding" || echo "  ✗ Healthcheck offline")" "" \
            "Recommended Action:" \
            "Repair will restore configuration files, inspect the container," \
            "and safely recreate or recover it. Persistent data is preserved."

        if ! gum_confirm "Proceed with Repair?"; then
            return 0
        fi
    fi

    local failed_stage=""
    local failed_reason=""
    local failed_technical=""
    local docker_repair_log="$target_dir/.docker_start.log"
    rm -f "$docker_repair_log" 2>/dev/null || true

    # Stage 1: Restore configuration & runtime files
    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        "$GUM_BIN" spin --spinner dot --title "Restoring configuration files..." -- sleep 0.4
    fi
    if ! write_runtime_files "$target_dir"; then
        failed_stage="Restoring configuration files"
        failed_reason="Failed to write runtime files into $target_dir"
    fi
    docker volume create altr_stream_data >/dev/null 2>&1 || true
    save_install_dir "$target_dir"

    # Stage 2: Inspect existing "altr-stream" container lifecycle
    local existing_exists=false
    local existing_status=""
    local existing_image=""
    local existing_mounts=""
    local existing_compatible=false
    local existing_healthy=false
    local existing_has_volume=false
    local needs_replacement=true

    if [ -z "$failed_stage" ] && command -v docker >/dev/null 2>&1; then
        if docker inspect altr-stream >/dev/null 2>&1; then
            existing_exists=true
            existing_status="$(docker inspect -f '{{.State.Status}}' altr-stream 2>/dev/null || true)"
            existing_image="$(docker inspect -f '{{.Config.Image}}' altr-stream 2>/dev/null || true)"
            existing_mounts="$(docker inspect -f '{{range .Mounts}}{{.Name}} {{end}}' altr-stream 2>/dev/null || true)"

            if echo "$existing_image" | grep -qi "altr-stream"; then
                existing_compatible=true
            fi
            if echo "$existing_mounts" | grep -q "altr_stream_data"; then
                existing_has_volume=true
            fi
            if [ "$existing_status" = "running" ] && (curl -sf "$web_url/api/v1/health" >/dev/null 2>&1 || curl -sf "$web_url/api/health" >/dev/null 2>&1); then
                existing_healthy=true
            fi

            # Requirement 5:
            # If the container is already running and healthy and the configuration is valid,
            # Repair should be allowed to treat that state as recoverable rather than reporting a false failure.
            if [ "$existing_compatible" = true ] && [ "$existing_healthy" = true ] && [ "$existing_has_volume" = true ]; then
                needs_replacement=false
            fi
        fi
    fi

    # Stage 3: Replacement / Recreate if needed
    if [ -z "$failed_stage" ] && [ "$needs_replacement" = true ] && [ -n "$compose_cmd" ]; then
        # Pull pinned image
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            "$GUM_BIN" spin --spinner dot --title "Pulling container image (${ALTR_IMAGE})..." -- \
                $compose_cmd -f "$target_dir/docker-compose.yml" pull || true
        else
            $compose_cmd -f "$target_dir/docker-compose.yml" pull 2>/dev/null || true
        fi

        # Requirement 4:
        # If replacement is required:
        # - stop/remove ONLY the existing "altr-stream" container
        # - recreate the canonical "altr-stream" container
        # - preserve "altr_stream_data"
        # - never run docker prune
        # - never remove unrelated containers, images, networks, or volumes.
        if [ "$existing_exists" = true ]; then
            if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
                "$GUM_BIN" spin --spinner dot --title "Preparing canonical container altr-stream..." -- bash -c "
                    docker stop altr-stream >/dev/null 2>&1 || true
                    docker rm altr-stream >/dev/null 2>&1 || true
                "
            else
                docker stop altr-stream >/dev/null 2>&1 || true
                docker rm altr-stream >/dev/null 2>&1 || true
            fi
        fi

        local recreate_failed=false
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            "$GUM_BIN" spin --spinner dot --title "Recreating container..." -- bash -c "
                $compose_cmd -f \"$target_dir/docker-compose.yml\" up -d >\"$docker_repair_log\" 2>&1
            " || recreate_failed=true
        else
            if ! $compose_cmd -f "$target_dir/docker-compose.yml" up -d >"$docker_repair_log" 2>&1; then
                recreate_failed=true
            fi
        fi

        if [ "$recreate_failed" = true ]; then
            failed_stage="Recreating container"
            failed_reason="Docker failed to recreate the Altr Stream container"
            if [ -f "$docker_repair_log" ]; then
                failed_technical="$(tail -n 5 "$docker_repair_log" | tr '\n' ' ' | sed 's/  */ /g')"
            fi
        fi
    fi

    # Stage 4: Health Verification
    if [ -z "$failed_stage" ]; then
        local attempts=0
        local healthy=false
        local timeout_limit="${HEALTH_TIMEOUT:-25}"
        while [ $attempts -lt $timeout_limit ]; do
            attempts=$((attempts + 1))
            if curl -sf "$web_url/api/v1/health" >/dev/null 2>&1 || curl -sf "$web_url/api/health" >/dev/null 2>&1; then
                healthy=true
                break
            fi
            sleep 1
        done

        if [ "$healthy" != true ]; then
            failed_stage="Waiting for Altr Stream health check"
            failed_reason="Health check timed out after waiting for ${web_url}/api/v1/health"
        fi
    fi

    # Stage 5: Strict Verification
    if [ -z "$failed_stage" ] && verify_installation "$target_dir"; then
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            show_repair_success_screen "$target_dir"
            return 0
        else
            echo "Altr Stream repair completed successfully and verified at ${web_url}"
            return 0
        fi
    else
        if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
            show_repair_failure_screen "$target_dir" "${failed_stage:-Health Verification}" "${failed_reason:-Altr Stream failed health verification after repair}" "${failed_technical}"
            return 0
        else
            echo "ERROR: Repair failed at stage: ${failed_stage:-Health Verification}"
            echo "Reason: ${failed_reason:-Altr Stream failed health verification after repair}"
            if [ -n "$failed_technical" ]; then
                echo "Technical Details: $failed_technical"
            fi
            echo "Inspect container logs: cd \"$target_dir\" && $compose_cmd logs altr-stream"
            exit 1
        fi
    fi
}

show_repair_success_screen() {
    local target_dir="$1"
    local web_url
    web_url="$(get_web_url "$target_dir")"

    while true; do
        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border double \
            --border-foreground 48 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✓ REPAIR COMPLETE" "" \
            "ALTR STREAM" "v${ALTR_VERSION}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 240 \
            --padding "0 2" \
            --width 68 \
            "Repair Summary:" "" \
            "  ✓ Configuration restored" \
            "  ✓ Persistent data preserved" \
            "  ✓ Container active" \
            "  ✓ Container running" \
            "  ✓ Container healthy" \
            "  ✓ Version verified" \
            "  ✓ Web Interface: ${web_url}"

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Launch Altr Stream" \
            "Open Web Interface" \
            "Installation Status" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Launch Altr Stream"|"Open Web Interface")
                launch_browser "$web_url"
                show_running_screen "$target_dir" "$web_url"
                return 0
                ;;
            "Installation Status")
                workflow_status "$target_dir"
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

show_repair_failure_screen() {
    local target_dir="$1"
    local stage="$2"
    local reason="$3"
    local technical="${4:-}"
    local compose_cmd
    compose_cmd="$(get_compose_cmd)"

    while true; do
        render_screen_top 26
        local pad left_pad
        pad="$(get_layout_padding 68 26)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 196 \
            --padding "1 2" \
            --width 68 \
            --align center \
            --bold \
            "✕ REPAIR FAILED"

        local docker_stat altr_stat
        docker_stat="$(get_docker_status_text)"
        altr_stat="$(get_altr_status_text "$target_dir")"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 240 \
            --padding "0 2" \
            --width 68 \
            "Repair failed during:" \
            "  ${stage:-Repair Verification}" "" \
            "Reason:" \
            "  ${reason:-Container failed health checks after repair}" \
            $([ -n "$technical" ] && echo "" && echo "Technical Details:" && echo "  ${technical}") "" \
            "Current State:" \
            "  Docker Engine: ${docker_stat}" \
            "  Container:     ${altr_stat}" \
            "  Path:          ${target_dir}"

        local choice
        choice="$(gum_choose \
            --cursor="❯ " \
            --cursor.foreground="48" \
            --header="What would you like to do?" \
            "Retry Repair" \
            "View Installation Status" \
            "View Container Logs" \
            "Back to Main Menu" \
            "Exit" || echo "Exit")"

        case "$choice" in
            "Retry Repair")
                workflow_repair "$target_dir"
                return 0
                ;;
            "View Installation Status")
                workflow_status "$target_dir"
                ;;
            "View Container Logs")
                local has_container=false
                if [ -n "$compose_cmd" ] && [ -f "$target_dir/docker-compose.yml" ]; then
                    local cid_proj
                    cid_proj="$($compose_cmd -f "$target_dir/docker-compose.yml" ps -q altr-stream 2>/dev/null || true)"
                    if [ -n "$cid_proj" ]; then
                        has_container=true
                    fi
                fi

                if [ "$has_container" = false ] || [ "$stage" = "Recreating container" ]; then
                    render_screen_top 22
                    local lpad
                    lpad="$(get_layout_padding 68 22)"
                    lpad="${lpad%% *}"

                    "$GUM_BIN" style \
                        --margin "0 0 0 $lpad" \
                        --border rounded \
                        --border-foreground 214 \
                        --padding "1 2" \
                        --width 68 \
                        --align center \
                        --bold \
                        "CONTAINER LOGS"

                    "$GUM_BIN" style \
                        --margin "0 0 0 $lpad" \
                        --border rounded \
                        --border-foreground 240 \
                        --padding "0 2" \
                        --width 68 \
                        "No logs are available for the recreated container because Docker" \
                        "encountered an error during container creation/startup." "" \
                        "Docker reported:" \
                        "  ${technical:-${reason}}"

                    local log_action
                    log_action="$(gum_choose \
                        --cursor="❯ " \
                        --cursor.foreground="48" \
                        --header="Actions:" \
                        "Back to Repair Menu" \
                        "Back to Main Menu" \
                        "Exit" || echo "Back to Repair Menu")"
                    case "$log_action" in
                        "Back to Main Menu") return 0 ;;
                        "Exit") exit 0 ;;
                        *) ;;
                    esac
                else
                    clear 2>/dev/null || true
                    "$GUM_BIN" style \
                        --border rounded \
                        --border-foreground 39 \
                        --padding "0 2" \
                        --width 68 \
                        "Altr Stream Container Logs (tail 50 lines):"
                    echo ""
                    $compose_cmd -f "$target_dir/docker-compose.yml" logs --tail 50 altr-stream 2>&1 | "$GUM_BIN" pager || true
                fi
                ;;
            "Back to Main Menu")
                return 0
                ;;
            "Exit"|*)
                clear 2>/dev/null || true
                "$GUM_BIN" style --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Workflow 4: Status
# ------------------------------------------------------------------------------
workflow_status() {
    local target_dir="${1:-}"
    if [ -z "$target_dir" ]; then
        target_dir="$(get_install_dir)"
    fi
    local compose_cmd
    compose_cmd="$(get_compose_cmd)"

    local docker_stat altr_stat
    docker_stat="$(get_docker_status_text)"
    altr_stat="$(get_altr_status_text "$target_dir")"

    local port web_url
    port="$(get_web_port "$target_dir")"
    web_url="$(get_web_url "$target_dir")"

    if [ -n "$GUM_BIN" ] && [ -t 0 ]; then
        render_screen_top 24
        local pad left_pad
        pad="$(get_layout_padding 68 24)"
        left_pad="${pad%% *}"

        "$GUM_BIN" style \
            --margin "0 0 0 $left_pad" \
            --border rounded \
            --border-foreground 39 \
            --padding "1 2" \
            --width 68 \
            "Altr Stream Installation Status" "" \
            "Installation:" \
            "  Configured Version: v${ALTR_VERSION}" \
            "  Target Directory:   ${target_dir}" \
            "  Canonical Image:    ${ALTR_IMAGE}" "" \
            "Runtime & Container:" \
            "  Docker Engine:      ${docker_stat}" \
            "  Altr Container:     ${altr_stat}" \
            "  Web Port:           ${port}" \
            "  Web Interface:      ${web_url}" \
            "  Named Volume:       altr_stream_data" "" \
            "Update Lifecycle:" \
            "  Host Supervisor:    Authoritative Host Supervisor"
        gum_choose --cursor="❯ " --header="" "Return" || true
    else
        echo "Altr Stream Installation Status: Configured Version v${ALTR_VERSION} at ${target_dir}"
    fi
}

# ------------------------------------------------------------------------------
# Entrypoint & CLI Fallback Dispatch
# ------------------------------------------------------------------------------
main() {
    local cmd="${1:-}"
    local target="${2:-}"

    # CLI subcommands bypass Gum completely
    case "$cmd" in
        install) workflow_install "$target"; return ;;
        uninstall) workflow_uninstall "$target"; return ;;
        repair) workflow_repair "$target"; return ;;
        status) workflow_status "$target"; return ;;
    esac

    # If first arg looks like a directory path
    if [ -n "$cmd" ] && ([ -d "$cmd" ] || [ "${cmd:0:1}" = "/" ] || [ "${cmd:0:2}" = "~/" ] || [ "${cmd:0:2}" = "./" ]); then
        workflow_install "$cmd"
        return
    fi

    # Headless / piped execution without subcommand defaults to install
    if [ ! -t 0 ]; then
        workflow_install "$target"
        return
    fi

    # Interactive Human Mode: Resolve Gum TUI
    if resolve_gum; then
        show_main_menu
    else
        echo "Notice: Interactive UI component (Gum) not found or could not be loaded."
        echo "Running standard setup..."
        workflow_install "$target"
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "${1:-}" "${2:-}"
fi
