# Complete Guide to the Antigravity AI Coding Harness

This guide documents the architecture, internals, operational commands, workflow prompts, quota fallback strategy, and maintenance procedures of this **Google Antigravity** setup on Linux (unified across **VS Code** and **`agy` CLI**).

> For the detailed technical map, file inventory, and skill dependency graph, see [STRUCTURE.md](./STRUCTURE.md).

---

## 1. Key Benefits

* **Major token & context savings (staying below the ~135k auto-compaction threshold)**:
  * **RTK (`1.2.0`)** transparently intercepts shell commands (`git`, `ls`, `grep`, `pytest`, `cargo`, `cmake`, `npm`) via a `PreToolUse` plugin hook, compressing verbose logs and stack traces before they reach the model context.
  * **Context Mode (`2.1.10`)** runs heavy commands in a local sandbox and indexes large files/documents into per-project **SQLite FTS5** databases (`~/.context-mode/projects/`), returning only matching excerpts.
  * **Repomix (`1.19.0`, SDK v2)** packs large repositories using **Tree-sitter `--compress`** syntax trees instead of raw source code.
* **Zero recurring API costs & smart quota routing (Google AI Pro)**:
  * Runs entirely on a **Google AI Pro** subscription with no pay-as-you-go external API keys.
  * **Gemini 4 Neon** / **`Orchestrator (Neon)`** handles planning, orchestration, and auditing (faster, more accurate, and more token-efficient than Argon); **Gemini 4 Hydrogen** handles fast execution; **`ai-review`** offloads adversarial code reviews to the separate **Claude Opus 5.5 (High)** quota pool.
* **Minimal code without over-engineering**:
  * `~/.gemini/config/GEMINI.md` and `~/.gemini/config/rules/ponytail.md` (`trigger: always_on`) enforce minimalism, surgical edits, security checks, and explicit reporting of skipped work and risks.
  * Optional `~/.gemini/config/rules/cpp-embedded-gem5.md` (`trigger: model_decision`) activates automatically on C/C++, ARM Cortex-M3, RISC-V, and gem5 projects.
* **Low-overhead modular skills**:
  * Slash-command-only skills (`disable-model-invocation: true`) consume **0 tokens** in the system prompt until explicitly invoked.
* **Unified environment**: Rules, skills, MCP servers, plugin hooks, and subagents live in `~/.gemini/config/` and work identically in **VS Code** (native Antigravity extension) and **`agy` CLI**.

---

## 2. Three-Tier Multi-Agent Architecture

The system uses **context isolation** so the main conversation is never flooded by build logs, raw exploration output, or intermediate retries.

```text
                       ┌──────────────────────────────────────┐
                       │   TIER 1: ORCHESTRATOR (Lead)        │
                       │  Orchestrator (Neon)                 │
                       │  • Read-only planning (Neon)         │
                       │  • Fast execution (Hydrogen)         │
                       │  • Reads AGENTS.md / SPEC.md         │
                       └──────────────────┬───────────────────┘
                                          │
          ┌───────────────────────────────┼───────────────────────────────┐
          ▼                               ▼                               ▼
┌───────────────────┐           ┌───────────────────┐           ┌───────────────────┐
│ codebase-explorer │           │ code-implementer  │           │    test-runner    │
│ Hydrogen (Low)    │           │ Hydrogen (High)   │           │  Hydrogen (Low)   │
│ • Read-only       │           │ • File edits only │           │ • Shell (auto)    │
│ • Maps file:line  │           │ • Shell: off      │           │ • RTK-filtered    │
│ (optional vs      │           │ (optional vs      │           │ • Max 3 lines OK  │
│  builtin research)│           │  Orchestrator)    │           └───────────────────┘
└───────────────────┘           └───────────────────┘
                                          │
                                          ▼
                       ┌──────────────────────────────────────┐
                       │   TIER 3: VALIDATION & AUDIT         │
                       │  • code-auditor (Gemini 4 Neon High) │
                       │    Read-only static audit in chat    │
                       │  • ai-review (Claude Opus 5.5 High)  │
                       │    Adversarial CLI diff review       │
                       └──────────────────────────────────────┘
```

