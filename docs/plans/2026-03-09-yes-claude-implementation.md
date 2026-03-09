# Yes Claude... Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a mobile app that lets users approve/deny Claude Code permission requests from their phone via push notifications.

**Architecture:** Flutter app + Firebase backend (Firestore relay, Cloud Functions for FCM push, FCM for notifications) + local bash/PowerShell hook scripts installed via curl one-liner. Three components: hook (intercepts Claude Code permissions) → Firebase (relay + push) → app (display + respond).

**Tech Stack:** Flutter/Dart, Firebase (Firestore, Cloud Functions, FCM), Node.js/TypeScript (Cloud Functions), Bash + curl, PowerShell

---

## Parallelization Phases

```
Phase 1: YES-2 (Firebase setup)
    │
    ├── Phase 2a: YES-3 (Cloud Functions)     ── can parallel
    ├── Phase 2b: YES-4 (Flutter scaffolding)  ── can parallel
    ├── Phase 2c: YES-7 (Mac/Linux scripts)    ── can parallel
    └── Phase 2d: YES-8 (Windows scripts)      ── can parallel
                    │
                    ├── Phase 3a: YES-5 (Pairing screen)   ── can parallel
                    └── Phase 3b: YES-6 (Request screen)   ── can parallel
                                    │
                                    └── Phase 4: YES-9 (E2E testing)
```

## Workflow Per Task

Every task follows this workflow:
1. Create worktree: `git worktree add .wormtrees/YES-N-description dev`
2. Work in worktree, commit frequently
3. Push branch: `git push -u origin feature/YES-N-description`
4. Open PR: `gh pr create --base dev --title "YES-N: Description" --assignee davidhir1811`
5. Run `/code-review` on the PR
6. For Flutter UI tasks (YES-5, YES-6): also run `/frontend-design` to review
7. Fix issues, push, re-review until approved
8. Merge: `gh pr merge --squash --delete-branch`
9. Transition Jira to Done (transition `41`)
10. Clean up: `git worktree remove .wormtrees/YES-N-description`

---

## Task 1: YES-2 — Firebase Project Setup + Firestore Schema + Security Rules

**Jira:** YES-2
**Branch:** `feature/YES-2-firebase-setup`
**Depends on:** Nothing (do this first)
**Blocks:** All other tasks

### Prerequisites (Manual — David must do these)

1. Go to Firebase Console → Create project "yes-claude"
2. Enable Firestore Database (start in test mode, we'll add rules)
3. Enable Cloud Messaging (FCM)
4. Add Android app: package `com.yesclaude.app` → download `google-services.json`
5. Add iOS app: bundle ID `com.yesclaude.app` → download `GoogleService-Info.plist`
6. Enable Cloud Functions (requires Blaze plan)
7. Store config files in project (they'll be needed by YES-4)

### Step 1: Create Firebase directory structure

```bash
mkdir -p firebase/functions
```

Create `firebase/.firebaserc`:
```json
{
  "projects": {
    "default": "yes-claude-XXXXX"
  }
}
```

Note: Replace `yes-claude-XXXXX` with actual Firebase project ID.

### Step 2: Create `firebase/firebase.json`

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "functions": {
    "source": "functions"
  }
}
```

### Step 3: Create `firebase/firestore.indexes.json`

```json
{
  "indexes": [
    {
      "collectionGroup": "requests",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "deviceId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

### Step 4: Create Firestore security rules

Create `firebase/firestore.rules`:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Devices: anyone can create (pairing), only matching secret can read/update
    match /devices/{pairingCode} {
      allow create: if true;
      allow read, update: if request.resource.data.secretToken == resource.data.secretToken
                          || request.auth != null;
      allow delete: if false;
    }

    // Requests: only the hook (with valid secret) can create
    // Only the paired device (with valid secret) can read and update
    match /requests/{requestId} {
      allow create: if request.resource.data.secretToken is string
                    && request.resource.data.secretToken.size() > 0;
      allow read: if resource.data.secretToken == request.resource.data.secretToken
                  || request.auth != null;
      allow update: if resource.data.secretToken == request.resource.data.secretToken
                    || request.auth != null;
      allow delete: if false;
    }
  }
}
```

### Step 5: Initialize Cloud Functions

```bash
cd firebase/functions
npm init -y
npm install firebase-admin firebase-functions
npm install -D typescript @types/node
```

Create `firebase/functions/tsconfig.json`:
```json
{
  "compilerOptions": {
    "module": "commonjs",
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "outDir": "lib",
    "sourceMap": true,
    "strict": true,
    "target": "es2017"
  },
  "compileOnSave": true,
  "include": ["src"]
}
```

Update `firebase/functions/package.json` to add:
```json
{
  "main": "lib/index.js",
  "scripts": {
    "build": "tsc",
    "serve": "npm run build && firebase emulators:start --only functions",
    "deploy": "firebase deploy --only functions"
  }
}
```

### Step 6: Create placeholder Cloud Function

Create `firebase/functions/src/index.ts`:
```typescript
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// Placeholder — full implementation in YES-3
export const onRequestCreated = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    functions.logger.info("New request created", { requestId: context.params.requestId });
  });
