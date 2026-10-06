import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  GoogleSignInService._();
  static final GoogleSignInService instance = GoogleSignInService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  /// Shows the Google account picker. Returns null if the user cancels.
  Future<GoogleSignInResult?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) return null;

    return GoogleSignInResult(
      idToken: idToken,
      displayName: account.displayName,
      email: account.email,
    );
  }

  Future<void> signOut() => _googleSignIn.signOut();
}

class GoogleSignInResult {
  final String idToken;
  final String? displayName;
  final String? email;

  const GoogleSignInResult({required this.idToken, this.displayName, this.email});
}
