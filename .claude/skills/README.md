# Shared Claude Code skills

GeniusNetwork is the source of truth for shared engineering skills. Install them in your personal Claude Code skills directory so they are available in GeniusNetwork, every nested submodule, and standalone repositories.

## Install or update

Run these commands from the GeniusNetwork repository root.

### macOS and Linux

```bash
mkdir -p "$HOME/.claude/skills/architecture-review"
cp -R .claude/skills/architecture-review/. "$HOME/.claude/skills/architecture-review/"
```

### Windows (PowerShell)

```powershell
$destination = "$HOME\.claude\skills\architecture-review"
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -Path ".claude\skills\architecture-review\*" -Destination $destination -Recurse -Force
```

If you use a custom `CLAUDE_CONFIG_DIR`, substitute that directory for `$HOME/.claude`. Back up any existing personal version of the skill before overwriting it. If the destination is a symbolic link or junction, resolve that first to avoid overwriting files in another repository.

The installed skill is available as `/architecture-review` in Claude Code. Start a new session if the skill does not appear in an existing session.

After pulling updates to GeniusNetwork, repeat the copy commands. This is a local copy, not a live link.

## Maintenance

- Edit the canonical skill in [architecture-review/SKILL.md](architecture-review/SKILL.md).
- Do not maintain independent copies in submodules. Check for existing repository-local copies of the same skill when migrating, and remove them through an approved repository change once they are no longer needed.
- Preserve each repository's own `CLAUDE.md`, architecture documentation, and GSD planning files.
- Invoke the skill by name in GSD workflows rather than requiring a repository-local copy.
