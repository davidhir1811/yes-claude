# Yes Claude... — Design Document

## Date: 2026-03-08

## Overview

"Yes Claude..." is a mobile app that lets you approve or deny Claude Code permission requests from your phone. When Claude Code needs permission to run a command, edit a file, or perform any action, the app sends a push notification with the request details and response buttons.

## Architecture

### Components

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Claude Code  │     │    Firebase       │     │ Flutter App │
│   Hook       │────>│  Firestore       │<────│  (Phone)    │
│ (local CLI)  │<────│  Cloud Functions  │────>│             │
│              │     │  FCM             │     │             │
└─────────────┘     └──────────────────┘     └─────────────┘
```

### Data Flow

1. Claude Code triggers the hook with permission details
2. Hook writes a doc to `requests/{id}` in Firestore (status: `pending`)
3. Cloud Function detects new doc, sends FCM push to paired device
4. App receives push, opens/foregrounds, shows request + buttons
5. User taps a button, app updates the doc (status: `responded`, response: chosen option)
6. Hook is polling the doc, sees status change, returns the response to Claude Code

## Tech Stack

| Component | Tech |
|-----------|------|
| Mobile app | Flutter + FlutterFire |
| Backend | Firebase (Firestore + Cloud Functions + FCM) |
| Local hook | Bash + curl (Mac/Linux), PowerShell (Windows) |
| Distribution | Install script hosted on GitHub |
| App distribution | Google Play + App Store |

## Firestore Data Model

### Collection: `devices/{pairingCode}`

```json
{
  "fcmToken": "device-fcm-token",
  "secretToken": "shared-auth-token",
  "createdAt": "timestamp",
  "pairedAt": "timestamp"
}
```

### Collection: `requests/{requestId}`

```json
{
  "deviceId": "pairing-code",
  "secretToken": "shared-auth-token",
  "command": "bash: rm -rf /tmp/old",
  "choices": ["Allow", "Deny", "Allow Always"],
  "status": "pending | responded",
  "response": null,
  "createdAt": "timestamp",
  "expiresAt": "timestamp"
}
```

## Flutter App

### Screen 1 — Pairing

- Text field for pairing code + "Connect" button
- On success, saves device config locally and navigates to Screen 2

### Screen 2 — Waiting / Request

- Default state: "Waiting for requests..."
- When request arrives: shows command text + a button for each choice
- After tapping: brief "Sent!" confirmation, back to waiting

## Install Script (Claude Code Side)

### Mac/Linux

```bash
curl -sSL https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.ps1 | iex
```

### What the install script does:

1. Downloads hook script to `~/.yes-claude/hook.sh` (or `.ps1` on Windows)
2. Generates a 6-character pairing code
3. Prints: "Enter this code in the Yes Claude app: ABC123"
4. Waits for pairing (polls Firestore REST API)
5. Saves paired device config to `~/.yes-claude/config.json`
6. Adds the hook entry to `~/.claude/settings.json`

### Hook script (bash + curl):

- Receives permission details from Claude Code
- POST to Firestore REST API to create request doc
- GET in a loop until status changes from `pending`
- Returns the choice to Claude Code

## Security

- Pairing code is one-time, expires after 10 minutes
- Shared secret token generated on pairing, stored locally and in Firestore
- All requests include the token; Firestore security rules reject invalid tokens
- A device can only read/write requests matching its own deviceId

## Edge Cases

- **Timeout:** Each request expires after 5 minutes. Hook returns "Deny" and unblocks Claude Code.
- **App killed:** FCM push wakes the app. If user still doesn't respond, timeout handles it.
- **No internet:** Hook fails to write to Firestore, falls back to Claude Code's default prompt.

## Explicitly NOT in v1

- No request history
- No multi-device / multi-computer
- No auto-approve rules
- No user accounts (just device pairing)
- No settings screen