### How the 5 Roles Work Together

1. **Main Orchestrator (`Orchestrator (Neon)` — `gemini-pro-orchestrator-neon`)**:
   * **Role**: Session Tech Lead. Internally splits read-only planning (**Gemini 4 Neon**) from execution (**Gemini 4 Hydrogen**), automatically returning to the planner if verification fails twice or an ambiguity surfaces.
   * **Practical note**: For most everyday tasks, `Orchestrator (Neon)` handles planning, editing, and verification on its own without forcing manual ping-pong between `codebase-explorer` and `code-implementer`.
2. **Explorer (`codebase-explorer` — `gemini-4-hydrogen-low`, read-only, shell `off`)**:
   * **Role**: Fast reconnaissance on large codebases returning only `file:line` coordinates, signatures, and dependencies.
   * **Practical note**: Overlaps with Antigravity's built-in `research` subagent; use it when you explicitly want `gemini-4-hydrogen-low` with ultra-compact output.
3. **Implementer (`code-implementer` — `gemini-4-hydrogen-high`, file edits, shell `off`)**:
   * **Role**: Scoped file edits without shell execution privileges.
   * **Practical note**: Useful for parallel delegation or tightly scoped patches; for small fixes, let `Orchestrator (Neon)` edit directly.
4. **Verifier (`test-runner` — `gemini-4-hydrogen-low`, read-only + shell `auto` filtered by RTK)**:
   * **Role**: Runs builds (`cmake`, `cargo`, `make`), linters, and test suites (`pytest`, `ctest`) in an isolated context.
   * **Output**: Maximum 3 lines if everything passes; otherwise only failing tests, essential stack traces, and `file:line`.
5. **Independent & Adversarial Reviewers (`code-auditor` + `ai-review`)**:
   * **`code-auditor`** (`gemini-4-neon-high`, read-only, shell `off`): Inspects code with "fresh eyes" (without generation bias), classifying issues as `[CRITICAL]`, `[IMPORTANT]`, or `[SUGGESTION]`. Best for memory-sensitive, concurrent, or security-critical code.
   * **`ai-review`** (`claude-opus-5-5-high` via CLI): Cross-family `git diff` review before pushing, using the separate Claude/GPT quota pool. **Recommended default for daily code reviews.**

---

## 3. Filesystem Map & Data Pipeline

```text
~/.gemini/config/                         # Single global source (VS Code + agy CLI)
├── GEMINI.md                             # Global always_on rules (symlinked from repo)
├── mcp_config.json                       # MCP servers (context-mode, repomix, context7, gemini-api-docs)
├── config.json                           # Runtime state (NEVER commit to Git)
├── agents/                               # 4 custom subagents (symlinked from repo)
│   ├── codebase-explorer.md              # model: gemini-4-hydrogen-low  | shell: off
│   ├── code-implementer.md               # model: gemini-4-hydrogen-high | shell: off
│   ├── test-runner.md                    # model: gemini-4-hydrogen-low  | shell: auto
│   └── code-auditor.md                   # model: gemini-4-neon-high     | shell: off
├── rules/                                # Modular rules with snake_case YAML frontmatter
│   ├── ponytail.md                       # trigger: always_on (installed upstream)
│   └── cpp-embedded-gem5.md              # trigger: model_decision (optional)
├── plugins/
│   ├── rtk/                              # Installed by rtk init -g --agent antigravity
│   └── gemini-skills/                    # Official Google git plugin (4 Gemini API skills)
├── skills/                               # Upstream skills (Matt Pocock, Ponytail, Context Mode) + optional custom skills
└── templates/
    └── AGENTS.md.template                # Copied by ai-init into new repositories

~/.local/bin/                             # CLI wrappers on PATH (symlinked from repo)
├── ai-init                               # Scaffolds AGENTS.md + GEMINI.md symlink + .agents/
├── ai-review                             # Adversarial git diff review on Claude Opus 5.5 High
└── ai-worktree                           # Creates feat/<name> branch + parallel worktree + ai-init

~/.context-mode/                          # Local SQLite FTS5 storage
├── projects/                             # Per-project SQLite databases
├── backups/
└── reports/

~/.agents/skills/                         # Managed by context-mode (ctx-{doctor,stats,upgrade}; dmi=true = 0 tokens)

<your-project>/                           # Per-repo structure created by ai-init
├── AGENTS.md                             # Project rules, architecture, Build/Test/Lint commands
├── GEMINI.md -> AGENTS.md                # Local symlink (ignored via .git/info/exclude)
└── .agents/                              # Optional repo-specific rules/skills/subagents
```

