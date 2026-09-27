// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RoomsTable extends Rooms with TableInfo<$RoomsTable, RoomRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nickMeta = const VerificationMeta('nick');
  @override
  late final GeneratedColumn<String> nick = GeneratedColumn<String>(
    'nick',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverMeta = const VerificationMeta('cover');
  @override
  late final GeneratedColumn<String> cover = GeneratedColumn<String>(
    'cover',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaMeta = const VerificationMeta('area');
  @override
  late final GeneratedColumn<String> area = GeneratedColumn<String>(
    'area',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onlineViewersMeta = const VerificationMeta('onlineViewers');
  @override
  late final GeneratedColumn<int> onlineViewers = GeneratedColumn<int>(
    'online_viewers',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _popularityMeta = const VerificationMeta('popularity');
  @override
  late final GeneratedColumn<int> popularity = GeneratedColumn<int>(
    'popularity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalViewersMeta = const VerificationMeta('totalViewers');
  @override
  late final GeneratedColumn<int> totalViewers = GeneratedColumn<int>(
    'total_viewers',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _followersMeta = const VerificationMeta('followers');
  @override
  late final GeneratedColumn<int> followers = GeneratedColumn<int>(
    'followers',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastStatusMeta = const VerificationMeta('lastStatus');
  @override
  late final GeneratedColumn<String> lastStatus = GeneratedColumn<String>(
    'last_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastLiveAtMeta = const VerificationMeta('lastLiveAt');
  @override
  late final GeneratedColumn<int> lastLiveAt = GeneratedColumn<int>(
    'last_live_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    platform,
    roomId,
    nick,
    title,
    avatar,
    cover,
    area,
    userId,
    onlineViewers,
    popularity,
    totalViewers,
    followers,
    lastStatus,
    lastLiveAt,
    extra,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(Insertable<RoomRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(_roomIdMeta, roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta));
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('nick')) {
      context.handle(_nickMeta, nick.isAcceptableOrUnknown(data['nick']!, _nickMeta));
    }
    if (data.containsKey('title')) {
      context.handle(_titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('avatar')) {
      context.handle(_avatarMeta, avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta));
    }
    if (data.containsKey('cover')) {
      context.handle(_coverMeta, cover.isAcceptableOrUnknown(data['cover']!, _coverMeta));
    }
    if (data.containsKey('area')) {
      context.handle(_areaMeta, area.isAcceptableOrUnknown(data['area']!, _areaMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta, userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('online_viewers')) {
      context.handle(
        _onlineViewersMeta,
        onlineViewers.isAcceptableOrUnknown(data['online_viewers']!, _onlineViewersMeta),
      );
    }
    if (data.containsKey('popularity')) {
      context.handle(_popularityMeta, popularity.isAcceptableOrUnknown(data['popularity']!, _popularityMeta));
    }
    if (data.containsKey('total_viewers')) {
      context.handle(_totalViewersMeta, totalViewers.isAcceptableOrUnknown(data['total_viewers']!, _totalViewersMeta));
    }
    if (data.containsKey('followers')) {
      context.handle(_followersMeta, followers.isAcceptableOrUnknown(data['followers']!, _followersMeta));
    }
    if (data.containsKey('last_status')) {
      context.handle(_lastStatusMeta, lastStatus.isAcceptableOrUnknown(data['last_status']!, _lastStatusMeta));
    }
    if (data.containsKey('last_live_at')) {
      context.handle(_lastLiveAtMeta, lastLiveAt.isAcceptableOrUnknown(data['last_live_at']!, _lastLiveAtMeta));
    }
    if (data.containsKey('extra')) {
      context.handle(_extraMeta, extra.isAcceptableOrUnknown(data['extra']!, _extraMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta, updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {platform, roomId},
  ];
  @override
  RoomRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      roomId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}room_id'])!,
      nick: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}nick'])!,
      title: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      avatar: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}avatar']),
      cover: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}cover']),
      area: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}area']),
      userId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      onlineViewers: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}online_viewers']),
      popularity: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}popularity']),
      totalViewers: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}total_viewers']),
      followers: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}followers']),
      lastStatus: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}last_status']),
      lastLiveAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}last_live_at']),
      extra: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}extra']),
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }
}

class RoomRow extends DataClass implements Insertable<RoomRow> {
  /// Internal row id; never leaves the device.
  final int id;

  /// Lower-case platform id.
  final String platform;

  /// Room id as the platform spells it.
  final String roomId;

  /// Streamer's display name.
  final String nick;

  /// Last known broadcast title.
  final String title;

  /// Streamer's avatar URL.
  final String? avatar;

  /// Last known cover URL.
  final String? cover;

  /// Last known area name.
  final String? area;

  /// The streamer's user id on the platform, when known.
  final String? userId;

  /// Concurrent viewers at the last refresh.
  final int? onlineViewers;

  /// Popularity score at the last refresh.
  final int? popularity;

  /// Cumulative viewers at the last refresh.
  final int? totalViewers;

  /// Follower count, when known.
  final int? followers;

  /// Last known state: `live`, `offline`, `replay` or `banned`; null means
  /// unknown. A cache only: the UI shows every follow as unknown at startup
  /// (store.md §6.4.10).
  final String? lastStatus;

  /// When the room was last seen live (UTC milliseconds).
  final int? lastLiveAt;

  /// JSON object with rarely used fields (notice, introduction, IPTV data).
  final String? extra;