```

### Step 7: Verify build

```bash
cd firebase/functions && npm run build
```

Expected: Compiles without errors.

### Step 8: Commit and PR

```bash
git add firebase/
git commit -m "YES-2: Firebase project setup with Firestore schema and security rules"
git push -u origin feature/YES-2-firebase-setup
gh pr create --base dev --title "YES-2: Firebase project setup" --assignee davidhir1811
```

Run `/code-review`, fix issues, merge.

---

## Task 2: YES-3 — Cloud Function: FCM Push + Cleanup

**Jira:** YES-3
**Branch:** `feature/YES-3-cloud-functions`
**Depends on:** YES-2
**Phase:** 2a (parallel with YES-4, YES-7, YES-8)

### Step 1: Implement `onRequestCreated` Cloud Function

Modify `firebase/functions/src/index.ts`:
```typescript
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Triggered when a new permission request is created.
 * Looks up the paired device's FCM token and sends a push notification.
 */
export const onRequestCreated = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const data = snap.data();

    if (!data.deviceId) {
      functions.logger.error("Request missing deviceId", { requestId });
      return;
    }

    try {
      // Look up the device's FCM token
      const deviceDoc = await db.collection("devices").doc(data.deviceId).get();
      if (!deviceDoc.exists) {
        functions.logger.error("Device not found", { deviceId: data.deviceId });
        return;
      }

      const deviceData = deviceDoc.data();
      if (!deviceData?.fcmToken) {
        functions.logger.error("Device has no FCM token", { deviceId: data.deviceId });
        return;
      }

      // Send FCM push notification
      await messaging.send({
        token: deviceData.fcmToken,
        notification: {
          title: "Yes Claude...",
          body: data.command || "Permission request",
        },
        data: {
          requestId: requestId,
          command: data.command || "",
          choices: JSON.stringify(data.choices || ["Allow", "Deny"]),
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              contentAvailable: true,
            },
          },
        },
      });

      functions.logger.info("Push notification sent", { requestId, deviceId: data.deviceId });
    } catch (error) {
      functions.logger.error("Failed to send push notification", { requestId, error });
    }
  });

/**
 * Scheduled function to clean up expired requests.
 * Runs every 5 minutes. Marks expired pending requests as denied.
 */
export const cleanupExpiredRequests = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const expired = await db
      .collection("requests")
      .where("status", "==", "pending")
      .where("expiresAt", "<=", now)
      .get();

    if (expired.empty) {
      return;
    }

    const batch = db.batch();
    expired.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: "expired",
        response: "Deny",
      });
    });

    await batch.commit();
    functions.logger.info("Cleaned up expired requests", { count: expired.size });
  });
```

### Step 2: Verify build

```bash
cd firebase/functions && npm run build
```

Expected: Compiles without errors.

### Step 3: Commit and PR

```bash
git add firebase/functions/
git commit -m "YES-3: Cloud Functions for FCM push and expired request cleanup"
git push -u origin feature/YES-3-cloud-functions
gh pr create --base dev --title "YES-3: Cloud Functions for FCM push + cleanup" --assignee davidhir1811
```

Run `/code-review`, fix issues, merge.

---

## Task 3: YES-4 — Flutter App: Scaffolding + Firebase Integration

**Jira:** YES-4
**Branch:** `feature/YES-4-flutter-scaffolding`
**Depends on:** YES-2
**Phase:** 2b (parallel with YES-3, YES-7, YES-8)

### Step 1: Create Flutter project

```bash
flutter create --org com.yesclaude --project-name yes_claude app
```

This creates the `app/` directory with the Flutter project.

### Step 2: Add FlutterFire dependencies

```bash
cd app
flutter pub add firebase_core cloud_firestore firebase_messaging shared_preferences
```

### Step 3: Add Firebase config files

Copy from Firebase Console:
- `app/android/app/google-services.json`
- `app/ios/Runner/GoogleService-Info.plist`

Update `app/android/build.gradle` to add Google services plugin.
Update `app/android/app/build.gradle`:
- Set `minSdkVersion` to 21
- Add `apply plugin: 'com.google.gms.google-services'`

### Step 4: Create app entry point

Replace `app/lib/main.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/pairing_screen.dart';
import 'screens/request_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const YesClaudeApp());
}

