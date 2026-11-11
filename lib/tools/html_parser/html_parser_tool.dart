import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import '../../core/plugin/tool_plugin.dart';
import '../../core/tokens.dart';
import '../../core/utils/html_utils.dart';

class HtmlParserTool implements ToolPlugin {
  @override
  String get id => 'html_parser';

  @override
  String get name => 'HTML Parser';

  @override
  IconData get icon => Icons.code;

  @override
  List<String> get categories => ['Developer'];

  @override
  List<String> get tags =>
      ['html', 'parser', 'css', 'scrape', 'ai', 'selector', 'script'];

  @override
  Widget buildPage(BuildContext context) => const HtmlParserPage();
}

// ───────────────────────── helpers (top-level) ─────────────────────────

const _dropTags = {
  'script', 'style', 'noscript', 'svg', 'link', 'iframe', 'canvas',
  'meta', 'path', 'template',
};

const _voidTags = {
  'br', 'hr', 'img', 'input', 'meta', 'link', 'source', 'area', 'base',
  'col', 'embed', 'track', 'wbr',
};

const _keepAttrs = {
  'id', 'class', 'href', 'src', 'name', 'type', 'value', 'placeholder',
  'alt', 'title', 'role', 'action', 'method', 'for', 'content',
  'itemprop', 'rel', 'target',
};

const _langs = [
  'Python (requests + BeautifulSoup)',
  'Python (Playwright)',
  'Node.js (axios + cheerio)',
  'Dart (http + html)',
  'JavaScript (browser console)',
];

final _identRe = RegExp(r'^[A-Za-z_][\w-]*$');
bool _ident(String s) => _identRe.hasMatch(s);

String _short(String s, int n) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > n ? '${t.substring(0, n)}…' : t;
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _attrString(dom.Element e) {
  final b = StringBuffer();
  e.attributes.forEach((k, v) {
    final key = k.toString();
    final keep = _keepAttrs.contains(key) ||
        key.startsWith('data-') ||
        key == 'aria-label';
    if (!keep) return;
    var val = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key == 'class' && val.isEmpty) return;
    if (val.startsWith('data:')) val = 'data:…';
    if (val.length > 150) val = '${val.substring(0, 150)}…';
    b.write(' $key="${val.replaceAll('"', "'")}"');
  });
  return b.toString();
}

/// AI-এর জন্য ছোট ও পরিষ্কার HTML বানায় (script/style/svg বাদ)।
void _cleanNode(StringBuffer b, dom.Node n, int depth, {int maxText = 160}) {
  final ind = '  ' * depth;

  if (n is dom.Text) {
    final t = n.data.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    final cut = t.length > maxText ? '${t.substring(0, maxText)}…' : t;
    b.writeln('$ind${_esc(cut)}');
    return;
  }
  if (n is! dom.Element) return;

  final tag = n.localName ?? '';
  if (_dropTags.contains(tag)) return;

  if (tag == 'head') {
    final title = n.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) {
      b.writeln('$ind<title>${_esc(title)}</title>');
    }
    return;
  }

  final attrs = _attrString(n);
  if (_voidTags.contains(tag)) {
    b.writeln('$ind<$tag$attrs>');
    return;
  }

  final kids = n.nodes.where((c) {
    if (c is dom.Element) return !_dropTags.contains(c.localName);
    if (c is dom.Text) return c.data.trim().isNotEmpty;
    return false;
  }).toList();

  if (kids.isEmpty) {
    if (attrs.isEmpty) return;
    b.writeln('$ind<$tag$attrs></$tag>');
    return;
  }

  if (kids.length == 1 && kids.first is dom.Text) {
    final t = (kids.first as dom.Text)
        .data
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cut = t.length > maxText ? '${t.substring(0, maxText)}…' : t;
    b.writeln('$ind<$tag$attrs>${_esc(cut)}</$tag>');
    return;
  }

  b.writeln('$ind<$tag$attrs>');
  for (final c in kids) {
    _cleanNode(b, c, depth + 1, maxText: maxText);
  }
  b.writeln('$ind</$tag>');
}

