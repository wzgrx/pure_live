import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/bytes.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/sync/webdav_client.dart';
import 'package:pure_live_app/features/sync/webdav_profiles.dart';

/// WebDAV profiles of this installation.
final webDavProfileStoreProvider = Provider<WebDavProfileStore>(
  (ref) => WebDavProfileStore(ref.watch(storeProvider).meta, ref.watch(secretStoreProvider)),
);

/// Creates a client for a profile; requests use the app's HTTP transport and
/// therefore its proxy policy (site id `webdav`).
final webDavClientFactoryProvider = Provider<WebDavClient Function(WebDavProfile profile)>((ref) {
  final http = ref.watch(liveHttpProvider);
  final profiles = ref.watch(webDavProfileStoreProvider);
  return (profile) =>
      WebDavClient(http, base: profile.base, username: profile.username, password: profiles.passwordOf(profile));
});

/// Chinese text for a failed WebDAV request.
String webDavErrorText(Object error) => switch (error) {
  WebDavException(error: WebDavError.unauthorized) => '用户名或密码不对',
  WebDavException(error: WebDavError.forbidden) => '这个账号没有权限访问该位置',
  WebDavException(error: WebDavError.notFound) => '远端没有这个文件或目录',
  WebDavException(error: WebDavError.insufficientStorage) => '网盘空间不足',
  WebDavException(error: WebDavError.network) => '连不上服务器，请检查地址和网络',
  WebDavException(error: WebDavError.invalidResponse) => '服务器的响应不是 WebDAV 格式，请检查地址',
  WebDavException(:final status) => '服务器出错（HTTP $status）',
  _ => backupErrorText(error),
};

/// WebDAV (F-DAV-01, store.md §10): several accounts, test the connection,
/// upload a full or follows-only v4 backup (accounts only behind a
/// passphrase), browse and delete remote files, restore in full or follows
/// only after the same dry run as a local restore.
class WebDavPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends ConsumerState<WebDavPage> {
  List<WebDavProfile> _profiles = const [];
  WebDavProfile? _current;
  List<String> _directory = const [];
  List<WebDavEntry>? _entries;
  String? _listError;
  bool _loading = true;
  String? _busy;
  // Results of requests started for an older profile or directory are
  // dropped (store.md §10).
  int _generation = 0;

