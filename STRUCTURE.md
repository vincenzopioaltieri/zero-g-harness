# STRUCTURE.md — Technical Map & Audit of the Antigravity Setup

> **Last verified audit:** 2026-11-21  
> **Environment:** Linux (Pop!\_OS 24.04) — VS Code (Antigravity IDE extension) + `agy` CLI (`1.5.12`)  
> **Plan:** Google AI Pro (separate quota pools: Gemini vs Claude/GPT, zero external API keys)

This document records the **verified architecture**, design rationale, skill dependency graph, and maintenance notes for the Antigravity AI coding harness.

---

## 1. Verified Components & Versions

| Component | Version / Status | Path / Source | Role |
| :--- | :--- | :--- | :--- |
| **Antigravity CLI (`agy`)** | `1.5.12` | `~/.local/bin/agy` | Terminal client & headless mode (`agy -p`) |
| **RTK (Rust Token Killer)** | `1.2.0` | `~/.local/bin/rtk` | Transparent shell output compression via `PreToolUse` |
| **Context Mode (MCP)** | `2.1.10` | Global `npm` binary | Sandbox + local SQLite FTS5 index (`~/.context-mode/`) |
| **Repomix (MCP)** | `1.19.0` (SDK v2) | Global `npm` binary | Tree-sitter `--compress` repository packing |
| **Gemini API Docs (MCP)** | Remote Streamable HTTP | `https://gemini-api-docs-mcp.dev` | Official Google Gemini documentation |
| **Plugin `gemini-skills`** | `2.7.0` (Git repo) | `~/.gemini/config/plugins/gemini-skills/` | 4 official Google Gemini API/Live/Omni/CLI skills |
| **Plugin `rtk`** | `1.0.0` | `~/.gemini/config/plugins/rtk/` | `PreToolUse` hook + RTK usage rule |

---

## 2. Filesystem Layout (Dotfiles + Symlink Pattern)

```text
~/.gemini/config/                           # Single global source (VS Code + agy CLI)
├── GEMINI.md                               # -> <repo>/config/GEMINI.md (always_on rules)
├── mcp_config.json                         # Copied from <repo>/config/mcp_config.json
├── config.json                             # Runtime state (NEVER commit to Git)
├── rules/
│   ├── ponytail.md                         # trigger: always_on (installed upstream)
│   └── cpp-embedded-gem5.md                # -> <repo>/config/optional/rules/... (optional, model_decision)
├── agents/                                 # 4 custom subagents (-> <repo>/config/agents/)
│   ├── codebase-explorer.md                # gemini-4-hydrogen-low  | shell: off  | read-only
│   ├── code-implementer.md                 # gemini-4-hydrogen-high | shell: off  | read/write
│   ├── test-runner.md                      # gemini-4-hydrogen-low  | shell: auto | build/test
│   └── code-auditor.md                     # gemini-4-neon-high     | shell: off  | read-only audit
├── plugins/
│   ├── rtk/                                # Installed by rtk init --agent antigravity
│   └── gemini-skills/                      # Official Google git plugin (v2.7.0)
├── skills/                                 # Upstream skills (static copies, no .git) + optional custom skills
└── templates/
    └── AGENTS.md.template                  # -> <repo>/config/templates/AGENTS.md.template

~/.local/bin/                               # CLI wrappers (-> <repo>/bin/)
├── ai-init                                 # Scaffolds AGENTS.md + GEMINI.md symlink + .agents/
├── ai-review                               # Adversarial git diff review on claude-opus-5-5-high
└── ai-worktree                             # Creates feat/<name> worktree + runs ai-init

~/.context-mode/                            # Local SQLite FTS5 storage (projects/, backups/, reports/)
~/.agents/skills/                           # Managed by context-mode (ctx-{doctor,stats,upgrade}; dmi=true = 0 tokens)
```

> **Path hygiene:** `~/.gemini/skills/`, `~/.gemini/antigravity-cli/skills/`, and `~/.gemini/GEMINI.md` are intentionally absent so VS Code and `agy` CLI never diverge.

---

## 3. Global & Modular Rules (`GEMINI.md` + `rules/`)

| File | Trigger | Purpose |
| :--- | :--- | :--- |
| `~/.gemini/config/GEMINI.md` | Always on (no frontmatter) | Engineering discipline, minimalism, surgical edits, ~135k compaction awareness, secret protection, and destructive-command confirmation. |
| `~/.gemini/config/rules/ponytail.md` | `always_on` | Anti-overengineering decision ladder (YAGNI, codebase/stdlib reuse, self-check on non-trivial logic, 1–2 closing lines on skipped checks and risks). |
| `~/.gemini/config/rules/cpp-embedded-gem5.md` | `model_decision` (optional) | C/C++ (`-Wall -Wextra`, `compile_commands.json`), ARM Cortex-M3 (`volatile`, no `malloc` in ISRs, `arm-none-eabi-size`), RISC-V (16-byte stack alignment), and gem5 (`rg` on `m5out/stats.txt`). |
| `~/.gemini/config/plugins/rtk/rules/AGENTS.md` | Always on (via RTK plugin) | Treats RTK-condensed shell output as complete; uses `rtk bypass <cmd>` only when output is unusable. |

---

## 4. Plugins, Hooks & MCP Servers

