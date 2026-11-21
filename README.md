# Antigravity AI Coding Harness

A lightweight, dotfiles-style configuration and multi-agent setup for **Google Antigravity** (unified across **VS Code** and **`agy` CLI** on Linux), designed for the **Google AI Pro** plan with zero external API keys.

## What's Included

- **Unified global config (`~/.gemini/config/`)** via symlinks so local edits stay automatically in sync with Git.
- **4 custom subagents** (`config/agents/`):
  - `codebase-explorer` (`gemini-4-hydrogen-low`, read-only)
  - `code-implementer` (`gemini-4-hydrogen-high`, read/write, shell `off`)
  - `test-runner` (`gemini-4-hydrogen-low`, shell `auto`, RTK-filtered)
  - `code-auditor` (`gemini-4-neon-high`, read-only independent audit)
- **Global rules** (`config/GEMINI.md`) + **project template** (`config/templates/AGENTS.md.template`).
- **MCP configuration** (`config/mcp_config.json`) wiring `context-mode`, `repomix`, and `gemini-api-docs`.
- **3 CLI helpers** (`bin/`):
  - `ai-init`: scaffolds `AGENTS.md`, creates a git-excluded `GEMINI.md` symlink, and prepares `.agents/`.
  - `ai-review [ref]`: runs adversarial `git diff` review via `agy -p` on `claude-opus-5-5-high` (separate Claude/GPT quota pool).
  - `ai-worktree <name>`: creates an isolated `feat/<name>` Git worktree and initializes it with `ai-init`.
- **Optional modules** (`config/optional/`): C/C++/ARM Cortex-M3/RISC-V/gem5 rule (`cpp-embedded-gem5.md`) and university study skill (`academic-tutor`).

For the complete operational guide and technical architecture map, see:
- [GUIDE.md](./GUIDE.md)
- [STRUCTURE.md](./STRUCTURE.md)

## Prerequisites

- Linux (tested on Pop!\_OS 24.04)
- [Google Antigravity](https://antigravity.google) (VS Code extension and/or `agy` CLI)
- Node.js / `npm` (for `context-mode`, `repomix`, and `npx skills`)

## Quick Start

```bash
git clone https://github.com/vincenzopioaltieri/antigravity-harness.git
cd antigravity-harness

# Full setup (symlinks + upstream tools & skills)
./install.sh

# Include optional embedded/university modules
./install.sh --with-optional

# Only create symlinks (if upstream tools are already installed)
./install.sh --links-only --with-optional
```

Then select **`Orchestrator (Neon)`** in VS Code (or `/model` in `agy`) and reload (`Developer: Reload Window` in VS Code / `/skills reload` in `agy`).

## Maintenance & Uninstall

```bash
# Update upstream MCP servers and git plugins
./install.sh --update

# Detach symlinks into standalone copies before deleting this repo
./install.sh --uninstall
```

## Credits & Licenses

This repository only contains original configuration files, custom subagents, and shell wrappers (MIT License). Third-party tools and skills are installed directly from their official upstream repositories during setup:

- [RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk) — Apache-2.0 / BUSL-1.1
- [Context Mode](https://github.com/mksglu/context-mode) — Elastic License 2.0 (ELv2)
- [Repomix](https://github.com/yamadashy/repomix) — MIT License
- [Google Gemini Skills](https://github.com/google-gemini/gemini-skills) — Apache-2.0 License
- [Matt Pocock Skills](https://github.com/mattpocock/skills) — MIT License
- [Ponytail](https://github.com/DietrichGebert/ponytail) — MIT License

*Disclaimer: This is an independent community configuration and is not affiliated with or endorsed by Google, DeepMind, or Anthropic.*