String _cleanElementHtml(dom.Element e, {int limit = 1500}) {
  final b = StringBuffer();
  _cleanNode(b, e, 0);
  var s = b.toString().trimRight();
  if (s.length > limit) s = '${s.substring(0, limit)}\n… (truncated)';
  return s;
}

dom.Element? _parentEl(dom.Element e) {
  final p = e.parentNode;
  return p is dom.Element ? p : null;
}

String _sig(dom.Element e) {
  final cls = e.classes.where(_ident).take(2).toList();
  return '${e.localName}${cls.isEmpty ? '' : '.${cls.join('.')}'}';
}

/// একটি element-এর জন্য CSS selector path বানায়।
String _cssPath(dom.Element e) {
  final parts = <String>[];
  dom.Element? cur = e;
  while (cur != null && cur.localName != 'html') {
    final c = cur;
    var seg = c.localName ?? '*';
    if (c.id.isNotEmpty && _ident(c.id)) {
      parts.insert(0, '#${c.id}');
      break;
    }
    final classes = c.classes.where(_ident).take(2).toList();
    if (classes.isNotEmpty) seg += '.${classes.join('.')}';
    final parent = _parentEl(c);
    if (parent != null && classes.isEmpty) {
      final sibs =
          parent.children.where((x) => x.localName == c.localName).toList();
      if (sibs.length > 1) seg += ':nth-of-type(${sibs.indexOf(c) + 1})';
    }
    parts.insert(0, seg);
    cur = parent;
  }
  return parts.join(' > ');
}

String _label(dom.Element e) {
  final id = e.id.isEmpty ? '' : '#${e.id}';
  final cls = e.classes.isEmpty ? '' : '.${e.classes.take(2).join('.')}';
  return '<${e.localName}$id$cls>';
}

// ───────────────────────── models ─────────────────────────

class _NodeRow {
  final dom.Element el;
  final int depth;
  _NodeRow(this.el, this.depth);
}

class _Match {
  final String path;
  final String tag;
  final String text;
  final Map<String, String> attrs;
  final String html;
  _Match({
    required this.path,
    required this.tag,
    required this.text,
    required this.attrs,
    required this.html,
  });
}

// ───────────────────────── page ─────────────────────────

class HtmlParserPage extends StatefulWidget {
  const HtmlParserPage({super.key});

  @override
  State<HtmlParserPage> createState() => _HtmlParserPageState();
}