### 4.1 RTK (`~/.gemini/config/plugins/rtk/hooks.json`)
- Registered as an Antigravity plugin on `PreToolUse` (`matcher: "run_command"`, `command: "rtk hook antigravity"`, `timeout: 10`).
- **Important quirk:** `rtk init --show` prints `[--] Hook: not found` because it only inspects Claude Code / OpenCode / Cursor paths. Always verify RTK in Antigravity with **`rtk gain`**.
- **Constraints:** Do not run VS Code through `agy acp` (ACP ignores plugin hooks) and never run `rtk init -g --gemini` (targets Gemini CLI's `~/.gemini/settings.json`).

### 4.2 MCP Servers (`~/.gemini/config/mcp_config.json`)
1. `context-mode` (`context-mode mcp --agent gemini`): `ctx_execute`, `ctx_batch`, `ctx_index`, `ctx_search`, `ctx_resume`, `ctx_stats`, `ctx_doctor`, `ctx_upgrade`, `ctx_purge`.
2. `repomix` (`repomix --mcp`): `pack_codebase`, `read_repomix_output`, `grep_repomix_output`, `pack_remote_repository`, `generate_skill`, `attach_packed_output`.
3. `context7` (`https://mcp.context7.com/mcp`): `resolve-library-id`, `query-docs` (version-accurate docs for external libraries/frameworks).
4. `gemini-api-docs` (`https://gemini-api-docs-mcp.dev`): `gemini_search_docs`, `gemini_get_doc`.

All MCP tools are lazy-loaded. `mcp_config.json` is **copied** (not symlinked) by `install.sh` because MCP installers may rewrite it atomically.

---

## 5. Custom Subagents (`config/agents/`)

| Subagent | Model | `commandExecutionPolicy` | Allowed `tools` | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `codebase-explorer` | `gemini-4-hydrogen-low` | `off` | `view_file`, `grep_search`, `find_by_name` | Fast read-only reconnaissance (`file:line`, signatures, deps). |
| `code-implementer` | `gemini-4-hydrogen-high` | `off` | `view_file`, `grep_search`, `find_by_name`, `write_to_file`, `replace_file_content` | Scoped file edits without shell execution. |
| `test-runner` | `gemini-4-hydrogen-low` | `auto` | `view_file`, `grep_search`, `run_command` | RTK-filtered builds, linters, and test suites (max 3 lines on pass). |
| `code-auditor` | `gemini-4-neon-high` | `off` | `view_file`, `grep_search`, `find_by_name` | Independent read-only audit (`[CRITICAL]` / `[IMPORTANT]` / `[SUGGESTION]`). |

> **Known risk to monitor:** An invalid or renamed tool name inside `tools:` can cause a subagent to hang silently. Recheck these 4 files after major Antigravity upgrades.

---

## 6. Skills Architecture & Dependency Graph

### Token Cost Mechanism (`disable-model-invocation`)
- **`disable-model-invocation: true` (27 skills)**: Slash-command-only. **0 tokens** in the system prompt until explicitly invoked.
- **`disable-model-invocation: false` (18 skills + 4 `gemini-skills`)**: Loaded into `<skills>` every session. Only these affect base prompt size.

### Dependency Graph (Root Nodes Must Not Be Deleted)

```text
grill-me                      ──▶ grilling
grill-with-docs               ──▶ grilling, domain-modeling
improve-codebase-architecture ──▶ codebase-design, domain-modeling, grilling
implement                     ──▶ tdd, code-review
implement-spec                ──▶ setup-matt-pocock-skills, to-spec, to-tickets
chief-of-staff                ──▶ to-spec, to-tickets, implement-spec, retro
wayfinder                     ──▶ grilling, prototype, research, setup-matt-pocock-skills
triage                        ──▶ grilling, setup-matt-pocock-skills
loop-me                       ──▶ grilling
tdd                           ──▶ codebase-design
setup-ts-deep-modules         ──▶ codebase-design
to-spec / to-tickets / code-review ──▶ setup-matt-pocock-skills
ask-matt                      ──▶ router over all Matt Pocock workflow skills
```

---

## 7. Personal CLI Wrappers (`bin/`)

| Script | Behavior | Design Rationale |
| :--- | :--- | :--- |
| `ai-init` | Copies `AGENTS.md.template` if `AGENTS.md` is missing; symlinks `GEMINI.md -> AGENTS.md`; creates `.agents/{rules,skills,agents}`; adds `GEMINI.md` to `.git/info/exclude`. | Keeps one tracked instructions file (`AGENTS.md`) without polluting `git status`. |
| `ai-review [ref]` | Runs `agy -p ... --model "claude-opus-5-5-high"` against `git diff $TARGET` (default `HEAD`). | Offloads heavy code reviews to the separate Claude/GPT quota pool. |
| `ai-worktree <name>` | Creates branch `feat/<name>` in `../<repo>-<name>` via `git worktree add` and runs `ai-init`. | Isolates parallel features without disturbing the main working tree. |

---

## 8. Audit Notes & Pragmatic Trade-offs

1. **Trimmed unused `dmi=false` skills (2026-11-21)**: Removed 4 out-of-stack skills (`git-guardrails-claude-code`, `migrate-to-shoehorn`, `setup-pre-commit`, `scaffold-exercises`) after verifying 0 external references.
2. **`~/.agents/skills/ctx-*` kept intentionally**: Checked by `context-mode doctor` for `vscode` and `opencode` (`PASS`) and costs 0 prompt tokens (`dmi=true`).
3. **Subagents vs `Orchestrator (Neon)`**: `Orchestrator (Neon)` already separates planning (Neon) from execution (Hydrogen), and `research` is built-in. `code-auditor` and `test-runner` provide the highest day-to-day value; `codebase-explorer` and `code-implementer` are optional for explicit delegation.
4. **Review standardization**: Use `ai-review` as the default pre-push review and `code-auditor` for targeted high-risk audits instead of stacking all review tools on every change.
5. **On-demand MCP**: Keep RTK always active; invoke Context Mode and Repomix on large repos, PDFs, or bulky logs rather than small projects.