  WebDavProfileStore get _store => ref.read(webDavProfileStoreProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  Future<void> _loadProfiles({String? select}) async {
    final profiles = await _store.load();
    final currentId = select ?? await _store.currentId();
    if (!mounted) return;
    final current = profiles.where((profile) => profile.id == currentId).firstOrNull ?? profiles.firstOrNull;
    setState(() {
      _profiles = profiles;
      _loading = false;
    });
    await _select(current);
  }

  Future<void> _select(WebDavProfile? profile) async {
    setState(() {
      _generation++;
      _current = profile;
      _directory = profile?.directory ?? const [];
      _entries = null;
      _listError = null;
    });
    if (profile != null) {
      await _store.setCurrent(profile.id);
      await _list();
    }
  }

  WebDavClient _client(WebDavProfile profile) => ref.read(webDavClientFactoryProvider)(profile);

  Future<void> _list() async {
    final profile = _current;
    if (profile == null) return;
    final generation = ++_generation;
    final directory = _directory;
    setState(() {
      _entries = null;
      _listError = null;
    });
    try {
      final entries = await _client(profile).list(directory);
      if (!mounted || generation != _generation) return;
      setState(() => _entries = [...entries.where((entry) => entry.isDirectory || _isBackupName(entry.name))]);
    } on WebDavException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _listError = error.error == WebDavError.notFound ? '远端目录还不存在，第一次上传时会自动创建' : webDavErrorText(error),
      );
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('webdav', 'list failed', error, stack);
      if (!mounted || generation != _generation) return;
      setState(() => _listError = webDavErrorText(error));
    }
  }

  // v4 files and the 3.x `purelive_*.txt`; the format is decided by content.
  static bool _isBackupName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.txt');
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(String label, Future<void> Function(int generation) action) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    final generation = _generation;
    try {
      await action(generation);
    } on Object catch (error, stack) {
      final log = ref.read(appLogProvider);
      if (error is WebDavException || error is FormatException || error is BackupTooNewException) {
        log.warning('webdav', '$label failed', error);
      } else {
        log.error('webdav', '$label failed', error, stack);
      }
      _toast(webDavErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _test() => _run('测试连接', (_) async {
    final exists = await _client(_current!).check(_current!.directory);
    _toast(exists ? '连接成功' : '连接成功；备份目录还不存在，第一次上传时会自动创建');
  });

  Future<void> _upload() async {
    final options = await showExportOptions(context, title: '上传备份', action: '上传');
    if (options == null) return;
    await _run('上传', (generation) async {
      final profile = _current!;
      final directory = _directory;
      final now = DateTime.now();
      final document = await ref
          .read(backupServiceProvider)
          .export(scope: options.scope, passphrase: options.passphrase, now: now);
      final client = _client(profile);
      await client.ensureDirectory(directory);
      await client.put([...directory, BackupService.fileName(options.scope, now)], encodeBackup(document));
      if (generation != _generation) return;
      _toast('已上传');
      unawaited(_list());
    });
  }

  Future<void> _restore(WebDavEntry entry, RestoreMode mode) => _run('恢复', (generation) async {
    final bytes = await _client(_current!).get(entry.path);
    if (!mounted || generation != _generation) return;
    await confirmAndRestore(
      context,
      service: ref.read(backupServiceProvider),
      document: decodeBackup(bytes),
      mode: mode,
      source: '来自 WebDAV：${entry.name}',
    );
  });

  Future<void> _delete(WebDavEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除远端文件'),
        content: Text('确定删除 ${entry.name}？删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run('删除', (generation) async {
      await _client(_current!).delete(entry.path);
      if (generation != _generation) return;
      _toast('已删除');
      unawaited(_list());
    });
  }

  void _open(List<String> directory) {
    setState(() => _directory = directory);
    unawaited(_list());
  }

  Future<void> _edit([WebDavProfile? profile]) async {
    final result = await showDialog<WebDavProfile>(
      context: context,
      builder: (context) => _ProfileDialog(profile: profile, store: _store, taken: _profiles),
    );
    if (result != null) await _loadProfiles(select: result.id);
  }

  Future<void> _remove(WebDavProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('删除“${profile.name}”和保存的密码？远端的备份文件不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(profile.id);
    await _loadProfiles();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV'),
        actions: [
          IconButton(tooltip: '帮助', icon: const Icon(Icons.help_outline), onPressed: () => _showHelp(context)),
          IconButton(tooltip: '添加账号', icon: const Icon(Icons.add), onPressed: _edit),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: _loading
              ? const LoadingView()
              : current == null
              ? MessageView(
                  icon: Icons.cloud_off_outlined,
                  title: '还没有 WebDAV 账号',
                  message: '添加坚果云、Nextcloud、群晖等支持 WebDAV 的网盘，把备份存到云端。',
                  actionLabel: '添加账号',
                  onAction: _edit,
                )
              : AbsorbPointer(absorbing: _busy != null, child: _body(current)),
        ),
      ),
    );
  }

  Widget _body(WebDavProfile current) {
    final entries = _entries;
    final path = _directory.isEmpty ? '/' : '/${_directory.join('/')}/';
    return RefreshIndicator(
      onRefresh: _list,
      child: ListView(
        children: [
          if (_busy != null) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(current.name),
            subtitle: Text('${current.baseUrl}${current.username.isEmpty ? '' : ' · ${current.username}'}'),
            trailing: PopupMenuButton<String>(
              tooltip: '账号',
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await _edit(current);
                  case 'delete':
                    await _remove(current);
                  default:
                    await _select(_profiles.firstWhere((profile) => profile.id == value));
                }
              },
              itemBuilder: (context) => [
                for (final profile in _profiles)
                  if (profile.id != current.id) PopupMenuItem(value: profile.id, child: Text('切换到 ${profile.name}')),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                OutlinedButton.icon(
                  onPressed: _test,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
                FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传备份'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          const Divider(),
          ListTile(
            dense: true,
            title: Text('远端文件 $path'),
            subtitle: const Text('点文件可以恢复或删除；3.x 的 purelive_*.txt 备份也能恢复'),
            trailing: IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _list),
          ),
          if (_directory.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('上一级'),
              onTap: () => _open(_directory.sublist(0, _directory.length - 1)),
            ),
          if (_listError case final error?)
            Padding(padding: const EdgeInsets.all(Space.s4), child: Text(error))
          else if (entries == null)
            const Padding(
              padding: EdgeInsets.all(Space.s6),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (entries.isEmpty)
            const Padding(padding: EdgeInsets.all(Space.s4), child: Text('这里还没有备份'))
          else
            for (final entry in entries) _entryTile(entry),
        ],
      ),
    );
  }

  Widget _entryTile(WebDavEntry entry) {
    if (entry.isDirectory) {
      return ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(entry.name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(entry.path),
      );
    }
    final details = [
      if (entry.modified case final time?) _formatTime(time),
      if (entry.size case final size?) formatBytes(size),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: PopupMenuButton<String>(
        tooltip: '操作',
        onSelected: (value) => switch (value) {
          'full' => _restore(entry, RestoreMode.full),
          'follows' => _restore(entry, RestoreMode.follows),
          _ => _delete(entry),
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'full', child: Text('完整恢复')),
          PopupMenuItem(value: 'follows', child: Text('仅恢复关注')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = time.toLocal();
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

void _showHelp(BuildContext context) => unawaited(
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('WebDAV 帮助'),
      content: const SingleChildScrollView(
        child: Text(
          '坚果云：地址填 https://dav.jianguoyun.com/dav/，用户名是登录邮箱，密码要用“账户信息 › 安全选项”里生成的第三方应用密码。\n\n'
          'Nextcloud / ownCloud：地址填 https://你的域名/remote.php/dav/files/用户名/。\n\n'
          '群晖：在套件中心安装 WebDAV Server，地址填 https://NAS地址:5006/。\n\n'
          'Alist 等：地址一般是 https://域名/dav/。\n\n'
          '备份目录默认是 pure_live，第一次上传时自动创建。密码加密保存在本机，不会进入普通备份。',
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
    ),
  ),
);

class _ProfileDialog extends StatefulWidget {
  const new({required this.profile, required this.store, required this.taken});

  final WebDavProfile? profile;
  final WebDavProfileStore store;
  final List<WebDavProfile> taken;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController(text: widget.profile?.name ?? (widget.taken.isEmpty ? '我的网盘' : ''));
  late final _url = TextEditingController(text: widget.profile?.baseUrl ?? 'https://');
  late final _user = TextEditingController(text: widget.profile?.username ?? '');
  final _password = TextEditingController();
  late final _directory = TextEditingController(text: widget.profile?.remoteDir ?? 'pure_live');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_name, _url, _user, _password, _directory]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final editing = widget.profile;
    final profile = WebDavProfile(
      id: editing?.id ?? WebDavProfileStore.newId(),
      name: _name.text,
      baseUrl: _url.text,
      username: _user.text,
      remoteDir: _directory.text,
    );
    try {
      // Editing keeps the stored password unless a new one is typed.
      final saved = await widget.store.save(
        profile,
        password: editing != null && _password.text.isEmpty ? null : _password.text,
      );
      if (mounted) Navigator.pop(context, saved);
    } on WebDavProfileException catch (error) {
      setState(() {
        _saving = false;
        _error = switch (error.error) {
          WebDavProfileError.emptyName => '请填写名称',
          WebDavProfileError.duplicateName => '已经有同名的账号',
          WebDavProfileError.invalidUrl => '地址要以 http:// 或 https:// 开头，不能带用户名、问号参数或 #',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.profile == null ? '添加 WebDAV 账号' : '编辑 WebDAV 账号'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '地址', hintText: 'https://dav.jianguoyun.com/dav/'),
            ),
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: '密码', helperText: widget.profile == null ? '加密保存在本机' : '不修改请留空'),
            ),
            TextField(
              controller: _directory,
              decoration: const InputDecoration(labelText: '备份目录', helperText: '留空表示根目录'),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
    ],
  );
}
