# Yes Claude v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add web app, progressive auth, rate limiting, multi-session support, response validation, history archival, multi-CLI adapter pattern, and admin scripts.

**Architecture:** Progressive Firebase Auth (anonymous → Google/Apple) with tiered rate limits enforced by Cloud Functions. Hook scripts refactored into core + adapter modules. Flutter web deployed via Firebase Hosting. All requests archived to user history subcollection.

**Tech Stack:** Flutter + FlutterFire, Firebase Auth/Firestore/Functions/Hosting/FCM, google_sign_in, sign_in_with_apple, Bash/PowerShell

---

## Dependency Graph

```
Phase 1: YES-11 (Auth + User model)
    ↓
Phase 2: YES-12 (Rate limiting) + YES-13 (Multi-session) + YES-16 (Response validation)  [parallel]
    ↓
Phase 3: YES-14 (Web app) + YES-15 (Hook refactoring) + YES-17 (History) + YES-18 (Admin) + YES-19 (Upgrade UI)  [parallel]
    ↓
Phase 4: YES-20 (E2E testing v2)
```

---

### Task 1: YES-11 — Firebase Auth + User Model

**Files:**
- Modify: `app/pubspec.yaml` — add firebase_auth, google_sign_in, sign_in_with_apple
- Create: `app/lib/services/auth_service.dart` — auth logic
- Modify: `app/lib/main.dart` — anonymous sign-in on startup
- Modify: `app/lib/screens/pairing_screen.dart` — link device to uid
- Modify: `firebase/firestore.rules` — add users collection + auth rules
- Modify: `firebase/functions/src/index.ts` — create user doc on first request
- Create: `firebase/firestore-seed.js` — seed config/tiers document

**Step 1:** Add dependencies to `app/pubspec.yaml`:
```yaml
  firebase_auth: ^5.5.1
  google_sign_in: ^6.2.2
  sign_in_with_apple: ^7.0.1
```

**Step 2:** Create `app/lib/services/auth_service.dart`:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../logger.dart';

class AuthService {
  static const _log = Log('AuthService');
  static final instance = AuthService._();
  AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  /// Sign in anonymously on first launch. Returns uid.
  Future<String> ensureSignedIn() async {
    if (_auth.currentUser != null) return _auth.currentUser!.uid;
    final cred = await _auth.signInAnonymously();
    _log.info('Signed in anonymously: ${cred.user!.uid}');
    await _ensureUserDoc(cred.user!.uid);
    return cred.user!.uid;
  }

  /// Link anonymous account to Google. Returns uid.
  Future<String> linkWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    try {
      await _auth.currentUser!.linkWithCredential(credential);
      _log.info('Linked anonymous account to Google');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        // Account exists — sign in directly
        await _auth.signInWithCredential(credential);
        _log.info('Signed in with existing Google account');
      } else {
        rethrow;
      }
    }
    await _updateTier('free');
    return _auth.currentUser!.uid;
  }

  Future<void> _ensureUserDoc(String uid) async {
    final doc = _db.collection('users').doc(uid);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'tier': 'anonymous',
        'dailyCount': 0,
        'dailyResetAt': Timestamp.now(),
        'monthlyCount': 0,
        'monthlyResetAt': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'devices': [],
      });
    }
  }

  Future<void> _updateTier(String tier) async {
    await _db.collection('users').doc(uid).update({'tier': tier});
  }

  Future<void> linkDevice(String deviceId) async {
    await _db.collection('users').doc(uid).update({
      'devices': FieldValue.arrayUnion([deviceId]),
    });
  }
}
```

**Step 3:** Modify `app/lib/main.dart` — add anonymous sign-in before routing:
- After `Firebase.initializeApp()`, call `await AuthService.instance.ensureSignedIn()`
- Pass uid down to screens or let them access via `AuthService.instance.uid`

**Step 4:** Modify `app/lib/screens/pairing_screen.dart`:
- After successful pairing, call `AuthService.instance.linkDevice(code)` to associate device with user

**Step 5:** Update Firestore rules (`firebase/firestore.rules`) with the rules from the v2 design doc:
- `config/{doc}` — read-only
- `users/{uid}` — auth-protected, own uid only
- `users/{uid}/history/{requestId}` — read only, Cloud Function writes
- `requests/{requestId}` — validate response in choices array on update

**Step 6:** Create `firebase/firestore-seed.js` — script to seed the config/tiers document:
```javascript
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function seed() {
  await db.collection('config').doc('tiers').set({
    anonymous: { dailyLimit: 5 },
    free: { dailyLimit: 20 },
    premium: { monthlyLimit: 1000 },
  });
  console.log('Seeded config/tiers');
}
seed().then(() => process.exit(0));
```

**Step 7:** Commit:
```
git add -A && git commit -m "feat(YES-11): Firebase Auth + user model + updated Firestore rules"
```

---

### Task 2: YES-12 — Rate Limiting

**Files:**
- Modify: `firebase/functions/src/index.ts` — add rate limit check, counter increment, reset functions

**Step 1:** In `onRequestCreated`, after fetching the device doc, look up the user:
```typescript
// After existing device/token validation...
const userQuery = await db.collection('users')
  .where('devices', 'array-contains', deviceId)
  .limit(1)
  .get();

