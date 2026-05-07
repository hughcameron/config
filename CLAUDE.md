# config

Hugh's chezmoi source repo — canonical home for dotfiles, shell config, settings under `~/.config/**` and `~/.local/**`, SSH/GPG settings, system packages, and machine automation. Anything that shapes Hugh's machines lives here and is applied via chezmoi.

## Session start

1. `chezmoi status` — see drift between repo and system
2. `git status` — see uncommitted edits in the source

## Operational gates

- **Chezmoi sync.** After ANY configuration change run `chezmoi diff`. Sync immediately — system→repo via `chezmoi add`, or repo→system via `chezmoi apply`. Repo and system never diverge.
- **Destructive operations.** Verify rollback path before running. System config is harder to recover than code.
- **New credentials.** Start with minimum access; expand only if required.
- **New automation.** Logs what it did, where, with timestamps.
