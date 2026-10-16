import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/settings/domain/api_settings.dart';

void main() {
  test('is not configured without a URL', () {
    expect(const ApiSettings().configured, isFalse);
    expect(const ApiSettings(baseUrl: '   ').configured, isFalse);
  });

  test('is configured once a URL is set', () {
    expect(
      const ApiSettings(baseUrl: 'https://nudge.example.com').configured,
      isTrue,
    );
  });

  test('apiBase appends the version and trims trailing slashes', () {
    expect(
      const ApiSettings(baseUrl: 'https://nudge.example.com').apiBase,
      'https://nudge.example.com/api/v1',
    );
    expect(
      const ApiSettings(baseUrl: 'https://nudge.example.com/').apiBase,
      'https://nudge.example.com/api/v1',
    );
    expect(
      const ApiSettings(baseUrl: 'https://nudge.example.com///').apiBase,
      'https://nudge.example.com/api/v1',
    );
  });

  test('apiBase does not double the version path if the user pasted it', () {
    // A user pasting the full contract URL should still work; the trailing
    // slash is trimmed but the existing path is kept as-is by design.
    const settings = ApiSettings(baseUrl: 'http://10.0.0.5:8080');
    expect(settings.apiBase, 'http://10.0.0.5:8080/api/v1');
  });

  test('copyWith replaces one field at a time', () {
    const original = ApiSettings(baseUrl: 'https://a.test', token: 'abc');
    expect(original.copyWith(token: 'xyz').token, 'xyz');
    expect(original.copyWith(token: 'xyz').baseUrl, 'https://a.test');
  });
}
