import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
    } on FirebaseAuthException catch (e, stackTrace) {
      if (e.code == 'credential-already-in-use') {
        _log.info('Credential already in use, signing in with existing account');
        await _auth.signInWithCredential(credential);
        _log.info('Signed in with existing Google account: ${_auth.currentUser!.uid}');
        // Ensure user doc exists for the switched-to account
        await _ensureUserDoc(_auth.currentUser!.uid);
      } else {
        _log.error('Failed to link Google credential', e, stackTrace);
        rethrow;
      }
    }
    await _updateTier('free');
    return _auth.currentUser!.uid;
  }

  /// Link anonymous account to Apple. Returns uid.
  Future<String> linkWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    );

    final credential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    try {
      await _auth.currentUser!.linkWithCredential(credential);
      _log.info('Linked anonymous account to Apple');
    } on FirebaseAuthException catch (e, stackTrace) {
      if (e.code == 'credential-already-in-use') {
        _log.info('Apple credential already in use, signing in with existing account');
        await _auth.signInWithCredential(credential);
        _log.info('Signed in with existing Apple account: ${_auth.currentUser!.uid}');
        await _ensureUserDoc(_auth.currentUser!.uid);
      } else {
        _log.error('Failed to link Apple credential', e, stackTrace);
        rethrow;
      }
    }
    await _updateTier('free');
    return _auth.currentUser!.uid;
  }

  /// Platform-aware sign-in: Apple on iOS, Google elsewhere.
  Future<String> linkAccount() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return linkWithApple();
    }
    return linkWithGoogle();
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
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
    try {
      await _db.collection('users').doc(uid).update({'tier': tier});
    } catch (e, stackTrace) {
      _log.error('Failed to update tier to $tier', e, stackTrace);
      rethrow;
    }
  }

  Future<void> linkDevice(String deviceId) async {
    try {
      await _db.collection('users').doc(uid).update({
        'devices': FieldValue.arrayUnion([deviceId]),
      });
    } catch (e, stackTrace) {
      _log.error('Failed to link device $deviceId', e, stackTrace);
      rethrow;
    }
  }
}
