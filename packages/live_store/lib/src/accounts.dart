import 'dart:convert';

import 'package:live_store/src/secrets.dart';

/// One remembered sign-in of a platform (docs/K-账号和登录/K01-账号和登录方式/K01.2-哔哩哔哩多账号):
/// who it is, its cookie and when it was last the current one.
final class SavedAccount {
  /// Creates the entry.
  const new({required this.uid, required this.name, required this.cookie, required this.usedAt});

  /// The account id the platform gave when the cookie was checked.
  final int uid;

  /// The account name at that check ('' when unknown).
  final String name;

  /// The cookie header that signs it in.
  final String cookie;

  /// When it last became the current sign-in.
  final DateTime usedAt;

  /// The entry as a backup carries it (`cookie` section, `<site>Accounts`).
  Map<String, Object?> toJson() => {
    'uid': uid,
    'name': name,
    'cookie': cookie,
    'usedAt': usedAt.millisecondsSinceEpoch ~/ 1000,
  };

  /// The entry of [json] (a backup's or the stored value); null when it has
  /// no positive uid or no cookie.
  static SavedAccount? fromJson(Object? json, {int? uid}) {
    if (json is! Map) return null;
    final id =
        uid ??
        switch (json['uid']) {
          final num value => value.toInt(),
          final String value => int.tryParse(value.trim()),
          _ => null,
        };
    final cookie = switch (json['cookie']) {
      final String value => normalizeCookie(value),
      _ => '',
    };
    if (id == null || id <= 0 || cookie.isEmpty) return null;
    final seconds = switch (json['usedAt']) {
      final num value => value.toInt(),
      _ => 0,
    };
    return SavedAccount(
      uid: id,
      name: switch (json['name']) {
        final String value => value.trim(),
        _ => '',
      },
      cookie: cookie,
      usedAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
  }

  String get _sealedValue => jsonEncode({'name': name, 'cookie': cookie, 'usedAt': toJson()['usedAt']});

  SavedAccount _with({String? name, String? cookie, DateTime? usedAt}) =>
      SavedAccount(uid: uid, name: name ?? this.name, cookie: cookie ?? this.cookie, usedAt: usedAt ?? this.usedAt);
}

/// The sign-ins remembered per platform (docs/K-账号和登录/K01-账号和登录方式/K01.2-哔哩哔哩多账号, V01.2),
/// so the user can switch between them without signing in again.
///
/// Each entry is one secret, `account/<site>/<uid>`, sealed like the
/// current cookie (its name and cookie included); the current sign-in
/// stays [SecretRefs.cookie] (3.x's key, D-018), and switching copies an
/// entry's cookie there. Nothing here is a setting, so backups carry the
/// entries only where they carry cookies (`BackupService.exportAll` with
/// `includeSensitiveData`). Entries this device cannot open are left out
/// and removed with the next write of that platform's roster.
final class AccountRoster {
  /// Creates the roster over `secrets`; [now] stamps [SavedAccount.usedAt].
  new(this._secrets, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SecretStore _secrets;
  final DateTime Function() _now;

  /// How many sign-ins one platform keeps (V01.2 S3): remembering one more
  /// forgets the least recently used of the others.
  static const int limit = 5;

  /// The remembered sign-ins of [site], most recently used first.
  List<SavedAccount> of(String site) {
    final prefix = SecretRefs.accountsOf(site);
    final found = <SavedAccount>[];
    for (final ref in _secrets.refs) {
      if (!ref.startsWith(prefix)) continue;
      final uid = int.tryParse(ref.substring(prefix.length));
      final value = _secrets.read(ref);
      if (uid == null || value == null) continue;
      Object? json;
      try {
        json = jsonDecode(value);
      } on FormatException {
        continue;
      }
      if (SavedAccount.fromJson(json, uid: uid) case final account?) found.add(account);
    }
    return found..sort((a, b) {
      final used = b.usedAt.compareTo(a.usedAt);
      return used != 0 ? used : a.uid.compareTo(b.uid);
    });
  }

  /// The platforms with remembered sign-ins.
  Set<String> get sites => {
    for (final ref in _secrets.refs)
      if (ref.startsWith(SecretRefs.accountPrefix)) ref.substring(SecretRefs.accountPrefix.length).split('/').first,
  };

  /// The remembered sign-in [uid] of [site], or null.
  SavedAccount? find(String site, int uid) {
    for (final account in of(site)) {
      if (account.uid == uid) return account;
    }
    return null;
  }

  /// The platforms whose roster changed (the names of the changed
  /// secrets).
  Stream<String> get changes => _secrets.changes
      .where((ref) => ref.startsWith(SecretRefs.accountPrefix))
      .map((ref) => ref.substring(SecretRefs.accountPrefix.length).split('/').first);

  /// Remembers [uid], signed in with [cookie] as [name], as the current
  /// sign-in of [site] (its cookie was just checked). A new entry or a new
  /// cookie is marked used now; a known one keeps its name when [name] is
  /// empty. Nothing is written when nothing changed. Beyond [limit], the
  /// least recently used other entries are forgotten.
  Future<void> remember(String site, {required int uid, required String name, required String cookie}) async {
    final value = normalizeCookie(cookie);
    if (uid <= 0 || value.isEmpty) return;
    final known = find(site, uid);
    final entry = known == null
        ? SavedAccount(uid: uid, name: name.trim(), cookie: value, usedAt: _now())
        : known._with(
            name: name.trim().isEmpty ? null : name.trim(),
            cookie: value,
            usedAt: known.cookie == value ? null : _now(),
          );
    if (known != null && known.name == entry.name && known.cookie == entry.cookie) return;
    await _secrets.writeAll(_trimmed(site, {entry}));
  }

  /// Makes [uid] the current sign-in of [site]: its cookie becomes the
  /// platform's cookie and it is marked used now, in one write. [previous]
  /// (the sign-in being left, when it is not remembered yet) is remembered
  /// in the same write. Null when [uid] is not remembered.
  Future<SavedAccount?> switchTo(String site, int uid, {SavedAccount? previous}) async {
    final target = find(site, uid);
    if (target == null) return null;
    final now = _now();
    final entry = target._with(usedAt: now);
    final earlier = previous == null || previous.uid == uid
        ? null
        : previous._with(usedAt: now.subtract(const Duration(seconds: 1)));
    await _secrets.writeAll({
      ..._trimmed(site, {entry, ?earlier}),
      SecretRefs.cookie(site): entry.cookie,
    });
    return entry;
  }

  /// Forgets the sign-ins [uids] of [site].
  Future<void> forget(String site, Iterable<int> uids) async {
    final refs = {for (final uid in uids) SecretRefs.account(site, uid): null};
    if (refs.isEmpty) return;
    await _secrets.writeAll(refs);
  }

  /// The writes that forget every sign-in of [site] that matches
  /// [isCurrent] (signing out of it), for a caller that removes the cookie
  /// in the same write.
  Map<String, String?> forgetting(String site, bool Function(SavedAccount account) isCurrent) => {
    for (final account in of(site))
      if (isCurrent(account)) SecretRefs.account(site, account.uid): null,
  };

  /// Takes in [accounts] of [site] from a backup or a device sync: each one
  /// replaces the entry with its uid, the others stay. Beyond [limit] the
  /// least recently used are forgotten, never the one signed in with the
  /// platform's current cookie.
  Future<void> merge(String site, List<SavedAccount> accounts) async {
    if (accounts.isEmpty) return;
    final current = _secrets.cookieFor(site);
    final byUid = {for (final account in accounts) account.uid: account};
    final keep = {
      for (final account in byUid.values)
        if (account.cookie == current) account,
    };
    await _secrets.writeAll(_trimmed(site, byUid.values.toSet(), keep: keep.isEmpty ? null : keep));
  }

  /// The writes that store [entries] in [site]'s roster, forget what goes
  /// beyond [limit] (least recently used first, never [keep], which
  /// defaults to [entries]) and drop the entries this device cannot open.
  Map<String, String?> _trimmed(String site, Set<SavedAccount> entries, {Set<SavedAccount>? keep}) {
    final kept = {for (final entry in keep ?? entries) entry.uid};
    final byUid = {for (final account in of(site)) account.uid: account};
    for (final entry in entries) {
      byUid[entry.uid] = entry;
    }
    final writes = <String, String?>{
      for (final entry in entries) SecretRefs.account(site, entry.uid): entry._sealedValue,
      for (final ref in _secrets.unreadable)
        if (ref.startsWith(SecretRefs.accountsOf(site))) ref: null,
    };
    final others = [
      for (final account in byUid.values)
        if (!kept.contains(account.uid)) account,
    ]..sort((a, b) => a.usedAt.compareTo(b.usedAt));
    var count = byUid.length;
    for (final account in others) {
      if (count <= limit) break;
      writes[SecretRefs.account(site, account.uid)] = null;
      count--;
    }
    return writes;
  }
}
