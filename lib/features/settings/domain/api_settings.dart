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

  /// Null when the settings are usable, a field message otherwise. An empty URL
  /// is valid and means "stay local"; a URL without a token is not, because
  /// every endpoint except /health needs one.
  String? get validationError {
    final url = baseUrl.trim();
    if (url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Enter a URL like https://nudge.example.com';
    }
    if (token.trim().isEmpty) {
      return 'Enter the API token for this server.';
    }
    return null;
  }

  ApiSettings copyWith({String? baseUrl, String? token}) {
    return ApiSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
    );
  }
}
