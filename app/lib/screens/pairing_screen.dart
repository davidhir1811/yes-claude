import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logger.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class PairingScreen extends StatefulWidget {
  final VoidCallback onPaired;

  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  static const _log = Log('PairingScreen');
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _codeController.addListener(() => setState(() {}));
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = 'Enter the full 6-character code');
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
          _error = 'Code not found. Check your terminal.';
          _loading = false;
        });
        return;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final fcmToken = await messaging.getToken();

      if (fcmToken == null) {
        setState(() {
          _error = 'Notification permission required.';
          _loading = false;
        });
        return;
      }

      await deviceDoc.update({
        'fcmToken': fcmToken,
        'pairedAt': FieldValue.serverTimestamp(),
      });

      final token = snapshot.data()?['secretToken'] as String?;
      if (token == null) {
        setState(() {
          _error = 'Invalid device record.';
          _loading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deviceId', code);
      await prefs.setString('secretToken', token);

      await AuthService.instance.linkDevice(code);
      _log.info('Paired successfully with device $code');
      widget.onPaired();
    } catch (e, stackTrace) {
      _log.error('Pairing failed', e, stackTrace);
      setState(() {
        _error = 'Connection failed. Try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _codeController.text.toUpperCase();

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // Logo area — subtle ember glow
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: YesClaudeTheme.emberGlow,
                      border: Border.all(
                        color: YesClaudeTheme.ember.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.terminal_rounded,
                      color: YesClaudeTheme.ember,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Yes Claude...',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the code from your terminal',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 48),

                  // Character boxes
                  GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        final hasChar = i < code.length;
                        final isActive = i == code.length && _focusNode.hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 48,
                          height: 60,
                          decoration: BoxDecoration(
                            color: hasChar
                                ? YesClaudeTheme.surfaceHighest
                                : YesClaudeTheme.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isActive
                                  ? YesClaudeTheme.ember
                                  : hasChar
                                      ? YesClaudeTheme.ember.withValues(alpha: 0.3)
                                      : Colors.transparent,
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: hasChar
                              ? Text(
                                  code[i],
                                  style: YesClaudeTheme.monoStyle(
                                    fontSize: 24,
                                    color: YesClaudeTheme.textPrimary,
                                  ),
                                )
                              : isActive
                                  ? _BlinkingCursor()
                                  : null,
                        );
                      }),
                    ),
                  ),

                  // Hidden text field
                  SizedBox(
                    width: 0,
                    height: 0,
                    child: TextField(
                      controller: _codeController,
                      focusNode: _focusNode,
                      autofocus: true,
                      maxLength: 6,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _pair(),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: YesClaudeTheme.deny,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AnimatedOpacity(
                      opacity: code.length == 6 ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: FilledButton(
                        onPressed:
                            code.length == 6 && !_loading ? _pair : null,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFF1A1A1A),
                                ),
                              )
                            : const Text('Connect'),
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 24,
        decoration: BoxDecoration(
          color: YesClaudeTheme.ember,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
