# Yes Claude... - Claude Code Instructions

## Project Overview
"Yes Claude..." is a mobile app (Flutter, Android + iOS) that lets you approve or deny Claude Code permission requests from your phone. When Claude Code needs permission to run a command, edit a file, etc., the app sends a push notification with the request and answer buttons.

**Not an MCP server** — uses Claude Code's hook system to intercept permission prompts.

## Session Startup Checklist

**MANDATORY: Run this checklist at the start of every new session before writing any code.**

Multiple Claude sessions may work on this project in parallel (different PCs, worktrees, or concurrent agents). Skipping this checklist risks merge conflicts, duplicate work, or stepping on another session's in-progress tickets.

### 1. Sync & Orient
```
git fetch origin && git checkout dev && git pull
```
- Read `current_progress.md` for handoff context
- Read this `CLAUDE.md` (architecture, patterns, known issues)
- Skim any implementation plan docs for ticket ordering and dependencies

### 2. Check GitHub PRs
```
gh pr list --repo davidhir1811/yes-claude --state open
```
- **Review each open PR:** what branch, what ticket, any conflicts?
- **Do NOT start work that touches the same files** as an open PR — wait for merge or coordinate
- If a PR has conflicts: rebase it onto dev, push, then merge before starting dependent work

### 3. Check Jira Board
```
# All open tickets, ordered by status
JQL: project = YES AND status != Done ORDER BY status ASC, key ASC
```
- **Check "In Progress" tickets** — these are claimed by another session. Do NOT work on them
- **Check assignees** — if a ticket has an assignee, it's taken
- **Check ticket dependencies** — don't start a ticket whose blockers aren't Done yet
- **Pick the lowest-numbered available ticket** that has all dependencies met

### 4. Claim Your Work
Before starting any ticket:
1. **Transition to "In Progress"** in Jira (transition ID `21`)
2. **Set assignee** to David (`712020:e9ba35d3-9c7c-42c2-a4de-3645d0ae6bf5`)
3. **Add a Jira comment** noting which session/PC is working on it

This prevents another session from picking up the same ticket.

### 5. Create Branch & Work
```
git checkout -b feature/TICKET-XXX-description dev
```
- Commit early and often — other sessions can see your branch
- Push branch to origin even before PR to signal "in progress"

### 6. PR & Review Protocol
When opening a PR:
- **Assignee:** David (the human reviewer)
- **PR title format:** `YES-XXX: Short description`
- **Use `gh` CLI** to create PRs and manage reviews

**Automated review flow (single session):**
1. Push feature branch and open PR via `gh pr create --base dev`
2. Run `/code-review` on the PR to get automated review
3. If frontend changes: also run `/frontend-design` to review UI quality
4. Fix any issues found, push, re-review until approved
5. Merge via `gh pr merge --squash --delete-branch`
6. Transition Jira ticket to "Done" (transition `41`)

**Multi-session review flow:**
1. Session A opens PR → transitions Jira ticket to "In Review" (transition `31`)
2. Session A does NOT merge — it moves on to the next ticket
3. Session B (or David) sees "In Review" tickets / open PRs during startup checklist
4. Session B runs `/code-review`
5. If approved: Session B merges the PR, transitions Jira to "Done" (`41`)
6. If changes needed: Session B comments on the PR with feedback

```bash
gh pr create --base dev --title "YES-XXX: Description" --assignee davidhir1811
```

### Worktree Workflow
- All feature work happens in git worktrees under `.wormtrees/`
- Create worktree: `git worktree add .wormtrees/YES-XXX-description dev`
- This allows parallel work on multiple tickets simultaneously
- `.wormtrees/` is gitignored
- Clean up after merge: `git worktree remove .wormtrees/YES-XXX-description`

### Parallelization Strategy
Tickets should be parallelized in phases:
- **Phase 1:** YES-2 (Firebase setup) — everything depends on this
- **Phase 2:** YES-3 + YES-4 + YES-7 + YES-8 (all depend only on YES-2, no file overlap)
- **Phase 3:** YES-5 + YES-6 (depend on YES-4, separate screens)
- **Phase 4:** YES-9 (E2E testing, depends on everything)

### 7. After Merging
1. Transition Jira ticket to "Done" (transition ID `31`)
2. Delete the feature branch (use `--delete-branch` on merge)
3. Update `current_progress.md` if the next steps have changed
4. Pull dev: `git checkout dev && git pull`