if (!userQuery.empty) {
  const userDoc = userQuery.docs[0];
  const userData = userDoc.data();
  const tier = userData.tier || 'anonymous';

  // Fetch tier limits
  const tierConfig = await db.collection('config').doc('tiers').get();
  const limits = tierConfig.data()?.[tier];

  if (limits) {
    const now = new Date();
    let isOverLimit = false;

    if (limits.dailyLimit !== undefined) {
      const resetAt = userData.dailyResetAt?.toDate() || new Date(0);
      const count = resetAt < new Date(now.toISOString().split('T')[0]) ? 0 : userData.dailyCount || 0;
      isOverLimit = count >= limits.dailyLimit;
    }
    if (limits.monthlyLimit !== undefined) {
      const resetAt = userData.monthlyResetAt?.toDate() || new Date(0);
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
      const count = resetAt < monthStart ? 0 : userData.monthlyCount || 0;
      isOverLimit = count >= limits.monthlyLimit;
    }

    if (isOverLimit) {
      // Auto-deny with rate limited flag
      await requestRef.update({
        status: 'responded',
        response: 'Deny',
        rateLimited: true,
      });
      logger.info(`Rate limited request ${requestId} for user ${userDoc.id} (tier: ${tier})`);
      return;
    }

    // Increment counters
    await userDoc.ref.update({
      dailyCount: admin.firestore.FieldValue.increment(1),
      monthlyCount: admin.firestore.FieldValue.increment(1),
    });
  }
}
```

**Step 2:** Add scheduled counter reset functions:
```typescript
export const resetDailyCounters = onSchedule('every day 00:00', async () => {
  const batch = db.batch();
  const users = await db.collection('users').get();
  for (const doc of users.docs) {
    batch.update(doc.ref, {
      dailyCount: 0,
      dailyResetAt: admin.firestore.Timestamp.now(),
    });
  }
  await batch.commit();
  logger.info(`Reset daily counters for ${users.size} users`);
});