### Compression Pipeline
1. **Terminal Hook (`RTK` via `PreToolUse`)**: Always active in the background on `run_command`. Use `rtk bypass <cmd>` only if filtering hides a needed diagnostic line.
2. **Sandbox & SQLite Index (`Context Mode` MCP — on-demand)**: Use `ctx_index` / `ctx_execute` + `ctx_search` on large PDFs, huge logs (e.g., gem5 `m5out/stats.txt`), or bulky outputs. Indexed data survives context auto-compaction.
3. **Syntax Mapping (`Repomix` MCP — on-demand)**: Use compressed `pack_codebase` on large repositories (>50k lines) to inspect signatures via Tree-sitter.
4. **Pragmatism rule**: Keep **RTK** always on; use **Context Mode** and **Repomix** only on large repos/logs/PDFs, not on small projects where `rg` and targeted reads are faster.

---

## 4. How Skills Work: Token Cost & Dependency Graph

Skills use the YAML frontmatter field `disable-model-invocation` (`dmi`):

* **`disable-model-invocation: true`**: **Slash-command-only**. Consumes **0 tokens** in the system prompt until explicitly invoked via `/<name>`.
* **`disable-model-invocation: false`**: Name and description are loaded into `<skills>` every session so the model can trigger them proactively.

### Skill Dependency Graph (Do Not Break During Cleanup)
Several slash commands are thin wrappers around core skills:

```text
/grill-me                      ──▶ grilling
/grill-with-docs               ──▶ grilling + domain-modeling
/improve-codebase-architecture ──▶ codebase-design + domain-modeling + grilling
/implement                     ──▶ tdd + code-review
/implement-spec                ──▶ setup-matt-pocock-skills + to-spec + to-tickets
/chief-of-staff                ──▶ to-spec + to-tickets + implement-spec + retro
/wayfinder                     ──▶ grilling + prototype + research + setup-matt-pocock-skills
/triage / /loop-me             ──▶ grilling (+ setup-matt-pocock-skills)
/tdd / /setup-ts-deep-modules  ──▶ codebase-design
/ask-matt                      ──▶ router across all Matt Pocock workflow skills
```

> **Safety rule:** Never delete `grilling`, `domain-modeling`, `codebase-design`, `tdd`, `code-review`, `prototype`, `research`, or `setup-matt-pocock-skills` if you use any downstream slash commands.

---

## 5. Operational Commands & Key Skills

### A. Linux CLI Commands (`~/.local/bin/`)

| Command | What it does | When to use |
| :--- | :--- | :--- |
| `ai-init` | Copies `AGENTS.md.template`, creates a git-excluded `GEMINI.md` symlink, and scaffolds `.agents/`. | **Once** in the root of every new or existing repository. |
| `ai-review [ref]` | Runs adversarial review on `git diff HEAD` (or a given ref) via `claude-opus-5-5-high`. | Before pushing or merging a feature. |
| `ai-worktree <name>` | Creates `feat/<name>` in `../<repo>-<name>` and runs `ai-init`. | For parallel features/experiments without dirtying the main working tree. |
| `rtk gain` | Shows intercepted commands and token savings (the true RTK health check in Antigravity). | To verify RTK is active and track savings. |
| `agy` / `agy -p "..."` | Launches Antigravity CLI interactively or headless. | Quick terminal tasks, scripting, or work outside VS Code. |

