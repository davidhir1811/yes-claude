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
