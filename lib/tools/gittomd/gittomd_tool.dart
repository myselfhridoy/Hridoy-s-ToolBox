import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

enum _Mode { readme, fullRepo, pick }

class GittomdPage extends StatefulWidget {
  const GittomdPage({super.key});

  @override
  State<GittomdPage> createState() => _GittomdPageState();
}

class _GittomdPageState extends State<GittomdPage> {
  // ── Session cache (survives navigation within a single app session) ──
  static final Map<String, String> _mdMem = {};
  static final Map<String, Map<String, dynamic>> _treeMem = {};
  static SharedPreferences? _prefs;

  static const _kLastUrl = 'gittomd_last_url';
  static const _kLastMode = 'gittomd_last_mode';
  static const _maxCacheBytes = 2 * 1024 * 1024; // 2 MB per entry

  final _urlController = TextEditingController();
  final _pickerSearchController = TextEditingController();
  _Mode _mode = _Mode.readme;

  bool _loading = false;
  String? _error;
  String _markdown = '';
  String? _resolvedRepo;

  // Picker state
  List<_TreeNode> _treeRoots = [];
  Set<String> _selectedPaths = {};
  Set<String> _expandedFolders = {};
  bool _showPicker = false;
  String _treeOwner = '';
  String _treeRepo = '';
  String _treeBranch = 'main';
  String _pickerQuery = '';

  // Generation progress
  int _genProgress = 0;
  int _genTotal = 0;