class YesClaudeApp extends StatelessWidget {
  const YesClaudeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yes Claude...',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD97757),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppRouter(),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _loading = true;
  bool _isPaired = false;

  @override
  void initState() {
    super.initState();
    _checkPairing();
  }

  Future<void> _checkPairing() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('deviceId');
    setState(() {
      _isPaired = deviceId != null;
      _loading = false;
    });
  }

  void _onPaired() {
    setState(() {
      _isPaired = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isPaired) {
      return const RequestScreen();
    }
    return PairingScreen(onPaired: _onPaired);
  }
}
```

### Step 5: Create placeholder screens

Create `app/lib/screens/pairing_screen.dart`:
```dart
import 'package:flutter/material.dart';

class PairingScreen extends StatelessWidget {
  final VoidCallback onPaired;

  const PairingScreen({super.key, required this.onPaired});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Pairing Screen — TODO')),
    );
  }
}
```

Create `app/lib/screens/request_screen.dart`:
```dart
import 'package:flutter/material.dart';

class RequestScreen extends StatelessWidget {
  const RequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Request Screen — TODO')),
    );
  }
}
```

### Step 6: Verify it builds

```bash
cd app && flutter analyze && flutter build apk --debug
```

Expected: No analysis errors, APK builds.

### Step 7: Commit and PR

```bash
git add app/
git commit -m "YES-4: Flutter app scaffolding with Firebase integration"
git push -u origin feature/YES-4-flutter-scaffolding
gh pr create --base dev --title "YES-4: Flutter app scaffolding + Firebase" --assignee davidhir1811
```

Run `/code-review`, fix issues, merge.

---

## Task 4: YES-5 — Flutter App: Pairing Screen

**Jira:** YES-5
**Branch:** `feature/YES-5-pairing-screen`
**Depends on:** YES-4
**Phase:** 3a (parallel with YES-6)

### Step 1: Implement pairing screen

Replace `app/lib/screens/pairing_screen.dart`:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PairingScreen extends StatefulWidget {
  final VoidCallback onPaired;

  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _pair() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a pairing code');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final deviceDoc = db.collection('devices').doc(code);
      final snapshot = await deviceDoc.get();

      if (!snapshot.exists) {
        setState(() {
          _error = 'Invalid pairing code. Check and try again.';
          _loading = false;
        });
        return;
      }

      // Request FCM token
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final fcmToken = await messaging.getToken();

      if (fcmToken == null) {
        setState(() {
          _error = 'Failed to get push notification token.';
          _loading = false;
        });
        return;
      }

      // Update device doc with FCM token and mark as paired
      await deviceDoc.update({
        'fcmToken': fcmToken,
        'pairedAt': FieldValue.serverTimestamp(),
      });

      // Save pairing locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deviceId', code);
      await prefs.setString('secretToken', snapshot.data()!['secretToken']);

      widget.onPaired();
    } catch (e) {
      setState(() {
        _error = 'Pairing failed. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Yes Claude...',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the pairing code from your terminal',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 32,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: '------',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _error,
                ),
                onSubmitted: (_) => _pair(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _loading ? null : _pair,
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 2: Verify build

```bash
cd app && flutter analyze
```

Expected: No analysis errors.

### Step 3: Commit and PR

```bash
git add app/lib/screens/pairing_screen.dart
git commit -m "YES-5: Pairing screen with code entry and FCM token registration"
git push -u origin feature/YES-5-pairing-screen
gh pr create --base dev --title "YES-5: Pairing screen" --assignee davidhir1811
```

Run `/code-review` AND `/frontend-design` (this is a UI screen), fix issues, merge.

---

## Task 5: YES-6 — Flutter App: Permission Request Screen + FCM Handling

**Jira:** YES-6
**Branch:** `feature/YES-6-request-screen`
**Depends on:** YES-4
**Phase:** 3b (parallel with YES-5)

### Step 1: Implement request screen

Replace `app/lib/screens/request_screen.dart`:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  String? _deviceId;
  String? _secretToken;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _setupFCM();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceId = prefs.getString('deviceId');
      _secretToken = prefs.getString('secretToken');
    });
  }

  void _setupFCM() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Firestore listener will pick up the new request automatically
    });

    // Handle background/terminated tap
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // App is already showing — Firestore listener handles it
    });
  }

  Future<void> _respond(String requestId, String choice) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'responded',
        'response': choice,
      });

      setState(() => _sent = true);

      // Brief confirmation, then reset
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _sent = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send response')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yes Claude...'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .where('deviceId', isEqualTo: _deviceId)
            .where('status', isEqualTo: 'pending')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (_sent) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('Sent!', style: TextStyle(fontSize: 24)),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_empty,
                      size: 64, color: Colors.grey.shade600),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for requests...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          final doc = snapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final command = data['command'] as String? ?? 'Unknown command';
          final choices = List<String>.from(data['choices'] ?? ['Allow', 'Deny']);

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Permission Request',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ...choices.map((choice) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _buildChoiceButton(context, doc.id, choice),
                  ),
                )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChoiceButton(BuildContext context, String requestId, String choice) {
    // "Allow" variants get filled/primary style, "Deny" gets outlined/error style
    final isDeny = choice.toLowerCase().contains('deny');

    if (isDeny) {
      return OutlinedButton(
        onPressed: () => _respond(requestId, choice),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        child: Text(
          choice,
          style: TextStyle(
            fontSize: 18,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }

    return FilledButton(
      onPressed: () => _respond(requestId, choice),
      child: Text(choice, style: const TextStyle(fontSize: 18)),
    );
  }
}
```

