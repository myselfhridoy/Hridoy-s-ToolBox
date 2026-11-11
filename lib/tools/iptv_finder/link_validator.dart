import 'dart:convert';
import 'iptv_models.dart';
import 'net_utils.dart';

/// Stalker-স্টাইল portal লিংক (.../play/live.php?mac=..&extension=ts&play_token=..)
/// -> play_token ছাড়া, extension=m3u8 দিয়ে বিকল্প URL। এমন লিংক না হলে null।
String? portalAlt(String u) {
  if (!RegExp(r'/play/live\.php\?', caseSensitive: false).hasMatch(u)) return null;
  if (!RegExp(r'[?&]mac=', caseSensitive: false).hasMatch(u)) return null;
  final p = u.indexOf('?');
  final parts = u.substring(p + 1).split('&');
  var hasTs = false;
  final out = <String>[];
  for (var q in parts) {
    if (RegExp(r'^play_token=', caseSensitive: false).hasMatch(q)) continue;
    if (q.toLowerCase() == 'extension=ts') {
      hasTs = true;
      q = 'extension=m3u8';
    }
    out.add(q);
  }
  return hasTs ? '${u.substring(0, p)}?${out.join('&')}' : null;
}

final _clearKeyCache = <String, String>{};

/// license_key=https://server/... -> "kid:key" হেক্স জোড়ায় রিজলভ করে, ফলাফল ক্যাশ করে।
Future<String> resolveClearKeyUrl(String url, Map<String, String> headers) async {
  if (_clearKeyCache.containsKey(url)) return _clearKeyCache[url]!;
  final r = await fetchFollow(url, headers, timeout: const Duration(seconds: 8), maxBytes: 200000);
  var out = '';
  final hexRe = RegExp(r'^[0-9a-f]{32}$', caseSensitive: false);
  if (r.code == 200) {
    try {
      final d = jsonDecode(r.body);
      final pairs = <String>[];
      if (d is Map && d['keys'] is List) {
        for (final kk in d['keys']) {
          if (kk['kid'] == null || kk['k'] == null) continue;
          final a = b64uToHex(kk['kid'].toString());
          final b = b64uToHex(kk['k'].toString());
          if (a.length == 32 && b.length == 32) pairs.add('$a:$b');
        }
      } else if (d is Map) {
        d.forEach((kk, vv) {
          if (vv is String && hexRe.hasMatch(kk.toString()) && hexRe.hasMatch(vv)) {
            pairs.add('$kk:$vv');
          }
        });
      } else {
        final body = r.body.trim();
        if (RegExp(r'^[0-9a-f]{32}:[0-9a-f]{32}(,[0-9a-f]{32}:[0-9a-f]{32})*$',
                caseSensitive: false)
            .hasMatch(body)) {
          pairs.add(body);
        }
      }
      out = pairs.join(',');
    } catch (_) {}
  }
  _clearKeyCache[url] = out;
  return out;
}

Future<void> enrichLicense(FoundLink m) async {
  if ((m.lickey ?? '').isNotEmpty) return;
  for (final p in m.props) {
    final x = RegExp(r'license_key=(https?://\S+)', caseSensitive: false).firstMatch(p);
    if (x != null &&
        !RegExp(r'[?&]key=[0-9a-f]{32}', caseSensitive: false).hasMatch(x.group(1)!)) {
      final k = await resolveClearKeyUrl(x.group(1)!, m.headers);
      if (k.isNotEmpty) m.lickey = k;
      return;
    }
  }
}

