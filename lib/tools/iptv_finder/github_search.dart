import 'dart:convert';
import 'package:http/http.dart' as http;

class GhSearchResult {
  final int totalCount;
  final List<GhItem> items;
  GhSearchResult({required this.totalCount, required this.items});
}

class GhItem {
  final String htmlUrl;
  final String path;
  final String repoFullName;
  GhItem({required this.htmlUrl, required this.path, required this.repoFullName});
}

class GhAuthException implements Exception {
  final String msg;
  GhAuthException(this.msg);
  @override
  String toString() => msg;
}

/// GitHub Code Search; rate-limit হলে onWait কল করে অপেক্ষা করে, তারপর রিট্রাই করে।
/// টোকেন খালি থাকলেও কল করা যায় (anonymous rate limit অনেক কম)।
Future<GhSearchResult?> ghSearch(
  String q,
  int page,
  String token, {
  required Future<void> Function(int seconds, String why) onWait,
  required void Function(String) onLog,
}) async {
  final uri = Uri.parse(
    'https://api.github.com/search/code?q=${Uri.encodeQueryComponent(q)}&per_page=100&page=$page',
  );
  for (var tryN = 0; tryN < 3; tryN++) {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'HridoysToolbox-IPTVFinder',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (e) {
      onLog('Search request failed: $e');
      return null;
    }

    if (res.statusCode == 200) {
      Map<String, dynamic> d;
      try {
        d = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
      final items = ((d['items'] as List?) ?? [])
          .map((it) => GhItem(
                htmlUrl: it['html_url'] ?? '',
                path: it['path'] ?? '',
                repoFullName: it['repository']?['full_name'] ?? '',
              ))
          .toList();
      final remaining = int.tryParse(res.headers['x-ratelimit-remaining'] ?? '');
      if (remaining != null && remaining <= 0) {
        final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '0') ?? 0;
        final w = reset - (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;
        await onWait(w.clamp(5, 70), 'Rate limit reached');
      } else {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
      return GhSearchResult(totalCount: d['total_count'] ?? 0, items: items);
    }
    if (res.statusCode == 401) throw GhAuthException('Invalid GitHub token (401)');
    if (res.statusCode == 403 || res.statusCode == 429) {
      var w = int.tryParse(res.headers['retry-after'] ?? '') ?? 0;
      if (w <= 0) {
        final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '0') ?? 0;
        w = reset - (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;
      }
      if (w <= 0 || w > 70) w = 60;
      await onWait(w, 'Rate limit (${res.statusCode})');
      continue;
    }
    onLog('Search error ${res.statusCode} (page $page)');
    return null;
  }
  return null;
}
