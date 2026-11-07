#!/usr/bin/env bash
# setup-ubuntu-environment.sh
#
# Ubuntu equivalent of setup-windows-environment.ps1 - provisions a CI runner
# (or dev box) with the toolchain the GeniusNetwork builds expect.
#
# Run with sudo (or as root):
#
#   sudo bash util/setup-ubuntu-environment.sh
#
# Options:
#   --no-docker   skip the Docker Engine install
#
# On Windows, Docker lives in a separate script (setup-windows-docker.ps1)
# because Docker Desktop is a heavyweight GUI product. On Ubuntu, Docker
# Engine is just apt packages from the official repo, so it is folded in
# here; use --no-docker if a machine must stay Docker-free.
#
# Differences from the Windows script, by design:
#   - No Visual Studio: clang/GCC come from apt (CI pins cc/c++ to clang).
#   - No Chocolatey: apt (plus the official GitHub CLI / Adoptium / Docker
#     repos) covers everything choco did on Windows.
#   - rust/cargo come from the OFFICIAL rustup installer, never from apt
#     (apt's rustc is years stale and not rustup-managed).

set -euo pipefail

# --------------------------------------------------------------------------
# Output helpers (same tone as the PowerShell original)
# --------------------------------------------------------------------------

log()  { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

NO_DOCKER=0
for arg in "$@"; do
    case "$arg" in
        --no-docker) NO_DOCKER=1 ;;
        *) die "Unknown option: $arg (supported: --no-docker)" ;;
    esac
done

# --------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------

# Root-or-sudo requirement (the analog of the Windows script's Require-Admin).
SUDO=""
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif have sudo; then
    SUDO="sudo"
else
    die "Please run this script as root or with sudo."
fi

. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    die "This script targets Ubuntu (apt-based). Detected: ${ID:-unknown} ${VERSION_ID:-}"
fi
log "Ubuntu $VERSION_CODENAME (${VERSION_ID})"

# The user the CI runner (and rustup/docker group) belong to. When invoked
# through sudo this is the calling user; running as root without sudo means
# there is no real target user and per-user tool installs must abort.
TARGET_USER="${SUDO_USER:-$USER}"

# --------------------------------------------------------------------------
# Base apt packages
# --------------------------------------------------------------------------

log "==> apt update + install base tools"
$SUDO apt-get update -y
$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

log "==> Installing apt packages"
# build-essential/clang/ninja -> compilers + generators; the wallet CI pins
#   cc/c++ to clang on Linux, so clang must exist on the runner.
# perl/ruby/python3          -> direct analogs of the winget list. Versions
#   are the distro defaults; pin a specific Python minor via deadsnakes PPA
#   only if a job starts requiring it (Windows pins 3.13, Ubuntu ships 3.12
#   on noble - both satisfy the build scripts).
# python3-pip/venv           -> util/ scripts and job helpers install wheels.
$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    clang \
    ninja-build \
    cmake \
    git \
    jq \
    perl \
    ruby-full \
    python3 \
    python3-pip \
    python3-venv \
    pkg-config

# --------------------------------------------------------------------------
# GitHub CLI (official apt repo - the analog of winget GitHub.cli)
# --------------------------------------------------------------------------