  static const _skipExt = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.svg',
    '.pdf', '.zip', '.tar', '.gz', '.mp4', '.mp3', '.woff', '.woff2',
    '.ttf', '.otf', '.eot', '.lock',
  };

  @override
  void initState() {
    super.initState();
    _restoreFromCache();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _pickerSearchController.dispose();
    super.dispose();
  }

  // ── Cache helpers ──
  static String _mdKey(String owner, String repo, String mode) =>
      'gittomd_md_${owner}_${repo}_$mode';

  static String _treeKey(String owner, String repo) =>
      'gittomd_tree_${owner}_${repo}';

  Future<String?> _loadMarkdown(String owner, String repo, String mode) async {
    final k = _mdKey(owner, repo, mode);
    if (_mdMem.containsKey(k)) return _mdMem[k];
    final disk = _prefs?.getString(k);
    if (disk != null) _mdMem[k] = disk;
    return disk;
  }

  Future<void> _saveMarkdown(
      String owner, String repo, String mode, String md) async {
    if (md.length > _maxCacheBytes) return; // skip huge payloads
    final k = _mdKey(owner, repo, mode);
    _mdMem[k] = md;
    await _prefs?.setString(k, md);
  }

  Future<void> _savePickerState() async {
    if (_treeOwner.isEmpty || _treeRepo.isEmpty) return;
    final k = _treeKey(_treeOwner, _treeRepo);
    final data = <String, dynamic>{
      'roots': _treeRoots.map((r) => r.toJson()).toList(),
      'selected': _selectedPaths.toList(),
      'expanded': _expandedFolders.toList(),
      'branch': _treeBranch,
    };
    _treeMem[k] = data;
    try {
      await _prefs?.setString(k, jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadPickerState(
      String owner, String repo) async {
    final k = _treeKey(owner, repo);
    if (_treeMem.containsKey(k)) return _treeMem[k];
    final s = _prefs?.getString(k);
    if (s == null) return null;
    try {
      final data = jsonDecode(s) as Map<String, dynamic>;
      _treeMem[k] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberLast(String url, _Mode mode) async {
    await _prefs?.setString(_kLastUrl, url);
    await _prefs?.setString(_kLastMode, mode.name);
  }

  Future<void> _restoreFromCache() async {
    _prefs ??= await SharedPreferences.getInstance();

    final lastUrl = _prefs!.getString(_kLastUrl) ?? '';
    final lastMode = _prefs!.getString(_kLastMode) ?? 'readme';

    if (lastUrl.isEmpty) return;

    _urlController.text = lastUrl;
    _mode = _Mode.values.firstWhere(
      (m) => m.name == lastMode,
      orElse: () => _Mode.readme,
    );

    final parsed = _parseRepoUrl(lastUrl);
    if (parsed == null) return;

    _resolvedRepo = '${parsed.owner}/${parsed.repo}';

    // Restore markdown for this mode
    final md = await _loadMarkdown(parsed.owner, parsed.repo, _mode.name);

    // Restore picker tree if Pick mode
    if (_mode == _Mode.pick) {
      final treeData = await _loadPickerState(parsed.owner, parsed.repo);
      if (treeData != null) {
        try {
          _treeRoots = (treeData['roots'] as List)
              .map((j) => _TreeNode.fromJson(j as Map<String, dynamic>))
              .toList();
          _selectedPaths =
              (treeData['selected'] as List).cast<String>().toSet();
          _expandedFolders =
              (treeData['expanded'] as List).cast<String>().toSet();
          _treeOwner = parsed.owner;
          _treeRepo = parsed.repo;
          _treeBranch = treeData['branch'] as String? ?? 'main';
          _showPicker = md == null || md.isEmpty;
        } catch (_) {}
      }
    }

    if (md != null && md.isNotEmpty) _markdown = md;

    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
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

  void _onModeChanged(Set<_Mode> s) async {
    final newMode = s.first;
    final parsed = _parseRepoUrl(_urlController.text);

    setState(() {
      _mode = newMode;
      _error = null;
      _pickerQuery = '';
      _pickerSearchController.clear();
      _genProgress = 0;
      _genTotal = 0;
    });

    if (parsed == null) {
      setState(() {
        _markdown = '';
        _treeRoots = [];
        _selectedPaths.clear();
        _expandedFolders.clear();
        _showPicker = false;
      });
      return;
    }

    // Restore markdown for the new mode
    final md = await _loadMarkdown(parsed.owner, parsed.repo, newMode.name);

    // Restore picker state if switching to Pick
    Map<String, dynamic>? treeData;
    if (newMode == _Mode.pick) {
      treeData = await _loadPickerState(parsed.owner, parsed.repo);
    }

    if (!mounted) return;
    setState(() {
      _resolvedRepo = '${parsed.owner}/${parsed.repo}';
      _markdown = md ?? '';

      if (newMode == _Mode.pick && treeData != null) {
        _treeRoots = (treeData['roots'] as List)
            .map((j) => _TreeNode.fromJson(j as Map<String, dynamic>))
            .toList();
        _selectedPaths =
            (treeData['selected'] as List).cast<String>().toSet();
        _expandedFolders =
            (treeData['expanded'] as List).cast<String>().toSet();
        _treeOwner = parsed.owner;
        _treeRepo = parsed.repo;
        _treeBranch = treeData['branch'] as String? ?? 'main';
        _showPicker = (md == null || md.isEmpty);
      } else {
        _treeRoots = [];
        _selectedPaths.clear();
        _expandedFolders.clear();
        _showPicker = false;
      }
    });
  }

  // ─────────────────────────── FETCH ───────────────────────────
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
      _genProgress = 0;
      _genTotal = 0;
    });

    await _rememberLast(_urlController.text.trim(), _mode);

    try {
      if (_mode == _Mode.pick) {
        await _loadTree(parsed.owner, parsed.repo);
        await _savePickerState();
        if (mounted) setState(() => _showPicker = true);
        return;
      }
      final md = _mode == _Mode.readme
          ? await _fetchReadme(parsed.owner, parsed.repo)
          : await _fetchFullRepo(parsed.owner, parsed.repo);
      await _saveMarkdown(parsed.owner, parsed.repo, _mode.name, md);
      if (mounted) setState(() => _markdown = md);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _fetchReadme(String owner, String repo) async {
    final uri = Uri.parse('https://api.github.com/repos/$owner/$repo/readme');
    final res = await http.get(
      uri,
      headers: {..._headers, 'Accept': 'application/vnd.github.raw+json'},
    );
    _checkStatus(res, what: 'README');
    return res.body;
  }

  Future<String> _fetchFullRepo(String owner, String repo) async {
    final repoRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo'),
      headers: _headers,
    );
    _checkStatus(repoRes, what: 'Repo');
    final repoJson = jsonDecode(repoRes.body) as Map<String, dynamic>;
    final branch = (repoJson['default_branch'] as String?) ?? 'main';

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

    final blobs = tree
        .where((e) => e['type'] == 'blob')
        .where((e) => (e['size'] as int? ?? 0) < 200 * 1024)
        .where((e) {
          final path = (e['path'] as String).toLowerCase();
          if (path.contains('node_modules/') || path.startsWith('.git/')) {
            return false;
          }
          return !_skipExt.any(path.endsWith);
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
      ..writeln(tree
          .where((e) => e['type'] == 'blob')
          .map((e) => e['path'])
          .join('\n'))
      ..writeln('```')
      ..writeln()
      ..writeln('## Files');

    final rawBase =
        'https://raw.githubusercontent.com/$owner/$repo/$branch';
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
      } catch (_) {}
    }
    return buf.toString();
  }

  void _checkStatus(http.Response res, {required String what}) {
    if (res.statusCode == 401) {
      throw Exception('টোকেন অবৈধ বা মেয়াদোত্তীর্ণ (401)');
    }
    if (res.statusCode == 403) {
      throw Exception('রেট লিমিট বা টোকেনের অনুমতি নেই (403)');
    }
    if (res.statusCode == 404) {
      throw Exception(
        GitHubTokenStore.instance.hasToken
            ? '$what পাওয়া যায়নি (404)। টোকেনের Contents: Read আছে? SSO authorize করা?'
            : '$what পাওয়া যায়নি (404)। প্রাইভেট রিপো হলে টোকেন সেট করুন।',
      );
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub API error ${res.statusCode}');
    }
  }

  // ─────────────────────────── PICKER ───────────────────────────
  Future<void> _loadTree(String owner, String repo) async {
    final repoRes = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo'),
      headers: _headers,
    );
    _checkStatus(repoRes, what: 'Repo');
    final repoJson = jsonDecode(repoRes.body) as Map<String, dynamic>;
    final branch = (repoJson['default_branch'] as String?) ?? 'main';

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

    final roots = _buildTree(tree, maxFiles: 500);
    if (mounted) {
      setState(() {
        _treeRoots = roots;
        _treeOwner = owner;
        _treeRepo = repo;
        _treeBranch = branch;
        _selectedPaths.clear();
        _expandedFolders.clear();
      });
    }
  }

  List<_TreeNode> _buildTree(List<Map<String, dynamic>> tree,
      {required int maxFiles}) {
    final blobs = tree
        .where((e) => e['type'] == 'blob')
        .where((e) => (e['size'] as int? ?? 0) < 200 * 1024)
        .where((e) {
          final path = (e['path'] as String).toLowerCase();
          if (path.contains('node_modules/') || path.startsWith('.git/')) {
            return false;
          }
          return !_skipExt.any(path.endsWith);
        })
        .take(maxFiles)
        .toList();

    final nodes = <String, _TreeNode>{};
    final folderPaths = <String>{};

    for (final item in blobs) {
      final path = item['path'] as String;
      nodes[path] = _TreeNode(
        name: path.split('/').last,
        path: path,
        isFolder: false,
        size: item['size'] as int? ?? 0,
      );
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        folderPaths.add(parts.sublist(0, i).join('/'));
      }
    }

    for (final fp in folderPaths) {
      nodes[fp] = _TreeNode(
        name: fp.split('/').last,
        path: fp,
        isFolder: true,
      );
    }

    final roots = <_TreeNode>[];
    for (final node in nodes.values) {
      final parentPath = _parentOf(node.path);
      if (parentPath.isEmpty) {
        roots.add(node);
      } else {
        nodes[parentPath]?.children.add(node);
      }
    }

    int compare(_TreeNode a, _TreeNode b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    for (final node in nodes.values) {
      node.children.sort(compare);
    }
    roots.sort(compare);
    return roots;
  }

  String _parentOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? '' : path.substring(0, idx);
  }

  Iterable<_TreeNode> _walk(_TreeNode node) sync* {
    yield node;
    for (final c in node.children) {
      yield* _walk(c);
    }
  }

  Iterable<_TreeNode> _allNodes() sync* {
    for (final r in _treeRoots) {
      yield* _walk(r);
    }
  }

  List<({_TreeNode node, int depth})> _flattenVisible() {
    final result = <({_TreeNode node, int depth})>[];
    final q = _pickerQuery.trim().toLowerCase();

    void visit(_TreeNode node, int depth) {
      if (q.isEmpty) {
        result.add((node: node, depth: depth));
        if (node.isFolder && _expandedFolders.contains(node.path)) {
          for (final c in node.children) {
            visit(c, depth + 1);
          }
        }
      } else {
        if (!node.isFolder) {
          if (node.path.toLowerCase().contains(q)) {
            result.add((node: node, depth: depth));
          }
        } else {
          final hasMatch =
              node.allFiles.any((f) => f.path.toLowerCase().contains(q));
          if (hasMatch) {
            result.add((node: node, depth: depth));
            for (final c in node.children) {
              visit(c, depth + 1);
            }
          }
        }
      }
    }

    for (final r in _treeRoots) {
      visit(r, 0);
    }
    return result;
  }

  void _toggleSelection(_TreeNode node) {
    final files = node.allFiles.toList();
    if (files.isEmpty) return;
    final allSelected =
        files.every((f) => _selectedPaths.contains(f.path));
    setState(() {
      if (allSelected) {
        for (final f in files) {
          _selectedPaths.remove(f.path);
        }
      } else {
        for (final f in files) {
          _selectedPaths.add(f.path);
        }
      }
    });
    _savePickerState();
  }

  void _selectAll() {
    setState(() {
      for (final r in _treeRoots) {
        for (final f in r.allFiles) {
          _selectedPaths.add(f.path);
        }
      }
    });
    _savePickerState();
  }

  void _clearSelection() {
    setState(_selectedPaths.clear);
    _savePickerState();
  }

  int get _selectedSize {
    var total = 0;
    for (final node in _allNodes()) {
      if (!node.isFolder && _selectedPaths.contains(node.path)) {
        total += node.size;
      }
    }
    return total;
  }

  Future<void> _generateFromSelection() async {
    if (_selectedPaths.isEmpty) {
      setState(() => _error = 'কিছু ফাইল/ফোল্ডার সিলেক্ট করুন');
      return;
    }
    final paths = _selectedPaths.toList()..sort();
    setState(() {
      _loading = true;
      _error = null;
      _genProgress = 0;
      _genTotal = paths.length;
    });

    try {
      final rawBase =
          'https://raw.githubusercontent.com/$_treeOwner/$_treeRepo/$_treeBranch';
      final buf = StringBuffer()
        ..writeln('# $_treeOwner/$_treeRepo')
        ..writeln()
        ..writeln('Selected files (`$_treeBranch`):')
        ..writeln('```')
        ..writeln(paths.join('\n'))
        ..writeln('```')
        ..writeln()
        ..writeln('## Contents');

      for (var i = 0; i < paths.length; i++) {
        final path = paths[i];
        try {
          final r = await http.get(
            Uri.parse('$rawBase/$path'),
            headers: _headers,
          );
          if (r.statusCode == 200) {
            final content = r.body;
            if (!content.contains('\u0000')) {
              final fence = '`' * (_longestBacktickRun(content) + 1);
              buf
                ..writeln()
                ..writeln('### `$path`')
                ..writeln('$fence${_langFromExt(path)}')
                ..writeln(content)
                ..writeln(fence);
            }
          }
        } catch (_) {}
        if (mounted) setState(() => _genProgress = i + 1);
      }

      final md = buf.toString();
      await _saveMarkdown(_treeOwner, _treeRepo, _Mode.pick.name, md);
      await _savePickerState();

      if (mounted) {
        setState(() {
          _markdown = md;
          _showPicker = false;
          _loading = false;
          _genProgress = 0;
          _genTotal = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _genProgress = 0;
          _genTotal = 0;
        });
      }
    }
  }

  // ─────────────────────────── UTILS ───────────────────────────
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
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
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
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

  // ─────────────────────────── BUILD ───────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasToken = GitHubTokenStore.instance.hasToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('gittomd'),
        actions: [
          if (_mode == _Mode.pick && !_showPicker && _markdown.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'Back to picker',
              onPressed: () => setState(() => _showPicker = true),
            ),
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
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(
                          value: _Mode.readme,
                          label: Text('README'),
                          icon: Icon(Icons.article_outlined, size: 14),
                        ),
                        ButtonSegment(
                          value: _Mode.fullRepo,
                          label: Text('Full'),
                          icon: Icon(Icons.folder_zip_outlined, size: 14),
                        ),
                        ButtonSegment(
                          value: _Mode.pick,
                          label: Text('Pick'),
                          icon: Icon(Icons.checklist, size: 14),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _onModeChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetch,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
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
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
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
          if (_resolvedRepo != null &&
              _markdown.isNotEmpty &&
              !_showPicker)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.greenAccent,
                  ),
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      if (_genTotal > 0) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _genTotal == 0 ? null : _genProgress / _genTotal,
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  'Fetching $_genProgress / $_genTotal',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (_mode == _Mode.pick && _showPicker) {
      return _buildPickerView();
    }

    if (_markdown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _mode == _Mode.readme
                ? 'Repo URL দিয়ে README আনুন'
                : _mode == _Mode.fullRepo
                    ? 'Repo URL দিয়ে পুরো রিপো Markdown-এ প্যাক করুন'
                    : 'Repo URL দিয়ে ফাইল ট্রি আনুন, তারপর নির্দিষ্ট ফাইল/ফোল্ডার বেছে নিন',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    return Markdown(
      data: _markdown,
      padding: const EdgeInsets.all(16),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        codeblockDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        code: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _buildPickerView() {
    if (_treeRoots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'কোনো ফাইল পাওয়া যায়নি—Fetch চাপুন',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    final visible = _flattenVisible();
    final selectedCount = _selectedPaths.length;
    final selectedSize = _selectedSize;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$selectedCount files · ${_formatSize(selectedSize)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectAll,
                    child: const Text('All'),
                  ),
                  TextButton(
                    onPressed: _clearSelection,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selectedCount == 0 || _loading
                      ? null
                      : _generateFromSelection,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(
                    selectedCount == 0
                        ? 'Generate Markdown'
                        : 'Generate Markdown ($selectedCount)',
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _pickerSearchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Filter by path…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              suffixIcon: _pickerQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _pickerSearchController.clear();
                        setState(() => _pickerQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _pickerQuery = v),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'No matches',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final item = visible[i];
                    return _buildTreeRow(item.node, item.depth);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTreeRow(_TreeNode node, int depth) {
    final files = node.allFiles.toList();
    final selectedInNode =
        files.where((f) => _selectedPaths.contains(f.path)).length;
    bool? checkboxValue;
    if (files.isEmpty) {
      checkboxValue = false;
    } else if (selectedInNode == files.length) {
      checkboxValue = true;
    } else if (selectedInNode == 0) {
      checkboxValue = false;
    } else {
      checkboxValue = null;
    }

    final isExpanded = _expandedFolders.contains(node.path);
    final showChildren =
        node.isFolder && (_pickerQuery.isEmpty ? isExpanded : true);

    return InkWell(
      onTap: node.isFolder
          ? () {
              setState(() {
                if (_expandedFolders.contains(node.path)) {
                  _expandedFolders.remove(node.path);
                } else {
                  _expandedFolders.add(node.path);
                }
              });
              _savePickerState();
            }
          : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: 8 + depth * 16.0,
          right: 12,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            if (node.isFolder)
              Icon(
                showChildren ? Icons.expand_more : Icons.chevron_right,
                size: 18,
              )
            else
              const SizedBox(width: 18),
            Checkbox(
              value: checkboxValue,
              tristate: node.isFolder,
              onChanged: files.isEmpty ? null : (_) => _toggleSelection(node),
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              node.isFolder ? Icons.folder : Icons.description,
              size: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      node.isFolder ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (!node.isFolder)
              Text(
                _formatSize(node.size),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── TREE NODE ───────────────────────────
class _TreeNode {
  final String name;
  final String path;
  final bool isFolder;
  final int size;
  final List<_TreeNode> children = [];

  _TreeNode({
    required this.name,
    required this.path,
    required this.isFolder,
    this.size = 0,
  });

  Iterable<_TreeNode> get allFiles sync* {
    if (!isFolder) {
      yield this;
    } else {
      for (final c in children) {
        yield* c.allFiles;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        'p': path,
        'f': isFolder,
        's': size,
        'c': children.map((c) => c.toJson()).toList(),
      };

  factory _TreeNode.fromJson(Map<String, dynamic> json) {
    final node = _TreeNode(
      name: json['n'] as String,
      path: json['p'] as String,
      isFolder: json['f'] as bool,
      size: json['s'] as int? ?? 0,
    );
    for (final c in (json['c'] as List? ?? [])) {
      node.children.add(_TreeNode.fromJson(c as Map<String, dynamic>));
    }
    return node;
  }
}
