# Yes Claude... v2 — Design Document

## Date: 2026-03-10

## Overview

v2 extends Yes Claude with: web app (PWA), user accounts with progressive auth, rate-limited tiers, persistent request history (backend-only), response validation, multi-session support, and multi-CLI adapter architecture.

## What's New vs v1

| Feature | v1 | v2 |
|---------|----|----|
| Platforms | Mobile (Android/iOS) | + Web PWA |
| Identity | Device pairing only | Progressive Firebase Auth (anonymous → Google/Apple) |
| Rate limiting | None | Tiered: anonymous (5/day), free (20/day), premium (1000/month) |
| Sessions | Single | Multiple concurrent sessions with labels |
| History | Cleaned up after expiry | Persisted to `users/{uid}/history/` |
| Response security | Trust app | Validated at every layer |
| CLI support | Claude Code only | Adapter pattern for any CLI |
| Payments | None | Prepared (RevenueCat + App Store/Play Store, future ticket) |

## Architecture

```
┌─────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│ CLI Hook     │     │ Firebase             │     │ Flutter App      │
│ (bash/ps1)   │────>│  Firestore           │<────│ (Phone/Web PWA)  │
│              │<────│  Cloud Functions      │────>│                  │
│ adapters:    │     │  FCM (mobile + web)   │     │ Progressive Auth │
│  --claude    │     │  Auth (anonymous +    │     │ Multi-session UI │
│  --cursor    │     │   Google/Apple)       │     │                  │
│  --etc       │     │  Hosting (web app)    │     │                  │
└─────────────┘     └──────────────────────┘     └──────────────────┘
```

## 1. User Identity — Progressive Firebase Auth

### Flow

1. **First launch** → Firebase Anonymous Auth silently creates a `uid` (zero friction)
2. **Anonymous tier** → 5 requests/day, enough to try the app
3. **Hit limit** → prompt: "Sign in with Google/Apple to continue"
4. **Sign in** → anonymous account links to Google/Apple (preserves uid + history)
5. **Premium** → requires sign-in + payment (future ticket)

### Why Progressive

- First impression is frictionless (no signup wall)
- Abuse is bounded (anonymous = 5 req/day, reinstalling only resets to 5)
- Real identity kicks in when it matters (hitting limits or buying premium)

### Persistence

- **Mobile:** uid survives app restarts (stored in app storage)
- **Web PWA:** uid survives browser restarts (stored in IndexedDB)
- **Google/Apple Sign-In:** uid survives reinstall/new device (linked to real account)

## 2. Rate Limiting

### Tier Configuration (Firestore)

```
config/tiers  (single document — admin control panel)
{
  "anonymous": { "dailyLimit": 5 },
  "free":      { "dailyLimit": 20 },
  "premium":   { "monthlyLimit": 1000 }
}
```

**These values are live — change them in Firestore and they take effect immediately, no redeployment.**

### Admin Scripts

`scripts/admin.sh` provides CLI tools:

```bash
# View current tier limits
./scripts/admin.sh get-limits

# Change tier limits (updates Firestore config/tiers doc)
./scripts/admin.sh set-limits --anonymous 5 --free 20 --premium 1000

# View a user's info and usage
./scripts/admin.sh user-info <uid>

# Manually set a user's tier
./scripts/admin.sh set-tier <uid> premium

# Reset a user's daily counter
./scripts/admin.sh reset-counter <uid>
```

### Enforcement

1. Hook creates request in Firestore
2. Cloud Function `onRequestCreated` reads `users/{uid}` counters + `config/tiers`
3. If over limit → auto-responds with "Deny", sets `rateLimited: true` flag
4. App shows appropriate upgrade prompt based on tier
5. Counters reset via scheduled Cloud Function:
   - Daily counters reset at midnight UTC
   - Monthly counters reset on 1st of month

### User Document

```
users/{uid}
{
  "tier": "anonymous" | "free" | "premium",
  "dailyCount": 3,
  "dailyResetAt": "2026-03-10T00:00:00Z",
  "monthlyCount": 45,
  "monthlyResetAt": "2026-03-01T00:00:00Z",
  "createdAt": "2026-03-10T12:00:00Z",
  "devices": ["ABCDEF", "GHIJKL"]
}
```

## 3. Web App — Flutter Web PWA

### Hosting

- Flutter Web build → Firebase Hosting
- Single `firebase deploy` handles Cloud Functions + web app + Firestore rules
- PWA manifest for "Add to Home Screen"

### Web Push Notifications

- FCM web push via `firebase-messaging-sw.js` service worker
- **Android Chrome:** full push support, works when tab is closed
- **iOS Safari:** push works only after adding PWA to home screen (OS limitation)
- App shows a one-time prompt explaining "Add to Home Screen" on iOS

### What Changes from Mobile

- Nothing in Dart code — same screens, same queries, same theme
- Add `firebase-messaging-sw.js` service worker
- Add Firebase config to `web/index.html`
- Firebase Hosting config in `firebase.json`

## 4. Data Storage & History

### Real-Time Relay (existing, stays lean)

```
requests/{requestId}
{
  "deviceId": "ABCDEF",
  "uid": "firebase-auth-uid",
  "secretToken": "shared-auth-token",
  "command": "bash: rm -rf /tmp/old",
  "choices": ["Allow", "Deny", "Allow Always"],
  "status": "pending" | "responded",
  "response": null | "Allow",
  "source": "claude",
  "sessionId": "abc123",
  "sessionLabel": "~/Projects/yes-claude",
  "machineId": "davids-macbook",
  "createdAt": "timestamp",
  "expiresAt": "timestamp",
  "rateLimited": false
}
```

