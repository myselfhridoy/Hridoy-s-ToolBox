import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import '../../core/plugin/tool_plugin.dart';
import '../../core/storage/github_token_store.dart';

class GittomdTool implements ToolPlugin {
  @override
  String get id => 'gittomd';

  @override
  String get name => 'gittomd';

  @override
  IconData get icon => Icons.folder_zip_outlined;

  @override
  List<String> get categories => ['Developer'];

  @override
  List<String> get tags => ['github', 'readme', 'markdown', 'repo', 'private'];

  @override
  Widget buildPage(BuildContext context) => const GittomdPage();
}

enum _Mode { readme, fullRepo }

class GittomdPage extends StatefulWidget {
  const GittomdPage({super.key});

  @override
  State<GittomdPage> createState() => _GittomdPageState();
}

class _GittomdPageState extends State<GittomdPage> {
  final _urlController = TextEditingController();
  _Mode _mode = _Mode.readme;

  bool _loading = false;
  String? _error;
  String _markdown = '';
  String? _resolvedRepo;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// সব GitHub রিকোয়েস্টে ব্যবহৃত হেডার।
  /// টোকেন থাকলে Authorization: Bearer <token>, নাহলে পাবলিক।
  Map<String, String> get _headers {
    final h = <String, String>{
      'User-Agent': 'Hridoys-ToolBox',
      'Accept': 'application/vnd.github+json',
    };
    final token = GitHubTokenStore.instance.token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  ({String owner, String repo})? _parseRepoUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('http://') || s.startsWith('https://')) {
      final uri = Uri.tryParse(s);
      if (uri == null) return null;
      final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
      if (segs.length < 2) return null;
      s = '${segs[0]}/${segs[1]}';
    }

