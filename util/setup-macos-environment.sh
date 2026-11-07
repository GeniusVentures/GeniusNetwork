#!/usr/bin/env bash
# setup-macos-environment.sh
#
# macOS equivalent of setup-windows-environment.ps1 - provisions a CI runner
# (or dev box) with the toolchain the GeniusNetwork builds expect.
#
# Run as your regular ADMIN user (NOT root - Homebrew refuses to run as root
# and invokes sudo itself when a cask needs /Library access):
#
#   bash util/setup-macos-environment.sh
#
# Differences from the Windows script, by design:
#   - No Visual Studio: Xcode provides clang. Full Xcode must already be
#     installed manually (the App Store install cannot be scripted headlessly).
#   - No Docker: macOS runners do not get Docker (runner policy).
#   - rust/cargo come from the OFFICIAL rustup installer, not Homebrew
#     (Homebrew's rust is a non-rustup-managed build; rustup is what the
#     rest of the fleet standardizes on).

set -euo pipefail

# Pick the Python minor version you want (Homebrew formula name).
PYTHON_FORMULA="python@3.13"

# --------------------------------------------------------------------------
# Output helpers (same tone as the PowerShell original)
# --------------------------------------------------------------------------

log()  { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------

# Inverse of the Windows script's Require-Admin: brew must NOT run as root.
if [ "$(id -u)" -eq 0 ]; then
    die "Run this script as your regular admin user, NOT root/sudo (Homebrew refuses root)."
fi

log "==> Checking Xcode command line tools"
if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode Command Line Tools not found. Run 'xcode-select --install', then rerun this script."
fi
DEVELOPER_DIR="$(xcode-select -p)"
ok "Developer dir: $DEVELOPER_DIR"

# Flutter iOS/macOS app builds need FULL Xcode (signing, xcodebuild); the CLT
# alone is enough for clang-only work. Machines with only CLT are flagged
# instead of rejected - a node-only runner does not need the full IDE.
case "$DEVELOPER_DIR" in
    *CommandLineTools*)
        warn "Only Command Line Tools are active ($DEVELOPER_DIR)."
        warn "iOS/macOS GeniusWallet builds require full Xcode + 'sudo xcodebuild -license accept'."
        ;;
    *) ;;
esac

# --------------------------------------------------------------------------
# Homebrew
# --------------------------------------------------------------------------

ensure_homebrew() {
    if have brew; then
        ok "Homebrew already installed"
        # Converge to latest, like any rerun of this script should.
        brew update
        return 0
    fi

    log "Installing Homebrew (official installer)"
    # NONINTERACTIVE=1: no prompts (the installer normally pauses for sudo).
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Expose brew to THIS session: Apple Silicon (/opt/homebrew) or Intel (/usr/local).
    if [ -x /opt/homebrew/bin/brew ]; then
        # shellcheck disable=SC2046
        eval $(/opt/homebrew/bin/brew shellenv)
    elif [ -x /usr/local/bin/brew ]; then
        # shellcheck disable=SC2046
        eval $(/usr/local/bin/brew shellenv)
    else
        die "Homebrew installed but the executable was not found in the usual prefixes."
    fi
}

ensure_homebrew

# --------------------------------------------------------------------------
# Packages
# --------------------------------------------------------------------------

log "==> Installing Homebrew packages"
# python/perl/ruby/cmake/jq/git/gh  -> direct analogs of the winget list.
# ninja, bash, gnu-tar               -> pre-provision what the GeniusWallet CI
#                                       'Configure macOS host' step installs,
#                                       so that step converges to a no-op.
# cocoapods                         -> required by the Flutter iOS build.
brew install \
    "$PYTHON_FORMULA" \
    perl \
    ruby \
    cmake \
    jq \
    git \
    gh \
    ninja \
    bash \
    gnu-tar \
    cocoapods

# --------------------------------------------------------------------------
# JDK (Temurin 17) + JAVA_HOME
# --------------------------------------------------------------------------

