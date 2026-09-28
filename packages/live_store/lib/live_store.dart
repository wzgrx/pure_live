/// Storage of Pure Live v4 (spec/modules/store.md, ADR 0004): the drift
/// database with typed stores, the settings registry, encrypted secrets,
/// backups and share codes. Pure Dart.
library;

export 'src/backup/backup_service.dart' show BackupService, RestoreMode;
export 'src/backup/import_plan.dart' show ImportPlan;
export 'src/backup/import_report.dart' show ImportCount, ImportIssue, ImportReport;
export 'src/backup/record_tasks.dart' show BackupRecordTask, RecordTaskBackup;
export 'src/backup/secret_envelope.dart' show WrongPassphraseException;
export 'src/backup/v4_format.dart' show BackupScope, BackupTooNewException;
export 'src/block_rules.dart' show BlockKind, BlockRule, BlockRuleStore;
export 'src/follow_areas.dart' show FollowAreaStore, FollowedArea;
export 'src/follows.dart' show FollowSource, FollowStore, FollowedRoom;
export 'src/history.dart' show HistoryEntry, HistoryStore;
export 'src/iptv.dart'
    show
        IptvEntryRecord,
        IptvGuideChannelRecord,
        IptvGuideSourceRecord,
        IptvPlaylistRecord,
        IptvProgrammeRecord,
        IptvSourceRecord,
        IptvStore,
        isRemoteSource;
export 'src/live_store.dart' show LiveStore;
export 'src/meta_store.dart' show MetaStore;
export 'src/room_prefs.dart' show PortraitOverride, RoomPrefStore;
export 'src/room_store.dart' show RoomStore;
export 'src/rooms.dart' show RoomSnapshot, StoredRoom;
export 'src/search_history.dart' show SearchHistoryEntry, SearchHistoryStore;
export 'src/secrets/secret_cipher.dart' show AesGcmSecretCipher, SecretCipher;
export 'src/secrets/secret_store.dart'
    show FileSecretBackend, MemorySecretBackend, SecretBackend, SecretRefs, SecretStore;
export 'src/settings/registry.dart' show Settings;
export 'src/settings/setting.dart'
    show
        BoolSetting,
        DoubleSetting,
        EnumSetting,
        IntSetting,
        LegacyConvert,
        LegacyKey,
        Setting,
        SettingScope,
        StringListSetting,
        StringSetting;
export 'src/settings/settings_store.dart' show SettingsStore;
export 'src/settings/values.dart';
export 'src/share_code.dart' show ShareCode;
export 'src/store_log.dart' show StoreLog;
export 'src/tags.dart' show Tag, TagNameException, TagStore;
