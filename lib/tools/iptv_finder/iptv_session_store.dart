import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// IPTV Finder সেশন ডিস্কে JSON-এ persist করে।
/// বড় ফাইল (কয়েক MB) হতে পারে, তাই SharedPreferences নয় — plain file।
class IptvSessionStore {
  IptvSessionStore._();
  static final IptvSessionStore instance = IptvSessionStore._();
  static const _fileName = 'iptv_session.json';

  File? _file;

  Future<File> _getFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$_fileName');
    _file = f;
    return f;
  }

  Future<void> ensureReady() async {
    try {
      await _getFile();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final f = await _getFile();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> data) async {
    try {
      final f = await _getFile();
      await f.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  /// App pause/detach ও dispose-এ ব্যবহারের জন্য — await করার সুযোগ থাকে না।
  void saveSync(Map<String, dynamic> data) {
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final f = await _getFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