# The jni plugin's CMake FindJNI needs the JNI headers, and Gradle / Android
# Gradle Plugin 8+ need JDK 17 or newer. Any JDK 17+ satisfies CI, so an
# existing usable install (e.g. a manual Temurin 21/25 LTS) is kept as-is
# instead of gaining a second side-by-side JDK - same policy as the Windows
# script's Get-AdoptiumJdkHome.
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

    # 2) The macOS JVM registry (/Library/Java/JavaVirtualMachines - where the
    #    Temurin cask and manual installs live). Prefer Temurin 17 explicitly,
    #    then any other JVM that passes the usability check.
    local vm
    for vm in \
        /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
        /Library/Java/JavaVirtualMachines/*.jdk/Contents/Home; do
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
        log "Installing Temurin 17 JDK (Homebrew cask - brew will sudo for /Library access)"
        brew install --cask temurin@17
        jdk_home="$(find_jdk_home || true)"
        [ -n "$jdk_home" ] || die "Could not locate the Temurin JDK home after install (expected /Library/Java/JavaVirtualMachines/temurin-17.jdk)."
    fi

    JAVA_HOME="$jdk_home"
    export JAVA_HOME
    ok "JAVA_HOME=$JAVA_HOME"

    # launchd scope: applies to processes launchd starts from now on (until
    # reboot) - covers a runner service restarted later in this script. The
    # durable, reboot-surviving copy goes into the runner's .env file below.
    if launchctl setenv JAVA_HOME "$JAVA_HOME" 2>/dev/null; then
        ok "launchctl setenv JAVA_HOME applied (launchd session)"
    else
        warn "launchctl setenv failed (no GUI session?) - relying on the runner .env file instead."
    fi
}

ensure_jdk

# --------------------------------------------------------------------------
# rustup (OFFICIAL installer - deliberately NOT from Homebrew)
# --------------------------------------------------------------------------

ensure_rustup() {
    if [ -x "$HOME/.cargo/bin/rustup" ]; then
        ok "rustup already installed for $USER - keeping it"
        return 0
    fi

    log "Installing rustup (official https://sh.rustup.rs installer)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain stable

    ok "rustup installed to $HOME/.cargo"
}

ensure_rustup

# rustup appends its PATH line to shell profiles; expose it to this session
# so the diagnostics below resolve the freshly installed tools.
# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
hash -r

# --------------------------------------------------------------------------
# GitHub Actions runner: env + PATH + restart
# --------------------------------------------------------------------------

# Same contract as the Windows script's Restart-ActionsRunnerService: the
# runner only reads environment changes when it starts, so we (a) persist
# JAVA_HOME and ~/.cargo/bin through the runner's own .env/.path files and
# (b) restart the launchd service.
#
# .env / .path are the runner's official per-runner config files:
#   .env  -> KEY=VALUE environment variables for every job
#   .path -> one directory per line, prepended to every job's PATH

upsert_runner_env() { # <file> <KEY> <value>
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    { [ -f "$file" ] && grep -v "^${key}=" "$file" || true; } > "$tmp"
    echo "${key}=${value}" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

add_runner_path() { # <file> <dir>
    local file="$1" dir="$2"
    if [ -f "$file" ] && grep -qxF "$dir" "$file"; then
        return 0
    fi
    # Ensure the existing content ends with a newline before appending.
    if [ -s "$file" ] && [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
        echo >> "$file"
    fi
    echo "$dir" >> "$file"
}

configure_actions_runner() {
    log "==> Configuring GitHub Actions runner (if present)"
    local found=0 plist label prog scope dir

    shopt -s nullglob
    for plist in \
        "$HOME/Library/LaunchAgents"/*.plist \
        /Library/LaunchAgents/*.plist \
        /Library/LaunchDaemons/*.plist; do
        # GitHub runner plists point at <runner-dir>/bin/runsvc.sh.
        grep -Eq 'runsvc\.sh|actions-runner' "$plist" 2>/dev/null || continue
        found=1

        label="$(plutil -extract Label raw -o - "$plist" 2>/dev/null || true)"
        prog="$(plutil -convert json -o - "$plist" 2>/dev/null \
            | jq -r '.ProgramArguments[0] // empty' 2>/dev/null || true)"

        dir=""
        case "$prog" in
            */bin/runsvc.sh) dir="$(cd "$(dirname "$prog")/.." && pwd)" ;;
        esac

        if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
            upsert_runner_env "$dir/.env" "JAVA_HOME" "$JAVA_HOME"
            add_runner_path "$dir/.path" "$HOME/.cargo/bin"
            ok "Runner env configured: $dir/.env + .path"
        else
            warn "Found runner plist $plist but could not resolve a writable runner dir - env files skipped."
        fi

        # kickstart -k = kill + restart the service in place.
        case "$plist" in
            /Library/LaunchDaemons/*) scope="system" ;;
            *) scope="gui/$(id -u)" ;;
        esac
        if [ -n "$label" ] && launchctl kickstart -k "$scope/$label" 2>/dev/null; then
            ok "Restarted runner service '$label'"
        else
            warn "Could not restart runner service '$label' - restart it manually so CI sees the new env."
        fi
    done
    shopt -u nullglob

    if [ "$found" -eq 0 ]; then
        warn "No GitHub Actions runner service found - skipping."
    fi
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

for cmd in cmake perl ruby python3 rustup cargo jq git gh pod java; do
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
printf '  pod --version\n'
printf '  java -version\n'
printf '  echo $JAVA_HOME\n'
printf '  xcodebuild -version   (full Xcode needed for iOS/macOS wallet builds)\n'
