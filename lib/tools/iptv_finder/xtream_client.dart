import 'dart:convert';
import 'iptv_models.dart';
import 'net_utils.dart';
import 'm3u_parser.dart';

class XtreamCreds {
  final String base;
  final String user;
  final String pass;
  final String? sid;
  final String kind;
  XtreamCreds({
    required this.base,
    required this.user,
    required this.pass,
    this.sid,
    required this.kind,
  });
}

/// URL থেকে Xtream username/password বের করার চেষ্টা করে —
/// ?username=&password=, বা /live|movie|series/user/pass/id.ext প্যাটার্ন।
XtreamCreds? xtreamCredsFromUrl(String url) {
  try {
    final p = Uri.parse(url);
    if (p.host.isEmpty) return null;
    final scheme = p.scheme.isEmpty ? 'http' : p.scheme;
    final base = '$scheme://${p.host}${p.hasPort ? ':${p.port}' : ''}';
    final path = p.path.isEmpty ? '/' : p.path;
    final q = p.queryParameters;

    if ((q['username'] ?? '').isNotEmpty && (q['password'] ?? '').isNotEmpty) {
      return XtreamCreds(base: base, user: q['username']!, pass: q['password']!, kind: 'query');
    }
    final m1 = RegExp(
      r'/(?:live|movie|series|timeshift)/([^/]+)/([^/]+)/(\d+)(?:\.[a-z0-9]+)?$',
      caseSensitive: false,
    ).firstMatch(path);
    if (m1 != null) {
      return XtreamCreds(
          base: base, user: m1.group(1)!, pass: m1.group(2)!, sid: m1.group(3), kind: 'path');
    }
    final m2 = RegExp(r'^/([^/]+)/([^/]+)/(\d+)\.(?:ts|m3u8|mp4|mkv)$', caseSensitive: false)
        .firstMatch(path);
    if (m2 != null) {
      return XtreamCreds(
          base: base, user: m2.group(1)!, pass: m2.group(2)!, sid: m2.group(3), kind: 'bare');
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> xtreamInfo(
  String base,
  String user,
  String pass,
  Map<String, String> headers,
) async {
  final u = '$base/player_api.php?username=${Uri.encodeQueryComponent(user)}'
      '&password=${Uri.encodeQueryComponent(pass)}';
  final r = await fetchFollow(u, headers, timeout: const Duration(seconds: 12), maxBytes: 2000000);
  if (r.code != 200) return {'ok': false, 'code': r.code, 'info': null, 'base': base};
  dynamic d;
  try {
    d = jsonDecode(r.body);
  } catch (_) {
    return {'ok': false, 'code': r.code, 'info': null, 'base': base};
  }
  if (d is! Map) return {'ok': false, 'code': r.code, 'info': null, 'base': base};
  final auth = d['user_info']?['auth'];
  if (auth != null && auth != 1) {
    return {'ok': false, 'code': 200, 'info': d, 'base': base, 'authfail': true};
  }
  return {'ok': true, 'code': 200, 'info': d, 'base': base};
}

Future<Map<String, String>> xtreamCategories(
  String base,
  String user,
  String pass,
  Map<String, String> headers,
) async {
  final u = '$base/player_api.php?username=${Uri.encodeQueryComponent(user)}'
      '&password=${Uri.encodeQueryComponent(pass)}&action=get_live_categories';
  final r = await fetchFollow(u, headers, timeout: const Duration(seconds: 15), maxBytes: 4000000);
  if (r.code != 200) return {};
  try {
    final d = jsonDecode(r.body);
    if (d is! List) return {};
    final m = <String, String>{};
    for (final c in d) {
      if (c['category_id'] != null && c['category_name'] != null) {
        m[c['category_id'].toString()] = c['category_name'].toString();
      }
    }
    return m;
  } catch (_) {
    return {};
  }
}

Future<List<dynamic>?> xtreamLiveStreams(
  String base,
  String user,
  String pass,
  Map<String, String> headers,
) async {
  final u = '$base/player_api.php?username=${Uri.encodeQueryComponent(user)}'
      '&password=${Uri.encodeQueryComponent(pass)}&action=get_live_streams';
  final r = await fetchFollow(u, headers,
      timeout: const Duration(seconds: 45), maxBytes: 60 * 1024 * 1024);
  if (r.code != 200) return null;
  try {
    final d = jsonDecode(r.body);
    return d is List ? d : null;
  } catch (_) {
    return null;
  }
}

Future<String?> xtreamGetM3U(
  String base,
  String user,
  String pass,
  Map<String, String> headers,
) async {
  final u = '$base/get.php?username=${Uri.encodeQueryComponent(user)}'
      '&password=${Uri.encodeQueryComponent(pass)}&type=m3u_plus&output=ts';
  final r = await fetchFollow(u, headers,
      timeout: const Duration(seconds: 90), maxBytes: 100 * 1024 * 1024);
  if (r.code != 200) return null;
  if (!r.body.toUpperCase().contains('#EXTM3U')) return null;
  return r.body;
}

/// নমুনা stream_id দিয়ে ৪টা URL প্যাটার্ন ট্রাই করে কোনটা সার্ভারে কাজ করছে বের করে।
Future<List<String>?> xtreamProbePattern(
  String base,
  String user,
  String pass,
  List<String> sampleIds,
  Map<String, String> headers,
) async {
  if (sampleIds.isEmpty) return null;
  final patterns = <List<String>>[
    ['live_m3u8', '$base/live/$user/$pass/{ID}.m3u8'],
    ['live_ts', '$base/live/$user/$pass/{ID}.ts'],
    ['bare_m3u8', '$base/$user/$pass/{ID}.m3u8'],
    ['bare', '$base/$user/$pass/{ID}'],
  ];
  final jobs = <List<dynamic>>[];
  for (var pi = 0; pi < patterns.length; pi++) {
    for (final sid in sampleIds) {
      jobs.add([pi, patterns[pi][1].replaceAll('{ID}', sid)]);
    }
  }
  final scores = <int, int>{};
  await runPool<List<dynamic>>(jobs, 16, (job) async {
    final pi = job[0] as int;
    final u = job[1] as String;
    final r = await fetchFollow(u, headers, timeout: const Duration(seconds: 7), maxBytes: 4096);
    if (r.code == 200 || r.code == 206) scores[pi] = (scores[pi] ?? 0) + 1;
  });
  if (scores.isEmpty) return null;
  final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final best = sorted.first;
  final minNeeded = (sampleIds.length / 2).ceil().clamp(1, 999999);
  return best.value >= minNeeded ? patterns[best.key] : null;
}

class XtreamEnumResult {
  final bool ok;
  final String? error;
  final String? method;
  final List<FoundLink> channels;
  final Map<String, dynamic>? info;
  final String base;
  final String user;
  final String pass;
  final String? pattern;
  XtreamEnumResult({
    required this.ok,
    this.error,
    this.method,
    required this.channels,
    this.info,
    required this.base,
    required this.user,
    required this.pass,
    this.pattern,
  });
}

/// player_api চেষ্টা করে; ব্যর্থ হলে get.php (M3U) ফলব্যাক, এবং stream_id
/// থেকে সরাসরি stream URL বানানোর প্যাটার্ন বের করে।
Future<XtreamEnumResult> xtreamEnumerate(
  String base,
  String user,
  String pass,
  Map<String, String> headers,
  void Function(String) onLog,
) async {
  onLog('Xtream probing $base as $user');
  final info = await xtreamInfo(base, user, pass, headers);
  if (info['ok'] != true && info['authfail'] != true) {
    onLog('player_api failed (HTTP ${info['code']}), trying get.php');
    final m3u = await xtreamGetM3U(base, user, pass, headers);
    if (m3u != null) {
      onLog('get.php M3U ok, parsing');
      final parsed = parsePlaylist(m3u, 'get.php:$base', hostFilter: extractHost(base));
      return XtreamEnumResult(
        ok: true, method: 'get.php', channels: parsed, info: null,
        base: base, user: user, pass: pass,
      );
    }
    return XtreamEnumResult(
      ok: false, error: 'player_api + get.php both failed', channels: const [],
      base: base, user: user, pass: pass,
    );
  }
  if (info['authfail'] == true) {
    return XtreamEnumResult(
      ok: false, error: 'Auth failed (bad user/pass)', channels: const [],
      base: base, user: user, pass: pass,
    );
  }

  onLog('player_api auth ok, fetching categories+streams');
  final cats = await xtreamCategories(base, user, pass, headers);
  final streams = await xtreamLiveStreams(base, user, pass, headers);
  if (streams == null) {
    onLog('get_live_streams failed, trying get.php');
    final m3u = await xtreamGetM3U(base, user, pass, headers);
    if (m3u != null) {
      final parsed = parsePlaylist(m3u, 'get.php:$base', hostFilter: extractHost(base));
      return XtreamEnumResult(
        ok: true, method: 'get.php', channels: parsed, info: info['info'],
        base: base, user: user, pass: pass,
      );
    }
    return XtreamEnumResult(
      ok: false, error: 'get_live_streams failed', channels: const [],
      base: base, user: user, pass: pass,
    );
  }

  onLog('get_live_streams returned ${streams.length} channels');

  final sampleIds = <String>[];
  for (final s in streams) {
    if (s['stream_id'] != null) {
      sampleIds.add(s['stream_id'].toString());
      if (sampleIds.length >= 3) break;
    }
  }
  final pattern =
      sampleIds.isNotEmpty ? await xtreamProbePattern(base, user, pass, sampleIds, headers) : null;
  final patternName = pattern != null ? pattern[0] : 'live_ts';
  final patternUrl = pattern != null ? pattern[1] : '$base/live/$user/$pass/{ID}.ts';
  onLog('URL pattern: $patternName');

  final channels = <FoundLink>[];
  const cap = 20000;
  for (final s in streams) {
    if (s['stream_id'] == null || s['name'] == null) continue;
    if (channels.length >= cap) {
      onLog('Cap reached ($cap)');
      break;
    }
    final sid = s['stream_id'].toString();
    channels.add(FoundLink(
      chIndex: -1,
      channelName: s['name'].toString().trim(),
      label: '',
      url: patternUrl.replaceAll('{ID}', sid),
      group: '',
      headers: Map<String, String>.from(headers),
      props: const [],
      tvgId: s['epg_channel_id']?.toString() ?? '',
      tvgLogo: s['stream_icon']?.toString() ?? '',
      host: extractHost(base),
      src: 'xtream:$base',
      cat: cats[s['category_id']?.toString() ?? ''] ?? '',
    ));
  }
  return XtreamEnumResult(
    ok: true, method: 'player_api', channels: channels, info: info['info'],
    base: base, user: user, pass: pass, pattern: patternName,
  );
}

Future<Map<String, String>> hostCommonProbes(String base, Map<String, String> headers) async {
  final paths = [
    '/playlist.m3u', '/playlist.m3u8', '/live.m3u', '/iptv.m3u', '/list.m3u',
    '/m3u', '/all.m3u',
  ];
  final hits = <String, String>{};
  await runPool<String>(paths, 7, (p) async {
    final r = await fetchFollow('$base$p', headers,
        timeout: const Duration(seconds: 8), maxBytes: 2000000);
    if (r.code == 200 && r.body.toUpperCase().contains('#EXTM3U')) {
      hits['$base$p'] = r.body;
    }
  });
  return hits;
}
