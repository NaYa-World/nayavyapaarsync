import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Stream<GoogleSignInAccount?> get onCurrentUserChanged => _googleSignIn.onCurrentUserChanged;

  /// Attempts to sign in the user silently (checks cached credentials)
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      var account = await _googleSignIn.signInSilently();
      if (account != null) {
        var auth = await account.authentication;
        if (auth.accessToken == null) {
          // Token might be expired. Force silent re-authentication to refresh token.
          account = await _googleSignIn.signInSilently(reAuthenticate: true);
          if (account != null) {
            auth = await account.authentication;
            if (auth.accessToken == null) {
              throw Exception('Token refresh failed');
            }
          }
        }
      }
      return account;
    } catch (e) {
      // If silent sign-in fails, return null. The app will prompt for manual login.
      return null;
    }
  }

  /// Triggers the interactive Google Sign-In flow
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      return account;
    } catch (e) {
      rethrow;
    }
  }

  /// Signs out the user
  Future<GoogleSignInAccount?> signOut() async {
    try {
      return await _googleSignIn.signOut();
    } catch (e) {
      rethrow;
    }
  }

  /// Checks if a user is currently signed in and token is valid
  Future<bool> isUserSignedIn() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      final auth = await account.authentication;
      return auth.accessToken != null;
    } catch (_) {
      return false;
    }
  }

  /// Obtains an authenticated HTTP client for Google API requests
  Future<http.Client?> getAuthenticatedClient() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return null;

    final client = await _googleSignIn.authenticatedClient();
    return client;
  }
}