### Quick Reference -- Jira Transitions
| ID | Transition |
|----|-----------|
| 11 | -> To Do |
| 21 | -> In Progress |
| 31 | -> Done |

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Claude Code  │     │    Firebase       │     │ Flutter App │
│   Hook       │────>│  Firestore       │<────│  (Phone)    │
│ (local CLI)  │<────│  Cloud Functions  │────>│             │
│              │     │  FCM             │     │             │
└─────────────┘     └──────────────────┘     └─────────────┘
```

- **Flutter app** — 2 screens: pairing + permission request with choice buttons
- **Firebase** — Firestore (relay), Cloud Functions (push trigger), FCM (notifications)
- **Local hook** — bash+curl (Mac/Linux), PowerShell (Windows)
- **Install** — curl one-liner from GitHub

### Data Flow
1. Claude Code hook writes request doc to Firestore (status: pending)
2. Cloud Function sends FCM push to paired device
3. App shows request + buttons
4. User taps → app updates Firestore doc (status: responded)
5. Hook picks up response → unblocks Claude Code

### Firestore Collections
- `devices/{pairingCode}` — fcmToken, secretToken, createdAt, pairedAt
- `requests/{requestId}` — deviceId, secretToken, command, choices, status, response, createdAt, expiresAt

See full design: `docs/plans/2026-03-08-yes-claude-design.md`

## Build & Deploy

### Tech Stack
| Component | Tech |
|-----------|------|
| Mobile app | Flutter + FlutterFire |
| Backend | Firebase (Firestore + Cloud Functions + FCM) |
| Local hook | Bash + curl (Mac/Linux), PowerShell (Windows) |
| Distribution | Install script on GitHub, app on Play Store + App Store |

### Jira Project
- **Key:** YES
- **Epic:** YES-1 (Yes Claude v1)
- **Tasks:** YES-2 through YES-9
- **Build order:** YES-2 → YES-3 → YES-4 → YES-5 → YES-6 → YES-7 → YES-8 → YES-9

## Logging Conventions

Establish a centralized logger — **never use raw `print()` statements**.

### Rules
1. **Every `catch` block MUST log** — include error object AND stack trace
2. **Never silently swallow exceptions** — at minimum log at error level
3. **Every service lifecycle event must log** — `initialize()`, `start()`, `stop()`, `dispose()`
4. **Tag = class name** — consistent, filterable
5. **No sensitive data in production logs** — don't leak keys, tokens, scores, or user data

## Gemini CLI Integration (Collaborative, Not a Pipe)
Gemini CLI (`gemini -p "..."`) is installed. Use it as a **collaborative partner**, NOT as a passthrough.

### How to Work WITH Gemini
1. **Form your own opinion first.** Think through the problem before asking Gemini.
2. **Ask Gemini with context.** Share what you know, ask for critique or alternatives.
3. **Debate and challenge.** Critically evaluate its answer. Push back where you disagree.
4. **Synthesize a converged answer.** Present combined best thinking, noting agreements/disagreements.
5. **Never relay Gemini's answer verbatim.** Always add your own analysis and judgment.

### When to Consult Gemini
- Web/current information (use instead of WebSearch/WebFetch)
- Plan review before major features
- Code review after writing significant modules
- Results review for sanity checks
- Domain knowledge for specialized topics

### Technical Notes
- Always use `-p` flag for non-interactive mode
- Set timeout to 120s for Gemini calls
- Fall back to WebSearch/WebFetch if Gemini is unavailable

## Known Issues & Lessons Learned
<!-- Accumulate project-specific lessons here -->

## Jira & GitHub Integration
- **Atlassian Cloud:** davidhir1811.atlassian.net
- **Cloud ID:** `f819f109-5df4-4769-8318-4ea91c25e545`
- **David's Account ID:** `712020:e9ba35d3-9c7c-42c2-a4de-3645d0ae6bf5`
- Use `gh` for GitHub operations

## Installed Plugins

| Plugin | Type | Trigger | Use Case |
|--------|------|---------|----------|
| **superpowers** | Skills + Commands + Hooks | Auto + `/brainstorm`, `/write-plan`, `/execute-plan` | Core dev workflow |
| **code-review** | Command | `/code-review` | Automated multi-agent PR review |
| **feature-dev** | Command | `/feature-dev` | Guided 7-phase feature development |
| **claude-md-management** | Skill + Command | `/revise-claude-md` + auto | Audit/update CLAUDE.md |
| **frontend-design** | Skill | Auto (frontend work) | Distinctive, production-grade UI |
| **security-guidance** | Hook | Auto (Edit/Write) | Security warnings |
| **claude-code-setup** | Skill | On request | Recommend Claude Code automations |

## Domain Skills (`.claude/skills/`)
TODO: Define after implementation begins.
