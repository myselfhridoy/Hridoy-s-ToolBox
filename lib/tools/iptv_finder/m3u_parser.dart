import 'dart:convert';
import 'iptv_models.dart';
import 'net_utils.dart';

List<ChannelQuery> parseChannelsInput(String text) {
  final out = <ChannelQuery>[];
  for (final lnRaw in text.split(RegExp(r'\r\n|\r|\n'))) {
    final parts =
        lnRaw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    final terms = <String>{};
    final words = <List<String>>[];
    for (final t in parts) {
      terms.add(t);
      final ns = t.replaceAll(' ', '');
      if (ns != t) terms.add(ns);
      final w = t
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (w.length >= 2) words.add(w);
    }
    final norms = <String>{for (final p in parts) norm(p)};
    out.add(ChannelQuery(
      name: parts.first,
      terms: terms.toList(),
      norms: norms.toList(),
      words: words,
    ));
  }
  return out;
}

bool _isDigit(String c) =>
    c.isNotEmpty && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

/// হাইস্ট্যাকে q খোঁজে, তবে q একটা বড় সংখ্যার মাঝখানে ম্যাচ করলে বাদ দেয়
/// (যেমন "5" যেন "15" বা "50"-এর ভেতরে ম্যাচ না করে)।
bool matchQ(String hay, String q) {
  if (q.isEmpty) return false;
  var o = 0;
  final L = q.length;
  while (true) {
    final p = hay.indexOf(q, o);
    if (p < 0) return false;
    final a = p > 0 ? hay[p - 1] : '';
    final b = (p + L < hay.length) ? hay[p + L] : '';
    var ok = true;
    if (_isDigit(q[L - 1]) && b.isNotEmpty && _isDigit(b)) ok = false;
    if (_isDigit(q[0]) && a.isNotEmpty && _isDigit(a)) ok = false;
    if (ok) return true;
    o = p + 1;
  }
}

bool chMatches(ChannelQuery ch, String hay) {
  if (hay.trim().isEmpty) return false;
  final hn = norm(hay);
  for (final q in ch.norms) {
    if (matchQ(hn, q)) return true;
  }
  if (ch.words.isNotEmpty) {
    final tok = hay
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((e) => e.isNotEmpty)
        .toSet();
    for (final ws in ch.words) {
      if (ws.every(tok.contains)) return true;
    }
  }
  return false;
}

String attrOf(String s, String k) {
  final re1 = RegExp('$k\\s*=\\s*"([^"]*)"', caseSensitive: false);
  final m1 = re1.firstMatch(s);
  if (m1 != null) return m1.group(1) ?? '';
  final re2 = RegExp("$k\\s*=\\s*'([^']*)'", caseSensitive: false);
  final m2 = re2.firstMatch(s);
  if (m2 != null) return m2.group(1) ?? '';
  return '';
}

/// চ্যানেলের নাম = প্রথম কমার পরের লেখা, যা quote-এর বাইরে।
String infName(String inf) {
  var name = '';
  final re = RegExp(r'^#EXTINF:[^,"]*(?:"[^"]*"[^,"]*)*,(.*)$', dotAll: true);
  final m = re.firstMatch(inf);
  if (m != null) name = m.group(1)!.trim();
  if (name.isEmpty || RegExp(r'\b[a-zA-Z-]+\s*=\s*"').hasMatch(name)) {
    final m2 = RegExp(r'^.*"\s*,\s*(.+)$', dotAll: true).firstMatch(inf);
    if (m2 != null) name = m2.group(1)!.trim();
  }
  if (name.isEmpty) name = attrOf(inf, 'tvg-name').trim();
  return name;
}

void hdrSet(Map<String, String> hd, String key, String value) {
  var k = key.trim().toLowerCase();
  var v = value.trim();
  if (v.isEmpty) return;
  const known = [
    'user-agent', 'http-user-agent', 'referer', 'referrer',
    'http-referer', 'http-referrer', 'origin', 'http-origin',
  ];
  if (known.contains(k) && RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(v)) {
    try {
      v = Uri.decodeComponent(v);
    } catch (_) {}
  }
  if (k == 'user-agent' || k == 'http-user-agent') {
    hd['user-agent'] = v;
  } else if (['referer', 'referrer', 'http-referer', 'http-referrer'].contains(k)) {
    hd['referer'] = v;
  } else if (k == 'origin' || k == 'http-origin') {
    hd['origin'] = v;
  } else {
    k = k.replaceFirst(RegExp(r'^http-'), '');
    if (RegExp(r'^[a-z0-9-]+$').hasMatch(k) && !RegExp(r'[\r\n]').hasMatch(v)) {
      hd['h_$k'] = v;
    }
  }
}

