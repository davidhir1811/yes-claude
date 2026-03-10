import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../logger.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class UpgradePrompt extends StatefulWidget {
  final String tier;

  const UpgradePrompt({super.key, required this.tier});

  @override
  State<UpgradePrompt> createState() => _UpgradePromptState();
}

class _UpgradePromptState extends State<UpgradePrompt> {
  static const _log = Log('UpgradePrompt');
  bool _loading = false;

  bool get _isAnonymous => widget.tier == 'anonymous';

  bool get _isApplePlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.linkAccount();
      _log.info('Sign-in successful from upgrade prompt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Signed in! Your limit has been increased.'),
            backgroundColor: YesClaudeTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e, stackTrace) {
      _log.error('Sign-in failed', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-in failed: ${e.message}'),
            backgroundColor: YesClaudeTheme.deny,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      _log.error('Sign-in failed', e, stackTrace);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: YesClaudeTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: YesClaudeTheme.ember.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: YesClaudeTheme.ember.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.speed_rounded,
              color: YesClaudeTheme.ember,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Daily limit reached',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _isAnonymous
                ? 'Sign in to get 20 requests per day'
                : 'Upgrade to Premium for 1,000 requests per month',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_isAnonymous)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1A1A1A),
                        ),
                      )
                    : Icon(_isApplePlatform ? Icons.apple : Icons.login_rounded),
                label: Text(_loading
                    ? 'Signing in...'
                    : _isApplePlatform
                        ? 'Sign in with Apple'
                        : 'Sign in with Google'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Premium coming soon!'),
                      backgroundColor: YesClaudeTheme.ember,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.star_rounded),
                label: const Text('Upgrade to Premium'),
              ),
            ),
        ],
      ),
    );
  }
}
