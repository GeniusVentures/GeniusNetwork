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

## Maintenance

- Edit the canonical skills in this directory.
- Do not maintain independent copies in submodules. Check for existing repository-local copies of the same skills when migrating, and remove them through an approved repository change once they are no longer needed.
- Preserve each repository's own `CLAUDE.md`, architecture documentation, and GSD planning files.
- Invoke skills by name in GSD workflows rather than requiring repository-local copies.