ensure_gh_cli() {
    if have gh; then
        ok "gh already installed ($(gh --version | head -n1)) - keeping it"
        return 0
    fi

    log "Installing GitHub CLI (official apt repo)"
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null

    $SUDO apt-get update -y
    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

ensure_gh_cli

# --------------------------------------------------------------------------
# JDK (Temurin 17) + JAVA_HOME
# --------------------------------------------------------------------------

# The jni plugin's CMake FindJNI needs the JNI headers, and Gradle / Android
# Gradle Plugin 8+ need JDK 17 or newer. Any JDK 17+ satisfies CI, so an
# existing usable install (e.g. distro openjdk-21 or a manual Temurin) is
# kept as-is instead of gaining a second side-by-side JDK - same policy as
# the Windows script's Get-AdoptiumJdkHome.
jdk_usable() {
    local jh="${1:-}"
    [ -n "$jh" ] || return 1
    [ -f "$jh/include/jni.h" ] || return 1

    if [ -f "$jh/release" ]; then
        local major
        major="$(sed -n 's/^JAVA_VERSION="\([0-9][0-9]*\).*/\1/p' "$jh/release" | head -n1)"
        if [ -n "$major" ] && [ "$major" -lt 17 ]; then
            return 1
        fi
    fi
    return 0
}

find_jdk_home() {
    # 1) Existing JAVA_HOME that still points at a usable JDK
    if jdk_usable "${JAVA_HOME:-}"; then
        printf '%s\n' "$JAVA_HOME"
        return 0
    fi

    # 2) Debian-style JVM roots, newest-satisfying first: Temurin 17 (what
    #    this script installs), distro OpenJDK 17, then any 17+ candidate.
    local vm
    for vm in \
        /usr/lib/jvm/temurin-17-jdk-* \
        /usr/lib/jvm/java-17-openjdk-* \
        /usr/lib/jvm/*; do
        if jdk_usable "$vm"; then
            printf '%s\n' "$vm"
            return 0
        fi
    done
    return 1
}

ensure_jdk() {
    local jdk_home
    jdk_home="$(find_jdk_home || true)"

    if [ -n "$jdk_home" ]; then
        ok "JDK already present ($jdk_home) - skipping Temurin install"
    else
        log "Installing Temurin 17 JDK (official Adoptium apt repo)"
        $SUDO install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
            | $SUDO gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
        $SUDO chmod a+r /etc/apt/keyrings/adoptium.gpg

        echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $VERSION_CODENAME main" \
            | $SUDO tee /etc/apt/sources.list.d/adoptium.list >/dev/null

        $SUDO apt-get update -y
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y temurin-17-jdk

        jdk_home="$(find_jdk_home || true)"
        [ -n "$jdk_home" ] || die "Could not locate the Temurin JDK home after install (expected /usr/lib/jvm/temurin-17-jdk-*)."
    fi

    JAVA_HOME="$jdk_home"
    export JAVA_HOME
    ok "JAVA_HOME=$JAVA_HOME"
}

ensure_jdk

# JAVA_HOME machine scope. The Windows script sets Machine-scope env because
# the runner service only inherits machine variables; on Ubuntu the systemd
# manager environment is the equivalent:
#   - /etc/profile.d            -> interactive login shells (humans)
#   - systemctl set-environment -> every unit systemd starts from now on
#                                  (lost at reboot)
#   - system.conf DefaultEnvironment -> persists across reboots
# Plus the runner's own .env file below as a per-runner copy.
ensure_java_home_machine_scope() {
    log "==> Setting machine-wide JAVA_HOME"

    {
        echo '# Managed by util/setup-ubuntu-environment.sh - do not edit by hand'
        echo 'if [ -z "${JAVA_HOME:-}" ]; then'
        echo "    export JAVA_HOME=\"$JAVA_HOME\""
        echo 'fi'
    } | $SUDO tee /etc/profile.d/00-java-home.sh >/dev/null
    ok "/etc/profile.d/00-java-home.sh written"

    if $SUDO systemctl set-environment JAVA_HOME="$JAVA_HOME" 2>/dev/null; then
        ok "systemd manager environment updated (this boot)"
    else
        warn "systemctl set-environment failed - units restarted this boot may miss JAVA_HOME."
    fi

    if ! grep -q '^DefaultEnvironment=.*JAVA_HOME' /etc/systemd/system.conf 2>/dev/null; then
        # Multiple DefaultEnvironment lines merge; only add one that carries JAVA_HOME.
        echo "DefaultEnvironment=JAVA_HOME=\"$JAVA_HOME\"" \
            | $SUDO tee -a /etc/systemd/system.conf >/dev/null
        ok "system.conf DefaultEnvironment updated (persists reboots)"
        # system.conf is only re-read on daemon-reexec (daemon-reload is not enough).
        $SUDO systemctl daemon-reexec 2>/dev/null \
            || warn "daemon-reexec failed - JAVA_HOME becomes machine-wide after the next reboot."
    fi
}

ensure_java_home_machine_scope

# --------------------------------------------------------------------------
# rustup (OFFICIAL installer - deliberately NOT from apt)
# --------------------------------------------------------------------------

ensure_rustup() {
    [ "$TARGET_USER" != "root" ] \
        || die "Refusing to install rustup into /root. Run this script with sudo as your CI user."

    local target_home
    target_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    if [ -x "$target_home/.cargo/bin/rustup" ]; then
        ok "rustup already installed for $TARGET_USER - keeping it"
        return 0
    fi

    log "Installing rustup (official https://sh.rustup.rs installer) for $TARGET_USER"
    # Download as root, execute as the target user so ~/.cargo lands in the
    # CI user's home (rustup refuses to run as root by default).
    local installer="/tmp/rustup-init-$$.sh"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$installer"
    chown "$TARGET_USER" "$installer"
    su - "$TARGET_USER" -c "sh '$installer' -y --profile minimal --default-toolchain stable"
    rm -f "$installer"

    ok "rustup installed to $target_home/.cargo"
}

ensure_rustup

# --------------------------------------------------------------------------
# Docker Engine (official apt repo) - the setup-windows-docker.ps1 analog
# --------------------------------------------------------------------------

install_docker() {
    log "==> Installing Docker Engine (official apt repo)"

    if have docker; then
        ok "Docker already installed ($(docker --version 2>/dev/null || echo present)) - keeping it"
    else
        $SUDO install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
            | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
            | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

        $SUDO apt-get update -y
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin
    fi

    $SUDO systemctl enable --now docker

    # The Ubuntu analog of the Windows docker-users landmine: the invoking
    # user must be in the 'docker' group to talk to the daemon without sudo,
    # and group membership only applies to NEW processes - the runner service
    # must be restarted after this (done below) to pick it up.
    if [ "$TARGET_USER" != "root" ] && ! id -nG "$TARGET_USER" | grep -qw docker; then
        $SUDO usermod -aG docker "$TARGET_USER"
        warn "'$TARGET_USER' added to the docker group - membership applies to NEW sessions only."
    else
        ok "'$TARGET_USER' already in docker group (or running as root)"
    fi
}

if [ "$NO_DOCKER" -eq 1 ]; then
    warn "--no-docker given - skipping Docker Engine install"
else
    install_docker
fi

# --------------------------------------------------------------------------
# GitHub Actions runner: env + PATH + restart
# --------------------------------------------------------------------------

# Same contract as the Windows script's Restart-ActionsRunnerService: the
# runner only reads environment changes when it starts, so we (a) persist
# JAVA_HOME and ~/.cargo/bin through the runner's own .env/.path files and
# (b) restart the systemd unit. svc.sh-created units are named
# actions.runner.<org>-<repo>.<name>.service.
#
# .env / .path are the runner's official per-runner config files:
#   .env  -> KEY=VALUE environment variables for every job
#   .path -> one directory per line, prepended to every job's PATH

upsert_runner_env() { # <file> <KEY> <value>
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    { [ -f "$file" ] && grep -v "^${key}=" "$file" || true; } > "$tmp"
    echo "${key}=${value}" >> "$tmp"
    # cat > preserves the file's ownership when run as root (mktemp is root's).
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

add_runner_path() { # <file> <dir>
    local file="$1" dir="$2"
    if [ -f "$file" ] && grep -qxF "$dir" "$file"; then
        return 0
    fi
    if [ -s "$file" ] && [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
        echo >> "$file"
    fi
    echo "$dir" >> "$file"
}

configure_actions_runner() {
    log "==> Configuring GitHub Actions runner service (if present)"
    local units unit dir wd exe owner cargo_bin
    units="$(systemctl list-unit-files 'actions.runner*' --no-legend --plain 2>/dev/null | awk '{print $1}' || true)"

    if [ -z "$units" ]; then
        warn "No GitHub Actions runner service found - skipping."
        return 0
    fi

    for unit in $units; do
        dir=""
        wd="$(systemctl show "$unit" -p WorkingDirectory --value 2>/dev/null || true)"
        if [ -n "$wd" ] && [ -d "$wd" ]; then
            dir="$wd"
        else
            # Fallback: derive the install dir from ExecStart (<dir>/bin/runsvc.sh).
            exe="$(systemctl show "$unit" -p ExecStart --value 2>/dev/null || true)"
            exe="${exe#*path=}"
            exe="${exe%%;*}"
            exe="${exe//\"/}"
            exe="${exe## }"
            case "$exe" in
                */bin/runsvc.sh) dir="$(dirname "$(dirname "$exe")")" ;;
                */*)             dir="$(dirname "$exe")" ;;
            esac
        fi

        if [ -z "$dir" ] || [ ! -d "$dir" ]; then
            warn "Could not resolve the runner directory for $unit - env files skipped."
            continue
        fi

        # Keep runner-owned files runner-owned even when run as root.
        owner="$(stat -c '%U:%G' "$dir")"
        upsert_runner_env "$dir/.env" "JAVA_HOME" "$JAVA_HOME"
        cargo_bin="$(getent passwd "$(stat -c '%U' "$dir")" | cut -d: -f6)/.cargo/bin"
        [ -d "$cargo_bin" ] && add_runner_path "$dir/.path" "$cargo_bin"
        $SUDO chown "$owner" "$dir/.env" "$dir/.path" 2>/dev/null || true
        ok "Runner env configured: $dir/.env + .path"

        # Restart AFTER the docker group add above so the new process picks
        # up both the env files and the supplementary group.
        if $SUDO systemctl restart "$unit" 2>/dev/null; then
            ok "Restarted '$unit'"
        else
            warn "Could not restart '$unit' - restart it manually so CI sees the new env."
        fi
    done
}

configure_actions_runner

# --------------------------------------------------------------------------
# Diagnostics
# --------------------------------------------------------------------------

show_resolution() {
    local cmd="$1" out
    printf '\n\033[36m==> Resolution for %s\033[0m\n' "$cmd"
    out="$(type -a "$cmd" 2>/dev/null || true)"
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        printf '%s not found in current session.\n' "$cmd"
    fi
}

for cmd in cmake perl ruby python3 rustup cargo jq git gh java docker; do
    [ "$cmd" = "docker" ] && [ "$NO_DOCKER" -eq 1 ] && continue
    show_resolution "$cmd"
done

printf '\n\033[36m==> java -version\033[0m\n'
java -version || true

printf '\n'
ok "Done."
printf '\033[36mRecommended checks:\033[0m\n'
printf '  cmake --version\n'
printf '  rustup --version\n'
printf '  cargo --version\n'
printf '  jq --version\n'
printf '  git --version\n'
printf '  gh --version\n'
printf '  java -version\n'
printf '  echo $JAVA_HOME\n'
if [ "$NO_DOCKER" -eq 0 ]; then
    printf '  docker version\n'
    printf '  docker run hello-world   (as the CI user, verifies docker-group membership)\n'
fi