### B. Main Slash Commands Inside Antigravity (`VS Code` or `agy`)

* **Planning, Specs & Development (Matt Pocock)**:
  * `/setup-matt-pocock-skills`: One-time repo setup (`docs/agents/{issue-tracker,domain,triage-labels}.md`).
  * `/grill-me` / `/grill-with-docs`: Relentless decision-tree interview (the latter also updates `GLOSSARY.md` and ADRs).
  * `/to-spec` → `/to-tickets` → `/implement-spec` / `/implement`: End-to-end pipeline from design to tickets and implementation.
  * `/tdd`: Guided *Red → Green → Refactor* cycle.
  * `/handoff` / `/retro`: Compacts session context to `/tmp` for a fresh agent, or reviews the session to improve `AGENTS.md`.
* **Quality, Refactoring & Debugging**:
  * `/ponytail-review` / `/code-review`: Diff review (minimalism/bugs or dual-axis Standards + Spec).
  * `/ponytail-audit` / `/ponytail-debt`: Whole-repo audit or `shortcut:` debt ledger.
  * `/improve-codebase-architecture` / `/domain-modeling` / `/diagnosing-bugs`: Deepening modules, domain modeling, and systematic root-cause analysis.
* **Study & Oral Exam Prep (Optional)**:
  * `/academic-tutor`: Maps theory → code, traces `file:line` and in-memory structures, explains trade-offs, and generates 2 oral-exam questions with answers.
* **Gemini API & Diagnostics**:
  * `/gemini-api-dev`, `/gemini-live-api-dev`, `/gemini-omni-flash-api`, `/gemini-api-cli`: Up-to-date Google Gemini SDK patterns.
  * `/ctx-stats` / `/ctx-doctor`: Context Mode FTS5 stats and health check.
  * `/skills reload`: Reloads skills, rules, and subagents in `agy`.

---

## 6. Context-Specific Workflow Prompts

### 1. Onboarding a New Repository
1. Run `ai-init` in the repository root.
2. Fill in real **Build**, **Test**, and **Lint** commands in `AGENTS.md`.
3. Select **`Orchestrator (Neon)`** in VS Code (or `/model` in `agy`).

### 2. Starting From a Spec / PDF Assignment
1. Place the spec in `docs/spec.pdf` and run `ai-init`.
2. **Step 1 (Analysis & Spec)**:
   > *"Index `docs/spec.pdf` with `ctx_index`, populate `AGENTS.md` with the stack and build/test commands, then run `/grill-with-docs` to resolve all edge cases before generating `docs/SPEC.md` with `/to-spec`."*
3. **Step 2 (Tickets & TDD)**:
   > *"Split `docs/SPEC.md` with `/to-tickets`. Implement **Ticket 1** following `/tdd` and `ponytail.md`, delegating build and tests to `test-runner`."*

### 3. Debugging Crashes, Memory Leaks, or Stalls on Large Codebases
> *"Do not load entire files or raw logs into chat: 1) map involved modules with Repomix (compressed `pack_codebase`) or `codebase-explorer` to get `file:line`; 2) index `build/output.log` with `ctx_index` and investigate using `ctx_search` and `/diagnosing-bugs`; 3) have `code-auditor` inspect pointer safety and memory management."*

### 4. Multi-File Refactor or Parallel Feature
1. Isolate work in a dedicated worktree:
   ```bash
   ai-worktree refactor-module-x
   ```
2. **Refactor Prompt**:
   > *"Apply `/improve-codebase-architecture` on module X keeping the diff minimal (`ponytail.md`); delegate regression builds/tests to `test-runner` and run a read-only final audit with `code-auditor`."*
