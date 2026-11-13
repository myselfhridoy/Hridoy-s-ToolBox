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
static final Map<String, String> _mdMem = {};
static final Map<String, JsonMap> _treeMem = {};
static SharedPreferences? _prefs;
static const _kLastUrl = 'gittomd_last_url';
static const _kLastMode = 'gittomd_last_mode';
static const _maxCacheBytes = 2 * 1024 * 1024;
final _urlController = TextEditingController();
final _pickerSearchController = TextEditingController();
_Mode _mode = _Mode.readme;
bool _loading = false;
String? _error;
String _markdown = '';
String? _resolvedRepo;
List<_TreeNode> _treeRoots = [];
Set<String> _selectedPaths = {};
Set<String> _expandedFolders = {};
bool _showPicker = false;
String _treeOwner = '';
String _treeRepo = '';
String _treeBranch = 'main';
String _pickerQuery = '';
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
static String mdKey(String owner, String repo, String mode) =>
'gittomd_md{owner}_{repo}_$mode';
static String treeKey(String owner, String repo) =>
'gittomd_tree{owner}_{repo}';
Future<String?> _loadMarkdown(String owner, String repo, String mode) async {
final k = _mdKey(owner, repo, mode);
if (_mdMem.containsKey(k)) return _mdMem[k];
final disk = _prefs?.getString(k);
if (disk != null) _mdMem[k] = disk;
return disk;
}
Future<void> _saveMarkdown(
String owner, String repo, String mode, String md) async {
if (md.length > _maxCacheBytes) return;
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
await prefs?.setString(k, jsonEncode(data));
} catch () {}
}
Future<JsonMap?> _loadPickerState(String owner, String repo) async {
final k = _treeKey(owner, repo);
if (_treeMem.containsKey(k)) return _treeMem[k];
final s = _prefs?.getString(k);
if (s == null) return null;
try {
final data = jsonDecode(s) as JsonMap;
treeMem[k] = data;
return data;
} catch () {
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
_resolvedRepo = '{parsed.owner}/{parsed.repo}';
final md = await _loadMarkdown(parsed.owner, parsed.repo, _mode.name);
if (_mode == _Mode.pick) {
final treeData = await _loadPickerState(parsed.owner, parsed.repo);
if (treeData != null) {
try {
_treeRoots = (treeData['roots'] as List)
.map((j) => _TreeNode.fromJson(j as JsonMap))
.toList();
_selectedPaths =
(treeData['selected'] as List).cast<String>().toSet();
_expandedFolders =
(treeData['expanded'] as List).cast<String>().toSet();
_treeOwner = parsed.owner;
_treeRepo = parsed.repo;
_treeBranch = treeData['branch'] as String? ?? 'main';
showPicker = md == null || md.isEmpty;
} catch () {}
}
}
if (md != null && md.isNotEmpty) _markdown = md;
if (mounted) setState(() {});
}
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
s = '{segs[0]}/{segs[1]}';
}
s = s.replaceAll(RegExp(r'.git$'), '');
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
final md = await _loadMarkdown(parsed.owner, parsed.repo, newMode.name);
JsonMap? treeData;
if (newMode == _Mode.pick) {
treeData = await _loadPickerState(parsed.owner, parsed.repo);
}
if (!mounted) return;
setState(() {
_resolvedRepo = '{parsed.owner}/{parsed.repo}';
_markdown = md ?? '';
if (newMode == _Mode.pick && treeData != null) {
_treeRoots = (treeData['roots'] as List)
.map((j) => _TreeNode.fromJson(j as JsonMap))
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
_resolvedRepo = '{parsed.owner}/{parsed.repo}';
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
final repoJson = jsonDecode(repoRes.body) as JsonMap;
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
final treeJson = jsonDecode(treeRes.body) as JsonMap;
final tree = (treeJson['tree'] as List).cast<JsonMap>();
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
..writeln('Branch: $branch')
..writeln()
..writeln('## Tree')
..writeln('') ..writeln(tree .where((e) => e['type'] == 'blob') .map((e) => e['path']) .join('\n')) ..writeln('')
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
final fence = '' * (_longestBacktickRun(content) + 1); buf ..writeln() ..writeln('### $path`')
..writeln('fence{langFromExt(path)}')
..writeln(content)
..writeln(fence);
count++;
if (count >= 60) {
buf.writeln('\n> …প্রথম 60টি ফাইল দেখানো হয়েছে');
break;
}
} catch () {}
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
Future<void> _loadTree(String owner, String repo) async {
final repoRes = await http.get(
Uri.parse('https://api.github.com/repos/$owner/$repo'),
headers: _headers,
);
_checkStatus(repoRes, what: 'Repo');
final repoJson = jsonDecode(repoRes.body) as JsonMap;
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
final treeJson = jsonDecode(treeRes.body) as JsonMap;
final tree = (treeJson['tree'] as List).cast<JsonMap>();
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
List<_TreeNode> _buildTree(List<JsonMap> tree,
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
'_treeOwner/https://raw.githubusercontent.com/_treeRepo/$_treeBranch';
final buf = StringBuffer()
..writeln('# _treeOwner/_treeRepo')
..writeln()
..writeln('Selected files ($_treeBranch):')
..writeln('') ..writeln(paths.join('\n')) ..writeln('')
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
final fence = '' * (_longestBacktickRun(content) + 1); buf ..writeln() ..writeln('### $path`')
..writeln('fence{langFromExt(path)}')
..writeln(content)
..writeln(fence);
}
}
} catch () {}
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
if (bytes < 1024) return '{bytes}B';
if (bytes < 1024 * 1024) {
return '{(bytes / 1024).toStringAsFixed(1)}KB';
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
Text(
'প্রাইভেট রিপো পড়তে PAT লাগবে।\n'
'Fine-grained: Contents → Read-only\n'
'Classic: repo স্কোপ',
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
hintText: 'github_pat_… or ghp_…',
suffixIcon: IconButton(
tooltip: obscure ? 'Show token' : 'Hide token',
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
final t = Theme.of(context).textTheme;
return Scaffold(
appBar: AppBar(
title: const Text('gittomd'),
centerTitle: false,
titleSpacing: 0,
actions: [
if (_mode == _Mode.pick && !_showPicker && _markdown.isNotEmpty)
IconButton(
icon: const Icon(Icons.list_alt_rounded),
tooltip: 'Back to picker',
onPressed: () => setState(() => _showPicker = true),
),
IconButton(
icon: Icon(
hasToken ? Icons.lock_rounded : Icons.lock_open_rounded,
color: hasToken ? AppColors.success : null,
),
tooltip: hasToken ? 'Token সেট আছে' : 'Token সেট করুন',
onPressed: _openTokenDialog,
),
if (_markdown.isNotEmpty)
IconButton(
icon: const Icon(Icons.copy_all_rounded),
tooltip: 'Copy Markdown',
onPressed: _copy,
),
],
),
body: AmbientBackdrop(
child: Column(
children: [
// ── Control Panel Card ──
Padding(
padding: const EdgeInsets.fromLTRB(
AppSpacing.lg,
AppSpacing.sm,
AppSpacing.lg,
AppSpacing.sm,
),
child: GlassCard(
radius: AppRadius.lg,
child: Padding(
padding: const EdgeInsets.all(AppSpacing.md),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
TextField(
controller: _urlController,
keyboardType: TextInputType.url,
textInputAction: TextInputAction.go,
decoration: InputDecoration(
hintText: 'https://github.com/owner/repo',
prefixIcon: const Icon(
Icons.link_rounded,
color: AppColors.primary,
),
suffixIcon: Padding(
padding: const EdgeInsets.only(right: 4),
child: _loading
? const Padding(
padding: EdgeInsets.all(14),
child: SizedBox(
width: 20,
height: 20,
child: CircularProgressIndicator(
strokeWidth: 2.2,
),
),
)
: IconButton(
tooltip: 'Fetch',
onPressed: fetch,
icon: const Icon(
Icons.arrow_circle_right_rounded,
color: AppColors.primary,
),
iconSize: 28,
),
),
),
onSubmitted: () {
if (!_loading) _fetch();
},
),
const SizedBox(height: AppSpacing.sm),
SizedBox(
width: double.infinity,
child: SegmentedButton<_Mode>(
segments: const [
ButtonSegment(
value: _Mode.readme,
label: Text('README'),
icon: Icon(Icons.article_outlined, size: 18),
),
ButtonSegment(
value: _Mode.fullRepo,
label: Text('Full'),
icon: Icon(Icons.folder_zip_outlined, size: 18),
),
ButtonSegment(
value: _Mode.pick,
label: Text('Pick'),
icon: Icon(Icons.checklist_rounded, size: 18),
),
],
selected: {_mode},
onSelectionChanged: _onModeChanged,
showSelectedIcon: false,
),
),
if (!hasToken) ...[
const SizedBox(height: AppSpacing.sm),
Row(
children: [
const Icon(
Icons.info_outline_rounded,
size: 15,
color: AppColors.textMuted,
),
const SizedBox(width: 6),
Expanded(
child: Text(
'টোকেন ছাড়া শুধু পাবলিক রিপো (৬০ req/hr)',
style: t.labelSmall?.copyWith(
color: AppColors.textMuted,
),
),
),
],
),
],
],
),
),
),
),
if (_error != null)
Padding(
padding: const EdgeInsets.fromLTRB(
AppSpacing.lg,
0,
AppSpacing.lg,
AppSpacing.sm,
),
child: Container(
width: double.infinity,
padding: const EdgeInsets.symmetric(
horizontal: AppSpacing.md,
vertical: 10,
),
decoration: BoxDecoration(
color: AppColors.error.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(AppRadius.md),
border: Border.all(
color: AppColors.error.withValues(alpha: 0.35),
),
),
child: Semantics(
liveRegion: true,
child: Text(
_error!,
style: t.bodySmall?.copyWith(color: AppColors.error),
),
),
),
),
if (_resolvedRepo != null &&
_markdown.isNotEmpty &&
!_showPicker)
Padding(
padding: const EdgeInsets.fromLTRB(
AppSpacing.lg,
0,
AppSpacing.lg,
AppSpacing.sm,
),
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: AppSpacing.md,
vertical: 7,
),
decoration: BoxDecoration(
color: AppColors.success.withValues(alpha: 0.1),
borderRadius: BorderRadius.circular(AppRadius.sm),
border: Border.all(
color: AppColors.success.withValues(alpha: 0.25),
),
),
child: Row(
children: [
const Icon(
Icons.check_circle_rounded,
size: 16,
color: AppColors.success,
),
const SizedBox(width: 8),
Expanded(
child: Text(
'$_resolvedRepo · ${_markdown.length} chars',
style: t.labelSmall?.copyWith(
color: AppColors.textSecondary,
fontWeight: FontWeight.w500,
),
),
),
],
),
),
),
const Divider(height: 1),
Expanded(child: _buildBody()),
],
),
),
);
}
Widget _buildBody() {
if (_loading) {
if (_genTotal > 0) {
return Center(
child: Padding(
padding: const EdgeInsets.all(AppSpacing.xxl),
child: GlassCard(
radius: AppRadius.lg,
child: Padding(
padding: const EdgeInsets.all(AppSpacing.xl),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
ClipRRect(
borderRadius: BorderRadius.circular(6),
child: LinearProgressIndicator(
value:
_genTotal == 0 ? null : _genProgress / _genTotal,
minHeight: 6,
backgroundColor: AppColors.fieldFill,
semanticsLabel: 'Fetching files',
semanticsValue: '$_genProgress of $_genTotal',
),
),
const SizedBox(height: AppSpacing.md),
Text(
'Fetching $_genProgress / $_genTotal',
style: Theme.of(context).textTheme.bodySmall,
),
],
),
),
),
),
);
}
return const SizedBox.shrink();
}
if (_mode == _Mode.pick && _showPicker) {
return _buildPickerView();
}
if (_markdown.isEmpty) {
final icon = _mode == _Mode.readme
? Icons.article_outlined
: _mode == _Mode.fullRepo
? Icons.folder_zip_outlined
: Icons.checklist_rounded;
return Center(
child: Padding(
padding: const EdgeInsets.all(AppSpacing.xxl),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Container(
width: 52,
height: 52,
decoration: BoxDecoration(
color: AppColors.primary.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(AppRadius.lg),
border: Border.all(
color: AppColors.primary.withValues(alpha: 0.25),
),
),
child: Icon(icon, size: 26, color: AppColors.primary),
),
const SizedBox(height: AppSpacing.md),
Text(
_mode == _Mode.readme
? 'Repo URL দিয়ে README আনুন'
: _mode == _Mode.fullRepo
? 'Repo URL দিয়ে পুরো রিপো Markdown-এ প্যাক করুন'
: 'Repo URL দিয়ে ফাইল ট্রি আনুন, তারপর নির্দিষ্ট ফাইল/ফোল্ডার বেছে নিন',
textAlign: TextAlign.center,
style: const TextStyle(color: AppColors.textMuted),
),
],
),
),
);
}
return Markdown(
data: _markdown,
padding: const EdgeInsets.all(AppSpacing.lg),
styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
codeblockDecoration: BoxDecoration(
color: AppColors.navBg,
borderRadius: BorderRadius.circular(AppRadius.md),
border: Border.all(color: AppColors.glassBorder),
),
code: const TextStyle(
fontFamily: 'monospace',
fontSize: 12,
color: AppColors.textPrimary,
),
blockquoteDecoration: BoxDecoration(
color: AppColors.primary.withValues(alpha: 0.08),
borderRadius: BorderRadius.circular(AppRadius.sm),
border: const Border(
left: BorderSide(color: AppColors.primary, width: 3),
),
),
),
);
}
Widget _buildPickerView() {
if (_treeRoots.isEmpty) {
return const Center(
child: Padding(
padding: EdgeInsets.all(AppSpacing.xxl),
child: Text(
'কোনো ফাইল পাওয়া যায়নি—Fetch চাপুন',
textAlign: TextAlign.center,
style: TextStyle(color: AppColors.textMuted),
),
),
);
}
final t = Theme.of(context).textTheme;
final visible = _flattenVisible();
final selectedCount = _selectedPaths.length;
final selectedSize = _selectedSize;
return Column(
children: [
Padding(
padding: const EdgeInsets.fromLTRB(
AppSpacing.lg,
AppSpacing.md,
AppSpacing.lg,
AppSpacing.sm,
),
child: GlassCard(
radius: AppRadius.md,
child: Padding(
padding: const EdgeInsets.all(AppSpacing.md),
child: Column(
children: [
Row(
children: [
Container(
padding: const EdgeInsets.symmetric(
horizontal: 10,
vertical: 4,
),
decoration: BoxDecoration(
color: AppColors.primary.withValues(alpha: 0.14),
borderRadius: BorderRadius.circular(999),
),
child: Text(
'$selectedCount files · ${_formatSize(selectedSize)}',
style: t.labelSmall?.copyWith(
color: AppColors.primary,
fontWeight: FontWeight.w600,
),
),
),
const Spacer(),
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
icon: const Icon(Icons.download_rounded, size: 20),
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
),
),
Padding(
padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
child: TextField(
controller: _pickerSearchController,
style: t.bodyMedium,
decoration: InputDecoration(
hintText: 'Filter by path…',
prefixIcon: const Icon(Icons.search_rounded, size: 20),
suffixIcon: _pickerQuery.isNotEmpty
? IconButton(
tooltip: 'Clear filter',
icon: const Icon(Icons.clear_rounded, size: 20),
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
const SizedBox(height: AppSpacing.sm),
const Divider(height: 1),
Expanded(
child: visible.isEmpty
? const Center(
child: Text(
'No matches',
style: TextStyle(color: AppColors.textMuted),
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
final t = Theme.of(context).textTheme;
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
final VoidCallback? onRowTap = node.isFolder
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
: (files.isEmpty ? null : () => _toggleSelection(node));
return InkWell(
onTap: onRowTap,
child: ConstrainedBox(
constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
child: Padding(
padding: EdgeInsets.only(
left: AppSpacing.sm + depth * 16.0,
right: AppSpacing.md,
),
child: Row(
children: [
if (node.isFolder)
Icon(
showChildren ? Icons.expand_more : Icons.chevron_right,
size: 20,
color: AppColors.textSecondary,
)
else
const SizedBox(width: 20),
Semantics(
label: 'Select ${node.name}',
child: Checkbox(
value: checkboxValue,
tristate: node.isFolder,
onChanged:
files.isEmpty ? null : (_) => _toggleSelection(node),
visualDensity: VisualDensity.compact,
),
),
Icon(
node.isFolder
? Icons.folder_rounded
: Icons.description_outlined,
size: 19,
color: node.isFolder
? AppColors.primary
: AppColors.textSecondary,
),
const SizedBox(width: 8),
Expanded(
child: Text(
node.name,
overflow: TextOverflow.ellipsis,
style: t.bodyMedium?.copyWith(
fontWeight:
node.isFolder ? FontWeight.w600 : FontWeight.normal,
),
),
),
if (!node.isFolder)
Text(
_formatSize(node.size),
style: t.labelSmall?.copyWith(color: AppColors.textMuted),
),
],
),
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
JsonMap toJson() => {
'n': name,
'p': path,
'f': isFolder,
's': size,
'c': children.map((c) => c.toJson()).toList(),
};
factory _TreeNode.fromJson(JsonMap json) {
final node = _TreeNode(
name: json['n'] as String,
path: json['p'] as String,
isFolder: json['f'] as bool,
size: json['s'] as int? ?? 0,
);
for (final c in (json['c'] as List? ?? [])) {
node.children.add(_TreeNode.fromJson(c as JsonMap));
}
return node;
}
}

---

### ২. `lib/tools/iptv_finder/iptv_finder_tool.dart`
```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/plugin/tool_plugin.dart';
import '../../core/storage/github_token_store.dart';
import '../../core/tokens.dart';
import '../../widgets/glass_card.dart';
import 'iptv_models.dart';
import 'net_utils.dart';
import 'm3u_parser.dart';
import 'github_search.dart';
import 'xtream_client.dart';
import 'link_validator.dart';

typedef StringMap = Map<String, String>;

class IptvFinderTool implements ToolPlugin {
  @override
  String get id => 'iptv_finder';

  @override
  String get name => 'IPTV Finder';

  @override
  IconData get icon => Icons.live_tv;

  @override
  List<String> get categories => ['Developer', 'Media'];

  @override
  List<String> get tags =>
      ['iptv', 'm3u', 'xtream', 'github', 'stream', 'scanner'];

  @override
  Widget buildPage(BuildContext context) => const IptvFinderPage();
}

// ───────────────────────── export helpers ─────────────────────────

String licHex(FoundLink r) {
  if ((r.lickey ?? '').isNotEmpty) return r.lickey!;
  final x = r.props.firstWhere(
    (p) => RegExp(r'license_key=', caseSensitive: false).hasMatch(p),
    orElse: () => '',
  );
  if (x.isEmpty) return '';
  final v = x
      .replaceFirst(RegExp(r'^.*?license_key=', caseSensitive: false), '')
      .trim();
  final hexp = RegExp(
      r'^[0-9a-f]{32}:[0-9a-f]{32}(,[0-9a-f]{32}:[0-9a-f]{32})*$',
      caseSensitive: false);
  if (RegExp(r'^https?:', caseSensitive: false).hasMatch(v)) {
    final kid = RegExp(r'[?&]keyid=([0-9a-f]{32})', caseSensitive: false)
        .firstMatch(v);
    final key =
        RegExp(r'[?&]key=([0-9a-f]{32})', caseSensitive: false).firstMatch(v);
    return (kid != null && key != null)
        ? '${kid.group(1)}:${key.group(1)}'
        : '';
  }
  if (v.startsWith('{')) {
    try {
      final obj = jsonDecode(v);
      if (obj is Map &&
          obj['keys'] is List &&
          (obj['keys'] as List).isNotEmpty) {
        return (obj['keys'] as List)
            .map((k) =>
                '${b64uToHex(k['kid'].toString())}:${b64uToHex(k['k'].toString())}')
            .join(',');
      }
      if (obj is Map) {
        final pairs = obj.entries
            .where((e) => e.value is String)
            .map((e) => '${e.key}:${e.value}')
            .join(',');
        if (hexp.hasMatch(pairs)) return pairs;
      }
    } catch (_) {}
    final flat = v.replaceAll(RegExp('[{}"\\x27\\s]'), '');
    if (hexp.hasMatch(flat)) return flat;
  }
  return hexp.hasMatch(v) ? v : '';
}

String finalUrl(FoundLink r, String player) {
  var u = r.url;
  final opts = <String>[];
  if (player == 'tivimate') {
    final k = licHex(r);
    if (k.isNotEmpty &&
        !RegExp(r'drmLicense=', caseSensitive: false).hasMatch(u)) {
      opts.add('drmScheme=clearkey');
      opts.add('drmLicense=$k');
    } else if (k.isEmpty &&
        !RegExp(r'drmLicense=', caseSensitive: false).hasMatch(u)) {
      final lp = r.props.firstWhere(
        (p) => RegExp(r'license_key=https?:', caseSensitive: false).hasMatch(p),
        orElse: () => '',
      );
      if (lp.isNotEmpty) {
        opts.add('drmScheme=clearkey');
        opts.add(
            'drmLicense=${lp.replaceFirst(RegExp(r'^.*?license_key=', caseSensitive: false), '').trim()}');
      }
    }
  }
  if (player != 'vlc') {
    final h = r.headers;
    if ((h['user-agent'] ?? '').isNotEmpty) {
      opts.add(
          'User-Agent=${player == 'kodi' ? Uri.encodeComponent(h['user-agent']!) : h['user-agent']}');
    }
    if ((h['referer'] ?? '').isNotEmpty) {
      opts.add(
          'Referer=${player == 'kodi' ? Uri.encodeComponent(h['referer']!) : h['referer']}');
    }
    if ((h['origin'] ?? '').isNotEmpty) {
      opts.add(
          'Origin=${player == 'kodi' ? Uri.encodeComponent(h['origin']!) : h['origin']}');
    }
    h.forEach((k, v) {
      if (k.startsWith('h_')) {
        final nm = headerCase(k.substring(2));
        opts.add('$nm=${player == 'kodi' ? Uri.encodeComponent(v) : v}');
      }
    });
  }
  if (opts.isNotEmpty) {
    u += (u.contains('|') ? '&' : '|') + opts.join('&');
  }
  return u;
}

String buildM3U(List<FoundLink> items, String player, String group) {
  final by = <String, List<FoundLink>>{};
  for (final r in items) {
    by.putIfAbsent(r.channelName, () => []).add(r);
  }
  final b = StringBuffer('#EXTM3U\n');
  for (final name in by.keys) {
    final arr = by[name]!;
    final bar = '##############[ $name ]##############';
    b.writeln(bar);
    for (final r in arr) {
      final t = (r.label.isNotEmpty ? r.label : r.channelName)
          .replaceAll(RegExp(r'[\r\n,]+'), ' ')
          .trim();
      final id = r.tvgId.isNotEmpty
          ? ' tvg-id="${r.tvgId.replaceAll('"', "'")}"'
          : '';
      final lo = r.tvgLogo.isNotEmpty
          ? ' tvg-logo="${r.tvgLogo.replaceAll('"', "'")}"'
          : '';
      final gtRaw = group.isNotEmpty
          ? group
          : (r.group.isNotEmpty
              ? r.group
              : ((r.cat ?? '').isNotEmpty ? r.cat! : name));
      final gt = gtRaw.replaceAll('"', "'");
      b.writeln('#EXTINF:-1$id$lo group-title="$gt",$t');
      if (player == 'kodi') {
        for (final p in r.props) {
          b.writeln('#KODIPROP:$p');
        }
      }
      if (player == 'vlc') {
        final h = r.headers;
        if ((h['user-agent'] ?? '').isNotEmpty) {
          b.writeln('#EXTVLCOPT:http-user-agent=${h['user-agent']}');
        }
        if ((h['referer'] ?? '').isNotEmpty) {
          b.writeln('#EXTVLCOPT:http-referrer=${h['referer']}');
        }
        if ((h['origin'] ?? '').isNotEmpty) {
          b.writeln('#EXTVLCOPT:http-origin=${h['origin']}');
        }
      }
      b.writeln(finalUrl(r, player));
    }
    b.writeln(bar);
    b.writeln();
  }
  return b.toString();
}

String _normalizeExtra(String u) {
  u = ghRawUrl(u);
  final glM = RegExp(r'^https://gitlab\.com/(.+?)/-/blob/', caseSensitive: false)
      .firstMatch(u);
  if (glM != null) {
    u = u.replaceFirst(
        glM.group(0)!, '[https://gitlab.com/$](https://gitlab.com/$){glM.group(1)}/-/raw/');
  }
  final gistM = RegExp(
          r'^https://gist\.github\.com/([^/\s]+)/([0-9a-f]+)/?$',
          caseSensitive: false)
      .firstMatch(u);
  if (gistM != null) {
    return '[https://gist.githubusercontent.com/$](https://gist.githubusercontent.com/$){gistM.group(1)}/${gistM.group(2)}/raw';
  }
  final pbM = RegExp(
          r'^https://pastebin\.com/(?!archive|trends|tools|login|signup|faq)([A-Za-z0-9]{6,10})/?$')
      .firstMatch(u);
  if (pbM != null) return '[https://pastebin.com/raw/$](https://pastebin.com/raw/$){pbM.group(1)}';
  return u;
}

Future<StringMap> _gistUserFiles(
  String user,
  String token,
  void Function(String) log,
) async {
  final out = <String, String>{};
  for (var pg = 1; pg <= 5; pg++) {
    final headers = <String, String>{
      if (token.isNotEmpty) 'h_authorization': 'Bearer $token',
    };
    final url =
        '[https://api.github.com/users/$](https://api.github.com/users/$){Uri.encodeComponent(user)}/gists?per_page=100&page=$pg';
    final r = await fetchFollow(url, headers,
        timeout: const Duration(seconds: 15), maxBytes: 3000000);
    if (r.code != 200) {
      log('gist:$user HTTP ${r.code}');
      break;
    }
    List d;
    try {
      d = jsonDecode(r.body) as List;
    } catch (_) {
      break;
    }
    if (d.isEmpty) break;
    for (final g in d) {
      final filesMap = g['files'] as Map?;
      if (filesMap == null) continue;
      filesMap.forEach((fn, f) {
        if (RegExp(r'\.(m3u8?|txt)$', caseSensitive: false)
                .hasMatch(fn.toString()) &&
            f['raw_url'] != null) {
          out[f['raw_url'].toString()] = 'gist:$user/$fn';
        }
      });
    }
  }
  return out;
}

