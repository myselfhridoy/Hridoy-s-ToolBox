class IptvFinderPage extends StatefulWidget {
  const IptvFinderPage({super.key});

  @override
  State<IptvFinderPage> createState() => _IptvFinderPageState();
}

class _IptvFinderPageState extends State<IptvFinderPage> {
  static SharedPreferences? _prefs;

  final _channelsC = TextEditingController();
  final _extraC = TextEditingController();
  final _hostsC = TextEditingController();
  final _xUserC = TextEditingController();
  final _xPassC = TextEditingController();
  final _groupC = TextEditingController();
  final _scrollC = ScrollController();

  String _mode = 'ch'; // ch | ht
  int _pages = 3;
  bool _validate = true;
  bool _keepDead = true;
  bool _verifyAllHosts = true;
  bool _useGhDomainSearch = true;
  String _player = 'tivimate';

  bool _busy = false;
  bool _aborted = false;
  String _stage = 'Ready';
  int _progA = 0;
  int _progB = 0;
  int _foundCount = 0;
  bool _finished = true;

  final List<String> _logLines = [];
  final Set<String> _chipNames = {};
  final List<FoundLink> _results = [];
  final Set<int> _selected = {};

  String _filterChannel = '';
  String _filterHost = '';
  bool _onlyOk = false;
  bool _hideDirect = false;
  bool _hideXtream = false;
  int _showLimit = 100;

  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  @override
  void dispose() {
    _channelsC.dispose();
    _extraC.dispose();
    _hostsC.dispose();
    _xUserC.dispose();
    _xPassC.dispose();
    _groupC.dispose();
    _scrollC.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    _channelsC.text = _prefs!.getString('iptv_channels') ?? '';
    _extraC.text = _prefs!.getString('iptv_extra') ?? '';
    _hostsC.text = _prefs!.getString('iptv_hosts') ?? '';
    _groupC.text = _prefs!.getString('iptv_group') ?? '';
    _mode = _prefs!.getString('iptv_mode') ?? 'ch';
    _player = _prefs!.getString('iptv_player') ?? 'tivimate';
    if (mounted) setState(() {});
  }

  Future<void> _savePrefs() async {
    await _prefs?.setString('iptv_channels', _channelsC.text);
    await _prefs?.setString('iptv_extra', _extraC.text);
    await _prefs?.setString('iptv_hosts', _hostsC.text);
    await _prefs?.setString('iptv_group', _groupC.text);
    await _prefs?.setString('iptv_mode', _mode);
    await _prefs?.setString('iptv_player', _player);
  }

  // ───────────── small UI helpers ─────────────

