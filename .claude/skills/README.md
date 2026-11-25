# Shared Claude Code skills

GeniusNetwork is the source of truth for shared engineering skills. Install them in your personal Claude Code skills directory so they are available in GeniusNetwork, every nested submodule, and standalone repositories.

## Available skills

- [architecture-review](architecture-review/SKILL.md): Review GSD plans, architecture and implementation changes before approval.
- [gnus-standup](gnus-standup/SKILL.md): Generate daily engineering standups with human and AI contributions, hours, delivery and verification.

## Install or update

Run these commands from the GeniusNetwork repository root. Back up any existing personal versions of the skills before overwriting them. If an existing destination is a symbolic link or junction, resolve that first to avoid overwriting files in another repository.

### macOS and Linux

```bash
mkdir -p "$HOME/.claude/skills"
cp -R .claude/skills/architecture-review .claude/skills/gnus-standup "$HOME/.claude/skills/"
```

### Windows (PowerShell)

```powershell
$destination = "$HOME\.claude\skills"
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -Path ".claude\skills\architecture-review", ".claude\skills\gnus-standup" -Destination $destination -Recurse -Force
```

If you use a custom `CLAUDE_CONFIG_DIR`, substitute that directory for `$HOME/.claude`.

The installed skills are available as `/architecture-review` and `/gnus-standup` in Claude Code. Start a new session if the skills do not appear in an existing session. The standup skill runs only when explicitly invoked.

After pulling updates to GeniusNetwork, repeat the copy commands. These are local copies, not live links.

## Install shared instructions without replacing personal preferences

GeniusNetwork's root `CLAUDE.md` imports the shared [architecture quality gate](../architecture-quality-gate.md). Install that file globally and append a small GNUS Shared Skills section to your existing personal instructions. Never replace your personal CLAUDE.md with the repository's CLAUDE.md.

From the GeniusNetwork root, after installing the skills, run the commands below. They create a personal CLAUDE.md if needed, preserve its existing content, and skip the append if the shared section already exists. If the architecture gate import was installed previously, they do not duplicate it.

### macOS and Linux

```bash
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$config_dir"
cp .claude/architecture-quality-gate.md "$config_dir/"
claude_file="$config_dir/CLAUDE.md"
touch "$claude_file"

if ! grep -Eq '^## GNUS Shared Skills[[:space:]]*$' "$claude_file"; then
    {
        printf '\n\n## GNUS Shared Skills\n\n'
        if ! grep -Eq '^@architecture-quality-gate\.md[[:space:]]*$' "$claude_file"; then
            printf '@architecture-quality-gate.md\n\n'
        fi
        printf '%s\n' '- Use `/gnus-standup` only when explicitly requested to generate the daily engineering standup.'
    } >> "$claude_file"
fi
```

### Windows (PowerShell)

```powershell
$configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
Copy-Item ".claude\architecture-quality-gate.md" -Destination $configDir -Force
$claudeFile = Join-Path $configDir "CLAUDE.md"
$existing = if (Test-Path -LiteralPath $claudeFile) { Get-Content -LiteralPath $claudeFile } else { @() }

if ($existing -notcontains "## GNUS Shared Skills") {
    $lines = @("", "", "## GNUS Shared Skills", "")
    if ($existing -notcontains "@architecture-quality-gate.md") {
        $lines += @("@architecture-quality-gate.md", "")
    }
    $lines += '- Use `/gnus-standup` only when explicitly requested to generate the daily engineering standup.'
    Add-Content -LiteralPath $claudeFile -Value $lines -Encoding UTF8
}
```

These commands append instructions only to your personal CLAUDE.md. They do not change the GSD-generated profile, personal preferences, coding standards, or other existing rules. If you already have a custom GNUS Shared Skills section, review it manually rather than replacing it. The architecture gate import must be outside any fenced code block.

Repeat the copy commands after pulling updates; the append step is safe to run again. Start a new Claude Code session and check `/memory` to confirm the instructions loaded. The gate applies to GeniusVentures, GNUS.ai, and related GSD projects. It requires review before phase execution and does not replace repository-specific architecture or coding standards.

## Maintenance

- Edit the canonical skills in this directory.
- Do not maintain independent copies in submodules. Check for existing repository-local copies of the same skills when migrating, and remove them through an approved repository change once they are no longer needed.
- Preserve each repository's own `CLAUDE.md`, architecture documentation, and GSD planning files.
- Invoke skills by name in GSD workflows rather than requiring repository-local copies.
