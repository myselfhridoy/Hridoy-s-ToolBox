import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart';
import '../../core/plugin/tool_plugin.dart';
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
  List<String> get tags => ['html', 'parser', 'css', 'scrape'];

  @override
  Widget buildPage(BuildContext context) => const HtmlParserPage();
}

class HtmlParserPage extends StatefulWidget {
  const HtmlParserPage({super.key});

  @override
  State<HtmlParserPage> createState() => _HtmlParserPageState();
}

class _HtmlParserPageState extends State<HtmlParserPage>
    with SingleTickerProviderStateMixin {
  final _htmlController = TextEditingController();
  final _selectorController = TextEditingController();
  late TabController _tabController;

  Document? _doc;
  String? _error;
  String _plainText = '';
  List<String> _links = [];
  List<_ElementResult> _selected = [];
  String _tree = '';

  static const _sampleHtml = '''<!DOCTYPE html>
<html>
<head><title>Sample Page</title></head>
<body>
  <h1 class="title">Hello, World!</h1>
  <p class="intro">This is a <b>sample</b> paragraph.</p>
  <ul id="menu">
    <li><a href="https://flutter.dev">Flutter</a></li>
    <li><a href="https://dart.dev">Dart</a></li>
    <li><a href="https://pub.dev">Pub</a></li>
  </ul>
</body>
</html>''';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _htmlController.dispose();
    _selectorController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _parse() {
    final html = _htmlController.text.trim();
    if (html.isEmpty) {
      setState(() => _error = 'Paste HTML first');
      return;
    }
    try {
      final doc = HtmlUtils.parse(html);
      setState(() {
        _doc = doc;
        _error = null;
        _plainText = doc.documentElement?.text.trim() ?? '';
        _links = HtmlUtils.attrs(doc, 'a[href]', 'href')
            .whereType<String>()
            .toList();
        _tree = _buildTree(doc);
        _selected = [];
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _select() {
    if (_doc == null) {
      setState(() => _error = 'Tap Parse first');
      return;
    }
    final selector = _selectorController.text.trim();
    if (selector.isEmpty) return;
    try {
      final elements = HtmlUtils.selectAll(_doc!, selector);
      setState(() {
        _error = null;
        _selected = elements
            .map((e) => _ElementResult(
                  tag: e.localName ?? '?',
                  text: e.text.trim(),
                  attributes: {
                    for (final entry in e.attributes.entries)
                      entry.key.toString(): entry.value,
                  },
                ))
            .toList();
      });
    } catch (e) {
      setState(() => _error = 'Invalid selector: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _htmlController.text = data!.text!;
    }
  }

  String _buildTree(Document doc) {
    final buf = StringBuffer();
    for (final node in doc.nodes) {
      _writeNode(buf, node, 0);
    }
    return buf.toString();
  }

  void _writeNode(StringBuffer buf, Node node, int depth) {
    final indent = '  ' * depth;
    if (node is Element) {
      final id = node.id.isEmpty ? '' : '#${node.id}';
      final cls = node.className.trim().isEmpty
          ? ''
          : '.${node.className.trim().replaceAll(' ', '.')}';
      buf.writeln('$indent<${node.localName}$id$cls>');
      for (final child in node.nodes) {
        _writeNode(buf, child, depth + 1);
      }
    } else if (node is Text) {
      final t = node.text.trim();
      if (t.isNotEmpty) {
        final truncated = t.length > 80 ? '${t.substring(0, 80)}…' : t;
        buf.writeln('$indent"$truncated"');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTML Parser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Paste from clipboard',
            onPressed: _pasteFromClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Load sample',
            onPressed: () {
              _htmlController.text = _sampleHtml;
              _parse();
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              _htmlController.clear();
              _selectorController.clear();
              _doc = null;
              _error = null;
              _plainText = '';
              _links = [];
              _selected = [];
              _tree = '';
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _htmlController,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '<html>\n  <body>Paste HTML here…</body>\n</html>',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Text'),
              Tab(text: 'Links'),
              Tab(text: 'Select'),
              Tab(text: 'Tree'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTextTab(),
                _buildLinksTab(),
                _buildSelectTab(),
                _buildTreeTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    if (_doc == null) return _empty('Parse HTML to see text');
    if (_plainText.isEmpty) return _empty('No text content');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(_plainText),
    );
  }

  Widget _buildLinksTab() {
    if (_doc == null) return _empty('Parse HTML to see links');
    if (_links.isEmpty) return _empty('No links found');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _links.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.link, size: 20),
        title: SelectableText(_links[i]),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: _links[i])),
        ),
      ),
    );
  }

  Widget _buildSelectTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _selectorController,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'CSS selector, e.g. a.link, #id, .class',
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
        Expanded(
          child: _selected.isEmpty
              ? _empty(_doc == null ? 'Parse HTML first' : 'No matches')
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _selected.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _selected[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '<${r.tag}>',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          ...r.attributes.entries.map(
                            (e) => Text(
                              '  ${e.key}="${e.value}"',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          if (r.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(r.text,
                                  style: const TextStyle(fontSize: 13)),
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

  Widget _buildTreeTab() {
    if (_doc == null) return _empty('Parse HTML to see structure');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _tree,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _ElementResult {
  final String tag;
  final String text;
  final Map<String, String> attributes;
  _ElementResult({
    required this.tag,
    required this.text,
    required this.attributes,
  });
}