/// main -> (master হলে) variant -> segment পর্যন্ত অনুসরণ করে দেখে স্ট্রিম
/// আসলেই কাজ করছে কিনা। link-এর ফিল্ড সরাসরি বদলে দেয়।
Future<void> _followChain(
  FoundLink link,
  String url, {
  required String kind, // main | variant | segment
  required int depth,
  Map<String, String>? overrideHeaders,
}) async {
  final headers = overrideHeaders ?? link.headers;
  final maxBytes = kind == 'segment' ? 2048 : 65536;
  var r = await fetchFollow(url, headers,
      timeout: Duration(seconds: kind == 'segment' ? 6 : 8), maxBytes: maxBytes);

  if (kind == 'main') link.ms = r.ms;

  if (r.code == 0 || r.code >= 500) {
    r = await fetchFollow(url, headers, timeout: const Duration(seconds: 15), maxBytes: maxBytes);
  }

  if ((r.code == 401 || r.code == 403) && (headers['user-agent'] ?? '').isEmpty) {
    final alt = Map<String, String>.from(headers)..['user-agent'] = kBrowserUA;
    final r2 = await fetchFollow(url, alt,
        timeout: Duration(seconds: kind == 'segment' ? 6 : 8), maxBytes: maxBytes);
    if (r2.code == 200 || r2.code == 206) {
      link.browserUa = kBrowserUA;
      link.note = (link.note + ' browser-UA').trim();
      r = r2;
    }
  }

  if (r.code != 200 && r.code != 206) {
    link.note = 'HTTP ${r.code}';
    link.ok = false;
    return;
  }

  final lead = r.body.trimLeft().toLowerCase();
  if (lead.startsWith('<!doctype') || lead.startsWith('<html')) {
    link.note = 'HTML page';
    link.ok = false;
    return;
  }

  if (kind == 'segment') {
    link.ok = true;
    return;
  }

  if (r.body.contains('<MPD')) {
    link.ok = true;
    link.note = 'DASH';
    return;
  }

  if (!r.body.contains('#EXTM3U')) {
    final b = r.body;
    final isTs = b.length > 376 &&
        b.codeUnitAt(0) == 0x47 &&
        b.codeUnitAt(188) == 0x47 &&
        b.codeUnitAt(376) == 0x47;
    if (isTs) {
      link.ok = true;
      link.note = 'ts';
    } else if (RegExp(r'video/|mpegurl|octet-stream|mp2t', caseSensitive: false)
        .hasMatch(r.contentType)) {
      link.ok = true;
      link.note = 'direct';
    } else {
      link.note = 'not a playlist';
      link.ok = false;
    }
    return;
  }

  if (depth >= 3) {
    link.note = 'too deep';
    link.ok = false;
    return;
  }

  final lines = r.body.split(RegExp(r'\r\n|\r|\n'));
  if (r.body.contains('#EXT-X-STREAM-INF')) {
    String? bestUrl;
    var bestBw = -1;
    var bestH = 0;
    for (var n = 0; n < lines.length; n++) {
      if (!lines[n].startsWith('#EXT-X-STREAM-INF')) continue;
      final bwM = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[n]);
      final hM = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[n]);
      final bw = bwM != null ? int.parse(bwM.group(1)!) : 0;
      final h = hM != null ? int.parse(hM.group(1)!) : 0;
      var u = '';
      for (var j = n + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        u = t;
        break;
      }
      if (u.isNotEmpty && bw > bestBw) {
        bestUrl = u;
        bestBw = bw;
        bestH = h;
      }
    }
    if (bestUrl == null) {
      link.note = 'empty master';
      link.ok = false;
      return;
    }
    link.h = bestH;
    link.bw = bestBw;
    return _followChain(link, resolveUrl(r.finalUrl, bestUrl),
        kind: 'variant', depth: depth + 1, overrideHeaders: headers);
  }

  var seg = '';
  for (final l in lines) {
    final t = l.trim();
    if (t.isNotEmpty && !t.startsWith('#')) {
      seg = t;
      break;
    }
  }
  if (seg.isEmpty) {
    link.note = 'no segments';
    link.ok = false;
    return;
  }
  return _followChain(link, resolveUrl(r.finalUrl, seg),
      kind: 'segment', depth: depth + 1, overrideHeaders: headers);
}

/// একটা লিংক validate করে; দরকার হলে Portal alt URL-ও চেষ্টা করে।
Future<void> validateLink(FoundLink link) async {
  await _followChain(link, link.url, kind: 'main', depth: 0);

  if (link.ok != true && !link.portalAltTried) {
    final alt = portalAlt(link.url);
    if (alt != null) {
      link.portalAltTried = true;
      link.origUrl = link.url;
      final before = link.url;
      link.url = alt;
      link.note = '';
      link.h = 0;
      link.bw = 0;
      await _followChain(link, alt, kind: 'main', depth: 0);
      if (link.ok != true) {
        link.url = before;
      } else {
        link.note = '${link.note} m3u8-alt'.trim();
      }
    }
  }

  if (link.ok == true && (link.browserUa ?? '').isNotEmpty) {
    link.headers = {...link.headers, 'user-agent': link.browserUa!};
  }
}

Future<void> validateLinks(
  List<FoundLink> links,
  Future<void> Function(FoundLink) onDone, {
  int concurrency = 12,
}) async {
  await runPool<FoundLink>(links, concurrency, (link) async {
    await validateLink(link);
    await onDone(link);
  });
}