    s = s.replaceAll(RegExp(r'\.git$'), '');
    final parts = s.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return null;
    return (owner: parts[0], repo: parts[1]);
  }

  Future<void> _fetch() async {
    final parsed = _parseRepoUrl(_urlController.text);
    if (parsed == null) {
      setState(() => _error = 'Use https://github.com/owner/repo or owner/repo');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _markdown = '';
      _resolvedRepo = '${parsed.owner}/${parsed.repo}';
    });

    try {
      final md = _mode == _Mode.readme
          ? await _fetchReadme(parsed.owner, parsed.repo)
          : await _fetchFullRepo(parsed.owner, parsed.repo);
      if (mounted) setState(() => _markdown = md);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// GitHub API-র readme endpoint, raw Accept header দিয়ে।
  /// প্রাইভেট রিপোতে Authorization হেডার লাগে।
  Future<String> _fetchReadme(String owner, String repo) async {
    final uri = Uri.parse('https://api.github.com/repos/$owner/$repo/readme');
    final res = await http.get(
      uri,
      headers: {..._headers, 'Accept': 'application/vnd.github.raw+json'},
    );

    if (res.statusCode == 401) {
      throw Exception('টোকেন অবৈধ বা মেয়াদোত্তীর্ণ (401)');
    }
    if (res.statusCode == 403) {
      throw Exception('রেট লিমিট বা টোকেনের অনুমতি নেই (403)');
    }
    if (res.statusCode == 404) {
      throw Exception(
        GitHubTokenStore.instance.hasToken
            ? 'README পাওয়া যায়নি। টোকেনে Contents: Read আছে? SSO authorize করা?'
            : 'README পাওয়া যায়নি। প্রাইভেট রিপো হলে টোকেন সেট করুন।',
      );
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub API error ${res.statusCode}');
    }
    return res.body;
  }

  Future<String> _fetchFullRepo(String owner, String repo) async {
    // ১. ডিফল্ট ব্র্যাঞ্চ
    final repoRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo'),
      headers: _headers,
    );
    if (repoRes.statusCode == 401) {
      throw Exception('টোকেন অবৈধ বা মেয়াদোত্তীর্ণ (401)');
    }
    if (repoRes.statusCode == 403) {
      throw Exception('রেট লিমিট বা অনুমতি নেই (403)');
    }
    if (repoRes.statusCode == 404) {
      throw Exception(
        GitHubTokenStore.instance.hasToken
            ? 'রিপো পাওয়া যায়নি (404)। টোকেনের অনুমতি/SSO চেক করুন।'
            : 'রিপো পাওয়া যায়নি (404)। প্রাইভেট হলে টোকেন সেট করুন।',
      );
    }
    if (repoRes.statusCode != 200) {
      throw Exception('Repo fetch failed (${repoRes.statusCode})');
    }

    final repoJson = jsonDecode(repoRes.body) as Map<String, dynamic>;
    final branch = (repoJson['default_branch'] as String?) ?? 'main';

    // ২. রিকার্সিভ ট্রি
    final treeRes = await http.get(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1',
      ),
      headers: _headers,
    );
    if (treeRes.statusCode != 200) {
      throw Exception('Tree fetch failed (${treeRes.statusCode})');
    }
    final treeJson = jsonDecode(treeRes.body) as Map<String, dynamic>;
    final tree = (treeJson['tree'] as List).cast<Map<String, dynamic>>();

    const skipExt = {
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.svg',
      '.pdf', '.zip', '.tar', '.gz', '.mp4', '.mp3', '.woff', '.woff2',
      '.ttf', '.otf', '.eot', '.lock',
    };

    final blobs = tree
        .where((e) => e['type'] == 'blob')
        .where((e) => (e['size'] as int? ?? 0) < 200 * 1024)
        .where((e) {
          final path = (e['path'] as String).toLowerCase();
          if (path.contains('node_modules/') || path.startsWith('.git/')) {
            return false;
          }
          return !skipExt.any(path.endsWith);
        })
        .toList();

    final buf = StringBuffer()
      ..writeln('# ${repoJson['full_name']}')
      ..writeln()
      ..writeln(repoJson['description'] ?? '')
      ..writeln()
      ..writeln('Branch: `$branch`')
      ..writeln()
      ..writeln('## Tree')
      ..writeln('```')
      ..writeln(
        tree
            .where((e) => e['type'] == 'blob')
            .map((e) => e['path'])
            .join('\n'),
      )
      ..writeln('```')
      ..writeln()
      ..writeln('## Files');

    // ৩. raw content — প্রাইভেট রিপোতে Authorization হেডার দরকার
    final rawBase = 'https://raw.githubusercontent.com/$owner/$repo/$branch';
    var count = 0;
    for (final f in blobs) {
      final path = f['path'] as String;
      try {
        final r = await http.get(
          Uri.parse('$rawBase/$path'),
          headers: _headers,
        );
        if (r.statusCode != 200) continue;
        final content = r.body;
        if (content.contains('\u0000')) continue;

        final fence = '`' * (_longestBacktickRun(content) + 1);
        buf
          ..writeln()
          ..writeln('### `$path`')
          ..writeln('$fence${_langFromExt(path)}')
          ..writeln(content)
          ..writeln(fence);
        count++;
        if (count >= 60) {
          buf.writeln('\n> _…প্রথম 60টি ফাইল দেখানো হয়েছে_');
          break;
        }
      } catch (_) {
        // স্কিপ
      }
    }
    return buf.toString();
  }

  int _longestBacktickRun(String s) {
    var max = 0, cur = 0;
    for (final ch in s.codeUnits) {
      if (ch == 0x60) {
        cur++;
        if (cur > max) max = cur;
      } else {
        cur = 0;
      }
    }
    return max;
  }

  String _langFromExt(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    final ext = path.substring(dot + 1).toLowerCase();
    const map = {
      'dart': 'dart', 'js': 'javascript', 'ts': 'typescript',
      'py': 'python', 'java': 'java', 'kt': 'kotlin',
      'swift': 'swift', 'go': 'go', 'rs': 'rust',
      'cpp': 'cpp', 'c': 'c', 'h': 'c', 'hpp': 'cpp',
      'html': 'html', 'css': 'css', 'json': 'json',
      'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown',
      'sh': 'bash', 'xml': 'xml', 'sql': 'sql',
    };
    return map[ext] ?? '';
  }

  Future<void> _copy() async {
    if (_markdown.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _markdown));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Markdown clipboard-এ কপি হয়েছে')),
      );
    }
  }

  Future<void> _openTokenDialog() async {
    final controller = TextEditingController(
      text: GitHubTokenStore.instance.token ?? '',
    );
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
              const Text(
                'প্রাইভেট রিপো পড়তে PAT লাগবে।\n'
                'Fine-grained: Contents → Read-only\n'
                'Classic: repo স্কোপ',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: obscure,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: 'github_pat_… or ghp_…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
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
              child: const Text('Cancel'),
            ),
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

  @override
  Widget build(BuildContext context) {
    final hasToken = GitHubTokenStore.instance.hasToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('gittomd'),
        actions: [
          IconButton(
            icon: Icon(
              hasToken ? Icons.lock : Icons.lock_open,
              color: hasToken ? Colors.greenAccent : null,
            ),
            tooltip: hasToken ? 'Token সেট আছে' : 'Token সেট করুন',
            onPressed: _openTokenDialog,
          ),
          if (_markdown.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copy Markdown',
              onPressed: _copy,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://github.com/owner/repo',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
              ),
              onSubmitted: (_) => _fetch(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(
                      value: _Mode.readme,
                      label: Text('README'),
                      icon: Icon(Icons.article_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: _Mode.fullRepo,
                      label: Text('Full Repo'),
                      icon: Icon(Icons.folder_zip_outlined, size: 16),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetch,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Fetch'),
                ),
              ],
            ),
          ),
          if (!hasToken)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'টোকেন ছাড়া শুধু পাবলিক রিপো (৬০ req/hr)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
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
          if (_resolvedRepo != null && _markdown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_resolvedRepo · ${_markdown.length} chars',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _markdown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _mode == _Mode.readme
                                ? 'Repo URL দিয়ে README আনুন (পাবলিক/প্রাইভেট)'
                                : 'Repo URL দিয়ে পুরো রিপো Markdown-এ প্যাক করুন',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      )
                    : Markdown(
                        data: _markdown,
                        padding: const EdgeInsets.all(16),
                        styleSheet: MarkdownStyleSheet.fromTheme(
                          Theme.of(context),
                        ).copyWith(
                          codeblockDecoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          code: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
