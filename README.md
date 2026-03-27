# Recall Stack

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-blueviolet?style=flat&logo=anthropic)](https://docs.anthropic.com/en/docs/claude-code)
[![Hindsight](https://img.shields.io/badge/Hindsight-compatible-00ADD8?style=flat)](https://github.com/vectorize-io/hindsight)
![Shell](https://img.shields.io/badge/-Shell-4EAA25?logo=gnu-bash&logoColor=white)
![Docker](https://img.shields.io/badge/-Docker-2496ED?logo=docker&logoColor=white)

> **Most people set up CLAUDE.md and call it done.** CLAUDE.md is a rules file. It does not remember what you did yesterday, what went wrong last week, or what patterns work best. And when context compacts, even your rules can get lost.

A 5-layer memory system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with pre-action gates that physically block repeated mistakes -- even after context compaction.

---

## How It Works

```
[You type "claude"]
  |
  v
Layer 1  CLAUDE.md loads             --> "how should I behave?"
Layer 2  primer.md loads             --> "where did we leave off?"
Layer 3  SessionStart hook fires     --> "what changed in the codebase?"
Layer 4  Hindsight recall fires      --> "what patterns should I follow?"
Layer 5  Obsidian vault mounts       --> "what's in the knowledge base?"
  |
  v
Claude sees everything before you type a word.
  ...you work...
  ...primer.md auto-rewrites after each completed task...
  ...post-commit hook logs every commit...
  |
  v
[Context compacts mid-session]
  |
PostCompact hook fires               --> re-injects git context + patterns
Active gates reminded                --> Claude knows what is blocked
  |
  v
[Tool call attempted]
  |
PreToolUse gate fires                --> checks gates.json
  blocked? deny + stderr message     --> physically prevented
  allowed? proceed                   --> normal execution
  |
  v
[Session ends]
  |
Layer 4  Hindsight retain fires      --> stores session summary
Auto-failure tracker runs            --> scans lessons.md for corrections
  3+ same mistake?                   --> auto-promotes to warning gate
```

---

## The 5 Layers + Gates

| # | Layer | What it does | How it loads | Updates |
|---|-------|-------------|--------------|---------|
| 1 | **CLAUDE.md** | Permanent rules, preferences, agent behavior | Auto, every session | You edit manually |
| 2 | **primer.md** | Active project, last task, next step, blockers | Auto (imported by CLAUDE.md) | Rewrites after each task |
| 3 | **Git Context** | Branch, commits, modified files, commit log | SessionStart hook | Fresh every launch |
| 4 | **Hindsight** | Behavioral learning from past sessions | SessionStart + SessionEnd hooks | Learns automatically |
| 5 | **Obsidian** | Full knowledge base as context | Shell alias | You add notes |
| -- | **Gates** | Blocks known-bad actions before execution | PreToolUse hook | Auto-promotes from corrections |

### Why gates?

Memory tells the agent what to do. Gates physically prevent what it should not do.

- **Memory** = "please remember not to force push" (gets lost on compaction)
- **Gates** = tool call denied before it executes (survives everything)

Gates run at the hook level, not the prompt level. Even if Claude forgets every instruction, the hook still fires and blocks the action.

### Why PostCompact?

When Claude compacts context mid-session, Layers 3 and 4 (git context + Hindsight patterns) live in the conversation history and get trimmed. The PostCompact hook re-injects them automatically so Claude does not lose awareness of your codebase state or behavioral patterns.

> **Why not just CLAUDE.md + primer.md?** Layers 1-2 handle rules and state. But Claude still cannot see what changed in your repo since yesterday (Layer 3), does not learn from corrections across sessions (Layer 4), and cannot access your notes (Layer 5). Gates add enforcement that survives compaction. Each piece fills a gap the others cannot.

---

## Quick Start

### One-command install

```bash
git clone https://github.com/kevli770/recall-stack.git
cd recall-stack
bash setup.sh --obsidian ~/path/to/your/vault
```

This installs everything immediately. Layer 4 (Hindsight) requires Docker -- the script will guide you.

### Or set up manually:

<details>
<summary><b>Layer 1+2: CLAUDE.md + primer.md</b> (5 minutes)</summary>

Copy the template files:
```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
cp primer.md ~/.claude/primer.md
```

The key rule in CLAUDE.md:
```
After completing any task (not just session end), silently overwrite
~/.claude/primer.md with: active project, what has been completed,
exact next step, open blockers. Keep under 100 lines.
```

After your first session, primer.md populates itself. After every task, it rewrites itself. If you kill the terminal mid-session, the last completed task state is already saved.

</details>

<details>
<summary><b>Layer 3+4: Hooks</b> (5 minutes)</summary>

Copy hooks and make them executable:
```bash
mkdir -p ~/.claude/hooks
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

Add to `~/.claude/settings.json` (or merge with existing):
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/session-start.sh\"", "timeout": 15 }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/pre-action-gate.sh\"", "timeout": 5 }]
      }
    ],
    "PostCompact": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/post-compact.sh\"", "timeout": 10 }]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/session-end.sh\"", "timeout": 10 }]
      }
    ]
  }
}
```

**Optional:** Add the post-commit hook to any repo for a running commit log:
```bash
cp hooks/post-commit your-repo/.git/hooks/post-commit
chmod +x your-repo/.git/hooks/post-commit
```

</details>

<details>
<summary><b>Layer 4: Hindsight</b> (10 minutes)</summary>

[Hindsight](https://github.com/vectorize-io/hindsight) extracts behavioral patterns from past sessions and injects them into future ones. Not retrieval -- adaptation.

> **Why Docker?** Hindsight requires `uvloop`, which only runs on Linux. Docker handles this on any OS.

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/), then:

```bash
export ANTHROPIC_API_KEY=your-key-here

docker run -d \
  --name hindsight \
  --restart unless-stopped \
  -p 8888:8888 \
  -p 9999:9999 \
  -e HINDSIGHT_API_LLM_PROVIDER=anthropic \
  -e HINDSIGHT_API_LLM_API_KEY=$ANTHROPIC_API_KEY \
  -v hindsight-data:/home/hindsight/.pg0 \
  ghcr.io/vectorize-io/hindsight:latest
```

Create the memory bank (one-time):
```bash
curl -s -X PUT http://localhost:8888/v1/default/banks/claude-sessions \
  -H 'Content-Type: application/json' \
  -d '{"name": "claude-sessions"}'
```

| Resource | URL |
|----------|-----|
| Hindsight API | `http://localhost:8888` |
| Hindsight UI | `http://localhost:9999` |

**Supported LLM providers:** `anthropic`, `openai`, `gemini`, `groq`, `ollama`, `lmstudio`

The hooks handle retain/recall automatically. No extra wiring needed.

</details>

<details>
<summary><b>Layer 5: Obsidian</b> (2 minutes)</summary>

Add a shell alias so your vault is always mounted:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias claude='claude --add-dir "$HOME/path/to/your/obsidian/vault"'
```

Every note in the vault becomes context Claude can read. Syncs to mobile via iCloud/Obsidian Sync. No plugin needed.

</details>

<details>
<summary><b>Gates</b> (2 minutes)</summary>

Gates block known-bad actions via a PreToolUse hook. The starter `gates.json` includes:

| Gate | Blocks | Level |
|------|--------|-------|
| no-force-push | `git push --force` | block |
| no-rm-rf-root | `rm -rf /` or `rm -rf ~` | block |
| no-credentials-in-files | API keys written to files | block |
| no-git-reset-hard | `git reset --hard` | warn |

**Add your own** -- edit `~/.claude/gates.json`:
```json
{
  "name": "my-custom-gate",
  "tool": "Bash",
  "pattern": "some-dangerous-command",
  "level": "block",
  "message": "Why this is blocked.",
  "enabled": true
}
```

Just add it to the `gates` array. No restart needed.

**Auto-promotion:** When you correct Claude and it logs the lesson to `tasks/lessons.md` (via the self-learning rule in CLAUDE.md), the session-end hook tracks it. After 3 occurrences of the same mistake, it auto-promotes to a warning gate. You correct once, twice, three times -- then it is enforced automatically.

</details>

---

## What Survives What

| Event | Layers 1-2 | Layer 3 | Layer 4 | Layer 5 | Gates |
|-------|-----------|---------|---------|---------|-------|
| New session | Loaded fresh | Loaded fresh | Loaded fresh | Loaded fresh | Active |
| Context compaction | Safe (system prompt) | **Re-injected by PostCompact** | **Re-injected by PostCompact** | Safe (system prompt) | Active (hook-level) |
| Terminal crash | primer.md has last state | Lost (re-injected next session) | Lost (re-injected next session) | Safe | Active |
| Model switch | Safe | Safe | Safe | Safe | Active |

---

## File Structure

```
~/.claude/
  CLAUDE.md              # Layer 1: permanent rules
  primer.md              # Layer 2: auto-rewriting session state
  settings.json          # Hook configuration
  gates.json             # Gate rules (block/warn patterns)
  failures.json          # Auto-failure tracker (auto-generated)
  hooks/
    session-start.sh     # Layer 3+4: git context + Hindsight recall
    session-end.sh       # Layer 4: Hindsight retain + failure tracking
    post-compact.sh      # Re-injects layers 3+4 after compaction
    pre-action-gate.sh   # Checks gates.json before every tool call
    post-commit          # Optional: logs commits to .claude-memory.md
```

---

## Without Hindsight

No Docker? The hooks gracefully skip Layer 4 if Hindsight is not running. You still get:

- **Layer 1+2:** Rules + auto-rewriting session state
- **Layer 3:** Git context injection every launch
- **Layer 5:** Obsidian vault as context
- **Gates:** Pre-action blocking + auto-failure tracking

That is already better than what most setups have.

---

## Adding Custom Gates

Edit `~/.claude/gates.json`:

```json
{
  "name": "my-custom-gate",
  "tool": "Bash",
  "pattern": "some-dangerous-command",
  "level": "block",
  "message": "Why this is blocked.",
  "enabled": true
}
```

- **tool**: which tool to match (`Bash`, `Write`, `Edit`, or `*` for all)
- **pattern**: regex matched against tool input
- **level**: `block` (deny the action) or `warn` (log only)
- **enabled**: toggle without deleting

---

## Requirements

| Requirement | Required for | Notes |
|------------|-------------|-------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Everything | The CLI this is built for |
| Git | Layer 3 | Git context injection |
| Python 3 | Gates + Layer 4 | Parses JSON in hooks |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Layer 4 only | Runs Hindsight server |
| [Obsidian](https://obsidian.md/) | Layer 5 only | Any vault, any sync method |

---

## FAQ

<details>
<summary><b>What if I close the terminal without ending the session properly?</b></summary>

primer.md rewrites after every completed task, not just at session end. If you kill the terminal, the state from the last completed task is already saved. The SessionEnd hook (Hindsight retain) will not fire, but the next session still has everything from primer.md + git context.

</details>

<details>
<summary><b>Does primer.md grow forever?</b></summary>

No. It gets overwritten (not appended to) every time. Capped at 100 lines by the CLAUDE.md rule. Always around 2-3KB.

</details>

<details>
<summary><b>Can I use this with Cursor / Codex / other tools?</b></summary>

Layers 1 and 2 (CLAUDE.md + primer.md) are Claude Code specific. Layers 3-5 and gates are generic shell scripts that could be adapted for any tool that supports hooks or launch scripts.

</details>

<details>
<summary><b>How much does Hindsight cost?</b></summary>

Hindsight is free and open source. It uses your LLM API key to process memories. Each retain/recall is a small API call (a few thousand tokens). At Anthropic Haiku pricing, this is fractions of a cent per session.

</details>

---

## Credits

Originally created by [@keshavsuki](https://github.com/keshavsuki).
Forked, adapted, and maintained by [@kevinliaksai](https://github.com/kevli770).
Powered by [Hindsight](https://github.com/vectorize-io/hindsight) for behavioral learning.

---

<div align="center">

**If this helped you, give it a star.**

</div>
