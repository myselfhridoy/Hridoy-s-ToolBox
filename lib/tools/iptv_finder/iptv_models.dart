/// IPTV Finder-এর জন্য মডেল ক্লাস।

/// একটা চ্যানেলের সার্চ কোয়েরি (নাম + alias-গুলো)।
class ChannelQuery {
  final String name;
  final List<String> terms;
  final List<String> norms;
  final List<List<String>> words;

  ChannelQuery({
    required this.name,
    required this.terms,
    required this.norms,
    required this.words,
  });
}

/// একটা পাওয়া স্ট্রিম লিংক — যাচাইয়ের আগে ও পরের অবস্থাসহ।
/// এটা একটা mutable ক্লাস: validate/verify ধাপে একই অবজেক্টের ফিল্ড
/// সরাসরি বদলে দেওয়া হয়, যাতে UI-তে আলাদা করে "আপডেট" করতে না হয়।
class FoundLink {
  /// ফলাফল লিস্টে এর ইনডেক্স (UI-তে সিলেকশনের জন্য ব্যবহৃত)।
  int i = -1;
  final int chIndex; // host scan-এ -1
  final String channelName;
  final String label;
  String url;
  final String group;
  Map<String, String> headers;
  final List<String> props;
  final String tvgId;
  final String tvgLogo;
  final String host;
  String src;
  final String? cat;
  bool xtream;
  String? xtUser;
  String? xtPass;
  String? xtBase;
  bool? ok;
  int? ms;
  int h;
  int bw;
  String note;
  String? lickey;
  String? origUrl;
  bool portalAltTried;
  String? browserUa;

  FoundLink({
    required this.chIndex,
    required this.channelName,
    required this.label,
    required this.url,
    required this.group,
    Map<String, String>? headers,
    List<String>? props,
    this.tvgId = '',
    this.tvgLogo = '',
    required this.host,
    required this.src,
    this.cat,
    this.xtream = false,
    this.xtUser,
    this.xtPass,
    this.xtBase,
    this.ok,
    this.ms,
    this.h = 0,
    this.bw = 0,
    this.note = '',
    this.lickey,
    this.origUrl,
    this.portalAltTried = false,
    this.browserUa,
  })  : headers = headers ?? {},
        props = props ?? [];

  bool get isXtream =>
      xtream ||
      RegExp(r'/(live|movie|series)/[^/?]+/[^/?]+/\d+',
              caseSensitive: false)
          .hasMatch(url) ||
      RegExp(r'[?&]username=', caseSensitive: false).hasMatch(url);

  bool get isPortal =>
      RegExp(r'[?&]mac=', caseSensitive: false).hasMatch(url);

  // ───────────────────────── persistence ─────────────────────────

  /// সেশন ফাইলে লেখার জন্য।
  Map<String, dynamic> toJson() => {
        'i': i,
        'chIndex': chIndex,
        'channelName': channelName,
        'label': label,
        'url': url,
        'group': group,
        'headers': headers,
        'props': props,
        'tvgId': tvgId,
        'tvgLogo': tvgLogo,
        'host': host,
        'src': src,
        'cat': cat,
        'xtream': xtream,
        'xtUser': xtUser,
        'xtPass': xtPass,
        'xtBase': xtBase,
        'ok': ok,
        'ms': ms,
        'h': h,
        'bw': bw,
        'note': note,
        'lickey': lickey,
        'origUrl': origUrl,
        'portalAltTried': portalAltTried,
        'browserUa': browserUa,
      };

  /// সেশন ফাইল থেকে পড়ার জন্য। unknown ফিল্ড ignore করে।
  factory FoundLink.fromJson(Map<String, dynamic> j) {
    final f = FoundLink(
      chIndex: (j['chIndex'] as num?)?.toInt() ?? -1,
      channelName: j['channelName'] as String? ?? '',
      label: j['label'] as String? ?? '',
      url: j['url'] as String? ?? '',
      group: j['group'] as String? ?? '',
      headers: (j['headers'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      props: (j['props'] as List?)?.map((e) => e.toString()).toList(),
      tvgId: j['tvgId'] as String? ?? '',
      tvgLogo: j['tvgLogo'] as String? ?? '',
      host: j['host'] as String? ?? '',
      src: j['src'] as String? ?? '',
      cat: j['cat'] as String?,
      xtream: j['xtream'] as bool? ?? false,
      xtUser: j['xtUser'] as String?,
      xtPass: j['xtPass'] as String?,
      xtBase: j['xtBase'] as String?,
      ok: j['ok'] as bool?,
      ms: (j['ms'] as num?)?.toInt(),
      h: (j['h'] as num?)?.toInt() ?? 0,
      bw: (j['bw'] as num?)?.toInt() ?? 0,
      note: j['note'] as String? ?? '',
      lickey: j['lickey'] as String?,
      origUrl: j['origUrl'] as String?,
      portalAltTried: j['portalAltTried'] as bool? ?? false,
      browserUa: j['browserUa'] as String?,
    );
    f.i = (j['i'] as num?)?.toInt() ?? -1;
    return f;
  }
}
