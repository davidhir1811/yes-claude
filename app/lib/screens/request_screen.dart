import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logger.dart';
import '../theme.dart';
import '../widgets/upgrade_prompt.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen>
    with TickerProviderStateMixin {
  static const _log = Log('RequestScreen');
  String? _deviceId;
  bool _sent = false;
  String? _lastResponse;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription? _fgSub;
  StreamSubscription? _openSub;
  StreamSubscription? _tokenRefreshSub;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _setupFCM();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fgSub?.cancel();
    _openSub?.cancel();
    _tokenRefreshSub?.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceId = prefs.getString('deviceId');
    });
  }

  void _setupFCM() {
    _fgSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _log.info('FCM foreground message received');
    });
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _log.info('FCM message opened app');
    });

    // Handle FCM token refresh — update Firestore so pushes keep working
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (!mounted) return;
      _log.info('FCM token refreshed');
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('deviceId');
      if (deviceId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('devices')
              .doc(deviceId)
              .update({'fcmToken': newToken});
          _log.info('Updated FCM token in Firestore');
        } catch (e, stackTrace) {
          _log.error('Failed to update FCM token', e, stackTrace);
        }
      }
    });
  }

  Future<void> _respond(String requestId, String choice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secretToken = prefs.getString('secretToken');
      if (secretToken == null) {
        _log.error('secretToken missing from prefs', Exception('secretToken null'), StackTrace.current);
        return;
      }

      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'responded',
        'response': choice,
        'secretToken': secretToken,
      });

      _log.info('Responded to $requestId with $choice');

      setState(() {
        _sent = true;
        _lastResponse = choice;
      });

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() => _sent = false);
      }
    } catch (e, stackTrace) {
      _log.error('Failed to respond to $requestId', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to send response'),
            backgroundColor: YesClaudeTheme.deny,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
      body: SafeArea(
        child: Stack(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('requests')
                  .where('deviceId', isEqualTo: _deviceId)
                  .where('status', isEqualTo: 'pending')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (_sent) {
                  return _buildSentConfirmation();
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  _log.error('Firestore stream error', snapshot.error!, snapshot.stackTrace);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Connection error. Check your internet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildWaitingState();
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final command = data['command'] as String? ?? 'Unknown command';
                    final choices =
                        List<String>.from(data['choices'] ?? ['Allow', 'Deny']);
                    final machineId = data['machineId'] as String?;
                    final sessionLabel = data['sessionLabel'] as String?;

                    return _buildRequestCard(
                      doc.id,
                      command,
                      choices,
                      machineId: machineId,
                      sessionLabel: sessionLabel,
                    );
                  },
                );
              },
            ),

            // Rate limit upgrade prompt overlay
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('requests')
                  .where('deviceId', isEqualTo: _deviceId)
                  .where('rateLimited', isEqualTo: true)
                  .orderBy('createdAt', descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, rateLimitSnapshot) {
                if (!rateLimitSnapshot.hasData ||
                    rateLimitSnapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final doc = rateLimitSnapshot.data!.docs.first;
                final data = doc.data() as Map<String, dynamic>;
                final createdAt = data['createdAt'] as Timestamp?;
                if (createdAt == null) return const SizedBox.shrink();

                // Only show if rate-limited within the last hour
                final age = DateTime.now().difference(createdAt.toDate());
                if (age.inHours >= 1) return const SizedBox.shrink();

                final user = FirebaseAuth.instance.currentUser;
                final isAnonymous = user?.isAnonymous ?? true;
                final tier = isAnonymous ? 'anonymous' : 'free';

                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: UpgradePrompt(tier: tier),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentConfirmation() {
    final isDeny = _lastResponse?.toLowerCase().contains('deny') ?? false;
    final color = isDeny ? YesClaudeTheme.deny : YesClaudeTheme.success;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: child,
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(
                isDeny ? Icons.block_rounded : Icons.check_rounded,
                size: 40,
                color: color,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _lastResponse ?? 'Sent',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: YesClaudeTheme.emberGlow,
                  border: Border.all(
                    color: YesClaudeTheme.ember
                        .withValues(alpha: _pulseAnimation.value * 0.5),
                  ),
                ),
                child: Icon(
                  Icons.terminal_rounded,
                  size: 32,
                  color: YesClaudeTheme.ember
                      .withValues(alpha: _pulseAnimation.value),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Listening...',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for permission requests',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    String requestId,
    String command,
    List<String> choices, {
    String? machineId,
    String? sessionLabel,
  }) {
    final hasSessionContext = machineId != null || sessionLabel != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Session context header (only if fields are present)
          if (hasSessionContext) ...[
            Row(
              children: [
                Icon(
                  Icons.computer_rounded,
                  size: 14,
                  color: YesClaudeTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [machineId, sessionLabel]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' \u00b7 '),
                    style: YesClaudeTheme.monoStyle(
                      fontSize: 11,
                      color: YesClaudeTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: YesClaudeTheme.surfaceHighest,
            ),
            const SizedBox(height: 12),
          ],

          // Command display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: YesClaudeTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: YesClaudeTheme.surfaceHighest,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: YesClaudeTheme.ember.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'claude',
                      style: YesClaudeTheme.monoStyle(
                        fontSize: 11,
                        color: YesClaudeTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  command,
                  style: YesClaudeTheme.monoStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Choice buttons
          ...choices.map((choice) {
            final isDeny = choice.toLowerCase().contains('deny');
            final isAlwaysAllow =
                choice.toLowerCase().contains('always');

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: isDeny
                    ? OutlinedButton(
                        onPressed: () => _respond(requestId, choice),
                        child: Text(choice),
                      )
                    : FilledButton(
                        onPressed: () => _respond(requestId, choice),
                        style: isAlwaysAllow
                            ? FilledButton.styleFrom(
                                backgroundColor:
                                    YesClaudeTheme.ember.withValues(alpha: 0.15),
                                foregroundColor: YesClaudeTheme.ember,
                              )
                            : null,
                        child: Text(choice),
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