### Step 2: Update main.dart for background message handling

Add to top of `app/lib/main.dart` (before `main()`):
```dart
// Must be top-level function for background FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // No-op: Firestore listener in RequestScreen handles display
}
```

Update `main()`:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const YesClaudeApp());
}
```

### Step 3: Verify build

```bash
cd app && flutter analyze
```

Expected: No analysis errors.

### Step 4: Commit and PR

```bash
git add app/lib/
git commit -m "YES-6: Permission request screen with FCM handling"
git push -u origin feature/YES-6-request-screen
gh pr create --base dev --title "YES-6: Permission request screen + FCM" --assignee davidhir1811
```

Run `/code-review` AND `/frontend-design` (this is the main UI screen), fix issues, merge.

---

## Task 6: YES-7 — Install Script + Hook Script (Mac/Linux)

**Jira:** YES-7
**Branch:** `feature/YES-7-install-macos-linux`
**Depends on:** YES-2
**Phase:** 2c (parallel with YES-3, YES-4, YES-8)

### Important: Firebase REST API

The hook scripts use Firestore REST API. The base URL format is:
```
https://firestore.googleapis.com/v1/projects/PROJECT_ID/databases/(default)/documents
```

For unauthenticated access matching our security rules, requests include the `secretToken` field in the document data.

### Step 1: Create install script

Create `install.sh` (project root):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Yes Claude... Installer for Mac/Linux
# Usage: curl -sSL https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.sh | bash

INSTALL_DIR="$HOME/.yes-claude"
HOOK_URL="https://raw.githubusercontent.com/davidhir1811/yes-claude/main/hook.sh"
FIREBASE_PROJECT="yes-claude-XXXXX"  # TODO: Replace with actual project ID
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

echo "==================================="
echo "  Yes Claude... Installer"
echo "==================================="
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download hook script
echo "Downloading hook script..."
curl -sSL "$HOOK_URL" -o "$INSTALL_DIR/hook.sh"
chmod +x "$INSTALL_DIR/hook.sh"

# Generate 6-character pairing code
PAIRING_CODE=$(head -c 3 /dev/urandom | xxd -p | tr 'a-f' 'A-F' | head -c 6)

# Generate shared secret token
SECRET_TOKEN=$(head -c 32 /dev/urandom | xxd -p)

# Create device doc in Firestore
echo "Registering device..."
CREATE_RESPONSE=$(curl -s -X POST \
  "${FIRESTORE_BASE}/devices?documentId=${PAIRING_CODE}" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"secretToken\": {\"stringValue\": \"${SECRET_TOKEN}\"},
      \"fcmToken\": {\"stringValue\": \"\"},
      \"createdAt\": {\"timestampValue\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
      \"pairedAt\": {\"nullValue\": null}
    }
  }")

if echo "$CREATE_RESPONSE" | grep -q "error"; then
  echo "ERROR: Failed to register device. Check your internet connection."
  echo "$CREATE_RESPONSE"
  exit 1
fi

echo ""
echo "==================================="
echo "  Enter this code in the app:"
echo ""
echo "        ${PAIRING_CODE}"
echo ""
echo "==================================="
echo ""
echo "Waiting for pairing..."

# Poll until FCM token is registered (device is paired)
TIMEOUT=600  # 10 minutes
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  DEVICE_DOC=$(curl -s "${FIRESTORE_BASE}/devices/${PAIRING_CODE}")
  FCM_TOKEN=$(echo "$DEVICE_DOC" | grep -o '"fcmToken"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

  if [ -n "$FCM_TOKEN" ] && [ "$FCM_TOKEN" != "" ]; then
    echo "Paired successfully!"
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "ERROR: Pairing timed out after 10 minutes."
  exit 1
fi

# Save config
cat > "$INSTALL_DIR/config.json" << EOF
{
  "deviceId": "${PAIRING_CODE}",
  "secretToken": "${SECRET_TOKEN}",
  "firebaseProject": "${FIREBASE_PROJECT}"
}
EOF

chmod 600 "$INSTALL_DIR/config.json"

# Add hook to Claude Code settings
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if [ -f "$CLAUDE_SETTINGS" ]; then
  # Check if settings already has hooks
  if command -v python3 &> /dev/null; then
    python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS', 'r') as f:
    settings = json.load(f)
hook_entry = {
    'type': 'command',
    'command': '$INSTALL_DIR/hook.sh'
}
if 'hooks' not in settings:
    settings['hooks'] = {}
if 'permissionPrompt' not in settings['hooks']:
    settings['hooks']['permissionPrompt'] = []
# Check if already installed
existing = [h for h in settings['hooks']['permissionPrompt'] if h.get('command') == '$INSTALL_DIR/hook.sh']
if not existing:
    settings['hooks']['permissionPrompt'].append(hook_entry)
with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
"
  else
    echo "WARNING: python3 not found. Please manually add the hook to $CLAUDE_SETTINGS"
  fi
else
  cat > "$CLAUDE_SETTINGS" << SETTINGS
{
  "hooks": {
    "permissionPrompt": [
      {
        "type": "command",
        "command": "$INSTALL_DIR/hook.sh"
      }
    ]
  }
}
SETTINGS
fi

echo ""
echo "Installation complete!"
echo "Yes Claude... is now active. Permission requests will be sent to your phone."
echo ""
echo "Config saved to: $INSTALL_DIR/config.json"
echo "Hook installed to: $INSTALL_DIR/hook.sh"
```