  /// When this row last changed (UTC milliseconds).
  final int updatedAt;
  const RoomRow({
    required this.id,
    required this.platform,
    required this.roomId,
    required this.nick,
    required this.title,
    this.avatar,
    this.cover,
    this.area,
    this.userId,
    this.onlineViewers,
    this.popularity,
    this.totalViewers,
    this.followers,
    this.lastStatus,
    this.lastLiveAt,
    this.extra,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['platform'] = Variable<String>(platform);
    map['room_id'] = Variable<String>(roomId);
    map['nick'] = Variable<String>(nick);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<String>(avatar);
    }
    if (!nullToAbsent || cover != null) {
      map['cover'] = Variable<String>(cover);
    }
    if (!nullToAbsent || area != null) {
      map['area'] = Variable<String>(area);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || onlineViewers != null) {
      map['online_viewers'] = Variable<int>(onlineViewers);
    }
    if (!nullToAbsent || popularity != null) {
      map['popularity'] = Variable<int>(popularity);
    }
    if (!nullToAbsent || totalViewers != null) {
      map['total_viewers'] = Variable<int>(totalViewers);
    }
    if (!nullToAbsent || followers != null) {
      map['followers'] = Variable<int>(followers);
    }
    if (!nullToAbsent || lastStatus != null) {
      map['last_status'] = Variable<String>(lastStatus);
    }
    if (!nullToAbsent || lastLiveAt != null) {
      map['last_live_at'] = Variable<int>(lastLiveAt);
    }
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      id: Value(id),
      platform: Value(platform),
      roomId: Value(roomId),
      nick: Value(nick),
      title: Value(title),
      avatar: avatar == null && nullToAbsent ? const Value.absent() : Value(avatar),
      cover: cover == null && nullToAbsent ? const Value.absent() : Value(cover),
      area: area == null && nullToAbsent ? const Value.absent() : Value(area),
      userId: userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      onlineViewers: onlineViewers == null && nullToAbsent ? const Value.absent() : Value(onlineViewers),
      popularity: popularity == null && nullToAbsent ? const Value.absent() : Value(popularity),
      totalViewers: totalViewers == null && nullToAbsent ? const Value.absent() : Value(totalViewers),
      followers: followers == null && nullToAbsent ? const Value.absent() : Value(followers),
      lastStatus: lastStatus == null && nullToAbsent ? const Value.absent() : Value(lastStatus),
      lastLiveAt: lastLiveAt == null && nullToAbsent ? const Value.absent() : Value(lastLiveAt),
      extra: extra == null && nullToAbsent ? const Value.absent() : Value(extra),
      updatedAt: Value(updatedAt),
    );
  }

  factory RoomRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomRow(
      id: serializer.fromJson<int>(json['id']),
      platform: serializer.fromJson<String>(json['platform']),
      roomId: serializer.fromJson<String>(json['roomId']),
      nick: serializer.fromJson<String>(json['nick']),
      title: serializer.fromJson<String>(json['title']),
      avatar: serializer.fromJson<String?>(json['avatar']),
      cover: serializer.fromJson<String?>(json['cover']),
      area: serializer.fromJson<String?>(json['area']),
      userId: serializer.fromJson<String?>(json['userId']),
      onlineViewers: serializer.fromJson<int?>(json['onlineViewers']),
      popularity: serializer.fromJson<int?>(json['popularity']),
      totalViewers: serializer.fromJson<int?>(json['totalViewers']),
      followers: serializer.fromJson<int?>(json['followers']),
      lastStatus: serializer.fromJson<String?>(json['lastStatus']),
      lastLiveAt: serializer.fromJson<int?>(json['lastLiveAt']),
      extra: serializer.fromJson<String?>(json['extra']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'platform': serializer.toJson<String>(platform),
      'roomId': serializer.toJson<String>(roomId),
      'nick': serializer.toJson<String>(nick),
      'title': serializer.toJson<String>(title),
      'avatar': serializer.toJson<String?>(avatar),
      'cover': serializer.toJson<String?>(cover),
      'area': serializer.toJson<String?>(area),
      'userId': serializer.toJson<String?>(userId),
      'onlineViewers': serializer.toJson<int?>(onlineViewers),
      'popularity': serializer.toJson<int?>(popularity),
      'totalViewers': serializer.toJson<int?>(totalViewers),
      'followers': serializer.toJson<int?>(followers),
      'lastStatus': serializer.toJson<String?>(lastStatus),
      'lastLiveAt': serializer.toJson<int?>(lastLiveAt),
      'extra': serializer.toJson<String?>(extra),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  RoomRow copyWith({
    int? id,
    String? platform,
    String? roomId,
    String? nick,
    String? title,
    Value<String?> avatar = const Value.absent(),
    Value<String?> cover = const Value.absent(),
    Value<String?> area = const Value.absent(),
    Value<String?> userId = const Value.absent(),
    Value<int?> onlineViewers = const Value.absent(),
    Value<int?> popularity = const Value.absent(),
    Value<int?> totalViewers = const Value.absent(),
    Value<int?> followers = const Value.absent(),
    Value<String?> lastStatus = const Value.absent(),
    Value<int?> lastLiveAt = const Value.absent(),
    Value<String?> extra = const Value.absent(),
    int? updatedAt,
  }) => RoomRow(
    id: id ?? this.id,
    platform: platform ?? this.platform,
    roomId: roomId ?? this.roomId,
    nick: nick ?? this.nick,
    title: title ?? this.title,
    avatar: avatar.present ? avatar.value : this.avatar,
    cover: cover.present ? cover.value : this.cover,
    area: area.present ? area.value : this.area,
    userId: userId.present ? userId.value : this.userId,
    onlineViewers: onlineViewers.present ? onlineViewers.value : this.onlineViewers,
    popularity: popularity.present ? popularity.value : this.popularity,
    totalViewers: totalViewers.present ? totalViewers.value : this.totalViewers,
    followers: followers.present ? followers.value : this.followers,
    lastStatus: lastStatus.present ? lastStatus.value : this.lastStatus,
    lastLiveAt: lastLiveAt.present ? lastLiveAt.value : this.lastLiveAt,
    extra: extra.present ? extra.value : this.extra,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RoomRow copyWithCompanion(RoomsCompanion data) {
    return RoomRow(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      nick: data.nick.present ? data.nick.value : this.nick,
      title: data.title.present ? data.title.value : this.title,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      cover: data.cover.present ? data.cover.value : this.cover,
      area: data.area.present ? data.area.value : this.area,
      userId: data.userId.present ? data.userId.value : this.userId,
      onlineViewers: data.onlineViewers.present ? data.onlineViewers.value : this.onlineViewers,
      popularity: data.popularity.present ? data.popularity.value : this.popularity,
      totalViewers: data.totalViewers.present ? data.totalViewers.value : this.totalViewers,
      followers: data.followers.present ? data.followers.value : this.followers,
      lastStatus: data.lastStatus.present ? data.lastStatus.value : this.lastStatus,
      lastLiveAt: data.lastLiveAt.present ? data.lastLiveAt.value : this.lastLiveAt,
      extra: data.extra.present ? data.extra.value : this.extra,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomRow(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('roomId: $roomId, ')
          ..write('nick: $nick, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('cover: $cover, ')
          ..write('area: $area, ')
          ..write('userId: $userId, ')
          ..write('onlineViewers: $onlineViewers, ')
          ..write('popularity: $popularity, ')
          ..write('totalViewers: $totalViewers, ')
          ..write('followers: $followers, ')
          ..write('lastStatus: $lastStatus, ')
          ..write('lastLiveAt: $lastLiveAt, ')
          ..write('extra: $extra, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    platform,
    roomId,
    nick,
    title,
    avatar,
    cover,
    area,
    userId,
    onlineViewers,
    popularity,
    totalViewers,
    followers,
    lastStatus,
    lastLiveAt,
    extra,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomRow &&
          other.id == this.id &&
          other.platform == this.platform &&
          other.roomId == this.roomId &&
          other.nick == this.nick &&
          other.title == this.title &&
          other.avatar == this.avatar &&
          other.cover == this.cover &&
          other.area == this.area &&
          other.userId == this.userId &&
          other.onlineViewers == this.onlineViewers &&
          other.popularity == this.popularity &&
          other.totalViewers == this.totalViewers &&
          other.followers == this.followers &&
          other.lastStatus == this.lastStatus &&
          other.lastLiveAt == this.lastLiveAt &&
          other.extra == this.extra &&
          other.updatedAt == this.updatedAt);
}

class RoomsCompanion extends UpdateCompanion<RoomRow> {
  final Value<int> id;
  final Value<String> platform;
  final Value<String> roomId;
  final Value<String> nick;
  final Value<String> title;
  final Value<String?> avatar;
  final Value<String?> cover;
  final Value<String?> area;
  final Value<String?> userId;
  final Value<int?> onlineViewers;
  final Value<int?> popularity;
  final Value<int?> totalViewers;
  final Value<int?> followers;
  final Value<String?> lastStatus;
  final Value<int?> lastLiveAt;
  final Value<String?> extra;
  final Value<int> updatedAt;
  const RoomsCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.roomId = const Value.absent(),
    this.nick = const Value.absent(),
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.cover = const Value.absent(),
    this.area = const Value.absent(),
    this.userId = const Value.absent(),
    this.onlineViewers = const Value.absent(),
    this.popularity = const Value.absent(),
    this.totalViewers = const Value.absent(),
    this.followers = const Value.absent(),
    this.lastStatus = const Value.absent(),
    this.lastLiveAt = const Value.absent(),
    this.extra = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  RoomsCompanion.insert({
    this.id = const Value.absent(),
    required String platform,
    required String roomId,
    this.nick = const Value.absent(),
    this.title = const Value.absent(),
    this.avatar = const Value.absent(),
    this.cover = const Value.absent(),
    this.area = const Value.absent(),
    this.userId = const Value.absent(),
    this.onlineViewers = const Value.absent(),
    this.popularity = const Value.absent(),
    this.totalViewers = const Value.absent(),
    this.followers = const Value.absent(),
    this.lastStatus = const Value.absent(),
    this.lastLiveAt = const Value.absent(),
    this.extra = const Value.absent(),
    required int updatedAt,
  }) : platform = Value(platform),
       roomId = Value(roomId),
       updatedAt = Value(updatedAt);
  static Insertable<RoomRow> custom({
    Expression<int>? id,
    Expression<String>? platform,
    Expression<String>? roomId,
    Expression<String>? nick,
    Expression<String>? title,
    Expression<String>? avatar,
    Expression<String>? cover,
    Expression<String>? area,
    Expression<String>? userId,
    Expression<int>? onlineViewers,
    Expression<int>? popularity,
    Expression<int>? totalViewers,
    Expression<int>? followers,
    Expression<String>? lastStatus,
    Expression<int>? lastLiveAt,
    Expression<String>? extra,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (platform != null) 'platform': platform,
      if (roomId != null) 'room_id': roomId,
      if (nick != null) 'nick': nick,
      if (title != null) 'title': title,
      if (avatar != null) 'avatar': avatar,
      if (cover != null) 'cover': cover,
      if (area != null) 'area': area,
      if (userId != null) 'user_id': userId,
      if (onlineViewers != null) 'online_viewers': onlineViewers,
      if (popularity != null) 'popularity': popularity,
      if (totalViewers != null) 'total_viewers': totalViewers,
      if (followers != null) 'followers': followers,
      if (lastStatus != null) 'last_status': lastStatus,
      if (lastLiveAt != null) 'last_live_at': lastLiveAt,
      if (extra != null) 'extra': extra,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  RoomsCompanion copyWith({
    Value<int>? id,
    Value<String>? platform,
    Value<String>? roomId,
    Value<String>? nick,
    Value<String>? title,
    Value<String?>? avatar,
    Value<String?>? cover,
    Value<String?>? area,
    Value<String?>? userId,
    Value<int?>? onlineViewers,
    Value<int?>? popularity,
    Value<int?>? totalViewers,
    Value<int?>? followers,
    Value<String?>? lastStatus,
    Value<int?>? lastLiveAt,
    Value<String?>? extra,
    Value<int>? updatedAt,
  }) {
    return RoomsCompanion(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      roomId: roomId ?? this.roomId,
      nick: nick ?? this.nick,
      title: title ?? this.title,
      avatar: avatar ?? this.avatar,
      cover: cover ?? this.cover,
      area: area ?? this.area,
      userId: userId ?? this.userId,
      onlineViewers: onlineViewers ?? this.onlineViewers,
      popularity: popularity ?? this.popularity,
      totalViewers: totalViewers ?? this.totalViewers,
      followers: followers ?? this.followers,
      lastStatus: lastStatus ?? this.lastStatus,
      lastLiveAt: lastLiveAt ?? this.lastLiveAt,
      extra: extra ?? this.extra,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (nick.present) {
      map['nick'] = Variable<String>(nick.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (cover.present) {
      map['cover'] = Variable<String>(cover.value);
    }
    if (area.present) {
      map['area'] = Variable<String>(area.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (onlineViewers.present) {
      map['online_viewers'] = Variable<int>(onlineViewers.value);
    }
    if (popularity.present) {
      map['popularity'] = Variable<int>(popularity.value);
    }
    if (totalViewers.present) {
      map['total_viewers'] = Variable<int>(totalViewers.value);
    }
    if (followers.present) {
      map['followers'] = Variable<int>(followers.value);
    }
    if (lastStatus.present) {
      map['last_status'] = Variable<String>(lastStatus.value);
    }
    if (lastLiveAt.present) {
      map['last_live_at'] = Variable<int>(lastLiveAt.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('roomId: $roomId, ')
          ..write('nick: $nick, ')
          ..write('title: $title, ')
          ..write('avatar: $avatar, ')
          ..write('cover: $cover, ')
          ..write('area: $area, ')
          ..write('userId: $userId, ')
          ..write('onlineViewers: $onlineViewers, ')
          ..write('popularity: $popularity, ')
          ..write('totalViewers: $totalViewers, ')
          ..write('followers: $followers, ')
          ..write('lastStatus: $lastStatus, ')
          ..write('lastLiveAt: $lastLiveAt, ')
          ..write('extra: $extra, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $FollowsTable extends Follows with TableInfo<$FollowsTable, FollowRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FollowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<int> room = GeneratedColumn<int>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES rooms (id) ON DELETE CASCADE'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _followedAtMeta = const VerificationMeta('followedAt');
  @override
  late final GeneratedColumn<int> followedAt = GeneratedColumn<int>(
    'followed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  @override
  List<GeneratedColumn> get $columns => [room, sortOrder, followedAt, source];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'follows';
  @override
  VerificationContext validateIntegrity(Insertable<FollowRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room')) {
      context.handle(_roomMeta, room.isAcceptableOrUnknown(data['room']!, _roomMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta, sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('followed_at')) {
      context.handle(_followedAtMeta, followedAt.isAcceptableOrUnknown(data['followed_at']!, _followedAtMeta));
    } else if (isInserting) {
      context.missing(_followedAtMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta, source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {room};
  @override
  FollowRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FollowRow(
      room: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}room'])!,
      sortOrder: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      followedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}followed_at'])!,
      source: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}source'])!,
    );
  }

  @override
  $FollowsTable createAlias(String alias) {
    return $FollowsTable(attachedDatabase, alias);
  }
}

class FollowRow extends DataClass implements Insertable<FollowRow> {
  /// The followed room.
  final int room;

  /// Custom order, ascending.
  final int sortOrder;

  /// When the room was followed (UTC milliseconds).
  final int followedAt;

  /// `user`, `import` or `backup`.
  final String source;
  const FollowRow({required this.room, required this.sortOrder, required this.followedAt, required this.source});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room'] = Variable<int>(room);
    map['sort_order'] = Variable<int>(sortOrder);
    map['followed_at'] = Variable<int>(followedAt);
    map['source'] = Variable<String>(source);
    return map;
  }

  FollowsCompanion toCompanion(bool nullToAbsent) {
    return FollowsCompanion(
      room: Value(room),
      sortOrder: Value(sortOrder),
      followedAt: Value(followedAt),
      source: Value(source),
    );
  }

  factory FollowRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FollowRow(
      room: serializer.fromJson<int>(json['room']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      followedAt: serializer.fromJson<int>(json['followedAt']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'room': serializer.toJson<int>(room),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'followedAt': serializer.toJson<int>(followedAt),
      'source': serializer.toJson<String>(source),
    };
  }

  FollowRow copyWith({int? room, int? sortOrder, int? followedAt, String? source}) => FollowRow(
    room: room ?? this.room,
    sortOrder: sortOrder ?? this.sortOrder,
    followedAt: followedAt ?? this.followedAt,
    source: source ?? this.source,
  );
  FollowRow copyWithCompanion(FollowsCompanion data) {
    return FollowRow(
      room: data.room.present ? data.room.value : this.room,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      followedAt: data.followedAt.present ? data.followedAt.value : this.followedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FollowRow(')
          ..write('room: $room, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('followedAt: $followedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(room, sortOrder, followedAt, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FollowRow &&
          other.room == this.room &&
          other.sortOrder == this.sortOrder &&
          other.followedAt == this.followedAt &&
          other.source == this.source);
}

class FollowsCompanion extends UpdateCompanion<FollowRow> {
  final Value<int> room;
  final Value<int> sortOrder;
  final Value<int> followedAt;
  final Value<String> source;
  const FollowsCompanion({
    this.room = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.followedAt = const Value.absent(),
    this.source = const Value.absent(),
  });
  FollowsCompanion.insert({
    this.room = const Value.absent(),
    required int sortOrder,
    required int followedAt,
    this.source = const Value.absent(),
  }) : sortOrder = Value(sortOrder),
       followedAt = Value(followedAt);
  static Insertable<FollowRow> custom({
    Expression<int>? room,
    Expression<int>? sortOrder,
    Expression<int>? followedAt,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (room != null) 'room': room,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (followedAt != null) 'followed_at': followedAt,
      if (source != null) 'source': source,
    });
  }

  FollowsCompanion copyWith({Value<int>? room, Value<int>? sortOrder, Value<int>? followedAt, Value<String>? source}) {
    return FollowsCompanion(
      room: room ?? this.room,
      sortOrder: sortOrder ?? this.sortOrder,
      followedAt: followedAt ?? this.followedAt,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (room.present) {
      map['room'] = Variable<int>(room.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (followedAt.present) {
      map['followed_at'] = Variable<int>(followedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FollowsCompanion(')
          ..write('room: $room, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('followedAt: $followedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $FollowAreasTable extends FollowAreas with TableInfo<$FollowAreasTable, FollowAreaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FollowAreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _platformMeta = const VerificationMeta('platform');
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _namespaceMeta = const VerificationMeta('namespace');
  @override
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
    'namespace',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaNameMeta = const VerificationMeta('areaName');
  @override
  late final GeneratedColumn<String> areaName = GeneratedColumn<String>(
    'area_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _typeNameMeta = const VerificationMeta('typeName');
  @override
  late final GeneratedColumn<String> typeName = GeneratedColumn<String>(
    'type_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _areaPicMeta = const VerificationMeta('areaPic');
  @override
  late final GeneratedColumn<String> areaPic = GeneratedColumn<String>(
    'area_pic',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shortNameMeta = const VerificationMeta('shortName');
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'short_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    platform,
    namespace,
    areaId,
    areaName,
    typeName,
    areaPic,
    shortName,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'follow_areas';
  @override
  VerificationContext validateIntegrity(Insertable<FollowAreaRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('platform')) {
      context.handle(_platformMeta, platform.isAcceptableOrUnknown(data['platform']!, _platformMeta));
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('namespace')) {
      context.handle(_namespaceMeta, namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta));
    }
    if (data.containsKey('area_id')) {
      context.handle(_areaIdMeta, areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta));
    } else if (isInserting) {
      context.missing(_areaIdMeta);
    }
    if (data.containsKey('area_name')) {
      context.handle(_areaNameMeta, areaName.isAcceptableOrUnknown(data['area_name']!, _areaNameMeta));
    }
    if (data.containsKey('type_name')) {
      context.handle(_typeNameMeta, typeName.isAcceptableOrUnknown(data['type_name']!, _typeNameMeta));
    }
    if (data.containsKey('area_pic')) {
      context.handle(_areaPicMeta, areaPic.isAcceptableOrUnknown(data['area_pic']!, _areaPicMeta));
    }
    if (data.containsKey('short_name')) {
      context.handle(_shortNameMeta, shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta, sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {platform, namespace, areaId},
  ];
  @override
  FollowAreaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FollowAreaRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      platform: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}platform'])!,
      namespace: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}namespace'])!,
      areaId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}area_id'])!,
      areaName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}area_name'])!,
      typeName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}type_name'])!,
      areaPic: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}area_pic']),
      shortName: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}short_name']),
      sortOrder: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $FollowAreasTable createAlias(String alias) {
    return $FollowAreasTable(attachedDatabase, alias);
  }
}

class FollowAreaRow extends DataClass implements Insertable<FollowAreaRow> {
  /// Internal row id.
  final int id;

  /// Lower-case platform id.
  final String platform;

  /// Area id namespace; only missevan uses one (store.md §2).
  final String namespace;

  /// Area id, trimmed.
  final String areaId;

  /// Area display name.
  final String areaName;

  /// Parent category name.
  final String typeName;

  /// Area icon URL.
  final String? areaPic;

  /// Short name.
  final String? shortName;

  /// Custom order, ascending.
  final int sortOrder;
  const FollowAreaRow({
    required this.id,
    required this.platform,
    required this.namespace,
    required this.areaId,
    required this.areaName,
    required this.typeName,
    this.areaPic,
    this.shortName,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['platform'] = Variable<String>(platform);
    map['namespace'] = Variable<String>(namespace);
    map['area_id'] = Variable<String>(areaId);
    map['area_name'] = Variable<String>(areaName);
    map['type_name'] = Variable<String>(typeName);
    if (!nullToAbsent || areaPic != null) {
      map['area_pic'] = Variable<String>(areaPic);
    }
    if (!nullToAbsent || shortName != null) {
      map['short_name'] = Variable<String>(shortName);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  FollowAreasCompanion toCompanion(bool nullToAbsent) {
    return FollowAreasCompanion(
      id: Value(id),
      platform: Value(platform),
      namespace: Value(namespace),
      areaId: Value(areaId),
      areaName: Value(areaName),
      typeName: Value(typeName),
      areaPic: areaPic == null && nullToAbsent ? const Value.absent() : Value(areaPic),
      shortName: shortName == null && nullToAbsent ? const Value.absent() : Value(shortName),
      sortOrder: Value(sortOrder),
    );
  }

  factory FollowAreaRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FollowAreaRow(
      id: serializer.fromJson<int>(json['id']),
      platform: serializer.fromJson<String>(json['platform']),
      namespace: serializer.fromJson<String>(json['namespace']),
      areaId: serializer.fromJson<String>(json['areaId']),
      areaName: serializer.fromJson<String>(json['areaName']),
      typeName: serializer.fromJson<String>(json['typeName']),
      areaPic: serializer.fromJson<String?>(json['areaPic']),
      shortName: serializer.fromJson<String?>(json['shortName']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'platform': serializer.toJson<String>(platform),
      'namespace': serializer.toJson<String>(namespace),
      'areaId': serializer.toJson<String>(areaId),
      'areaName': serializer.toJson<String>(areaName),
      'typeName': serializer.toJson<String>(typeName),
      'areaPic': serializer.toJson<String?>(areaPic),
      'shortName': serializer.toJson<String?>(shortName),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  FollowAreaRow copyWith({
    int? id,
    String? platform,
    String? namespace,
    String? areaId,
    String? areaName,
    String? typeName,
    Value<String?> areaPic = const Value.absent(),
    Value<String?> shortName = const Value.absent(),
    int? sortOrder,
  }) => FollowAreaRow(
    id: id ?? this.id,
    platform: platform ?? this.platform,
    namespace: namespace ?? this.namespace,
    areaId: areaId ?? this.areaId,
    areaName: areaName ?? this.areaName,
    typeName: typeName ?? this.typeName,
    areaPic: areaPic.present ? areaPic.value : this.areaPic,
    shortName: shortName.present ? shortName.value : this.shortName,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  FollowAreaRow copyWithCompanion(FollowAreasCompanion data) {
    return FollowAreaRow(
      id: data.id.present ? data.id.value : this.id,
      platform: data.platform.present ? data.platform.value : this.platform,
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      areaName: data.areaName.present ? data.areaName.value : this.areaName,
      typeName: data.typeName.present ? data.typeName.value : this.typeName,
      areaPic: data.areaPic.present ? data.areaPic.value : this.areaPic,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FollowAreaRow(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('namespace: $namespace, ')
          ..write('areaId: $areaId, ')
          ..write('areaName: $areaName, ')
          ..write('typeName: $typeName, ')
          ..write('areaPic: $areaPic, ')
          ..write('shortName: $shortName, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, platform, namespace, areaId, areaName, typeName, areaPic, shortName, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FollowAreaRow &&
          other.id == this.id &&
          other.platform == this.platform &&
          other.namespace == this.namespace &&
          other.areaId == this.areaId &&
          other.areaName == this.areaName &&
          other.typeName == this.typeName &&
          other.areaPic == this.areaPic &&
          other.shortName == this.shortName &&
          other.sortOrder == this.sortOrder);
}

class FollowAreasCompanion extends UpdateCompanion<FollowAreaRow> {
  final Value<int> id;
  final Value<String> platform;
  final Value<String> namespace;
  final Value<String> areaId;
  final Value<String> areaName;
  final Value<String> typeName;
  final Value<String?> areaPic;
  final Value<String?> shortName;
  final Value<int> sortOrder;
  const FollowAreasCompanion({
    this.id = const Value.absent(),
    this.platform = const Value.absent(),
    this.namespace = const Value.absent(),
    this.areaId = const Value.absent(),
    this.areaName = const Value.absent(),
    this.typeName = const Value.absent(),
    this.areaPic = const Value.absent(),
    this.shortName = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  FollowAreasCompanion.insert({
    this.id = const Value.absent(),
    required String platform,
    this.namespace = const Value.absent(),
    required String areaId,
    this.areaName = const Value.absent(),
    this.typeName = const Value.absent(),
    this.areaPic = const Value.absent(),
    this.shortName = const Value.absent(),
    required int sortOrder,
  }) : platform = Value(platform),
       areaId = Value(areaId),
       sortOrder = Value(sortOrder);
  static Insertable<FollowAreaRow> custom({
    Expression<int>? id,
    Expression<String>? platform,
    Expression<String>? namespace,
    Expression<String>? areaId,
    Expression<String>? areaName,
    Expression<String>? typeName,
    Expression<String>? areaPic,
    Expression<String>? shortName,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (platform != null) 'platform': platform,
      if (namespace != null) 'namespace': namespace,
      if (areaId != null) 'area_id': areaId,
      if (areaName != null) 'area_name': areaName,
      if (typeName != null) 'type_name': typeName,
      if (areaPic != null) 'area_pic': areaPic,
      if (shortName != null) 'short_name': shortName,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  FollowAreasCompanion copyWith({
    Value<int>? id,
    Value<String>? platform,
    Value<String>? namespace,
    Value<String>? areaId,
    Value<String>? areaName,
    Value<String>? typeName,
    Value<String?>? areaPic,
    Value<String?>? shortName,
    Value<int>? sortOrder,
  }) {
    return FollowAreasCompanion(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      namespace: namespace ?? this.namespace,
      areaId: areaId ?? this.areaId,
      areaName: areaName ?? this.areaName,
      typeName: typeName ?? this.typeName,
      areaPic: areaPic ?? this.areaPic,
      shortName: shortName ?? this.shortName,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (areaName.present) {
      map['area_name'] = Variable<String>(areaName.value);
    }
    if (typeName.present) {
      map['type_name'] = Variable<String>(typeName.value);
    }
    if (areaPic.present) {
      map['area_pic'] = Variable<String>(areaPic.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FollowAreasCompanion(')
          ..write('id: $id, ')
          ..write('platform: $platform, ')
          ..write('namespace: $namespace, ')
          ..write('areaId: $areaId, ')
          ..write('areaName: $areaName, ')
          ..write('typeName: $typeName, ')
          ..write('areaPic: $areaPic, ')
          ..write('shortName: $shortName, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameFoldedMeta = const VerificationMeta('nameFolded');
  @override
  late final GeneratedColumn<String> nameFolded = GeneratedColumn<String>(
    'name_folded',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, nameFolded, description, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(Insertable<TagRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_folded')) {
      context.handle(_nameFoldedMeta, nameFolded.isAcceptableOrUnknown(data['name_folded']!, _nameFoldedMeta));
    } else if (isInserting) {
      context.missing(_nameFoldedMeta);
    }
    if (data.containsKey('description')) {
      context.handle(_descriptionMeta, description.isAcceptableOrUnknown(data['description']!, _descriptionMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta, sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      nameFolded: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name_folded'])!,
      description: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      sortOrder: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  /// Tag id; ids from 3.x are kept.
  final String id;

  /// Display name.
  final String name;

  /// Trimmed, lower-cased name; names are unique regardless of case.
  final String nameFolded;

  /// Optional description.
  final String description;

  /// Custom order, ascending.
  final int sortOrder;
  const TagRow({
    required this.id,
    required this.name,
    required this.nameFolded,
    required this.description,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['name_folded'] = Variable<String>(nameFolded);
    map['description'] = Variable<String>(description);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      nameFolded: Value(nameFolded),
      description: Value(description),
      sortOrder: Value(sortOrder),
    );
  }

  factory TagRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameFolded: serializer.fromJson<String>(json['nameFolded']),
      description: serializer.fromJson<String>(json['description']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nameFolded': serializer.toJson<String>(nameFolded),
      'description': serializer.toJson<String>(description),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  TagRow copyWith({String? id, String? name, String? nameFolded, String? description, int? sortOrder}) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameFolded: nameFolded ?? this.nameFolded,
    description: description ?? this.description,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameFolded: data.nameFolded.present ? data.nameFolded.value : this.nameFolded,
      description: data.description.present ? data.description.value : this.description,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameFolded: $nameFolded, ')
          ..write('description: $description, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameFolded, description, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameFolded == this.nameFolded &&
          other.description == this.description &&
          other.sortOrder == this.sortOrder);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> nameFolded;
  final Value<String> description;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameFolded = const Value.absent(),
    this.description = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    required String nameFolded,
    this.description = const Value.absent(),
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       nameFolded = Value(nameFolded),
       sortOrder = Value(sortOrder);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nameFolded,
    Expression<String>? description,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameFolded != null) 'name_folded': nameFolded,
      if (description != null) 'description': description,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? nameFolded,
    Value<String>? description,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameFolded: nameFolded ?? this.nameFolded,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameFolded.present) {
      map['name_folded'] = Variable<String>(nameFolded.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameFolded: $nameFolded, ')
          ..write('description: $description, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomTagsTable extends RoomTags with TableInfo<$RoomTagsTable, RoomTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<int> room = GeneratedColumn<int>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES rooms (id) ON DELETE CASCADE'),
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES tags (id) ON DELETE CASCADE'),
  );
  @override
  List<GeneratedColumn> get $columns => [room, tag];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_tags';
  @override
  VerificationContext validateIntegrity(Insertable<RoomTagRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room')) {
      context.handle(_roomMeta, room.isAcceptableOrUnknown(data['room']!, _roomMeta));
    } else if (isInserting) {
      context.missing(_roomMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(_tagMeta, tag.isAcceptableOrUnknown(data['tag']!, _tagMeta));
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {room, tag};
  @override
  RoomTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomTagRow(
      room: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}room'])!,
      tag: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}tag'])!,
    );
  }

  @override
  $RoomTagsTable createAlias(String alias) {
    return $RoomTagsTable(attachedDatabase, alias);
  }
}

class RoomTagRow extends DataClass implements Insertable<RoomTagRow> {
  /// The tagged room.
  final int room;

  /// The tag.
  final String tag;
  const RoomTagRow({required this.room, required this.tag});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room'] = Variable<int>(room);
    map['tag'] = Variable<String>(tag);
    return map;
  }

  RoomTagsCompanion toCompanion(bool nullToAbsent) {
    return RoomTagsCompanion(room: Value(room), tag: Value(tag));
  }

  factory RoomTagRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomTagRow(room: serializer.fromJson<int>(json['room']), tag: serializer.fromJson<String>(json['tag']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'room': serializer.toJson<int>(room), 'tag': serializer.toJson<String>(tag)};
  }

  RoomTagRow copyWith({int? room, String? tag}) => RoomTagRow(room: room ?? this.room, tag: tag ?? this.tag);
  RoomTagRow copyWithCompanion(RoomTagsCompanion data) {
    return RoomTagRow(
      room: data.room.present ? data.room.value : this.room,
      tag: data.tag.present ? data.tag.value : this.tag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomTagRow(')
          ..write('room: $room, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(room, tag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RoomTagRow && other.room == this.room && other.tag == this.tag);
}

class RoomTagsCompanion extends UpdateCompanion<RoomTagRow> {
  final Value<int> room;
  final Value<String> tag;
  final Value<int> rowid;
  const RoomTagsCompanion({
    this.room = const Value.absent(),
    this.tag = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomTagsCompanion.insert({required int room, required String tag, this.rowid = const Value.absent()})
    : room = Value(room),
      tag = Value(tag);
  static Insertable<RoomTagRow> custom({Expression<int>? room, Expression<String>? tag, Expression<int>? rowid}) {
    return RawValuesInsertable({
      if (room != null) 'room': room,
      if (tag != null) 'tag': tag,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomTagsCompanion copyWith({Value<int>? room, Value<String>? tag, Value<int>? rowid}) {
    return RoomTagsCompanion(room: room ?? this.room, tag: tag ?? this.tag, rowid: rowid ?? this.rowid);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (room.present) {
      map['room'] = Variable<int>(room.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomTagsCompanion(')
          ..write('room: $room, ')
          ..write('tag: $tag, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryEntriesTable extends HistoryEntries with TableInfo<$HistoryEntriesTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<int> room = GeneratedColumn<int>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE REFERENCES rooms (id) ON DELETE CASCADE'),
  );
  static const VerificationMeta _lastWatchedAtMeta = const VerificationMeta('lastWatchedAt');
  @override
  late final GeneratedColumn<int> lastWatchedAt = GeneratedColumn<int>(
    'last_watched_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, room, lastWatchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(Insertable<HistoryRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('room')) {
      context.handle(_roomMeta, room.isAcceptableOrUnknown(data['room']!, _roomMeta));
    } else if (isInserting) {
      context.missing(_roomMeta);
    }
    if (data.containsKey('last_watched_at')) {
      context.handle(
        _lastWatchedAtMeta,
        lastWatchedAt.isAcceptableOrUnknown(data['last_watched_at']!, _lastWatchedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      room: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}room'])!,
      lastWatchedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}last_watched_at']),
    );
  }

  @override
  $HistoryEntriesTable createAlias(String alias) {
    return $HistoryEntriesTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  /// Insertion order; breaks ties and orders entries without a time.
  final int id;

  /// The watched room.
  final int room;

  /// When the room was last watched (UTC milliseconds); null for 3.x entries
  /// recorded before the field existed.
  final int? lastWatchedAt;
  const HistoryRow({required this.id, required this.room, this.lastWatchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['room'] = Variable<int>(room);
    if (!nullToAbsent || lastWatchedAt != null) {
      map['last_watched_at'] = Variable<int>(lastWatchedAt);
    }
    return map;
  }

  HistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return HistoryEntriesCompanion(
      id: Value(id),
      room: Value(room),
      lastWatchedAt: lastWatchedAt == null && nullToAbsent ? const Value.absent() : Value(lastWatchedAt),
    );
  }

  factory HistoryRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<int>(json['id']),
      room: serializer.fromJson<int>(json['room']),
      lastWatchedAt: serializer.fromJson<int?>(json['lastWatchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'room': serializer.toJson<int>(room),
      'lastWatchedAt': serializer.toJson<int?>(lastWatchedAt),
    };
  }

  HistoryRow copyWith({int? id, int? room, Value<int?> lastWatchedAt = const Value.absent()}) => HistoryRow(
    id: id ?? this.id,
    room: room ?? this.room,
    lastWatchedAt: lastWatchedAt.present ? lastWatchedAt.value : this.lastWatchedAt,
  );
  HistoryRow copyWithCompanion(HistoryEntriesCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      room: data.room.present ? data.room.value : this.room,
      lastWatchedAt: data.lastWatchedAt.present ? data.lastWatchedAt.value : this.lastWatchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('room: $room, ')
          ..write('lastWatchedAt: $lastWatchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, room, lastWatchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.id == this.id &&
          other.room == this.room &&
          other.lastWatchedAt == this.lastWatchedAt);
}

class HistoryEntriesCompanion extends UpdateCompanion<HistoryRow> {
  final Value<int> id;
  final Value<int> room;
  final Value<int?> lastWatchedAt;
  const HistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.room = const Value.absent(),
    this.lastWatchedAt = const Value.absent(),
  });
  HistoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int room,
    this.lastWatchedAt = const Value.absent(),
  }) : room = Value(room);
  static Insertable<HistoryRow> custom({Expression<int>? id, Expression<int>? room, Expression<int>? lastWatchedAt}) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (room != null) 'room': room,
      if (lastWatchedAt != null) 'last_watched_at': lastWatchedAt,
    });
  }

  HistoryEntriesCompanion copyWith({Value<int>? id, Value<int>? room, Value<int?>? lastWatchedAt}) {
    return HistoryEntriesCompanion(
      id: id ?? this.id,
      room: room ?? this.room,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (room.present) {
      map['room'] = Variable<int>(room.value);
    }
    if (lastWatchedAt.present) {
      map['last_watched_at'] = Variable<int>(lastWatchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('room: $room, ')
          ..write('lastWatchedAt: $lastWatchedAt')
          ..write(')'))
        .toString();
  }
}

class $BlockRulesTable extends BlockRules with TableInfo<$BlockRulesTable, BlockRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueFoldedMeta = const VerificationMeta('valueFolded');
  @override
  late final GeneratedColumn<String> valueFolded = GeneratedColumn<String>(
    'value_folded',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, kind, value, valueFolded, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'block_rules';
  @override
  VerificationContext validateIntegrity(Insertable<BlockRuleRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(_kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('value_folded')) {
      context.handle(_valueFoldedMeta, valueFolded.isAcceptableOrUnknown(data['value_folded']!, _valueFoldedMeta));
    } else if (isInserting) {
      context.missing(_valueFoldedMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {kind, valueFolded},
  ];
  @override
  BlockRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockRuleRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      kind: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      valueFolded: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value_folded'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BlockRulesTable createAlias(String alias) {
    return $BlockRulesTable(attachedDatabase, alias);
  }
}

class BlockRuleRow extends DataClass implements Insertable<BlockRuleRow> {
  /// Internal row id.
  final int id;

  /// `keyword` or `user`.
  final String kind;

  /// The value as the user typed it (trimmed).
  final String value;

  /// Trimmed, lower-cased value used for matching and uniqueness.
  final String valueFolded;

  /// When the rule was added (UTC milliseconds).
  final int createdAt;
  const BlockRuleRow({
    required this.id,
    required this.kind,
    required this.value,
    required this.valueFolded,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['value'] = Variable<String>(value);
    map['value_folded'] = Variable<String>(valueFolded);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BlockRulesCompanion toCompanion(bool nullToAbsent) {
    return BlockRulesCompanion(
      id: Value(id),
      kind: Value(kind),
      value: Value(value),
      valueFolded: Value(valueFolded),
      createdAt: Value(createdAt),
    );
  }

  factory BlockRuleRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockRuleRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      value: serializer.fromJson<String>(json['value']),
      valueFolded: serializer.fromJson<String>(json['valueFolded']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'value': serializer.toJson<String>(value),
      'valueFolded': serializer.toJson<String>(valueFolded),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BlockRuleRow copyWith({int? id, String? kind, String? value, String? valueFolded, int? createdAt}) => BlockRuleRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    value: value ?? this.value,
    valueFolded: valueFolded ?? this.valueFolded,
    createdAt: createdAt ?? this.createdAt,
  );
  BlockRuleRow copyWithCompanion(BlockRulesCompanion data) {
    return BlockRuleRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      value: data.value.present ? data.value.value : this.value,
      valueFolded: data.valueFolded.present ? data.valueFolded.value : this.valueFolded,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockRuleRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('value: $value, ')
          ..write('valueFolded: $valueFolded, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, value, valueFolded, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockRuleRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.value == this.value &&
          other.valueFolded == this.valueFolded &&
          other.createdAt == this.createdAt);
}

class BlockRulesCompanion extends UpdateCompanion<BlockRuleRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> value;
  final Value<String> valueFolded;
  final Value<int> createdAt;
  const BlockRulesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.value = const Value.absent(),
    this.valueFolded = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BlockRulesCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String value,
    required String valueFolded,
    required int createdAt,
  }) : kind = Value(kind),
       value = Value(value),
       valueFolded = Value(valueFolded),
       createdAt = Value(createdAt);
  static Insertable<BlockRuleRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? value,
    Expression<String>? valueFolded,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (value != null) 'value': value,
      if (valueFolded != null) 'value_folded': valueFolded,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BlockRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? value,
    Value<String>? valueFolded,
    Value<int>? createdAt,
  }) {
    return BlockRulesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      value: value ?? this.value,
      valueFolded: valueFolded ?? this.valueFolded,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (valueFolded.present) {
      map['value_folded'] = Variable<String>(valueFolded.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockRulesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('value: $value, ')
          ..write('valueFolded: $valueFolded, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $RoomPrefsTable extends RoomPrefs with TableInfo<$RoomPrefsTable, RoomPrefRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomPrefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomMeta = const VerificationMeta('room');
  @override
  late final GeneratedColumn<int> room = GeneratedColumn<int>(
    'room',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES rooms (id) ON DELETE CASCADE'),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [room, key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_prefs';
  @override
  VerificationContext validateIntegrity(Insertable<RoomPrefRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room')) {
      context.handle(_roomMeta, room.isAcceptableOrUnknown(data['room']!, _roomMeta));
    } else if (isInserting) {
      context.missing(_roomMeta);
    }
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {room, key};
  @override
  RoomPrefRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomPrefRow(
      room: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}room'])!,
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $RoomPrefsTable createAlias(String alias) {
    return $RoomPrefsTable(attachedDatabase, alias);
  }
}

class RoomPrefRow extends DataClass implements Insertable<RoomPrefRow> {
  /// The room.
  final int room;

  /// Preference key, for example `volume`.
  final String key;

  /// JSON value.
  final String value;
  const RoomPrefRow({required this.room, required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room'] = Variable<int>(room);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  RoomPrefsCompanion toCompanion(bool nullToAbsent) {
    return RoomPrefsCompanion(room: Value(room), key: Value(key), value: Value(value));
  }

  factory RoomPrefRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomPrefRow(
      room: serializer.fromJson<int>(json['room']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'room': serializer.toJson<int>(room),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  RoomPrefRow copyWith({int? room, String? key, String? value}) =>
      RoomPrefRow(room: room ?? this.room, key: key ?? this.key, value: value ?? this.value);
  RoomPrefRow copyWithCompanion(RoomPrefsCompanion data) {
    return RoomPrefRow(
      room: data.room.present ? data.room.value : this.room,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomPrefRow(')
          ..write('room: $room, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(room, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomPrefRow && other.room == this.room && other.key == this.key && other.value == this.value);
}

class RoomPrefsCompanion extends UpdateCompanion<RoomPrefRow> {
  final Value<int> room;
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const RoomPrefsCompanion({
    this.room = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomPrefsCompanion.insert({
    required int room,
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : room = Value(room),
       key = Value(key),
       value = Value(value);
  static Insertable<RoomPrefRow> custom({
    Expression<int>? room,
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (room != null) 'room': room,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomPrefsCompanion copyWith({Value<int>? room, Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return RoomPrefsCompanion(
      room: room ?? this.room,
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (room.present) {
      map['room'] = Variable<int>(room.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomPrefsCompanion(')
          ..write('room: $room, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingEntriesTable extends SettingEntries with TableInfo<$SettingEntriesTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<SettingRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta, updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SettingEntriesTable createAlias(String alias) {
    return $SettingEntriesTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  /// Registry id, for example `danmaku.speed`.
  final String key;

  /// JSON value.
  final String value;

  /// When the value last changed (UTC milliseconds).
  final int updatedAt;
  const SettingRow({required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SettingEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingEntriesCompanion(key: Value(key), value: Value(value), updatedAt: Value(updatedAt));
  }

  factory SettingRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SettingRow copyWith({String? key, String? value, int? updatedAt}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value, updatedAt: updatedAt ?? this.updatedAt);
  SettingRow copyWithCompanion(SettingEntriesCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow && other.key == this.key && other.value == this.value && other.updatedAt == this.updatedAt);
}

class SettingEntriesCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SettingEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingEntriesCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MetaEntriesTable extends MetaEntries with TableInfo<$MetaEntriesTable, MetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(Insertable<MetaRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRow(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $MetaEntriesTable createAlias(String alias) {
    return $MetaEntriesTable(attachedDatabase, alias);
  }
}

class MetaRow extends DataClass implements Insertable<MetaRow> {
  /// Entry key.
  final String key;

  /// Entry value.
  final String value;
  const MetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaEntriesCompanion toCompanion(bool nullToAbsent) {
    return MetaEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory MetaRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRow(key: serializer.fromJson<String>(json['key']), value: serializer.fromJson<String>(json['value']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'key': serializer.toJson<String>(key), 'value': serializer.toJson<String>(value)};
  }

  MetaRow copyWith({String? key, String? value}) => MetaRow(key: key ?? this.key, value: value ?? this.value);
  MetaRow copyWithCompanion(MetaEntriesCompanion data) {
    return MetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MetaRow && other.key == this.key && other.value == this.value);
}

class MetaEntriesCompanion extends UpdateCompanion<MetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaEntriesCompanion.insert({required String key, required String value, this.rowid = const Value.absent()})
    : key = Value(key),
      value = Value(value);
  static Insertable<MetaRow> custom({Expression<String>? key, Expression<String>? value, Expression<int>? rowid}) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaEntriesCompanion copyWith({Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return MetaEntriesCompanion(key: key ?? this.key, value: value ?? this.value, rowid: rowid ?? this.rowid);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$StoreDatabase extends GeneratedDatabase {
  _$StoreDatabase(QueryExecutor e) : super(e);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $FollowsTable follows = $FollowsTable(this);
  late final $FollowAreasTable followAreas = $FollowAreasTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $RoomTagsTable roomTags = $RoomTagsTable(this);
  late final $HistoryEntriesTable historyEntries = $HistoryEntriesTable(this);
  late final $BlockRulesTable blockRules = $BlockRulesTable(this);
  late final $RoomPrefsTable roomPrefs = $RoomPrefsTable(this);
  late final $SettingEntriesTable settingEntries = $SettingEntriesTable(this);
  late final $MetaEntriesTable metaEntries = $MetaEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    rooms,
    follows,
    followAreas,
    tags,
    roomTags,
    historyEntries,
    blockRules,
    roomPrefs,
    settingEntries,
    metaEntries,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName('rooms', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('follows', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('rooms', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('room_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('tags', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('room_tags', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('rooms', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('history', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('rooms', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('room_prefs', kind: UpdateKind.delete)],
    ),
  ]);
}
