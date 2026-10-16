/// Connection details for the Nudge backend.
///
/// The token is a secret and lives in secure storage; the URL is not, so it
/// lives with the other preferences. Both are empty on a fresh install, which
/// means "stay local".
class ApiSettings {
  const ApiSettings({this.baseUrl = '', this.token = ''});

  /// Origin of the server without the `/api/v1` suffix, e.g.
  /// `https://nudge.example.com`.
  final String baseUrl;

  final String token;

  /// Whether the app should talk to a server at all.
  bool get configured => baseUrl.trim().isNotEmpty;

  /// The base URL with the API version path appended.
  String get apiBase {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$normalized/api/v1';
  }

  ApiSettings copyWith({String? baseUrl, String? token}) {
    return ApiSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
    );
  }
}