### Step 2: Create hook script

Create `hook.sh` (project root):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Yes Claude... Hook Script
# Called by Claude Code when a permission prompt is needed.
# Reads permission details from stdin, sends to Firestore, waits for response.

CONFIG_FILE="$HOME/.yes-claude/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Yes Claude not configured. Run the installer first." >&2
  exit 1
fi

# Read config
DEVICE_ID=$(grep -o '"deviceId":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
SECRET_TOKEN=$(grep -o '"secretToken":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
FIREBASE_PROJECT=$(grep -o '"firebaseProject":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

# Read permission details from stdin (JSON from Claude Code)
INPUT=$(cat)

# Extract the command/tool description from the hook input
COMMAND=$(echo "$INPUT" | grep -o '"tool"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "Unknown")
TOOL_INPUT=$(echo "$INPUT" | grep -o '"input"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")

DISPLAY_COMMAND="${COMMAND}: ${TOOL_INPUT}"

# Build choices array based on what Claude Code expects
CHOICES='["Allow", "Deny", "Allow Always"]'

# Generate request ID
REQUEST_ID=$(head -c 8 /dev/urandom | xxd -p)

# Calculate expiry (5 minutes from now)
EXPIRES_AT=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

# Create request in Firestore
curl -s -X POST \
  "${FIRESTORE_BASE}/requests?documentId=${REQUEST_ID}" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"deviceId\": {\"stringValue\": \"${DEVICE_ID}\"},
      \"secretToken\": {\"stringValue\": \"${SECRET_TOKEN}\"},
      \"command\": {\"stringValue\": $(echo "$DISPLAY_COMMAND" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')},
      \"choices\": {\"arrayValue\": {\"values\": [
        {\"stringValue\": \"Allow\"},
        {\"stringValue\": \"Deny\"},
        {\"stringValue\": \"Allow Always\"}
      ]}},
      \"status\": {\"stringValue\": \"pending\"},
      \"response\": {\"nullValue\": null},
      \"createdAt\": {\"timestampValue\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
      \"expiresAt\": {\"timestampValue\": \"${EXPIRES_AT}\"}
    }
  }" > /dev/null

# Poll for response (timeout: 5 minutes)
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  RESPONSE_DOC=$(curl -s "${FIRESTORE_BASE}/requests/${REQUEST_ID}")
  STATUS=$(echo "$RESPONSE_DOC" | grep -o '"status"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

  if [ "$STATUS" = "responded" ] || [ "$STATUS" = "expired" ]; then
    RESPONSE=$(echo "$RESPONSE_DOC" | grep -o '"response"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

    # Map response to Claude Code expected output
    case "$RESPONSE" in
      "Allow")
        echo '{"allow": true}'
        exit 0
        ;;
      "Allow Always")
        echo '{"allow": true, "always": true}'
        exit 0
        ;;
      "Deny"|*)
        echo '{"allow": false}'
        exit 0
        ;;
    esac
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

# Timeout — deny by default
echo '{"allow": false}'
exit 0
```

### Step 3: Make hook executable

```bash
chmod +x install.sh hook.sh
```

### Step 4: Commit and PR

```bash
git add install.sh hook.sh
git commit -m "YES-7: Install script and hook script for Mac/Linux"
git push -u origin feature/YES-7-install-macos-linux
gh pr create --base dev --title "YES-7: Install + hook scripts (Mac/Linux)" --assignee davidhir1811
```

Run `/code-review`, fix issues, merge.

---

## Task 7: YES-8 — Install Script + Hook Script (Windows PowerShell)

**Jira:** YES-8
**Branch:** `feature/YES-8-install-windows`
**Depends on:** YES-2
**Phase:** 2d (parallel with YES-3, YES-4, YES-7)

### Step 1: Create PowerShell install script

Create `install.ps1` (project root):
```powershell
# Yes Claude... Installer for Windows
# Usage: irm https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$InstallDir = "$env:USERPROFILE\.yes-claude"
$HookUrl = "https://raw.githubusercontent.com/davidhir1811/yes-claude/main/hook.ps1"
$FirebaseProject = "yes-claude-XXXXX"  # TODO: Replace with actual project ID
$FirestoreBase = "https://firestore.googleapis.com/v1/projects/$FirebaseProject/databases/(default)/documents"

Write-Host "==================================="
Write-Host "  Yes Claude... Installer"
Write-Host "==================================="
Write-Host ""

# Create install directory
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Download hook script
Write-Host "Downloading hook script..."
Invoke-RestMethod -Uri $HookUrl -OutFile "$InstallDir\hook.ps1"

# Generate 6-character pairing code
$PairingCode = -join ((65..90) | Get-Random -Count 6 | ForEach-Object { [char]$_ })

# Generate shared secret token
$SecretToken = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

# Create device doc in Firestore
Write-Host "Registering device..."
$Body = @{
    fields = @{
        secretToken = @{ stringValue = $SecretToken }
        fcmToken = @{ stringValue = "" }
        createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        pairedAt = @{ nullValue = $null }
    }
} | ConvertTo-Json -Depth 5

try {
    Invoke-RestMethod -Uri "$FirestoreBase/devices?documentId=$PairingCode" `
        -Method Post -ContentType "application/json" -Body $Body | Out-Null
} catch {
    Write-Host "ERROR: Failed to register device. Check your internet connection."
    Write-Host $_.Exception.Message
    exit 1
}

Write-Host ""
Write-Host "==================================="
Write-Host "  Enter this code in the app:"
Write-Host ""
Write-Host "        $PairingCode"
Write-Host ""
Write-Host "==================================="
Write-Host ""
Write-Host "Waiting for pairing..."

# Poll until FCM token is registered
$Timeout = 600
$Elapsed = 0
$Paired = $false

while ($Elapsed -lt $Timeout) {
    try {
        $DeviceDoc = Invoke-RestMethod -Uri "$FirestoreBase/devices/$PairingCode"
        $FcmToken = $DeviceDoc.fields.fcmToken.stringValue

        if ($FcmToken -and $FcmToken -ne "") {
            Write-Host "Paired successfully!"
            $Paired = $true
            break
        }
    } catch {}

    Start-Sleep -Seconds 2
    $Elapsed += 2
}

if (-not $Paired) {
    Write-Host "ERROR: Pairing timed out after 10 minutes."
    exit 1
}

# Save config
$Config = @{
    deviceId = $PairingCode
    secretToken = $SecretToken
    firebaseProject = $FirebaseProject
} | ConvertTo-Json

Set-Content -Path "$InstallDir\config.json" -Value $Config

# Add hook to Claude Code settings
$ClaudeSettings = "$env:USERPROFILE\.claude\settings.json"
$ClaudeDir = Split-Path $ClaudeSettings

if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
}

$HookEntry = @{
    type = "command"
    command = "powershell -File `"$InstallDir\hook.ps1`""
}

if (Test-Path $ClaudeSettings) {
    $Settings = Get-Content $ClaudeSettings | ConvertFrom-Json
    if (-not $Settings.hooks) {
        $Settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
    }
    if (-not $Settings.hooks.permissionPrompt) {
        $Settings.hooks | Add-Member -NotePropertyName "permissionPrompt" -NotePropertyValue @()
    }
    $Existing = $Settings.hooks.permissionPrompt | Where-Object { $_.command -like "*yes-claude*" }
    if (-not $Existing) {
        $Settings.hooks.permissionPrompt += $HookEntry
    }
    $Settings | ConvertTo-Json -Depth 10 | Set-Content $ClaudeSettings
} else {
    @{
        hooks = @{
            permissionPrompt = @($HookEntry)
        }
    } | ConvertTo-Json -Depth 10 | Set-Content $ClaudeSettings
}

Write-Host ""
Write-Host "Installation complete!"
Write-Host "Yes Claude... is now active. Permission requests will be sent to your phone."
Write-Host ""
Write-Host "Config saved to: $InstallDir\config.json"
Write-Host "Hook installed to: $InstallDir\hook.ps1"
```

### Step 2: Create PowerShell hook script

Create `hook.ps1` (project root):
```powershell
# Yes Claude... Hook Script (Windows)
# Called by Claude Code when a permission prompt is needed.

$ErrorActionPreference = "Stop"

$ConfigFile = "$env:USERPROFILE\.yes-claude\config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Yes Claude not configured. Run the installer first."
    exit 1
}

$Config = Get-Content $ConfigFile | ConvertFrom-Json
$DeviceId = $Config.deviceId
$SecretToken = $Config.secretToken
$FirebaseProject = $Config.firebaseProject
$FirestoreBase = "https://firestore.googleapis.com/v1/projects/$FirebaseProject/databases/(default)/documents"

# Read permission details from stdin
$Input = $input | Out-String

# Extract command info
try {
    $InputObj = $Input | ConvertFrom-Json
    $Command = $InputObj.tool
    $ToolInput = $InputObj.input
    $DisplayCommand = "${Command}: ${ToolInput}"
} catch {
    $DisplayCommand = "Unknown command"
}

# Generate request ID
$RequestId = -join ((48..57) + (97..102) | Get-Random -Count 16 | ForEach-Object { [char]$_ })

# Calculate expiry
$ExpiresAt = (Get-Date).AddMinutes(5).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Create request in Firestore
$Body = @{
    fields = @{
        deviceId = @{ stringValue = $DeviceId }
        secretToken = @{ stringValue = $SecretToken }
        command = @{ stringValue = $DisplayCommand }
        choices = @{
            arrayValue = @{
                values = @(
                    @{ stringValue = "Allow" },
                    @{ stringValue = "Deny" },
                    @{ stringValue = "Allow Always" }
                )
            }
        }
        status = @{ stringValue = "pending" }
        response = @{ nullValue = $null }
        createdAt = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
        expiresAt = @{ timestampValue = $ExpiresAt }
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$FirestoreBase/requests?documentId=$RequestId" `
    -Method Post -ContentType "application/json" -Body $Body | Out-Null

# Poll for response (timeout: 5 minutes)
$Timeout = 300
$Elapsed = 0

while ($Elapsed -lt $Timeout) {
    try {
        $ResponseDoc = Invoke-RestMethod -Uri "$FirestoreBase/requests/$RequestId"
        $Status = $ResponseDoc.fields.status.stringValue

        if ($Status -eq "responded" -or $Status -eq "expired") {
            $Response = $ResponseDoc.fields.response.stringValue

            switch ($Response) {
                "Allow" { Write-Output '{"allow": true}'; exit 0 }
                "Allow Always" { Write-Output '{"allow": true, "always": true}'; exit 0 }
                default { Write-Output '{"allow": false}'; exit 0 }
            }
        }
    } catch {}

    Start-Sleep -Seconds 2
    $Elapsed += 2
}

# Timeout — deny by default
Write-Output '{"allow": false}'
exit 0
```

### Step 3: Commit and PR

```bash
git add install.ps1 hook.ps1
git commit -m "YES-8: Install script and hook script for Windows PowerShell"
git push -u origin feature/YES-8-install-windows
gh pr create --base dev --title "YES-8: Install + hook scripts (Windows)" --assignee davidhir1811
```

Run `/code-review`, fix issues, merge.

---

## Task 8: YES-9 — End-to-End Integration Testing

**Jira:** YES-9
**Branch:** `feature/YES-9-e2e-testing`
**Depends on:** All previous tasks
**Phase:** 4

### Step 1: Create E2E test checklist document

Create `docs/e2e-test-checklist.md`:
```markdown
# End-to-End Test Checklist

## Prerequisites
- [ ] Firebase project deployed (Firestore rules, Cloud Functions)
- [ ] Flutter app built for target platform
- [ ] Install script accessible from GitHub raw URL

## Test Scenarios

### 1. Happy Path — Mac + Android
- [ ] Run `curl -sSL .../install.sh | bash`
- [ ] Pairing code displayed in terminal
- [ ] Enter code in app → "Paired successfully!"
- [ ] Trigger Claude Code permission prompt
- [ ] Phone receives push notification
- [ ] App shows command + buttons
- [ ] Tap "Allow" → Claude Code unblocks and proceeds
- [ ] Tap "Deny" on next prompt → Claude Code shows denied

### 2. Happy Path — Mac + iOS
- [ ] Same as above on iOS device/simulator

### 3. Happy Path — Linux + Android
- [ ] Same as above on Linux

### 4. Happy Path — Windows + Android
- [ ] Run `irm .../install.ps1 | iex`
- [ ] Same flow as above

### 5. Timeout/Expiry
- [ ] Trigger permission prompt
- [ ] Do NOT respond on phone
- [ ] After 5 minutes, hook returns Deny
- [ ] Claude Code continues with denial

### 6. Security
- [ ] Try reading another device's requests → rejected
- [ ] Try updating with wrong secretToken → rejected

### 7. Sequential Requests
- [ ] Trigger first prompt → respond Allow
- [ ] Trigger second prompt → respond Deny
- [ ] Both handled correctly in sequence

### 8. App States
- [ ] App in foreground → request shows immediately
- [ ] App in background → push notification appears → tap opens request
- [ ] App terminated → push notification appears → tap opens app with request

### 9. No Internet
- [ ] Disconnect internet on computer
- [ ] Trigger permission prompt → hook fails gracefully
- [ ] Claude Code falls back to default prompt
```

### Step 2: Run through checklist manually

Execute each test scenario and document results.

### Step 3: Commit and PR

```bash
git add docs/e2e-test-checklist.md
git commit -m "YES-9: E2E test checklist and results"
git push -u origin feature/YES-9-e2e-testing
gh pr create --base dev --title "YES-9: E2E testing checklist" --assignee davidhir1811
```

Run `/code-review`, fix any issues discovered during testing, merge.

---

## Post-Completion

After all tasks are merged to dev:
1. Update `current_progress.md` with completion status
2. Tag a release: `git tag v1.0.0`
3. Deploy Cloud Functions: `cd firebase && firebase deploy`
4. Build release APK/IPA for app stores
5. Ensure install scripts point to correct Firebase project ID