class _HtmlParserPageState extends State<HtmlParserPage>
    with SingleTickerProviderStateMixin {
  final _urlC = TextEditingController();
  final _htmlC = TextEditingController();
  final _selC = TextEditingController();
  final _taskC = TextEditingController();
  late final TabController _tab;

  dom.Document? _doc;
  String? _error;
  bool _loading = false;
  String _sourceUrl = '';
  String _clean = '';
  String _report = '';
  List<_NodeRow> _rows = [];
  List<_Match> _matches = [];
  int _matchTotal = 0;

  String _lang = _langs.first;
  int _maxChars = 30000;

  static const _sampleHtml = '''<!DOCTYPE html>
<html>
<head><title>Sample Page</title></head>
<body>
  <h1 class="title">Hello, World!</h1>
  <p class="intro">This is a <b>sample</b> paragraph.</p>
  <ul id="menu">
    <li class="item"><a href="https://flutter.dev">Flutter</a></li>
    <li class="item"><a href="https://dart.dev">Dart</a></li>
    <li class="item"><a href="https://pub.dev">Pub</a></li>
  </ul>
</body>
</html>''';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _urlC.dispose();
    _htmlC.dispose();
    _selC.dispose();
    _taskC.dispose();
    _tab.dispose();
    super.dispose();
  }

  // ───────────── actions ─────────────

  Future<void> _copy(String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _fetchUrl() async {
    var u = _urlC.text.trim();
    if (u.isEmpty) {
      setState(() => _error = 'URL দিন');
      return;
    }
    if (!u.startsWith('http')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null) {
      setState(() => _error = 'Invalid URL');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,*/*',
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}');
      }
      _htmlC.text = utf8.decode(res.bodyBytes, allowMalformed: true);
      _sourceUrl = u;
      _parse();
    } catch (e) {
      if (mounted) setState(() => _error = 'Fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parse() {
    final html = _htmlC.text.trim();
    if (html.isEmpty) {
      setState(() => _error = 'HTML পেস্ট করুন বা URL fetch করুন');
      return;
    }
    try {
      final doc = HtmlUtils.parse(html);
      final root = doc.documentElement;
      final b = StringBuffer();
      if (root != null) _cleanNode(b, root, 0);
      setState(() {
        _doc = doc;
        _error = null;
        _clean = b.toString();
        _report = _buildReport(doc);
        _rows = _buildRows(doc);
        _matches = [];
        _matchTotal = 0;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _select([String? selector]) {
    if (selector != null) _selC.text = selector;
    if (_doc == null) {
      setState(() => _error = 'আগে Parse করুন');
      return;
    }
    final s = _selC.text.trim();
    if (s.isEmpty) return;
    try {
      final els = HtmlUtils.selectAll(_doc!, s);
      setState(() {
        _error = null;
        _matchTotal = els.length;
        _matches = els.take(200).map(_toMatch).toList();
      });
    } catch (e) {
      setState(() => _error = 'Invalid selector: $e');
    }
  }

  _Match _toMatch(dom.Element e) => _Match(
        path: _cssPath(e),
        tag: e.localName ?? '?',
        text: _short(e.text, 300),
        attrs: {
          for (final en in e.attributes.entries) en.key.toString(): en.value,
        },
        html: _cleanElementHtml(e),
      );

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _htmlC.text = data!.text!;
      _parse();
    }
  }

  void _clearAll() {
    setState(() {
      _urlC.clear();
      _htmlC.clear();
      _selC.clear();
      _doc = null;
      _error = null;
      _sourceUrl = '';
      _clean = '';
      _report = '';
      _rows = [];
      _matches = [];
      _matchTotal = 0;
    });
  }

  // ───────────── builders ─────────────

  List<_NodeRow> _buildRows(dom.Document doc) {
    final out = <_NodeRow>[];
    void visit(dom.Element e, int d) {
      if (out.length >= 2000 || d > 14) return;
      if (_dropTags.contains(e.localName)) return;
      out.add(_NodeRow(e, d));
      for (final c in e.children) {
        visit(c, d + 1);
      }
    }

    final r = doc.documentElement;
    if (r != null) visit(r, 0);
    return out;
  }

  String _buildReport(dom.Document doc) {
    final b = StringBuffer();
    final all = doc.querySelectorAll('*');
    final title = doc.querySelector('title')?.text.trim() ?? '-';

    b.writeln('Title: $title');
    if (_sourceUrl.isNotEmpty) b.writeln('URL: $_sourceUrl');
    final canonical =
        doc.querySelector('link[rel="canonical"]')?.attributes['href'];
    if (canonical != null) b.writeln('Canonical: $canonical');
    b.writeln(
      'Elements: ${all.length} | '
      'Links: ${doc.querySelectorAll('a[href]').length} | '
      'Images: ${doc.querySelectorAll('img').length} | '
      'Forms: ${doc.querySelectorAll('form').length} | '
      'Tables: ${doc.querySelectorAll('table').length}',
    );

    // Headings
    final heads = doc.querySelectorAll('h1,h2,h3').take(12).toList();
    if (heads.isNotEmpty) {
      b.writeln('\n### Headings');
      for (final h in heads) {
        b.writeln('${h.localName}: ${_short(h.text, 80)}');
      }
    }

    // Meta
    final metas = doc.querySelectorAll('meta').where((m) {
      final k = m.attributes['name'] ?? m.attributes['property'] ?? '';
      return k.isNotEmpty && (m.attributes['content'] ?? '').isNotEmpty;
    }).take(20);
    if (metas.isNotEmpty) {
      b.writeln('\n### Meta');
      for (final m in metas) {
        final k = m.attributes['name'] ?? m.attributes['property'];
        b.writeln('$k: ${_short(m.attributes['content']!, 140)}');
      }
    }

    // Embedded JSON + API-like URLs
    final jsonBlocks = <String>[];
    final apiUrls = <String>{};
    final urlRe = RegExp(r'''https?://[^\s"'<>\\)]+''');
    final stateRe = RegExp(r'window\.([A-Za-z_$][\w$]*)\s*=');
    for (final s in doc.querySelectorAll('script')) {
      final type = s.attributes['type'] ?? '';
      final txt = s.text.trim();
      if (txt.isEmpty) continue;
      final isJson = type.contains('json') ||
          s.id == '__NEXT_DATA__' ||
          s.id == '__NUXT_DATA__';
      if (isJson) {
        final label = s.id.isNotEmpty ? '#${s.id}' : type;
        jsonBlocks.add('[$label] ${txt.length} chars: ${_short(txt, 700)}');
      } else {
        final m = stateRe.firstMatch(txt);
        if (m != null && txt.length > 200 && jsonBlocks.length < 6) {
          jsonBlocks.add(
              '[window.${m.group(1)}] ${txt.length} chars: ${_short(txt, 500)}');
        }
      }
      for (final m in urlRe.allMatches(txt)) {
        final u = m.group(0)!;
        final l = u.toLowerCase();
        if (l.contains('api') ||
            l.contains('graphql') ||
            l.contains('.json') ||
            l.contains('ajax')) {
          apiUrls.add(u);
        }
      }
    }
    if (jsonBlocks.isNotEmpty) {
      b.writeln('\n### Embedded JSON / state (data may be here, not in DOM)');
      for (final j in jsonBlocks.take(5)) {
        b.writeln('- $j');
      }
    }
    if (apiUrls.isNotEmpty) {
      b.writeln('\n### API-like URLs found in scripts');
      for (final u in apiUrls.take(15)) {
        b.writeln('- $u');
      }
    }

    // Forms
    final forms = doc.querySelectorAll('form').take(5).toList();
    if (forms.isNotEmpty) {
      b.writeln('\n### Forms');
      for (final f in forms) {
        b.writeln(
          '${_cssPath(f)}  action="${f.attributes['action'] ?? ''}" '
          'method="${f.attributes['method'] ?? 'get'}"',
        );
        for (final i
            in f.querySelectorAll('input,select,textarea,button').take(15)) {
          b.writeln(
            '  ${i.localName} name="${i.attributes['name'] ?? ''}" '
            'type="${i.attributes['type'] ?? ''}"',
          );
        }
      }
    }

    // Tables
    final tables = doc.querySelectorAll('table').take(3).toList();
    if (tables.isNotEmpty) {
      b.writeln('\n### Tables');
      for (final t in tables) {
        final rows = t.querySelectorAll('tr');
        b.writeln('${_cssPath(t)}  rows=${rows.length}');
        for (final r in rows.take(3)) {
          final cells = r
              .querySelectorAll('th,td')
              .map((c) => _short(c.text, 30))
              .join(' | ');
          b.writeln('  | $cells');
        }
      }
    }

    // Repeated patterns (likely list items)
    const skipSig = {'br', 'option', 'source', 'hr', 'td', 'th', 'col', 'dd', 'dt'};
    final found =
        <({dom.Element parent, String sig, List<dom.Element> items})>[];
    for (final p in all) {
      if (_dropTags.contains(p.localName)) continue;
      final kids =
          p.children.where((c) => !_dropTags.contains(c.localName)).toList();
      if (kids.length < 3) continue;
      final bySig = <String, List<dom.Element>>{};
      for (final c in kids) {
        bySig.putIfAbsent(_sig(c), () => []).add(c);
      }
      bySig.forEach((sig, list) {
        final tag = list.first.localName ?? '';
        if (list.length >= 3 &&
            !skipSig.contains(tag) &&
            list.first.text.trim().isNotEmpty) {
          found.add((parent: p, sig: sig, items: list));
        }
      });
    }
    int score(({dom.Element parent, String sig, List<dom.Element> items}) g) =>
        g.items.length * math.min(g.items.first.text.trim().length, 200);
    found.sort((a, c) => score(c).compareTo(score(a)));
    if (found.isNotEmpty) {
      b.writeln('\n### Repeated patterns (likely list items)');
      var i = 1;
      for (final g in found.take(8)) {
        final pp = _cssPath(g.parent);
        b.writeln('$i. ${g.items.length} × <${g.sig}> inside $pp');
        b.writeln('   selector: $pp > ${g.sig}');
        b.writeln('   sample: ${_short(g.items.first.text, 100)}');
        i++;
      }
    }

    return b.toString();
  }

  String _selectedBlock() {
    final s = _selC.text.trim();
    final b = StringBuffer()
      ..writeln('## Elements I selected')
      ..writeln('Selector: `$s`')
      ..writeln('Matches: $_matchTotal');
    for (final m in _matches.take(3)) {
      b
        ..writeln()
        ..writeln('```html')
        ..writeln(m.html)
        ..writeln('```');
    }
    return b.toString();
  }

  String _buildPack() {
    final task = _taskC.text.trim();
    final b = StringBuffer()
      ..writeln(
          'You are an expert web-scraping engineer. Write a complete, runnable script in: $_lang.')
      ..writeln()
      ..writeln('## Task')
      ..writeln(task.isEmpty
          ? 'Extract the main repeating data items from this page.'
          : task)
      ..writeln()
      ..writeln('## Rules')
      ..writeln(
          '- Use ONLY selectors/structure that exist in the HTML below; do not invent elements.')
      ..writeln(
          '- Prefer stable selectors (ids, semantic classes, data-* attributes) over long nth-child chains.')
      ..writeln(
          '- Handle missing elements without crashing, strip whitespace, resolve relative URLs.')
      ..writeln(
          '- Set a browser-like User-Agent, add timeouts and basic error handling.')
      ..writeln('- Output the result as JSON and show how to save it to a file.')
      ..writeln(
          '- If the needed data is NOT in this HTML (JS-rendered), say so and use the embedded JSON / API URLs listed below instead.')
      ..writeln('- Briefly explain which selector maps to which field.')
      ..writeln();

    if (_sourceUrl.isNotEmpty) {
      b
        ..writeln('## Page URL')
        ..writeln(_sourceUrl)
        ..writeln();
    }
    if (_matches.isNotEmpty) {
      b
        ..writeln(_selectedBlock())
        ..writeln();
    }
    final rep = _report.length > 5000
        ? '${_report.substring(0, 5000)}\n…(truncated)'
        : _report;
    b
      ..writeln('## Detected structure')
      ..writeln(rep)
      ..writeln();

    var html = _clean;
    var note = '';
    if (_maxChars > 0 && html.length > _maxChars) {
      html = html.substring(0, _maxChars);
      note = '(truncated: original cleaned HTML was ${_clean.length} chars)';
    }
    b
      ..writeln('## Cleaned HTML (scripts/styles removed)')
      ..writeln('```html')
      ..writeln(html)
      ..writeln('```');
    if (note.isNotEmpty) b.writeln(note);
    return b.toString();
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML Parser'),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Paste HTML',
            onPressed: _paste,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Load sample',
            onPressed: () {
              _htmlC.text = _sampleHtml;
              _parse();
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlC,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/page',
                      prefixIcon: const Icon(Icons.link, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _fetchUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _fetchUrl,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Fetch'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _htmlC,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '…অথবা HTML এখানে পেস্ট করুন',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.fieldFill,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _parse,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Parse'),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'AI Pack'),
              Tab(text: 'Clean'),
              Tab(text: 'Select'),
              Tab(text: 'Tree'),
              Tab(text: 'Data'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _aiTab(),
                _cleanTab(),
                _selectTab(),
                _treeTab(),
                _dataTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String m) => Center(
        child: Text(
          m,
          style: TextStyle(color: AppColors.textMuted),
        ),
      );

  // ── AI Pack ──
  Widget _aiTab() {
    if (_doc == null) return _empty('Parse করুন, তারপর AI Prompt বানান');
    final pack = _buildPack();
    final tokens = (pack.length / 4).round();
    final preview =
        pack.length > 2500 ? '${pack.substring(0, 2500)}\n…' : pack;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _taskC,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'কী extract করতে চান?',
            hintText: 'যেমন: সব প্রোডাক্টের নাম, দাম আর লিংক',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: _lang,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Language',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final l in _langs)
                    DropdownMenuItem(
                      value: l,
                      child: Text(l, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _lang = v ?? _lang),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                value: _maxChars,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'HTML limit',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 15000, child: Text('15k')),
                  DropdownMenuItem(value: 30000, child: Text('30k')),
                  DropdownMenuItem(value: 60000, child: Text('60k')),
                  DropdownMenuItem(value: 0, child: Text('All')),
                ],
                onChanged: (v) => setState(() => _maxChars = v ?? _maxChars),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${pack.length} chars · ≈ $tokens tokens'
          '${_matches.isNotEmpty ? ' · selected elements included' : ''}',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _copy(_buildPack(), 'AI prompt কপি হয়েছে'),
          icon: const Icon(Icons.copy_all),
          label: const Text('Copy AI Prompt'),
        ),
        const SizedBox(height: 16),
        Text(
          'Preview',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          preview,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }

  // ── Clean ──
  Widget _cleanTab() {
    if (_doc == null) return _empty('Parse করলে পরিষ্কার HTML দেখা যাবে');
    final shown = _clean.length > 20000
        ? '${_clean.substring(0, 20000)}\n\n… (শুধু প্রথম 20k দেখানো হচ্ছে, Copy করলে সব কপি হবে)'
        : _clean;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_htmlC.text.length} → ${_clean.length} chars '
                  '(≈ ${(_clean.length / 4).round()} tokens)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy clean HTML',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copy(_clean, 'Clean HTML কপি হয়েছে'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              shown,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Select ──
  Widget _selectTab() {
    const quick = ['a[href]', 'img', 'h1,h2,h3', 'table', 'form', 'button', 'input'];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _selC,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'CSS selector, e.g. ul#menu > li.item',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _select(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _select, child: const Text('Run')),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final q in quick)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _select(q),
                  ),
                ),
            ],
          ),
        ),
        if (_matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$_matchTotal matches'
                    '${_matchTotal > _matches.length ? ' (প্রথম ${_matches.length} দেখানো)' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _copy(_selectedBlock(), 'Selected elements কপি হয়েছে'),
                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                  label: const Text('Copy for AI'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _matches.isEmpty
              ? _empty(_doc == null ? 'আগে Parse করুন' : 'No matches')
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _matches.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _matches[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  m.path,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '<${m.tag}>',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                for (final e in m.attrs.entries)
                                  Text(
                                    '  ${e.key}="${_short(e.value, 120)}"',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                if (m.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      m.text,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: 'Copy HTML',
                            onPressed: () => _copy(m.html, 'HTML কপি হয়েছে'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Tree ──
  Widget _treeTab() {
    if (_doc == null) return _empty('Parse করলে structure দেখা যাবে');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'যেকোনো node-এ ট্যাপ করলে তার selector তৈরি হয়ে Select ট্যাবে চলে যাবে',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length,
            itemBuilder: (_, i) {
              final r = _rows[i];
              final own = _short(
                r.el.nodes
                    .whereType<dom.Text>()
                    .map((t) => t.data.trim())
                    .join(' '),
                40,
              );
              return InkWell(
                onTap: () {
                  _select(_cssPath(r.el));
                  _tab.animateTo(2);
                },
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12 + r.depth * 12.0,
                    right: 12,
                    top: 16,
                    bottom: 16,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _label(r.el),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        if (own.isNotEmpty)
                          TextSpan(
                            text: '  $own',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Data ──
  Widget _dataTab() {
    if (_doc == null) return _empty('Parse করলে page-এর সারসংক্ষেপ দেখা যাবে');
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: TextButton.icon(
              onPressed: () => _copy(_report, 'Report কপি হয়েছে'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              _report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
