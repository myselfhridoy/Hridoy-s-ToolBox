import 'dart:convert';
import 'package:http/http.dart' as http;

const kDefaultUA = 'VLC/3.0.18 LibVLC/3.0.18';
const kBrowserUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String headerCase(String k) => k
    .split('-')
    .map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
    .join('-');

String extractHost(String url) {
  try {
    final u = Uri.parse(url);
    if (u.host.isEmpty) return '';
    var h = u.host.toLowerCase();
    if (h.startsWith('www.')) h = h.substring(4);
    return u.hasPort ? '$h:${u.port}' : h;
  } catch (_) {
    return '';
  }
}

String resolveUrl(String base, String rel) {
  try {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(rel)) return rel;
    return Uri.parse(base).resolve(rel).toString();
  } catch (_) {
    return rel;
  }
}

String normalizeHostInput(String h) {
  h = h.trim();
  if (h.isEmpty) return '';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(h)) h = 'http://$h';
  return h.endsWith('/') ? h.substring(0, h.length - 1) : h;
}

/// GitHub blob URL (নির্দিষ্ট SHA-সহ) -> সর্বশেষ ব্রাঞ্চের raw URL।
String ghRawUrl(String url) {
  final m1 =
      RegExp(r'^https://github\.com/([^/]+/[^/]+)/blob/[^/]+/(.+)$').firstMatch(url);
  if (m1 != null) {
    return 'https://raw.githubusercontent.com/${m1.group(1)}/HEAD/${m1.group(2)}';
  }
  final m2 =
      RegExp(r'^https://github\.com/([^/]+/[^/]+)/blob/(.*)$').firstMatch(url);
  if (m2 != null) {
    return 'https://raw.githubusercontent.com/${m2.group(1)}/${m2.group(2)}';
  }
  return url;
}

String b64uToHex(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  try {
    final b = base64.decode(t);
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  } catch (_) {
    return '';
  }
}

/// সীমিত concurrency-তে কাজ চালায় — PHP-র curl_multi-র সহজ Dart বিকল্প।
Future<void> runPool<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) task,
) async {
  if (items.isEmpty) return;
  var idx = 0;
  Future<void> worker() async {
    while (idx < items.length) {
      final i = idx++;
      try {
        await task(items[i]);
      } catch (_) {}
    }
  }

  await Future.wait(
    List.generate(concurrency.clamp(1, items.length), (_) => worker()),
  );
}

class FetchResult {
  final int code;
  final String body;
  final String finalUrl;
  final String contentType;
  final int ms;
  FetchResult({
    required this.code,
    required this.body,
    required this.finalUrl,
    required this.contentType,
    required this.ms,
  });
}

Map<String, String> buildReqHeaders(Map<String, String> h) {
  final out = <String, String>{'User-Agent': h['user-agent'] ?? kDefaultUA};
  if ((h['referer'] ?? '').isNotEmpty) out['Referer'] = h['referer']!;
  if ((h['origin'] ?? '').isNotEmpty) out['Origin'] = h['origin']!;
  h.forEach((k, v) {
    if (k.startsWith('h_') && v.isNotEmpty) out[headerCase(k.substring(2))] = v;
  });
  return out;
}

/// রিডাইরেক্ট নিজে অনুসরণ করে, যাতে শেষ URL জানা যায় (relative path
/// resolve-এর জন্য দরকার)। maxBytes-এর পরে বডি পড়া বন্ধ করে দেয়।
Future<FetchResult> fetchFollow(
  String url,
  Map<String, String> headers, {
  int maxRedirects = 4,
  Duration timeout = const Duration(seconds: 8),
  int maxBytes = 65536,
}) async {
  var currentUrl = url;
  final sw = Stopwatch()..start();
  final client = http.Client();
  try {
    for (var i = 0; i <= maxRedirects; i++) {
      final req = http.Request('GET', Uri.parse(currentUrl));
      req.headers.addAll(buildReqHeaders(headers));
      req.followRedirects = false;
      final streamed = await client.send(req).timeout(timeout);
      if (streamed.isRedirect && streamed.headers['location'] != null) {
        currentUrl = resolveUrl(currentUrl, streamed.headers['location']!);
        continue;
      }
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) break;
      }
      return FetchResult(
        code: streamed.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        finalUrl: currentUrl,
        contentType: streamed.headers['content-type'] ?? '',
        ms: sw.elapsedMilliseconds,
      );
    }
    return FetchResult(
      code: 0,
      body: '',
      finalUrl: currentUrl,
      contentType: '',
      ms: sw.elapsedMilliseconds,
    );
  } catch (_) {
    return FetchResult(
      code: 0,
      body: '',
      finalUrl: currentUrl,
      contentType: '',
      ms: sw.elapsedMilliseconds,
    );
  } finally {
    client.close();
  }
}

Future<Map<String, String?>> fetchFiles(
  List<String> urls, {
  int concurrency = 6,
}) async {
  final out = <String, String?>{};
  await runPool<String>(urls, concurrency, (u) async {
    final r = await fetchFollow(
      u,
      const {},
      maxBytes: 20000000,
      timeout: const Duration(seconds: 45),
    );
    out[u] = (r.code == 200 && r.body.isNotEmpty) ? r.body : null;
  });
  return out;
}
