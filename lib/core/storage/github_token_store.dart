import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// GitHub Personal Access Token নিরাপদে সংরক্ষণ করে।
/// Android-এ EncryptedSharedPreferences, iOS-এ Keychain ব্যবহার করে।
class GitHubTokenStore {
  GitHubTokenStore._();
  static final GitHubTokenStore instance = GitHubTokenStore._();

  static const _key = 'github_pat';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _cached;

  /// অ্যাপ শুরুর সময় একবার কল করুন।
  Future<void> load() async {
    _cached = await _storage.read(key: _key);
  }

  String? get token => _cached;

  bool get hasToken => _cached != null && _cached!.isNotEmpty;

  Future<void> save(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _key, value: trimmed);
    _cached = trimmed;
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    _cached = null;
  }
}
