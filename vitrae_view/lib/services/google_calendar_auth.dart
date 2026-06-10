import 'package:google_sign_in/google_sign_in.dart';

class GoogleCalendarAuth {
  // Client ID do tipo "Aplicação Web" criado na Fase 0
  static const String _webClientId =
      '555974802803-4na1f4nbj856kmqkfc2hv5808fc17kmk.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
    serverClientId: _webClientId,
    forceCodeForRefreshToken: true, // garante refresh token no lado da janela
  );

  /// Abre o login Google e devolve o código de autorização,
  /// ou null se o utilizador cancelar.
  static Future<String?> obterAuthCode() async {
    await _googleSignIn.signOut(); // força a escolha de conta e um código novo
    final conta = await _googleSignIn.signIn();
    return conta?.serverAuthCode;
  }
}