/// লাইন-ভিত্তিক M3U পার্সার — newline flatten করে না, তাই কোনো URL
/// পরের #EXTVLCOPT/#KODIPROP লাইন গিলে ফেলতে পারে না, আর tvg-logo="http://…"
/// থাকলেও EXTINF মেটাডেটা তাড়াতাড়ি কাটা পড়ে না।
List<FoundLink> parsePlaylist(
  String txt,
  String srcLabel, {
  List<ChannelQuery>? chs,
  String hostFilter = '',
}) {
  txt = txt.replaceFirst(RegExp('^\uFEFF'), '');
  final lines = txt.split(RegExp(r'\r\n|\r|\n'));
  final n = lines.length;
  final res = <FoundLink>[];
  String? inf;
  var hd = <String, String>{};
  var props = <String>[];

  int quoteCount(String s) => '"'.allMatches(s).length;

  for (var i = 0; i < n; i++) {
    var line = lines[i].trim();
    if (line.isEmpty) continue;

    if (RegExp(r'^#?EXTINF:', caseSensitive: false).hasMatch(line)) {
      if (!line.startsWith('#')) line = '#$line';
      var guard = 0;
      while (quoteCount(line) % 2 == 1 && i + 1 < n && guard++ < 5) {
        final nx = lines[i + 1].trim();
        if (nx.isEmpty ||
            nx.startsWith('#') ||
            RegExp(r'^https?://', caseSensitive: false).hasMatch(nx)) break;
        line = '$line $nx';
        i++;
      }
      inf = line;
      continue;
    }

    // ভাঙা attribute-এর পরের অংশ (যেমন license_key= পরের লাইনে চলে গেছে)
    if (!line.startsWith('#') &&
        !RegExp(r'https?://', caseSensitive: false).hasMatch(line) &&
        props.isNotEmpty) {
      final li = props.length - 1;
      final openB = '{'.allMatches(props[li]).length;
      final closeB = '}'.allMatches(props[li]).length;
      if (RegExp(r'[=?&]\s*$').hasMatch(props[li]) || openB > closeB) {
        props[li] = props[li] + line;
        continue;
      }
    }

    if (line.startsWith('#')) {
      final jm =
          RegExp(r'^#EXTHTTP:\s*(\{.*\})', caseSensitive: false).firstMatch(line);
      if (jm != null) {
        try {
          final j = jsonDecode(jm.group(1)!);
          if (j is Map) {
            j.forEach((jk, jv) {
              if (jv is String) hdrSet(hd, jk.toString(), jv);
            });
          }
        } catch (_) {}
      } else {
        final km = RegExp(r'^#KODIPROP:(.*)$', caseSensitive: false).firstMatch(line);
        if (km != null) {
          props.add(km.group(1)!.trim());
        } else {
          final vm =
              RegExp(r'^#EXTVLCOPT:(.*)$', caseSensitive: false).firstMatch(line);
          if (vm != null) {
            final d = vm.group(1)!.trim();
            final om =
                RegExp(r'^(http-[a-z-]+)=(.*)$', caseSensitive: false).firstMatch(d);
            if (om != null) hdrSet(hd, om.group(1)!, om.group(2)!);
          }
        }
      }
      continue;
    }

    if (inf == null) continue;
    final um = RegExp(r'https?://.*$', caseSensitive: false).firstMatch(line);
    if (um == null) continue;
    line = um.group(0)!.trim();
    if (!line.contains('|')) line = line.split(RegExp(r'\s+')).first;

    final name = infName(inf);

    var url = line;
    final ph = <String, String>{};
    final pIdx = line.indexOf('|');
    if (pIdx >= 0) {
      url = line.substring(0, pIdx);
      final rest = line.substring(pIdx + 1);
      for (final kv in rest.split(RegExp(r'[|&]'))) {
        final x = kv.split('=');
        final k = (x.isNotEmpty ? x[0] : '').trim().toLowerCase();
        var v = x.length > 1 ? x.sublist(1).join('=').trim() : '';
        try {
          v = Uri.decodeComponent(v);
        } catch (_) {}
        if (k == 'user-agent') {
          ph['user-agent'] = v;
        } else if (k == 'referer' || k == 'referrer') {
          ph['referer'] = v;
        } else if (k == 'origin') {
          ph['origin'] = v;
        } else if (k == 'drmlicense') {
          props.add('inputstream.adaptive.license_type=clearkey');
          props.add('inputstream.adaptive.license_key=$v');
        }
      }
    }

    final curInf = inf;
    final curHd = Map<String, String>.from(hd);
    final curProps = List<String>.from(props);
    inf = null;
    hd = {};
    props = [];

    if (RegExp(r'\.(mp4|mkv|avi|jpe?g|png|gif|webp|srt|vtt|json|txt)(\?|$)',
            caseSensitive: false)
        .hasMatch(url)) continue;

    final tvgid = attrOf(curInf, 'tvg-id');
    final tvglogo = attrOf(curInf, 'tvg-logo');
    final grp = attrOf(curInf, 'group-title').trim();
    final hay = '$name ${attrOf(curInf, 'tvg-name')} $tvgid';
    final hdrs = {...curHd, ...ph};

    if (chs != null) {
      for (var ci = 0; ci < chs.length; ci++) {
        if (chMatches(chs[ci], hay)) {
          res.add(FoundLink(
            chIndex: ci,
            channelName: chs[ci].name,
            label: name,
            url: url,
            group: grp,
            headers: hdrs,
            props: curProps,
            tvgId: tvgid,
            tvgLogo: tvglogo,
            host: extractHost(url),
            src: srcLabel,
          ));
        }
      }
    } else if (hostFilter.isNotEmpty) {
      if (url.toLowerCase().contains(hostFilter.toLowerCase()) ||
          extractHost(url) == hostFilter) {
        res.add(FoundLink(
          chIndex: -1,
          channelName: name,
          label: '',
          url: url,
          group: grp,
          headers: hdrs,
          props: curProps,
          tvgId: tvgid,
          tvgLogo: tvglogo,
          host: extractHost(url),
          src: srcLabel,
        ));
      }
    }
  }
  return res;
}