export const resetMonthlyCounters = onSchedule('1 of month 00:00', async () => {
  const batch = db.batch();
  const users = await db.collection('users').get();
  for (const doc of users.docs) {
    batch.update(doc.ref, {
      monthlyCount: 0,
      monthlyResetAt: admin.firestore.Timestamp.now(),
    });
  }
  await batch.commit();
  logger.info(`Reset monthly counters for ${users.size} users`);
});
```

**Step 3:** Commit:
```
git commit -m "feat(YES-12): rate limiting in Cloud Functions with daily/monthly counters"
```

---

### Task 3: YES-13 — Multi-Session Support

**Files:**
- Modify: `hook.sh` — send sessionLabel, machineId, source
- Modify: `hook.ps1` — same
- Modify: `app/lib/screens/request_screen.dart` — show list of pending requests with session info

**Step 1:** In `hook.sh`, add session context to the Firestore request body:
```bash
SESSION_LABEL=$(basename "$PWD")
MACHINE_ID=$(hostname)
SOURCE="claude"
```
Add these as fields in the Firestore POST body alongside existing fields.

**Step 2:** Same in `hook.ps1`:
```powershell
$SessionLabel = Split-Path -Leaf (Get-Location)
$MachineId = $env:COMPUTERNAME
$Source = "claude"
```

**Step 3:** In `request_screen.dart`, change from `.limit(1)` to showing all pending requests:
- Remove `limit(1)` from the Firestore query
- Change `StreamBuilder` to render a `ListView` of request cards
- Each card shows: `machineId · sessionLabel` header + command + buttons
- Keep the same button styles and response logic

**Step 4:** Commit:
```
git commit -m "feat(YES-13): multi-session support with session labels in hooks and app"
```

---

### Task 4: YES-14 — Web App + Firebase Hosting

**Files:**
- Modify: `app/web/index.html` — add Firebase SDK config
- Create: `app/web/firebase-messaging-sw.js` — service worker for web push
- Modify: `app/web/manifest.json` — update PWA metadata
- Modify: `firebase/firebase.json` — add hosting config
- Create: `scripts/deploy-web.sh` — build + deploy script

**Step 1:** Update `app/web/index.html` with Firebase config scripts (firebase-app, firebase-messaging).

**Step 2:** Create `app/web/firebase-messaging-sw.js`:
```javascript
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  // Firebase config will be injected during build
  apiKey: '...',
  projectId: 'yes-claude-XXXXX',
  messagingSenderId: '...',
  appId: '...',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Yes Claude...';
  const body = payload.notification?.body || 'Permission request';
  return self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    data: payload.data,
  });
});
```

**Step 3:** Update `app/web/manifest.json`:
```json
{
  "name": "Yes Claude...",
  "short_name": "YesClaude",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#131316",
  "theme_color": "#D97757",
  "description": "Approve Claude Code permissions from your phone or browser",
  "orientation": "portrait",
  "prefer_related_applications": false,
  "icons": [...]
}
```

**Step 4:** Add Firebase Hosting to `firebase/firebase.json`:
```json
{
  "hosting": {
    "public": "../app/build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
```

**Step 5:** Create `scripts/deploy-web.sh`:
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
echo "Building Flutter web..."
cd app && flutter build web --release
cd ../firebase
echo "Deploying to Firebase Hosting..."
firebase deploy --only hosting
echo "Done! Web app deployed."
```

**Step 6:** Commit:
```
git commit -m "feat(YES-14): Flutter web PWA with Firebase Hosting and FCM service worker"
```

---

### Task 5: YES-15 — Hook Refactoring (Adapter Pattern)

**Files:**
- Create: `hooks/core.sh` — shared Firestore API, polling, config
- Create: `hooks/adapters/claude.sh` — Claude-specific stdin/stdout
- Modify: `hook.sh` — thin entry point that sources core + adapter
- Create: `hooks/core.ps1`, `hooks/adapters/claude.ps1`, modify `hook.ps1`
- Modify: `install.sh` — accept `--cli` flag
- Modify: `install.ps1` — accept `-Cli` parameter

**Step 1:** Extract shared logic from `hook.sh` into `hooks/core.sh`:
- Config reading (`~/.yes-claude/config.json`)
- Firestore REST API functions (create_request, poll_response)
- Request ID generation, expiry calculation
- Session context (hostname, PWD)

**Step 2:** Create `hooks/adapters/claude.sh`:
- Parse Claude's stdin format: `{"tool": "X", "input": "Y"}`
- Format Claude's stdout: `{"allow": true/false, "always": true/false}`
- Define choices: `["Allow", "Deny", "Allow Always"]`

**Step 3:** Simplify `hook.sh` to:
```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hooks/core.sh"
source "$SCRIPT_DIR/hooks/adapters/${YES_CLAUDE_CLI:-claude}.sh"
run_hook
```

**Step 4:** Same refactoring for PowerShell (`core.ps1`, `adapters/claude.ps1`).

**Step 5:** Update `install.sh` to accept `--cli` flag:
```bash
CLI_TYPE="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cli) CLI_TYPE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
```
Save `CLI_TYPE` to config.json as `"cli": "claude"`.

**Step 6:** Download hooks directory structure instead of single file.

**Step 7:** Commit:
```
git commit -m "feat(YES-15): refactor hooks into core + adapter pattern for multi-CLI support"
```

---

### Task 6: YES-16 — Response Validation

**Files:**
- Modify: `firebase/firestore.rules` — validate response in choices
- Modify: `hook.sh` — validate response before returning
- Modify: `hook.ps1` — same

**Step 1:** Firestore rules already updated in YES-11. Verify the response validation rule:
```
allow update: if request.resource.data.status == 'responded'
              && request.resource.data.response is string
              && request.resource.data.response in resource.data.choices;
```

**Step 2:** In `hook.sh`, after reading the response, validate against known choices:
```bash
case "$RESPONSE" in
  "Allow") echo '{"allow": true}' ;;
  "Allow Always") echo '{"allow": true, "always": true}' ;;
  *) echo '{"allow": false}' ;;
esac
```
(Already exists in v1, but verify it's in the adapter module after refactoring.)

**Step 3:** Commit:
```
git commit -m "feat(YES-16): response validation at Firestore rules and hook layer"
```

---

### Task 7: YES-17 — History Archival

**Files:**
- Modify: `firebase/functions/src/index.ts` — add onRequestUpdated trigger

**Step 1:** Add a Cloud Function that triggers on request status change:
```typescript
export const archiveToHistory = onDocumentUpdated('requests/{requestId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (!before || !after) return;
  if (before.status === 'pending' && after.status === 'responded' && !after.rateLimited) {
    // Find user by device
    const userQuery = await db.collection('users')
      .where('devices', 'array-contains', after.deviceId)
      .limit(1)
      .get();

    if (userQuery.empty) return;
    const uid = userQuery.docs[0].id;

    await db.collection('users').doc(uid).collection('history').doc(event.params.requestId).set({
      command: after.command || '',
      choices: after.choices || [],
      response: after.response || '',
      source: after.source || 'claude',
      sessionLabel: after.sessionLabel || '',
      machineId: after.machineId || '',
      deviceId: after.deviceId || '',
      createdAt: after.createdAt || null,
      respondedAt: admin.firestore.Timestamp.now(),
    });

    logger.info(`Archived request ${event.params.requestId} to history for user ${uid}`);
  }
});
```

**Step 2:** Commit:
```
git commit -m "feat(YES-17): archive responded requests to user history subcollection"
```

---

### Task 8: YES-18 — Admin Scripts

**Files:**
- Create: `scripts/admin.sh` — admin CLI for tier management

**Step 1:** Create `scripts/admin.sh`:
```bash
#!/usr/bin/env bash
# Yes Claude... Admin CLI
# Usage:
#   ./scripts/admin.sh get-limits
#   ./scripts/admin.sh set-limits --anonymous 5 --free 20 --premium 1000
#   ./scripts/admin.sh user-info <uid>
#   ./scripts/admin.sh set-tier <uid> <tier>
#   ./scripts/admin.sh reset-counter <uid>

set -e
FIREBASE_PROJECT="yes-claude-XXXXX"
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/$FIREBASE_PROJECT/databases/(default)/documents"

# Requires: gcloud auth application-default login (for authenticated access)
TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null || echo "")

case "${1:-help}" in
  get-limits)
    curl -s -H "Authorization: Bearer $TOKEN" "$FIRESTORE_BASE/config/tiers" | python3 -m json.tool
    ;;
  set-limits)
    # Parse --anonymous N --free N --premium N flags and PATCH to Firestore
    shift
    # ... (build JSON body from args, PATCH to config/tiers)
    ;;
  user-info)
    curl -s -H "Authorization: Bearer $TOKEN" "$FIRESTORE_BASE/users/$2" | python3 -m json.tool
    ;;
  set-tier)
    # PATCH users/$2 with tier=$3
    ;;
  reset-counter)
    # PATCH users/$2 with dailyCount=0
    ;;
  *)
    echo "Usage: admin.sh {get-limits|set-limits|user-info|set-tier|reset-counter}"
    ;;
esac
```

**Step 2:** Make executable and commit:
```
chmod +x scripts/admin.sh
git commit -m "feat(YES-18): admin CLI scripts for tier and user management"
```

---

### Task 9: YES-19 — Upgrade Prompt UI

**Files:**
- Modify: `app/lib/screens/request_screen.dart` — show upgrade prompt when rate limited

**Step 1:** In the request screen, detect `rateLimited: true` on the latest request:
- When a request comes in with `rateLimited: true`, show an overlay/bottom sheet:
  - Anonymous users: "Daily limit reached. Sign in to continue." + Google/Apple buttons
  - Free users: "Daily limit reached. Upgrade to Premium." + upgrade button (placeholder)
- Use `AuthService.instance.linkWithGoogle()` for the sign-in flow
- After sign-in, tier changes from `anonymous` to `free`, counters continue

**Step 2:** Commit:
```
git commit -m "feat(YES-19): upgrade prompt when rate limited"
```

---

### Task 10: YES-20 — E2E Testing v2

**Depends on:** All above tasks + Firebase Console setup (manual)

**Test matrix:**
- Install hook on Mac → pair with Android app → send multiple requests → verify multi-session labels
- Hit anonymous rate limit (5 requests) → verify auto-deny + upgrade prompt
- Sign in with Google → verify tier upgrade to free → 20 requests/day
- Test web PWA: open in Chrome → pair → approve request → verify web push
- Test response validation: try to write invalid response directly to Firestore → verify rejection
- Test expired request cleanup still works
- Test admin scripts: get-limits, set-tier
- Verify history documents in Firestore after responding

---

## Parallelization Strategy

| Phase | Tickets | Dependencies |
|-------|---------|-------------|
| 1 | YES-11 (Auth + User model) | None — foundation for everything |
| 2 | YES-12 + YES-13 + YES-16 | YES-11 (parallel with each other) |
| 3 | YES-14 + YES-15 + YES-17 + YES-18 + YES-19 | YES-12 (parallel with each other) |
| 4 | YES-20 (E2E) | All above + Firebase Console |