3. Run `ai-review` from the terminal before merging.

### 5. Oral Exam / Deep-Dive Study (Optional Skill)
> *"Activate `/academic-tutor` on `src/pipeline.cpp` and `src/cache.cpp`: connect each component to theoretical principles, trace `file:line` for how data structures mutate in memory, justify design trade-offs, and ask 2 tough oral-exam questions with rigorous answers."*

---

## 7. Troubleshooting & Quota Fallback Playbook

### A. Quota Buckets (Google AI Pro)
Quotas refresh every 5 hours (with a weekly cap) across separate pools:

1. **Bucket 1 — Deep Reasoning (`Gemini 4 Neon` / `Orchestrator (Neon)`)**:
   * *Primary*: `Orchestrator (Neon)` for lead orchestration, `code-auditor` on `gemini-4-neon-high`.
   * *Fallback*: Step down to **`gemini-4-neon-medium`** / **`gemini-4-argon-high`**, or switch directly to **`Gemini 4 Hydrogen (High/XHigh)`**.
2. **Bucket 2 — High Speed (`Gemini 4 Hydrogen` & `Gemini 3.8 Flash`)**:
   * *Primary*: Fast execution, `test-runner`, and `codebase-explorer` (`gemini-4-hydrogen-low`).
   * *Fallback*: Move `test-runner` / `codebase-explorer` to **`gemini-3.8-flash-low`** in `config/agents/`.
3. **Bucket 3 — External Models (`Claude Opus 5.5` / `Claude Sonnet 5.5`)**:
   * *Strategic use*: Separate quota pool from Gemini. Use via `ai-review` (`claude-opus-5-5-high`) or switch to **`Claude Sonnet 5.5 (High)`** in chat if Gemini pools hit rate limits.

### B. Common Technical Issues

* **`rtk init --show` reports `[--] Hook: not found`**:
  * **Expected**: `rtk init --show` only checks Claude Code / OpenCode / Cursor paths (`~/.claude/CLAUDE.md`, etc.) and does not inspect `~/.gemini/config/plugins/rtk/hooks.json`. Verify RTK in Antigravity with **`rtk gain`**.
  * **Never run** `rtk init -g --gemini` (modifies `~/.gemini/settings.json` for Gemini CLI) and **do not use `agy acp`** in VS Code (ACP does not apply plugin hooks).
* **`context-mode doctor` shows `WARN hook-seen` or `SKIPPED gemini`**:
  * **Expected**: `gemini` checks the standalone Gemini CLI; as long as `vscode`/`opencode` are `PASS` and `ctx_*` MCP tools work in Antigravity, everything is healthy. **Do not delete `~/.agents/skills/ctx-*`** (`context-mode doctor` checks it and it costs 0 prompt tokens).
* **Changes to rules, skills, subagents, or `mcp_config.json` are not picked up**:
  * In **VS Code**: `Ctrl+Shift+P` → **`Developer: Reload Window`**.
  * In **`agy` CLI**: `/skills reload`.
* **A custom subagent hangs without responding**:
  * Check the `tools:` list in `config/agents/*.md` (`view_file`, `grep_search`, `find_by_name`, `write_to_file`, `replace_file_content`, `run_command`): a renamed or invalid tool name after a major Antigravity update can hang subagent execution.
* **GitHub Copilot prompt in VS Code (*"Migrate MCP Servers"*)**:
  * Always click **`Ignore`** to avoid spawning duplicate MCP server processes.

---

## 8. Maintenance & Updates

```bash
# Update upstream MCP servers and git plugins
./install.sh --update

# Check RTK savings & version (use rtk gain, NOT rtk init --show)
rtk --version && rtk gain

# Check available Antigravity model IDs
agy --version && agy models
# -> If any model ID changes, update config/agents/*.md and bin/ai-review, then git commit & push
```