Still cleaned up after expiry by the existing scheduled function.

### Persistent History (new, backend-only)

```
users/{uid}/history/{requestId}
{
  "command": "bash: rm -rf /tmp/old",
  "choices": ["Allow", "Deny", "Allow Always"],
  "response": "Allow",
  "source": "claude",
  "sessionLabel": "~/Projects/yes-claude",
  "machineId": "davids-macbook",
  "deviceId": "ABCDEF",
  "createdAt": "timestamp",
  "respondedAt": "timestamp"
}
```

- Cloud Function copies request to history when `status` changes to `responded`
- **No history screen in the app** — data is for backend analytics only
- Queryable by date range, source CLI, device

## 5. Response Validation (Security)

Validated at every layer:

1. **Hook** — hardcodes `["Allow", "Deny", "Allow Always"]` in request
2. **App** — only renders buttons for those choices (no free text input)
3. **Firestore security rules** — validates `response` is in the document's `choices` array
4. **Cloud Function** — double-checks response validity before copying to history
5. **Hook response mapping** — only maps known strings, anything unexpected → `{"allow": false}`

Even with direct Firestore write access, an attacker can only set a valid choice.

## 6. Multi-Session Support

### Problem

Multiple CLI sessions running on different machines (or same machine, different terminals) each send permission requests. The app needs to show which is which.

### Solution

Hook scripts send session context with each request:

| Field | Source | Example |
|-------|--------|---------|
| `sessionId` | Claude Code stdin (if available) or generated | `abc123` |
| `sessionLabel` | `$PWD` / project folder name | `~/Projects/yes-claude` |
| `machineId` | `hostname` / `$env:COMPUTERNAME` | `davids-macbook` |
| `source` | `--cli` flag from install | `claude` |

### App UI

- Request screen shows a **list of all pending requests** (not just the latest)
- Each request card displays: machine name + project folder + command
- Example card:
  ```
  davids-macbook · yes-claude
  ─────────────────────────
  > bash: rm -rf /tmp/old
  [Allow]  [Allow Always]  [Deny]
  ```

## 7. Multi-CLI Adapter Architecture

### Adapter Pattern

The hook gets a `--cli` flag during install (defaults to `claude`):

```bash
# Claude Code (default)
curl -sSL .../install.sh | bash

# Cursor (future)
curl -sSL .../install.sh | bash -s -- --cli cursor

# Other AI CLI (future)
curl -sSL .../install.sh | bash -s -- --cli aider
```

### What Each Adapter Handles

| Concern | Claude adapter | Future adapters |
|---------|---------------|-----------------|
| Parse stdin | `{"tool": "X", "input": "Y"}` | CLI-specific format |
| Format stdout | `{"allow": true/false}` | CLI-specific format |
| Choices | Allow / Deny / Allow Always | CLI-specific options |
| Settings path | `~/.claude/settings.json` | CLI-specific config |

### What's Shared (core)

- Firestore request creation
- Polling for response
- Config reading (`~/.yes-claude/config.json`)
- Pairing flow

### File Structure

```
hooks/
  core.sh          # shared: Firestore API, polling, config
  adapters/
    claude.sh      # parse Claude stdin, format Claude stdout
    cursor.sh      # (future) parse Cursor stdin, format Cursor stdout
hook.sh            # entry point: sources core + selected adapter
```

Same structure for PowerShell: `core.ps1`, `adapters/claude.ps1`, `hook.ps1`.

## 8. Payments (Future — Not in This Build)

### Prepared Infrastructure

- `users/{uid}.tier` field ready for `"premium"` value
- Rate limiting checks tier on every request
- "Upgrade" prompt in app when limit hit
- `config/tiers` document for limit configuration

### Future Payment Ticket

- **RevenueCat** SDK for unified App Store + Play Store subscriptions
- Apple/Google fully support Israeli developers (paid to Israeli bank)
- Web payments via Paddle or LemonSqueezy (Stripe doesn't support Israel)
- RevenueCat free up to $2,500/month revenue

## 9. Firestore Security Rules (Updated)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Admin config — read-only from client
    match /config/{doc} {
      allow read: if true;
      allow write: if false;
    }

    // User documents — users can read/write their own
    match /users/{uid} {
      allow read, update: if request.auth != null && request.auth.uid == uid;
      allow create: if request.auth != null;
      allow delete: if false;

      // History subcollection — read-only from client (Cloud Function writes)
      match /history/{requestId} {
        allow read: if request.auth != null && request.auth.uid == uid;
        allow write: if false;
      }
    }

    // Devices — pairing flow (unauthenticated hook writes)
    match /devices/{pairingCode} {
      allow create: if true;
      allow read: if true;
      allow update: if true;
      allow delete: if false;
    }

    // Requests — real-time relay
    match /requests/{requestId} {
      allow create: if request.resource.data.secretToken is string
                    && request.resource.data.secretToken.size() > 0
                    && request.resource.data.deviceId is string
                    && request.resource.data.deviceId.size() > 0;
      allow read: if true;
      // Validate response is one of the original choices
      allow update: if request.resource.data.status == 'responded'
                    && request.resource.data.response is string
                    && request.resource.data.response in resource.data.choices;
      allow delete: if false;
    }
  }
}
```

## 10. What the App Does NOT Do

- No history screen (history is backend-only)
- No settings screen
- No auto-approve rules
- No in-app payments (prepared but not wired)
- No free-text responses (buttons only, validated at every layer)