  void _scheduleRebuild() {
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    Future.delayed(const Duration(milliseconds: 150), () {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _log(String m) {
    _logLines.add(m);
    if (_logLines.length > 200) _logLines.removeAt(0);
    _scheduleRebuild();
  }

  Future<void> _wait(int seconds, String why) async {
    _log('Waiting ${seconds}s: $why');
    await Future.delayed(Duration(seconds: seconds));
  }

  void _progress(String stage, int a, int b, {int? found}) {
    _stage = stage;
    _progA = a;
    _progB = b;
    if (found != null) _foundCount = found;
    _scheduleRebuild();
  }

  void _fail(String msg) {
    _log('⚠ $msg');
    _toast(msg);
    setState(() => _busy = false);
  }

  void _done(int found, int files, {String mode = 'channel'}) {
    _finished = true;
    _foundCount = found;
    _log(
        'শেষ — $found লিংক${files > 0 ? ' ($files ফাইল স্ক্যান করা হয়েছে)' : ''}');
    setState(() => _busy = false);
  }

  void _addChannelChip(String name) {
    if (_chipNames.add(name)) _scheduleRebuild();
  }

  void _addResult(FoundLink m) {
    m.i = _results.length;
    _results.add(m);
    _scheduleRebuild();
  }

  Timer? _toastTimer;
  String? _toastMsg;
  void _toast(String msg) {
    setState(() => _toastMsg = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Copied $label');
  }

  // ───────────── scan control ─────────────

  Future<void> _start() async {
    if (_mode == 'ch' && _channelsC.text.trim().isEmpty) {
      _toast('অন্তত একটা চ্যানেলের নাম দিন');
      return;
    }
    if (_mode == 'ht' && _hostsC.text.trim().isEmpty) {
      _toast('অন্তত একটা host বা URL দিন');
      return;
    }
    await _savePrefs();
    setState(() {
      _results.clear();
      _selected.clear();
      _chipNames.clear();
      _logLines.clear();
      _showLimit = 100;
      _filterChannel = '';
      _filterHost = '';
      _busy = true;
      _aborted = false;
      _finished = false;
      _stage = 'শুরু হচ্ছে…';
      _progA = 0;
      _progB = 0;
      _foundCount = 0;
    });
    try {
      if (_mode == 'ch') {
        await _runChannelScan();
      } else {
        await _runHostScan();
      }
    } catch (e) {
      _fail(e.toString());
      return;
    }
    if (!_finished) _done(_results.length, 0);
  }

  void _stop() {
    _aborted = true;
    _log('Stop চাপা হয়েছে — চলমান রিকোয়েস্ট শেষ হলে থামবে');
  }

  // ───────────── channel-mode scan ─────────────

  Future<void> _runChannelScan() async {
    final token = GitHubTokenStore.instance.token ?? '';
    final extra = _extraC.text.trim();
    if (token.isEmpty && extra.isEmpty) {
      _fail(
          'GitHub টোকেন সেট করুন (উপরে 🔒 আইকন) অথবা অন্তত একটা extra source দিন');
      return;
    }
    final chs = parseChannelsInput(_channelsC.text);
    if (chs.isEmpty) {
      _fail('অন্তত একটা চ্যানেলের নাম দিন');
      return;
    }
    for (final c in chs) {
      _addChannelChip(c.name);
    }

    final queries = <String>{};
    for (final c in chs) {
      for (final t in c.terms) {
        for (final e in ['m3u8', 'm3u']) {
          queries.add('"$t" extension:$e');
        }
      }
    }
    final uniqQueries = token.isEmpty ? <String>[] : queries.toList();
    final qTotal = uniqQueries.length;
    if (token.isEmpty) _log('No token: GitHub search skipped');

    final files = <String, String>{};
    var qn = 0;
    for (final q in uniqQueries) {
      if (_aborted) return;
      qn++;
      for (var p = 1; p <= _pages; p++) {
        if (_aborted) return;
        _progress('Searching p$p', qn, qTotal);
        GhSearchResult? d;
        try {
          d = await ghSearch(q, p, token, onWait: _wait, onLog: _log);
        } catch (e) {
          _fail(e.toString());
          return;
        }
        if (d == null || d.items.isEmpty) break;
        for (final it in d.items) {
          final raw = ghRawUrl(it.htmlUrl);
          if (raw.contains('raw.githubusercontent.com') &&
              !files.containsKey(raw)) {
            files[raw] = '${it.repoFullName}/${it.path}';
          }
        }
        final tc = d.totalCount;
        if (tc > 0 && p * 100 >= (tc < 1000 ? tc : 1000)) break;
      }
      _log('[$qn/$qTotal] $q -> ${files.length} files total');
    }

    var ex = 0;
    for (var eu in extra.split(RegExp(r'\r\n|\r|\n'))) {
      eu = eu.trim();
      if (eu.isEmpty) continue;
      final gm =
          RegExp(r'^gist:([A-Za-z0-9-]+)$', caseSensitive: false).firstMatch(eu);
      if (gm != null) {
        final g = await _gistUserFiles(gm.group(1)!, token, _log);
        for (final entry in g.entries) {
          if (!files.containsKey(entry.key)) {
            files[entry.key] = entry.value;
            ex++;
          }
        }
        _log('gist:${gm.group(1)} -> ${g.length} files');
        continue;
      }
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(eu)) continue;
      final neu = _normalizeExtra(eu);
      if (!files.containsKey(neu)) {
        files[neu] = 'extra: ${Uri.tryParse(neu)?.host ?? ''}';
        ex++;
      }
    }
    if (ex > 0) _log('$ex extra URL(s) added');

    final urls = files.keys.toList();
    final T = urls.length;
    final seen = <String>{};
    var found = 0, done = 0, okc = 0, chk = 0;
    final why = <String, int>{};

    for (var start = 0; start < urls.length; start += 30) {
      if (_aborted) return;
      final end = (start + 30 > urls.length) ? urls.length : start + 30;
      final chunk = urls.sublist(start, end);
      final bodies = await fetchFiles(chunk, concurrency: 6);
      final batch = <FoundLink>[];
      for (final u in chunk) {
        final body = bodies[u];
        if (body == null) continue;
        for (final m in parsePlaylist(body, files[u] ?? u, chs: chs)) {
          final k =
              '${m.chIndex}|${m.url}|${m.props.join(';')}|${m.headers['h_cookie'] ?? ''}';
          if (seen.contains(k)) continue;
          seen.add(k);
          if (_validate) {
            batch.add(m);
          } else {
            found++;
            _addResult(m);
          }
        }
      }
      if (_validate && batch.isNotEmpty) {
        await validateLinks(batch, (m) async {
          chk++;
          if (m.ok == true) {
            okc++;
            await enrichLicense(m);
          } else {
            final n = m.note.isEmpty ? 'unknown' : m.note;
            why[n] = (why[n] ?? 0) + 1;
          }
          if (m.ok == true || _keepDead) _addResult(m);
          if (chk % 8 == 0) _progress('Validating ($chk)', done, T, found: okc);
        }, concurrency: 10);
      }
      done += chunk.length;
      _progress('Scanning files', done, T, found: _validate ? okc : found);
    }

    if (_validate) {
      found = okc;
      _log('Validation: $okc ok, ${chk - okc} failed of $chk');
      if (why.isNotEmpty) {
        final sortedWhy = why.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final pp =
            sortedWhy.take(8).map((e) => '${e.key} x${e.value}').join(', ');
        _log('Failed: $pp');
      }
    }
    _done(found, T);
  }

  // ───────────── host-mode scan ─────────────

  Future<void> _runHostScan() async {
    final token = GitHubTokenStore.instance.token ?? '';
    final hostsIn = _hostsC.text.trim();
    final userOv = _xUserC.text.trim();
    final passOv = _xPassC.text.trim();
    final verifyAll = _verifyAllHosts;
    final useGh = _useGhDomainSearch && token.isNotEmpty;

    final hosts = hostsIn
        .split(RegExp(r'\r\n|\r|\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (hosts.isEmpty) {
      _fail('অন্তত একটা host বা URL দিন');
      return;
    }

    final seen = <String>{};
    var totalFound = 0;
    var totalOk = 0;
    final toVerify = <FoundLink>[];

    void emitRes(FoundLink m) {
      if (totalFound >= 20000) return;
      final k = '${m.url}|${m.headers['h_cookie'] ?? ''}';
      if (seen.contains(k)) return;
      seen.add(k);
      totalFound++;
      _addResult(m);
      if (verifyAll) toVerify.add(m);
    }

    for (var hi = 0; hi < hosts.length; hi++) {
      if (_aborted) return;
      _progress('Host ${hi + 1}', hi, hosts.length, found: totalFound);
      final h = hosts[hi];
      final hUrl = normalizeHostInput(h);
      var creds = xtreamCredsFromUrl(hUrl);
      final baseHost = extractHost(hUrl);
      _addChannelChip('Host: $baseHost');

      if (userOv.isNotEmpty && passOv.isNotEmpty) {
        try {
          final p = Uri.parse(hUrl);
          final b =
              '${p.scheme.isEmpty ? 'http' : p.scheme}://${p.host}${p.hasPort ? ':${p.port}' : ''}';
          creds = XtreamCreds(
              base: b, user: userOv, pass: passOv, kind: 'manual');
        } catch (_) {}
      }

      var hostFound = 0;

      if (creds != null) {
        _log('Xtream creds detected for $baseHost (${creds.kind})');
        final enumRes = await xtreamEnumerate(
            creds.base, creds.user, creds.pass, const {}, _log);
        if (enumRes.ok) {
          _log(
              'Xtream: ${enumRes.channels.length} channels via ${enumRes.method} (pattern: ${enumRes.pattern ?? 'n/a'})');
          final acc =
              enumRes.info?['user_info']?['username']?.toString() ?? '';
          for (final c in enumRes.channels) {
            c.src = 'xtream:$baseHost${acc.isNotEmpty ? ' ($acc)' : ''}';
            c.xtream = true;
            c.xtUser = creds.user;
            c.xtPass = creds.pass;
            c.xtBase = creds.base;
            emitRes(c);
            hostFound++;
          }
          _log('Host $baseHost: $hostFound channels emitted');
        } else {
          _log('Xtream failed for $baseHost: ${enumRes.error}');
        }
      }

      if (hostFound == 0 && useGh) {
        _log('GitHub search for domain $baseHost...');
        final domain = baseHost.split(':').first;
        final ghQ = ['"$domain" extension:m3u', '"$domain" extension:m3u8'];
        final ghFiles = <String>{};
        var cappedOut = false;
        for (final q in ghQ) {
          if (cappedOut) break;
          for (var p = 1; p <= 3; p++) {
            GhSearchResult? d;
            try {
              d = await ghSearch(q, p, token, onWait: _wait, onLog: _log);
            } catch (e) {
              _fail(e.toString());
              return;
            }
            if (d == null || d.items.isEmpty) break;
            for (final it in d.items) {
              final raw = ghRawUrl(it.htmlUrl);
              if (raw.contains('raw.githubusercontent.com')) ghFiles.add(raw);
            }
            if (ghFiles.length > 200) {
              cappedOut = true;
              break;
            }
          }
        }
        _log('GitHub: ${ghFiles.length} files containing domain');
        if (ghFiles.isNotEmpty) {
          final foundXtream = <String, XtreamCreds>{};
          final keys = ghFiles.toList();
          for (var start = 0; start < keys.length; start += 30) {
            final end = (start + 30 > keys.length) ? keys.length : start + 30;
            final chunk = keys.sublist(start, end);
            final bodies = await fetchFiles(chunk, concurrency: 6);
            for (final u in chunk) {
              final body = bodies[u];
              if (body == null) continue;
              final parsed =
                  parsePlaylist(body, 'gh-host:$u', hostFilter: baseHost);
              for (final m in parsed) {
                emitRes(m);
                hostFound++;
                final cc = xtreamCredsFromUrl(m.url);
                if (cc != null) {
                  foundXtream.putIfAbsent(
                      '${cc.base}|${cc.user}|${cc.pass}', () => cc);
                }
              }
            }
          }
          for (final cc in foundXtream.values) {
            _log('Discovered Xtream: ${cc.base} -> enumerating');
            final enumRes = await xtreamEnumerate(
                cc.base, cc.user, cc.pass, const {}, _log);
            if (enumRes.ok) {
              for (final c in enumRes.channels) {
                c.src = 'xtream-enum:${extractHost(cc.base)}';
                c.xtream = true;
                c.xtUser = cc.user;
                c.xtPass = cc.pass;
                c.xtBase = cc.base;
                emitRes(c);
                hostFound++;
              }
              _log('Enumerated ${enumRes.channels.length} from ${cc.base}');
            }
          }
        }
      }

      if (hostFound == 0) {
        try {
          final p = Uri.parse(hUrl);
          if (p.host.isNotEmpty) {
            final b =
                '${p.scheme.isEmpty ? 'http' : p.scheme}://${p.host}${p.hasPort ? ':${p.port}' : ''}';
            _log('Probing common paths on $b...');
            final hits = await hostCommonProbes(b, const {});
            hits.forEach((hu, body) {
              final parsed =
                  parsePlaylist(body, 'probe:$hu', hostFilter: baseHost);
              for (final m in parsed) {
                emitRes(m);
                hostFound++;
              }
            });
          }
        } catch (_) {}
      }

      if (hostFound == 0) _log('Host $baseHost: nothing found');
      _progress('Host ${hi + 1}', hi + 1, hosts.length, found: totalFound);
    }

    if (verifyAll && toVerify.isNotEmpty) {
      _log('Starting verification for ${toVerify.length} links...');
      final chunks = <List<FoundLink>>[];
      for (var i = 0; i < toVerify.length; i += 50) {
        final end = (i + 50 > toVerify.length) ? toVerify.length : i + 50;
        chunks.add(toVerify.sublist(i, end));
      }
      for (var ci = 0; ci < chunks.length; ci++) {
        if (_aborted) return;
        await validateLinks(chunks[ci], (m) async {
          if (m.ok == true) {
            totalOk++;
            await enrichLicense(m);
          }
          _scheduleRebuild();
        }, concurrency: 20);
        _progress('Verifying (${ci + 1}/${chunks.length})', ci + 1,
            chunks.length,
            found: totalOk);
      }
      _log('Verification finished. Found $totalOk working links.');
    }

    _log('Total: $totalFound channels from ${hosts.length} host(s)');
    _done(totalFound, 0, mode: 'host');
  }

  Future<void> _verifyUnverified() async {
    final items = _results.where((r) => r.ok != true).toList();
    if (items.isEmpty) {
      _toast('কিছু ভ্যারিফাই করার নেই');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('যাচাই করবেন?'),
        content: Text('${items.length}টি লিংক যাচাই করতে সময় লাগতে পারে।'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('যাচাই করুন')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await validateLinks(items, (m) async {
      if (m.ok == true) await enrichLicense(m);
      _scheduleRebuild();
    }, concurrency: 16);
    setState(() => _busy = false);
  }

  void _exploreHost(String host) {
    setState(() {
      _mode = 'ht';
      _hostsC.text = host;
    });
    _scrollC.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ───────────── filtering/selection ─────────────

  int _cmp(FoundLink a, FoundLink b) {
    final okA = a.ok == true ? 1 : 0, okB = b.ok == true ? 1 : 0;
    if (okB != okA) return okB - okA;
    if (b.h != a.h) return b.h - a.h;
    final msA = a.ms ?? 900000, msB = b.ms ?? 900000;
    return msA - msB;
  }

  List<FoundLink> get _visibleResults {
    final list = _results.where((r) {
      if (_filterChannel.isNotEmpty && r.channelName != _filterChannel) {
        return false;
      }
      if (_filterHost.isNotEmpty && r.host != _filterHost) return false;
      if (_onlyOk && r.ok != true) return false;
      if (_hideDirect && r.note == 'direct') return false;
      if (_hideXtream && r.isXtream) return false;
      return true;
    }).toList();
    list.sort(_cmp);
    return list;
  }

  List<FoundLink> get _pickItems {
    if (_selected.isEmpty) return _visibleResults;
    final list = _results.where((r) => _selected.contains(r.i)).toList();
    list.sort(_cmp);
    return list;
  }

  List<String> get _channelOptions =>
      _results.map((r) => r.channelName).toSet().toList()..sort();

  List<({String host, int ok, int total})> get _hostStats {
    final by = <String, ({int ok, int total})>{};
    for (final r in _results) {
      if (r.host.isEmpty) continue;
      final cur = by[r.host] ?? (ok: 0, total: 0);
      by[r.host] = (ok: cur.ok + (r.ok == true ? 1 : 0), total: cur.total + 1);
    }
    final list = by.entries
        .map((e) => (host: e.key, ok: e.value.ok, total: e.value.total))
        .toList();
    list.sort((a, b) => b.ok != a.ok ? b.ok - a.ok : b.total - a.total);
    return list;
  }

  // ───────────── token dialog ─────────────

  Future<void> _openTokenDialog() async {
    final controller =
        TextEditingController(text: GitHubTokenStore.instance.token ?? '');
    var obscure = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('GitHub Token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GitHub Code Search-এর জন্য একটা Personal Access Token লাগবে।\n'
                'gittomd টুলের সাথে এই টোকেন শেয়ার করা হয়।',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                obscureText: obscure,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: 'ghp_… or github_pat_…',
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show token' : 'Hide token',
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await GitHubTokenStore.instance.clear();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Clear'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await GitHubTokenStore.instance.save(controller.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  // ───────────── build ─────────────

  @override
  Widget build(BuildContext context) {
    final hasToken = GitHubTokenStore.instance.hasToken;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPTV Finder'),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Icon(
              hasToken ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: hasToken ? AppColors.success : null,
            ),
            tooltip: hasToken ? 'Token সেট আছে' : 'GitHub token সেট করুন',
            onPressed: _openTokenDialog,
          ),
        ],
      ),
      body: AmbientBackdrop(
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollC,
              slivers: [
                SliverToBoxAdapter(child: _buildForm(t)),
                SliverToBoxAdapter(child: _buildProgressPanel(t)),
                if (_results.isNotEmpty)
                  SliverToBoxAdapter(child: _buildToolsPanel(t)),
                if (_results.isNotEmpty) _buildResultsSliver(t),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
            if (_toastMsg != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 100,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Text(
                      _toastMsg!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _results.isNotEmpty ? _buildDock(t) : null,
    );
  }

  Widget _buildForm(TextTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: GlassCard(
        radius: AppRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ch',
                      label: Text('By Channel'),
                      icon: Icon(Icons.tv_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: 'ht',
                      label: Text('By Host'),
                      icon: Icon(Icons.dns_rounded, size: 18),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_mode == 'ch') _buildChannelForm(t) else _buildHostForm(t),
              const SizedBox(height: AppSpacing.md),
              Text('Player format',
                  style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                value: _player,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: 'tivimate', child: Text('TiviMate / OTT')),
                  DropdownMenuItem(value: 'kodi', child: Text('Kodi')),
                  DropdownMenuItem(value: 'vlc', child: Text('VLC')),
                ],
                onChanged: (v) => setState(() => _player = v ?? _player),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(_busy ? 'চলছে…' : 'Start scan'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? _stop : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                        color: _busy
                            ? AppColors.error.withValues(alpha: 0.5)
                            : AppColors.glassBorder,
                      ),
                    ),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelForm(TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('চ্যানেল · এক লাইনে একটা, alias-এর জন্য | ব্যবহার করুন',
            style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _channelsC,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'Sky Sports Cricket | SkySportsCricket\nStar Sports 1\nT Sports',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Extra sources', style: t.titleMedium),
          children: [
            Text('Playlist / gist / pastebin URL, অথবা gist:username',
                style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _extraC,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '[https://example.com/playlist.m3u](https://example.com/playlist.m3u)\ngist:username',
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('GitHub search pages',
            style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<int>(
          value: _pages,
          items: const [1, 3, 5, 10]
              .map((p) => DropdownMenuItem(value: p, child: Text('$p')))
              .toList(),
          onChanged: (v) => setState(() => _pages = v ?? _pages),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Deep validate'),
          subtitle: const Text('manifest → variant → segment'),
          value: _validate,
          onChanged: (v) => setState(() => _validate = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show failed links'),
          subtitle: const Text('মৃত লিংকও ফলাফলে রাখুন'),
          value: _keepDead,
          onChanged: (v) => setState(() => _keepDead = v),
        ),
      ],
    );
  }

  Widget _buildHostForm(TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Host / URL · host, host:port অথবা পূর্ণ Xtream URL',
            style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _hostsC,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                '[http://iptv.example.com:8080/live/user1/pass1/12345.m3u8](http://iptv.example.com:8080/live/user1/pass1/12345.m3u8)\n'
                'another-server.com',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
            'যেকোনো কাজ করা Xtream স্ট্রিম URL পেস্ট করলেই credential বের করে সব চ্যানেল এনুমারেট হবে।',
            style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _xUserC,
                decoration:
                    const InputDecoration(hintText: 'username (optional)'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _xPassC,
                decoration:
                    const InputDecoration(hintText: 'password (optional)'),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verify all channels'),
          subtitle: const Text('ধীরে, কিন্তু বেশি নির্ভুল'),
          value: _verifyAllHosts,
          onChanged: (v) => setState(() => _verifyAllHosts = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('GitHub domain search'),
          subtitle: const Text('GitHub token লাগবে'),
          value: _useGhDomainSearch,
          onChanged: (v) => setState(() => _useGhDomainSearch = v),
        ),
      ],
    );
  }

  Widget _buildProgressPanel(TextTheme t) {
    final pct =
        _progB > 0 ? (_progA / _progB * 100).clamp(0, 100).round() : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: GlassCard(
        radius: AppRadius.md,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _busy
                          ? AppColors.primary
                          : (_foundCount > 0
                              ? AppColors.success
                              : AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_stage${_progB > 0 ? ' · $_progA/$_progB' : ''}${_foundCount > 0 ? ' · found $_foundCount' : ''}',
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: t.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progB > 0 ? _progA / _progB : (_busy ? null : 0.0),
                  minHeight: 6,
                  backgroundColor: AppColors.fieldFill,
                ),
              ),
              if (_logLines.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Log দেখুন',
                      style:
                          t.labelSmall?.copyWith(color: AppColors.textMuted)),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.navBg,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: Text(
                            _logLines.join('\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolsPanel(TextTheme t) {
    final channelOpts = _channelOptions;
    final hostOpts = _hostStats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            radius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value:
                              _filterChannel.isEmpty ? null : _filterChannel,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          hint: const Text('All channels'),
                          items: channelOpts
                              .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _filterChannel = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filterHost.isEmpty ? null : _filterHost,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          hint: const Text('All hosts'),
                          items: hostOpts
                              .map((h) => DropdownMenuItem(
                                  value: h.host,
                                  child: Text(
                                      '${h.host} (${h.ok}/${h.total})',
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _filterHost = v ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        label: const Text('✓ Verified only'),
                        selected: _onlyOk,
                        onSelected: (v) => setState(() => _onlyOk = v),
                      ),
                      FilterChip(
                        label: const Text('Hide direct'),
                        selected: _hideDirect,
                        onSelected: (v) => setState(() => _hideDirect = v),
                      ),
                      FilterChip(
                        label: const Text('Hide Xtream'),
                        selected: _hideXtream,
                        onSelected: (v) => setState(() => _hideXtream = v),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title:
                        Text('Selection, verify ও group', style: t.titleMedium),
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(() {
                              for (final r in _visibleResults) {
                                _selected.add(r.i);
                              }
                            }),
                            child: const Text('Select shown'),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              for (final r in _visibleResults) {
                                if (r.ok == true) _selected.add(r.i);
                              }
                            }),
                            child: const Text('Select verified'),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(_selected.clear),
                            child: const Text('Clear selection'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : _verifyUnverified,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error),
                            child: const Text('Verify unverified'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _groupC,
                        decoration: const InputDecoration(
                            labelText:
                                'M3U group-title (ফাঁকা = সোর্সের group)'),
                      ),
                    ],
                  ),
                  if (hostOpts.length > 1) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text('Hosts',
                        style: t.labelSmall
                            ?.copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: hostOpts.length > 50 ? 50 : hostOpts.length,
                        itemBuilder: (_, i) {
                          final hst = hostOpts[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(hst.host,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12)),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                Chip(
                                    label: Text('${hst.ok}/${hst.total}'),
                                    visualDensity: VisualDensity.compact),
                                TextButton(
                                    onPressed: () => _exploreHost(hst.host),
                                    child: const Text('Explore')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildResultsSliver(TextTheme t) {
    final visible = _visibleResults;
    final shown = visible.take(_showLimit).toList();
    final hasMore = visible.length > _showLimit;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverList.separated(
        itemCount: shown.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i >= shown.length) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _showLimit += 100),
                child: Text(
                    'আরও ${(visible.length - _showLimit).clamp(0, 100)} দেখান'),
              ),
            );
          }
          return _resultCard(shown[i], t);
        },
      ),
    );
  }

  Widget _resultCard(FoundLink r, TextTheme t) {
    final color = r.ok == true
        ? AppColors.success
        : r.ok == false
            ? AppColors.error
            : AppColors.textMuted;
    final lic = licHex(r);
    final url = finalUrl(r, _player);

    return GlassCard(
      radius: AppRadius.md,
      borderColor: r.ok == true
          ? AppColors.success.withValues(alpha: 0.35)
          : AppColors.glassBorder,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.07), Colors.transparent],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _selected.contains(r.i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(r.i);
                } else {
                  _selected.remove(r.i);
                }
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.channelName, style: t.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _badge(
                        r.ok == true
                            ? '✓ verified'
                            : (r.ok == false ? '✕ failed' : '• unchecked'),
                        color: color,
                      ),
                      if (r.h > 0) _badge('${r.h}p'),
                      if (r.ms != null) _badge('${r.ms}ms'),
                      if (r.note.isNotEmpty) _badge(r.note),
                      if (r.isXtream)
                        _badge('xtream', color: AppColors.secondary),
                      if (r.isPortal)
                        _badge('portal', color: AppColors.secondary),
                      if (lic.isNotEmpty)
                        _badge('🔑 key', color: AppColors.success),
                      if (r.group.isNotEmpty) _badge(r.group),
                      if (r.host.isNotEmpty)
                        _badge(r.host, color: AppColors.primary),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(r.src,
                      style: t.labelSmall?.copyWith(color: AppColors.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.navBg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(url,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      TextButton.icon(
                        onPressed: () => _copy(url, 'link'),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy'),
                      ),
                      if (r.host.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _exploreHost(r.host),
                          icon: const Icon(Icons.explore_outlined, size: 16),
                          label: const Text('Explore host'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style:
              TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDock(TextTheme t) {
    final count = _visibleResults.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.navBg,
          border: Border(top: BorderSide(color: AppColors.glassBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$count links',
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
                Text(
                    _selected.isNotEmpty
                        ? '${_selected.length} selected'
                        : 'all shown',
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final items = _pickItems;
                      if (items.isEmpty) return;
                      _copy(buildM3U(items, _player, _groupC.text.trim()),
                          '${items.length} channels (M3U)');
                    },
                    child: const Text('Copy M3U'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final items = _pickItems;
                      if (items.isEmpty) return;
                      _copy(items.map((r) => finalUrl(r, _player)).join('\n'),
                          '${items.length} URLs');
                    },
                    child: const Text('URLs'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final items = _pickItems;
                      if (items.isEmpty) return;
                      final list = items
                          .map((r) => {
                                'name': r.channelName,
                                'url': finalUrl(r, _player),
                                'group': r.group,
                                'host': r.host,
                                'ok': r.ok,
                                'note': r.note,
                              })
                          .toList();
                      _copy(const JsonEncoder.withIndent('  ').convert(list),
                          '${items.length} items (JSON)');
                    },
                    child: const Text('JSON'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

