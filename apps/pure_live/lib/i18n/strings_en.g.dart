///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class TranslationsEn with BaseTranslations<AppLocale, Translations> implements Translations {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsEn({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.en,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <en>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsEn _root = this; // ignore: unused_field

  @override
  TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) =>
      TranslationsEn(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$about$en about = _Translations$about$en._(_root);
  @override
  late final _Translations$accounts$en accounts = _Translations$accounts$en._(_root);
  @override
  late final _Translations$alerts$en alerts = _Translations$alerts$en._(_root);
  @override
  late final _Translations$app$en app = _Translations$app$en._(_root);
  @override
  late final _Translations$audience$en audience = _Translations$audience$en._(_root);
  @override
  late final _Translations$backup$en backup = _Translations$backup$en._(_root);
  @override
  late final _Translations$cast$en cast = _Translations$cast$en._(_root);
  @override
  late final _Translations$common$en common = _Translations$common$en._(_root);
  @override
  late final _Translations$danmaku$en danmaku = _Translations$danmaku$en._(_root);
  @override
  late final _Translations$diagnostics$en diagnostics = _Translations$diagnostics$en._(_root);
  @override
  late final _Translations$discover$en discover = _Translations$discover$en._(_root);
  @override
  late final _Translations$errors$en errors = _Translations$errors$en._(_root);
  @override
  late final _Translations$follows$en follows = _Translations$follows$en._(_root);
  @override
  late final _Translations$fonts$en fonts = _Translations$fonts$en._(_root);
  @override
  late final _Translations$health$en health = _Translations$health$en._(_root);
  @override
  late final _Translations$iptv$en iptv = _Translations$iptv$en._(_root);
  @override
  late final _Translations$me$en me = _Translations$me$en._(_root);
  @override
  late final _Translations$multiview$en multiview = _Translations$multiview$en._(_root);
  @override
  late final _Translations$onboarding$en onboarding = _Translations$onboarding$en._(_root);
  @override
  late final _Translations$quality$en quality = _Translations$quality$en._(_root);
  @override
  late final _Translations$recording$en recording = _Translations$recording$en._(_root);
  @override
  late final _Translations$room$en room = _Translations$room$en._(_root);
  @override
  late final _Translations$rooms$en rooms = _Translations$rooms$en._(_root);
  @override
  late final _Translations$search$en search = _Translations$search$en._(_root);
  @override
  late final _Translations$settings$en settings = _Translations$settings$en._(_root);
  @override
  late final _Translations$share$en share = _Translations$share$en._(_root);
  @override
  late final _Translations$sites$en sites = _Translations$sites$en._(_root);
  @override
  late final _Translations$sync$en sync = _Translations$sync$en._(_root);
  @override
  late final _Translations$system$en system = _Translations$system$en._(_root);
  @override
  late final _Translations$tv$en tv = _Translations$tv$en._(_root);
  @override
  late final _Translations$ui$en ui = _Translations$ui$en._(_root);
  @override
  late final _Translations$web$en web = _Translations$web$en._(_root);
}

// Path: about
class _Translations$about$en implements Translations$about$zh_Hans {
  _Translations$about$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get versionAndUpdates => 'Version and updates';
  @override
  String get versionSubtitle => 'Release notes and downloads';
  @override
  String newVersion({required Object version}) => 'New version ${version}';
  @override
  String get platformStatus => 'Platform status';
  @override
  String get platformStatusSubtitle => 'Check whether each platform is reachable now';
  @override
  String get projectPage => 'Project page';
  @override
  String get feedback => 'Report a problem';
  @override
  String get feedbackSubtitle =>
      'Attach the diagnostics bundle from Settings › Data and sync › Diagnostics and logs when you report a problem';
  @override
  String get releases => 'Releases';
  @override
  String get licenses => 'Open-source licences';
  @override
  String get licensesSubtitle => 'This app is released under AGPL-3.0; the licences of its components are listed here';
  @override
  String get privacy => 'Privacy';
  @override
  String get privacyBody =>
      'Pure Live collects and sends no data. Platform cookies and passwords are stored encrypted on this device and are left out of backups by default; LAN sync needs a pairing code and the receiver\'s confirmation; crash reports are off by default, and when on they only offer to export a diagnostics bundle on this device.';
  @override
  String get trademarks => 'Trademarks';
  @override
  String get trademarksBody =>
      'Platform names and logos belong to their owners and only show where content comes from.';
  @override
  String get pickInstaller => 'Choose the downloaded installer';
  @override
  String verifyMatch({required Object file, required Object asset}) => 'Verified: ${file} matches ${asset} exactly.';
  @override
  String verifyMismatch({required Object file}) =>
      'Verification failed: the SHA-256 of ${file} differs from the one on the release page. Download it again and do not install it.';
  @override
  String verifyNoHashes({required Object hash}) =>
      'This release publishes no SHA-256, so it cannot be verified. The file\'s SHA-256 is ${hash}';
  @override
  String verifyUnknown({required Object file, required Object hash}) =>
      'No matching file: the SHA-256 of ${file} is ${hash}, which matches no file of this release.';
  @override
  String readFileFailed({required Object message}) => 'Could not read the file: ${message}';
  @override
  String currentVersion({required Object version}) => 'Current version ${version}';
  @override
  String get channelPreview => 'Preview: update checks include previews';
  @override
  String get channelStable => 'Stable: update checks include stable releases only';
  @override
  String get checkForUpdates => 'Check for updates';
  @override
  String get openReleasePage => 'Open release page';
  @override
  String get upToDate => 'You are up to date';
  @override
  String get olderReleases => 'Earlier releases';
  @override
  String get noNotes => '(No release notes)';
  @override
  String get preview => 'Preview';
  @override
  String newRelease({required Object version}) => 'New version ${version}';
  @override
  String get releasePage => 'Release page';
  @override
  String get recommendedDownloads => 'Downloads for this device';
  @override
  String get otherDownloads => 'Other platforms and files';
  @override
  String get calculating => 'Calculating…';
  @override
  String get verifyDownload => 'Verify a downloaded file';
  @override
  String get androidPreviewNote =>
      'The Android preview\'s package name ends in .next, so it installs alongside 3.x; open the downloaded file to install over an earlier preview.';
  @override
  String get releaseNotes => 'Release notes';
  @override
  String get androidUniversal => 'Android · Universal';
  @override
  String get windowsSetup => 'Windows · Installer';
  @override
  String get windowsPortable => 'Windows · Portable';
  @override
  String get checksums => 'Checksums';
  @override
  String get otherFile => 'Other file';
  @override
  String get downloadLinkCopied => 'Download link copied';
  @override
  String get hashCopied => 'SHA-256 copied';
  @override
  String get copyDownloadLink => 'Copy download link';
  @override
  String get copyHash => 'Copy SHA-256';
  @override
  String get errorRateLimited => 'GitHub is limiting update checks. Try again later.';
  @override
  String get errorNetwork => 'Cannot reach GitHub. Check your network or proxy.';
  @override
  String errorServer({required Object detail}) => 'Update check failed (${detail})';
  @override
  String get unknownError => 'unknown error';
  @override
  String newPreviewVersion({required Object version}) => 'New preview version ${version}';
  @override
  String get view => 'View';
}

// Path: accounts
class _Translations$accounts$en implements Translations$accounts$zh_Hans {
  _Translations$accounts$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get sessionExpired => 'Your sign-in has expired. Sign in again.';
  @override
  String get signedOut => 'Not signed in';
  @override
  String get guestCookie => 'A cookie is saved, but it has no sign-in';
  @override
  String get validUnknown => 'Signed in · expiry unknown';
  @override
  String validUntil({required Object end}) => 'Signed in · valid until ${end}';
  @override
  String validUntilRenewable({required Object end}) => 'Signed in · valid until ${end}, renewable before then';
  @override
  String expiredRenewable({required Object end}) => 'Expired on ${end}; it can be renewed';
  @override
  String get expired => 'Expired. Sign in again.';
  @override
  String signedInAs({required Object name}) => 'Signed in · ${name}';
  @override
  String signedInAsWithUid({required Object name, required Object uid}) => 'Signed in · ${name} (UID ${uid})';
  @override
  String get verifying => 'Signed in · verifying';
  @override
  String get cookieExpired => 'The cookie has expired. Sign in again.';
  @override
  String verifyFailed({required Object reason}) => 'Signed in · verification failed: ${reason}';
  @override
  String get cookieSaved => 'Cookie saved';
  @override
  String signedInUid({required Object uid}) => 'Signed in · UID ${uid}';
  @override
  String get storageNote =>
      'Sign-in data is encrypted with this device\'s system key, never uploaded, and left out of backups by default.';
  @override
  String qrFetchFailed({required Object reason}) => 'Could not get the QR code: ${reason}';
  @override
  String qrPollFailed({required Object reason}) => 'Could not check the scan: ${reason}';
  @override
  String get qrVerifyRejected => 'The sign-in did not verify. Refresh the QR code and scan again.';
  @override
  String qrVerifyFailed({required Object reason}) => 'Sign-in verification failed: ${reason}';
  @override
  String get qrLoading => 'Getting the QR code';
  @override
  String get qrWaiting => 'Scan the QR code with the Bilibili mobile app';
  @override
  String get qrScanned => 'Scanned. Confirm the sign-in on your phone.';
  @override
  String get qrExpired => 'The QR code has expired';
  @override
  String get verifyingSignIn => 'Verifying sign-in';
  @override
  String signedInName({required Object name}) => 'Signed in: ${name}';
  @override
  String get signInFailed => 'Sign-in failed';
  @override
  String get qrLabel => 'Bilibili sign-in QR code';
  @override
  String get qrRefresh => 'Refresh QR code';
  @override
  late final _Translations$accounts$cookieTip$en cookieTip = _Translations$accounts$cookieTip$en._(_root);
  @override
  String get pasteCookieFirst => 'Paste a cookie first';
  @override
  String get cookieSavedRejoin => 'Saved. It applies when you reopen the room.';
  @override
  String get saveFailed => 'Could not save. Try again.';
  @override
  String get cookieHidden => 'The saved cookie is not shown; pasting a new one replaces it';
  @override
  String get ltp0Label => 'LTP0 (for renewal)';
  @override
  String get keptIfEmpty => 'Saved; leave empty to keep it';
  @override
  String get didLabel => 'dy_did (device ID)';
  @override
  String get nothingToSave => 'Nothing to save';
  @override
  String get douyuKeysSaved => 'Saved LTP0 and dy_did for renewal';
  @override
  String get passportKept => 'This is a passport cookie: LTP0 and dy_did are saved and the current sign-in is kept';
  @override
  String get passportNeedsLogin =>
      'This is a passport cookie: LTP0 and dy_did are saved. Paste the cookie of a www.douyu.com page too to sign in.';
  @override
  String get noLoginKept => 'The pasted cookie has no sign-in; the current sign-in is kept';
  @override
  String savedWith({required Object summary}) => 'Saved. ${summary}';
  @override
  String get noDouyuCookie => 'No Douyu cookie saved yet';
  @override
  String get renewMissingKeys => 'LTP0 or dy_did is missing, so it cannot be renewed';
  @override
  String get renewNoLogin => 'The cookie has no sign-in, so it cannot be renewed';
  @override
  String get renewNoResult => 'Douyu returned no new sign-in; nothing was renewed';
  @override
  String get renewed => 'Renewed';
  @override
  String renewedUntil({required Object end}) => 'Renewed; now valid until ${end}';
  @override
  String renewFailed({required Object reason}) => 'Renewal failed: ${reason}';
  @override
  String signOutTitle({required Object name}) => 'Sign out of ${name}?';
  @override
  String get signOutBody => 'The sign-in saved on this device will be deleted.';
  @override
  String get signOutBodyBrowser =>
      'The sign-in saved on this device will be deleted, and the built-in browser will be signed out.';
  @override
  String get signOut => 'Sign out';
  @override
  String get signedOutToast => 'Signed out';
  @override
  String accountTitle({required Object name}) => '${name} account';
  @override
  String get verify => 'Verify';
  @override
  String get renewNow => 'Renew now';
  @override
  String get signOutAction => 'Sign out';
  @override
  String get switchAccount => 'Sign in with another account';
  @override
  String get signIn => 'Sign in';
  @override
  String get signedInToast => 'Signed in';
  @override
  String get qrSignIn => 'Sign in with a QR code';
  @override
  String get qrSignInSubtitle => 'Scan with the Bilibili mobile app';
  @override
  String get webSignIn => 'Sign in on the web';
  @override
  String get webSignInSubtitle => 'Sign in with a password or text message in the built-in browser';
  @override
  String get manualCookie => 'Enter a cookie manually';
  @override
  String get replaceCookie => 'Replace cookie';
  @override
  String get enterCookie => 'Enter cookie';
  @override
  String get storageNoteFull =>
      'Sign-in data is encrypted with this device\'s system key, never uploaded and never shown in the app or logs; it is left out of backups by default.';
  @override
  String get webReadFailed => 'Could not read the sign-in. Sign in again.';
  @override
  String get webNoCookie => 'No sign-in was found. Sign in again.';
  @override
  String get webRejected => 'The sign-in did not verify. Sign in again.';
  @override
  String webTitle({required Object name}) => 'Web sign-in · ${name}';
  @override
  String get webUnavailable => 'Web sign-in is not available here';
  @override
  String get webUnavailableHint => 'Sign in with a QR code or enter a cookie instead.';
  @override
  String get reload => 'Reload';
}

// Path: alerts
class _Translations$alerts$en implements Translations$alerts$zh_Hans {
  _Translations$alerts$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get notificationsDenied =>
      'Notifications are not allowed, so live alerts stay off. Allow notifications for this app in system settings and turn them on again.';
  @override
  String get liveAlerts => 'Live alerts';
  @override
  String get liveAlertsSubtitle =>
      'Get a notification when a followed streamer goes live. Checks run at the refresh interval while the app is in the background; turn them off for single streamers on the Following page.';
  @override
  String get notificationsUnsupported => 'This system does not support notifications';
  @override
  String get enableAlertsFirst => 'Turn on live alerts in Settings › General first';
  @override
  String get roomAlertOff => 'No alert when this streamer goes live';
  @override
  String get roomAlertOn => 'Notify when live';
  @override
  String get reminderSet => 'Reminder set';
  @override
  String get remindMe => 'Remind me';
  @override
  String get cannotRemind => 'Cannot set a reminder';
  @override
  String get reminderDenied =>
      'Notifications are not allowed. Allow notifications for this app in system settings, then set programme reminders.';
  @override
  String wentLive({required Object name}) => '${name} is live';
  @override
  String manyWentLive({required Object n, required Object first}) => '${n} streamers are live, including ${first}';
  @override
  String namesAndMore({required Object names}) => '${names} and more';
  @override
  String get liveChannelDescription => 'Alerts when followed streamers go live';
  @override
  String get programmeReminders => 'Programme reminders';
  @override
  String get programmeChannelDescription => 'Reminders one minute before an IPTV programme starts';
  @override
  String programmeStarting({required Object title}) => '${title} starts soon';
  @override
  String programmeBody({required Object channel, required Object time}) => '${channel} · starts at ${time}';
}

// Path: app
class _Translations$app$en implements Translations$app$zh_Hans {
  _Translations$app$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get name => 'Pure Live';
  @override
  String get previewName => 'Pure Live Preview';
  @override
  late final _Translations$app$tabs$en tabs = _Translations$app$tabs$en._(_root);
  @override
  String get expandNavigation => 'Expand navigation';
  @override
  String get collapseNavigation => 'Collapse navigation';
  @override
  String get history => 'Watch history';
  @override
  String get recordings => 'Recordings';
  @override
  String get multiview => 'Multi-view';
  @override
  String get accounts => 'Platform accounts';
  @override
  String get backup => 'Backup and sync';
  @override
  String get settings => 'Settings';
  @override
  String get about => 'About';
  @override
  String get comingSoon => 'Not available in the preview yet';
  @override
  String get appearance => 'Appearance';
  @override
  String get themeSystem => 'Follow system';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get themeBlack => 'Pure black';
  @override
  String get version => 'Version';
  @override
  String get previewNotice => 'This is the v4 preview. It installs alongside 3.x.';
  @override
  String get offlineBanner => 'You are offline. Lists and playback reload when the connection is back.';
}

// Path: audience
class _Translations$audience$en implements Translations$audience$zh_Hans {
  _Translations$audience$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  Map<String, String> get notes => {
    'bilibili': 'Lists and the chat heartbeat report popularity, and total views of the stream are separate; neither is concurrent viewers',
    'douyu': 'Figures in public lists are heat, not real viewer counts',
    'huya': 'Figures in lists, details and the room all measure heat; there is no separate viewer count',
    'douyin': 'Viewers come from the room data; total views are separate',
    'kuaishou': 'Current viewers',
    'cc': 'Heat and viewers are separate: heat from webcc, viewers from vision',
    'yy': 'Public figures show the platform\'s heat; there is no separate viewer count',
    'soop': 'Total viewers on PC and mobile',
    'acfun': 'Viewers; likes and followers are separate',
    'twitch': 'Current concurrent viewers',
    'iptv': 'IPTV has no viewer counts',
  };
}

// Path: backup
class _Translations$backup$en implements Translations$backup$zh_Hans {
  _Translations$backup$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get exportTitle => 'Export backup';
  @override
  String passphraseTooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'The passphrase needs at least ${n} character',
    other: 'The passphrase needs at least ${n} characters',
  );
  @override
  String get passphraseMismatch => 'The passphrases do not match';
  @override
  String get scopeFull => 'Full backup';
  @override
  String get scopeFollows => 'Follows only';
  @override
  String get scopeFullDetail => 'Follows, groups, history, blocked words, room preferences and settings';
  @override
  String get scopeFollowsDetail => 'Only followed rooms and followed categories';
  @override
  String get includeAccounts => 'Include platform sign-ins';
  @override
  String get includeAccountsDetail =>
      'Cookies and WebDAV passwords are encrypted with a passphrase; enter the same passphrase to import them';
  @override
  String get passphrase => 'Passphrase';
  @override
  String get passphraseRepeat => 'Enter it again';
  @override
  String get passphraseRemember => 'Remember this passphrase. Without it the account data cannot be restored.';
  @override
  String get pickBackupFile => 'Choose a backup file';
  @override
  String get saveBackup => 'Save backup';
  @override
  String get errorTooNew => 'This backup comes from a newer version. Update the app first.';
  @override
  String get errorFollowsOnly => 'This backup has follows only. Use "Restore follows only".';
  @override
  String get errorUnknownFile => 'This is not a backup file the app recognises';
  @override
  String get errorBusy => 'Another restore is running. Try again later.';
  @override
  String get confirmImport => 'Confirm import';
  @override
  String get wrongPassphrase => 'Wrong passphrase';
  @override
  String get skipAccountsQuestion => 'Platform sign-ins will not be imported. Import everything else?';
  @override
  String get continueImport => 'Continue import';
  @override
  String get importDone => 'Import complete';
  @override
  String get restoreFull => 'Full restore';
  @override
  String get restoreFollows => 'Restore follows only';
  @override
  String get restoreFullDetail => 'Parts in the backup replace the same data on this device; everything else stays.';
  @override
  String get restoreFollowsDetail => 'Only followed rooms and followed categories are replaced; other data stays.';
  @override
  String get encryptedAccountsHint =>
      'The backup has encrypted platform sign-ins. Enter the passphrase set at export to import them too, or leave it empty to skip them.';
  @override
  String get passphraseOptional => 'Passphrase (optional)';
  @override
  String get plainAccountsHint =>
      'The backup has platform sign-ins; they are imported too and stored encrypted on this device.';
  @override
  late final _Translations$backup$section$en section = _Translations$backup$section$en._(_root);
  @override
  String format({required Object format}) => 'Backup format: ${format}';
  @override
  String get nothingToImport => 'The file has nothing to import';
  @override
  String get accountsSkipped => 'Platform sign-ins were not imported this time.';
  @override
  String readCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} item read',
    other: '${n} items read',
  );
  @override
  String writtenCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} item written',
    other: '${n} items written',
  );
  @override
  String skippedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, other: ', ${n} skipped');
  @override
  String sectionLine({required Object section, required Object counts}) => '${section}: ${counts}';
  @override
  String get saved => 'Backup saved';
  @override
  String get localFiles => 'Local files';
  @override
  String get exportSubtitle =>
      'Full or follows only; platform sign-ins are left out unless you add them with a passphrase';
  @override
  String get restoreFollowsSubtitle => 'Works with v4 and 3.x backups; imports only follows and followed categories';
  @override
  String get restoreFullSubtitle => 'Imports everything in the backup; what it lacks stays unchanged';
  @override
  String get webdavSubtitle =>
      'Upload backups to Jianguoyun, Nextcloud, Synology or other WebDAV drives and restore them on other devices';
  @override
  String get lanSync => 'LAN sync';
  @override
  String get lanSyncSubtitle =>
      'Transfer directly between two devices on the same network; nothing is imported until the receiver confirms';
  @override
  String get backupAndRestore => 'Backup and restore';
  @override
  String get backupAndRestoreSubtitle => 'Export or import backup files, including 3.x backups';
  @override
  String get diagnostics => 'Diagnostics and logs';
  @override
  String get diagnosticsSubtitle => 'Export a diagnostics bundle and view recent logs';
  @override
  String get crashReports => 'Crash reports';
  @override
  String get crashReportsSubtitle =>
      'After a crash, offer to export a diagnostics bundle at the next start; nothing is uploaded';
  @override
  String get clipboardRooms => 'Detect rooms on the clipboard';
  @override
  String get clipboardRoomsSubtitle =>
      'When you return to the app, recognise a copied share code or room link and offer to open it';
  @override
  String get okay => 'OK';
}

// Path: cast
class _Translations$cast$en implements Translations$cast$zh_Hans {
  _Translations$cast$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get noAddressYet => 'No stream address yet. Cast once the video is playing.';
  @override
  String get notHttp => 'The current line is not an http(s) address, so the TV cannot open it';
  @override
  String get invalidAddress => 'The current line\'s address is invalid';
  @override
  String get localAddress => 'The current line is a local address the TV cannot reach';
  @override
  String get defaultTitle => 'Live stream';
  @override
  late final _Translations$cast$failure$en failure = _Translations$cast$failure$en._(_root);
  @override
  late final _Translations$cast$tv$en tv = _Translations$cast$tv$en._(_root);
  @override
  String get stopNotDelivered => 'The stop command did not arrive; the TV may still be playing';
  @override
  String get title => 'Cast';
  @override
  String get searchAgain => 'Search again';
  @override
  String get cannotCast => 'This address cannot be cast';
  @override
  String get headersHint => 'This platform\'s streams may need special request headers; the TV might not play them';
  @override
  String get expiresHint => 'Stream addresses expire. When the TV stops, cast again.';
  @override
  String failedWith({required Object reason}) => 'Cast failed: ${reason}';
  @override
  String get searching => 'Searching for TVs and boxes on this Wi-Fi…';
  @override
  String get searchInterrupted => 'Search interrupted; the list may be incomplete';
  @override
  String get searchFailed => 'Search failed';
  @override
  String get searchFailedHint => 'Check that your phone is on Wi-Fi, then try again';
  @override
  String get noDevices => 'No devices found';
  @override
  String get noDevicesHint =>
      'Make sure the TV or box is on, has casting (DLNA) enabled and is on the same Wi-Fi as your phone';
  @override
  String get castingThisRoom => 'Casting this room';
  @override
  String castingOther({required Object title}) => 'Casting: ${title}';
  @override
  String castTo({required Object device}) => 'Cast to ${device}';
  @override
  String get stop => 'Stop casting';
}

// Path: common
class _Translations$common$en implements Translations$common$zh_Hans {
  _Translations$common$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get retry => 'Retry';
  @override
  String get ok => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get delete => 'Delete';
  @override
  String get remove => 'Remove';
  @override
  String get undo => 'Undo';
  @override
  String get close => 'Close';
  @override
  String get refresh => 'Refresh';
  @override
  String get more => 'More';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get add => 'Add';
  @override
  String get edit => 'Edit';
  @override
  String get rename => 'Rename';
  @override
  String get import => 'Import';
  @override
  String get export => 'Export';
  @override
  String get send => 'Send';
  @override
  String get start => 'Start';
  @override
  String get stop => 'Stop';
  @override
  String get play => 'Play';
  @override
  String get pause => 'Pause';
  @override
  String get resume => 'Resume';
  @override
  String get back => 'Back';
  @override
  String get gotIt => 'Got it';
  @override
  String get clear => 'Clear';
  @override
  String get done => 'Done';
  @override
  String get exit => 'Quit';
  @override
  String get all => 'All';
  @override
  String get sync => 'Sync';
  @override
  String get paste => 'Paste';
  @override
  String get name => 'Name';
  @override
  String get username => 'Username';
  @override
  String get password => 'Password';
  @override
  String get loadFailed => 'Could not load';
  @override
  String get loadMoreFailed => 'Could not load. Tap to retry.';
  @override
  String get noMore => 'No more';
  @override
  String get noRooms => 'No rooms here yet';
  @override
  String get openRoom => 'Open room';
  @override
  String get follow => 'Follow';
  @override
  String get followed => 'Following';
  @override
  String get unfollow => 'Unfollow';
  @override
  String get openSite => 'Open on site';
  @override
  String get copyLink => 'Copy link';
  @override
  String get linkCopied => 'Link copied';
  @override
  String get offline => 'Offline';
  @override
  String get replay => 'Replay';
  @override
  String get unsupported => 'Not supported yet';
  @override
  String get couldNotOpenLink => 'Could not open the link';
  @override
  String get couldNotOpenWindow => 'Could not open a new window';
  @override
  String seconds({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} second', other: '${n} seconds');
  @override
  String minutes({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} minute', other: '${n} minutes');
  @override
  String items({required Object n}) => '${n}';
  @override
  String get unlimited => 'No limit';
  @override
  String get auto => 'Auto';
  @override
  String get on => 'On';
  @override
  String get off => 'Off';
  @override
  String get listSeparator => ', ';
  @override
  String error({required Object error}) => 'Something went wrong: ${error}';
  @override
  String monthDay({required Object month, required Object day}) => '${month}/${day}';
}

// Path: danmaku
class _Translations$danmaku$en implements Translations$danmaku$zh_Hans {
  _Translations$danmaku$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get blockListTitle => 'Blocked words and users';
  @override
  String get blockKeywords => 'Keywords';
  @override
  String get blockUsers => 'Users';
  @override
  String alreadyBlocked({required Object value}) => '"${value}" is already on the list';
  @override
  String unblocked({required Object value}) => 'Removed "${value}"';
  @override
  String get keywordHint => 'Word to block';
  @override
  String get userHint => 'User name to block';
  @override
  String get keywordHelper => 'Danmaku containing this word are hidden';
  @override
  String get userHelper => 'Matches the whole user name';
  @override
  String get blockListLoadFailed => 'Could not load the block list';
  @override
  String get noBlockedKeywords => 'No blocked words yet';
  @override
  String get noBlockedUsers => 'No blocked users yet';
  @override
  String get blockFromRoomHint => 'You can also tap a danmaku in a room to block it';
  @override
  String get blockKeyword => 'Block keyword';
  @override
  String get blockUser => 'Block user';
  @override
  String keywordBlocked({required Object keyword}) => 'Blocked the keyword "${keyword}"';
  @override
  String userBlocked({required Object user}) => 'Blocked the user "${user}"';
  @override
  String get blockKeywordHint => 'Danmaku containing this word are hidden';
  @override
  String get caseInsensitive => 'Not case-sensitive';
  @override
  String get block => 'Block';
  @override
  String get off => 'Danmaku is off';
  @override
  String get offHint => 'Turn it on to connect to the chat and show danmaku on the video';
  @override
  String get turnOn => 'Turn on danmaku';
  @override
  String get offlineNoDanmaku => 'No danmaku while the room is offline';
  @override
  String get localHint => 'Post a local danmaku (shown on this device only)';
  @override
  String get reconnect => 'Reconnect';
  @override
  String get settings => 'Danmaku settings';
  @override
  String newMessages({required Object n}) => '${n} new';
  @override
  String get jumpToLatest => 'Jump to latest';
  @override
  late final _Translations$danmaku$preset$en preset = _Translations$danmaku$preset$en._(_root);
  @override
  String get show => 'Show danmaku';
  @override
  String get showSubtitle => 'When off, the chat is not connected';
  @override
  String get style => 'Style';
  @override
  String get fontSize => 'Font size';
  @override
  String get fontWeight => 'Font weight';
  @override
  String get opacity => 'Opacity';
  @override
  String get speedHint => 'Speed (higher is faster)';
  @override
  String get area => 'Display area';
  @override
  String get topMargin => 'Top margin';
  @override
  String get bottomMargin => 'Bottom margin';
  @override
  String get stroke => 'Outline';
  @override
  String get strokeWidth => 'Outline width';
  @override
  String get hideEmoji => 'Hide emoji';
  @override
  String get hideEmojiSubtitle => 'Hide danmaku that are only emoji';
  @override
  String get autoFps => 'Automatic frame rate';
  @override
  String get autoFpsSubtitle => 'Follows General › Refresh rate';
  @override
  String get fps => 'Frame rate';
  @override
  String get videoTaps => 'Tapping danmaku on the video';
  @override
  String get tapDanmaku => 'Tap a danmaku';
  @override
  String get opensActions => 'Opens copy and block';
  @override
  String get longPressDanmaku => 'Long-press a danmaku';
  @override
  String get filters => 'Filters';
  @override
  String get collapseRepeated => 'Merge repeated danmaku';
  @override
  String get collapseWindow => 'Merge window';
  @override
  String get filterSimilar => 'Filter similar danmaku';
  @override
  String get filterSimilarSubtitle => 'Short danmaku in busy rooms may be filtered';
  @override
  String get similarityThreshold => 'Similarity threshold';
  @override
  String get compareRecent => 'Compare with the last';
  @override
  String get compareMost => 'Compare at most';
  @override
  String get douyuBots => 'Filter suspected Douyu bot danmaku';
  @override
  String get douyuBotsSubtitle => 'Off by default; it may hide real danmaku';
  @override
  String presetApplied({required Object name}) => 'Applied "${name}"';
  @override
  String get saveMyStyle => 'Save as my style';
  @override
  String get styleSaved => 'Saved the current danmaku style';
  @override
  String get restoreMyStyle => 'Restore my style';
  @override
  String get styleRestored => 'Restored the saved danmaku style';
  @override
  String get styleBroken => 'The saved style is damaged and could not be restored';
  @override
  String get pip => 'Picture-in-picture danmaku';
  @override
  String get pipShow => 'Show danmaku in picture-in-picture';
  @override
  String get speed => 'Speed';
  @override
  String get maxOnScreen => 'At most on screen';
  @override
  String get noEmoji => 'Hide emoji';
  @override
  String get connecting => 'Connecting to the chat…';
  @override
  String get reconnecting => 'Chat disconnected, reconnecting…';
  @override
  String get disconnected => 'Chat disconnected';
  @override
  String get unsupported => 'Danmaku are not supported on this platform yet';
  @override
  String get replayMode => 'Playing a recording; danmaku come from the recording';
  @override
  String get bilibiliGuest => 'Not signed in to Bilibili, so the platform hides viewer names';
  @override
  String get timeout => 'The chat connection timed out';
  @override
  String get noCredentials => 'Chat connection failed: no platform credentials';
  @override
  String get rejected => 'The platform refused the chat connection';
  @override
  String get retriesFailed => 'The chat failed to reconnect several times';
  @override
  late final _Translations$danmaku$audience$en audience = _Translations$danmaku$audience$en._(_root);
  @override
  String giftMany({required Object gift, required Object count}) => 'Sent ${gift} ×${count}';
  @override
  String gift({required Object gift}) => 'Sent ${gift}';
  @override
  String get localSender => 'Me';
  @override
  String chatName({required Object name}) => '${name}: ';
}

// Path: diagnostics
class _Translations$diagnostics$en implements Translations$diagnostics$zh_Hans {
  _Translations$diagnostics$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get saveBundle => 'Save diagnostics bundle';
  @override
  String get bundleSaved => 'Diagnostics bundle saved';
  @override
  String exportFailed({required Object error}) => 'Export failed: ${error}';
  @override
  String get exportBundle => 'Export diagnostics bundle';
  @override
  String get exportBundleSubtitle =>
      'Version, device details, settings and recent logs in one JSON file; no cookies, passwords or other account data';
  @override
  String get crashReportsSubtitle =>
      'After a crash, offer to export a diagnostics bundle at the next start. Nothing is uploaded.';
  @override
  String get recentLogs => 'Recent logs';
  @override
  String get recentLogsSubtitle =>
      'Kept on this device only, up to about 768 KB; cookies and tokens are removed before writing';
  @override
  String get noLogs => 'No logs in this run yet';
}

// Path: discover
class _Translations$discover$en implements Translations$discover$zh_Hans {
  _Translations$discover$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get unfollowArea => 'Remove from saved categories';
  @override
  String get followArea => 'Save category';
  @override
  String get areaGone => 'This category is no longer available';
  @override
  String get savedAreas => 'Saved';
  @override
  String get recommended => 'Recommended';
  @override
  String get areas => 'Categories';
}

// Path: errors
class _Translations$errors$en implements Translations$errors$zh_Hans {
  _Translations$errors$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get channelMissing => 'Channel not found';
  @override
  String get channelMissingDetail => 'This channel is no longer in the playlist. It may have been renamed or removed.';
  @override
  String get roomMissing => 'Room not found';
  @override
  String get roomMissingDetail => 'The room number may no longer be valid, or the streamer moved to another room.';
  @override
  String get needsLogin => 'Sign-in required';
  @override
  String get needsLoginDetail => 'Sign in to the platform to watch this. You can sign in under Me → Platform accounts.';
  @override
  String get rateLimited => 'Too many requests';
  @override
  String get rateLimitedDetail => 'The platform is limiting requests. Try again in a moment.';
  @override
  String get riskControl => 'Blocked by the platform';
  @override
  String get riskControlDetail => 'The platform refused the request for now. Try again later or on another network.';
  @override
  String get regionBlocked => 'Not available in your region';
  @override
  String get regionBlockedDetail =>
      'The platform restricts access from this region. You can set a proxy for this platform in Settings.';
  @override
  String get noStream => 'No stream available';
  @override
  String get noStreamDetail => 'The platform has no playable line right now. Try again later.';
  @override
  String get unsupportedLink => 'Link not supported';
  @override
  String get unsupportedLinkDetail => 'Room links from Douyu, Huya, Bilibili, Douyin and Kuaishou are supported.';
  @override
  String get apiChanged => 'The platform changed';
  @override
  String get apiChangedDetail => 'Update the app to keep using this platform.';
  @override
  String get network => 'Network error';
  @override
  String get networkDetail => 'Check your network or proxy settings and try again.';
  @override
  String get platformUnsupported => 'Platform not supported';
  @override
  String platformUnsupportedDetail({required Object name}) =>
      '${name} has been retired or is not supported by this version. Its follows and watch history are kept.';
  @override
  String get generic => 'Something went wrong';
}

// Path: follows
class _Translations$follows$en implements Translations$follows$zh_Hans {
  _Translations$follows$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get followFailed => 'Could not follow; nothing was saved. Try again.';
  @override
  String get unfollowFailed => 'Could not unfollow; the follow is still there. Try again.';
  @override
  String unfollowed({required Object name}) => 'Unfollowed ${name}';
  @override
  String get undoFailed => 'Could not undo; the follow was not restored';
  @override
  String get emptyTitle => 'You are not following anyone yet';
  @override
  String get emptyMessage => 'Find streamers in Discover or Search, open their room and tap Follow.';
  @override
  String get goDiscover => 'Go to Discover';
  @override
  String get orderNotSaved => 'The order was not saved. Try again.';
  @override
  String get reorder => 'Reorder';
  @override
  late final _Translations$follows$sort$en sort = _Translations$follows$sort$en._(_root);
  @override
  String get sortTooltip => 'Sort';
  @override
  String get editCustomOrder => 'Edit custom order';
  @override
  String get openMultiview => 'Watch in multi-view';
  @override
  String get refreshStatus => 'Refresh live status';
  @override
  String get loadFailed => 'Could not load your follows';
  @override
  String get liveFollows => 'Live follows';
  @override
  String platformRetired({required Object name}) =>
      '${name} has been retired or is not supported by this version. Your follow is kept.';
  @override
  String lastLive({required Object ago}) => 'Last live ${ago}';
  @override
  late final _Translations$follows$tag$en tag = _Translations$follows$tag$en._(_root);
  @override
  String unsupportedPlatform({required Object name}) => '${name} · not supported yet';
  @override
  String get unknownDetail => 'Could not get the live status';
  @override
  String get missingDetail => 'The platform cannot find this room';
  @override
  String get replayDetail => 'Showing a rerun';
  @override
  String get checking => 'Checking live status';
  @override
  String refreshFailed({required Object platforms}) =>
      'Refreshing ${platforms} failed; those streamers\' status is unknown for now';
  @override
  String get viewStatus => 'View status';
  @override
  late final _Translations$follows$filter$en filter = _Translations$follows$filter$en._(_root);
  @override
  String get manageGroups => 'Manage groups';
  @override
  String get noneLive => 'None of the streamers you follow are live';
  @override
  String allCount({required Object n}) => 'All follows ${n}';
  @override
  String offlineCount({required Object n}) => 'Offline ${n}';
  @override
  String get ungrouped => 'Ungrouped';
  @override
  String get noGroups => 'No groups yet';
  @override
  String get noGroupsHint => 'Create groups in Manage groups, then set a streamer\'s groups from its More menu';
  @override
  String get groupEmpty => 'No streamers in this group yet';
  @override
  String get newGroup => 'New group';
  @override
  String get groupName => 'Group name';
  @override
  String get groupDescription => 'Description (optional)';
  @override
  String get groupDescriptionHint => 'For example: evening streams';
  @override
  String groupExists({required Object name}) => 'A group named "${name}" already exists';
  @override
  String get groupNameEmpty => 'The group name cannot be empty';
  @override
  String get editGroup => 'Edit group';
  @override
  String get groupNotSaved => 'The groups were not saved. Try again.';
  @override
  String setGroupsFor({required Object title}) => 'Groups · ${title}';
  @override
  String get groupsHint => 'Groups sort the streamers you follow; view them by group on the Following page.';
  @override
  String get renameAndDescribe => 'Rename and describe';
  @override
  String groupDeleted({required Object name}) => 'Deleted the group "${name}"';
}

// Path: fonts
class _Translations$fonts$en implements Translations$fonts$zh_Hans {
  _Translations$fonts$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String downloadFailed({required Object font}) =>
      'Could not download "${font}". Check your network or proxy and try again.';
  @override
  String downloaded({required Object name}) => '"${name}" downloaded';
  @override
  String deleted({required Object name}) => 'Deleted "${name}"; it stops using memory after a restart';
  @override
  String get title => 'Fonts';
  @override
  String get listFailed => 'Could not load the font list';
  @override
  String get systemFont => 'System font';
  @override
  String get inUse => 'In use';
  @override
  String get appFont => 'Interface font';
  @override
  String get danmakuFont => 'Danmaku font';
  @override
  String get resetAppFont => 'Use the system font for the interface';
  @override
  String get resetDanmakuFont => 'Use the system font for danmaku';
  @override
  String get downloadable => 'Fonts to download';
  @override
  String get downloadableNote =>
      'Only fonts that are free to use and share (SIL OFL 1.1, IPA Font License) are listed. The files are large; download them on Wi-Fi.';
  @override
  String get useInterface => 'interface';
  @override
  String get useDanmaku => 'danmaku';
  @override
  String usedFor({required Object uses}) => 'Used for ${uses}';
  @override
  String get and => ' and ';
  @override
  String get download => 'Download';
  @override
  String get use => 'Use';
  @override
  String get useForInterface => 'Use for the interface';
  @override
  String get useForDanmaku => 'Use for danmaku';
}

// Path: health
class _Translations$health$en implements Translations$health$zh_Hans {
  _Translations$health$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get imageCacheCleared => 'Image cache cleared';
  @override
  String get clearImageCache => 'Clear image cache';
  @override
  String get calculating => 'Calculating';
  @override
  String imageCacheSize({required Object size}) =>
      'Covers and avatars use ${size} MB; follows, history and recordings are not affected';
  @override
  String get timeout => 'No response within 15 seconds';
  @override
  String get checkAgain => 'Check again';
  @override
  String get checkingAll => 'Checking platforms';
  @override
  String get checkFailed => 'Check failed';
  @override
  String ok({required Object ms}) => 'OK · ${ms} ms';
  @override
  String get failed => 'Failing';
  @override
  String get method =>
      'How it checks: each platform\'s category list is requested. When a platform fails, Following and Discover show what they had last time, and its rooms may not open.';
}

// Path: iptv
class _Translations$iptv$en implements Translations$iptv$zh_Hans {
  _Translations$iptv$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get notSynced => 'Not synced';
  @override
  String get syncedJustNow => 'Synced just now';
  @override
  String syncedMinutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Synced ${n} minute ago',
    other: 'Synced ${n} minutes ago',
  );
  @override
  String syncedHoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Synced ${n} hour ago',
    other: 'Synced ${n} hours ago',
  );
  @override
  String syncedAt({required Object date, required Object time}) => 'Synced ${date} ${time}';
  @override
  String get url => 'URL';
  @override
  String get nameOptional => 'Name (optional)';
  @override
  String guideSummary({required Object channels, required Object programmes}) =>
      '${channels} channels, ${programmes} programmes';
  @override
  String get addGuide => 'Add TV guide';
  @override
  String guideAdded({required Object summary}) => 'Added: ${summary}';
  @override
  String get pickGuide => 'Choose a TV guide (XMLTV or JSON, .gz allowed)';
  @override
  String guideSynced({required Object summary}) => 'Synced: ${summary}';
  @override
  String get sourceCopied => 'Source address copied';
  @override
  String get deleteGuide => 'Delete TV guide';
  @override
  String deleteGuideConfirm({required Object name}) => 'Delete "${name}" and its programmes?';
  @override
  String get guide => 'TV guide';
  @override
  String get guideHint =>
      'Choose the TV guide to use; channels are matched by tvg-id and name. Guides keep programmes for two days either side of today.';
  @override
  String get guideSources => 'Guide sources';
  @override
  String get noGuide => 'No TV guide';
  @override
  String get noGuides => 'No TV guides yet';
  @override
  String get guideFormats => 'XMLTV (.xml, .xml.gz) and JSON guides are supported';
  @override
  String get playlistGuide => 'Guide from the playlist';
  @override
  String get addFromUrl => 'Add from URL';
  @override
  String get addFromFile => 'Add from file';
  @override
  String channelsAndSynced({required num n, required Object synced}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} channel · ${synced}',
        other: '${n} channels · ${synced}',
      );
  @override
  String lastSyncFailed({required Object error}) => 'Last sync failed: ${error}';
  @override
  String get autoSync => 'Auto sync';
  @override
  String get copySource => 'Copy source address';
  @override
  String get noPlaylists => 'No playlists yet';
  @override
  String get noPlaylistsHint =>
      'Import an M3U, TXT or JSON playlist and its channels appear here by group; you can follow them like rooms.';
  @override
  String get importPlaylist => 'Import playlist';
  @override
  String get allChannels => 'All channels';
  @override
  String get groups => 'Groups';
  @override
  String get ungrouped => 'Ungrouped';
  @override
  String get managePlaylists => 'Manage playlists';
  @override
  String get noChannels => 'This playlist has no channels yet';
  @override
  String get playlistNotSynced => 'This playlist has not been synced yet';
  @override
  String importSummary({required Object name, required Object channels, required Object lines}) =>
      '"${name}": ${channels} channels, ${lines} lines';
  @override
  String importSummarySkipped({
    required Object name,
    required Object channels,
    required Object lines,
    required Object skipped,
  }) => '"${name}": ${channels} channels, ${lines} lines, ${skipped} lines skipped';
  @override
  String get importFromUrl => 'Import from URL';
  @override
  String imported({required Object summary}) => 'Imported ${summary}';
  @override
  String signedInAndImported({required Object summary}) => 'Signed in and imported ${summary}';
  @override
  String get pickPlaylist => 'Choose a playlist (M3U, TXT or JSON)';
  @override
  String get sharedFileName => 'Shared playlist.m3u';
  @override
  String get importShared => 'Import shared playlist';
  @override
  String get allSynced => 'Everything synced';
  @override
  String syncedWithFailures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Sync finished; ${n} source failed',
    other: 'Sync finished; ${n} sources failed',
  );
  @override
  String syncedPlaylist({required Object summary}) => 'Synced ${summary}';
  @override
  String get playlistUserAgent => 'User-Agent for this playlist';
  @override
  String get userAgentEmpty => 'Leave empty to use the global setting';
  @override
  String get playlistUserAgentHint =>
      'Sent when downloading the list and playing its channels; a channel\'s own value wins';
  @override
  String get deletePlaylist => 'Delete playlist';
  @override
  String deletePlaylistConfirm({required num n, required Object name}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Delete "${name}" and its ${n} channel? Followed channels stay but show "Channel not found".',
        other: 'Delete "${name}" and its ${n} channels? Followed channels stay but show "Channel not found".',
      );
  @override
  String get title => 'IPTV';
  @override
  String get syncAll => 'Sync all';
  @override
  String get playlists => 'Playlists';
  @override
  String get playlistsHint =>
      'Import M3U, TXT or JSON playlists from a file or URL; channels appear under Discover › IPTV';
  @override
  String get playlistsLoadFailed => 'Could not load playlists';
  @override
  String get importFromFile => 'Import from file';
  @override
  String get xtreamAccount => 'Xtream account';
  @override
  String get noGuideAdded => 'None yet. Import an XMLTV or JSON guide to see programmes and catch up.';
  @override
  String get noGuideSelected => 'None selected';
  @override
  String currentGuide({required Object name}) => 'Current: ${name}';
  @override
  String get autoSyncHint => 'Syncs due URL playlists and guides 3 seconds after start';
  @override
  String get syncInterval => 'Sync interval';
  @override
  String get every6h => 'Every 6 hours';
  @override
  String get every12h => 'Every 12 hours';
  @override
  String get daily => 'Daily';
  @override
  String get every2d => 'Every 2 days';
  @override
  String get every3d => 'Every 3 days';
  @override
  String get weekly => 'Weekly';
  @override
  String get customUserAgent => 'Custom User-Agent';
  @override
  String get userAgentUnset => 'Not set (the player\'s default)';
  @override
  String get userAgentExample => 'For example okhttp/4.12.0';
  @override
  String get userAgentHint =>
      'Sent when downloading playlists and guides and playing channels; a playlist\'s or channel\'s own value wins';
  @override
  String get notSyncedHint => 'Not synced. Tap Sync to get the channels.';
  @override
  String get noAutoSync => 'Not auto-synced';
  @override
  String get xtreamHint => 'Enter the server address (for example http://example.com:8080), user name and password';
  @override
  String get xtreamSignIn => 'Sign in to Xtream';
  @override
  String get serverAddress => 'Server address';
  @override
  String get showPassword => 'Show password';
  @override
  String get hidePassword => 'Hide password';
  @override
  String get xtreamStorageNote =>
      'The user name and password are stored encrypted on this device only; backups and sync never contain them in plain text.';
  @override
  String get signInAndImport => 'Sign in and import';
  @override
  String get backToLive => 'Back to live';
  @override
  String get backToLiveFailed => 'Could not go back to live; tap Retry on the video';
  @override
  String get notStarted => 'The programme has not started yet';
  @override
  String catchingUp({required Object title}) => 'Catching up: ${title}';
  @override
  String get noCatchUp => 'This programme cannot be watched again';
  @override
  String get channelNoCatchUp => 'This channel has no catch-up';
  @override
  String get outOfCatchUpWindow => 'Outside the catch-up window';
  @override
  String get onAir => 'On air';
  @override
  String get catchUp => 'Catch-up';
  @override
  String lines({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} line', other: '${n} lines');
  @override
  String upNext({required Object time, required Object title}) => 'Next at ${time}: ${title}';
  @override
  String get loadingGuide => 'Loading the TV guide…';
  @override
  String get noGuideMatch => 'No guide matched. Add or change a guide source and it matches automatically.';
  @override
  String get noProgrammeNow => 'The guide has nothing for this time yet';
  @override
  String get returnToLive => 'Back to live';
  @override
  String get today => 'Today';
  @override
  String get yesterday => 'Yesterday';
  @override
  String get dayBeforeYesterday => '2 days ago';
  @override
  String get tomorrow => 'Tomorrow';
  @override
  String dayWithDate({required Object label, required Object date}) => '${label} ${date}';
  @override
  String get guideLoadFailed => 'Could not load the TV guide';
  @override
  String get noProgrammes => 'No programmes';
  @override
  String get noProgrammesHint => 'The guide has nothing for this channel two days either side of today.';
  @override
  String get noCatchUpTag => 'No catch-up';
  @override
  late final _Translations$iptv$error$en error = _Translations$iptv$error$en._(_root);
  @override
  String xtreamGuideName({required Object title}) => '${title} guide';
  @override
  String get defaultPlaylistName => 'Playlist';
  @override
  late final _Translations$iptv$xtream$en xtream = _Translations$iptv$xtream$en._(_root);
}

// Path: me
class _Translations$me$en implements Translations$me$zh_Hans {
  _Translations$me$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get pureBlackSubtitle => 'Use a pure black background in dark mode, for OLED screens';
  @override
  String get denseFollows => 'Compact cards on Following';
  @override
  String get denseFollowsSubtitle => 'Streamer name and title on one line, so more rooms fit on screen';
  @override
  String get historyCleared => 'Watch history cleared';
  @override
  String get noHistory => 'No watch history yet';
  @override
  String get iptvSubtitle => 'IPTV playlists, TV guides and auto sync';
  @override
  String get backupSubtitle => 'Backup files, WebDAV and LAN sync; 3.x backups can be imported';
  @override
  String aboutSubtitle({required Object version}) => 'Version ${version} · updates, licences';
}

// Path: multiview
class _Translations$multiview$en implements Translations$multiview$zh_Hans {
  _Translations$multiview$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get addRoom => 'Add room';
  @override
  String offlineCell({required Object name}) => '${name} is offline\nTap here to pick another';
  @override
  String get interrupted => 'Playback stopped';
  @override
  String get danmakuOff => 'Turn off danmaku';
  @override
  String get danmakuOn => 'Turn on danmaku';
  @override
  String get quality => 'Quality';
  @override
  String get line => 'Line';
  @override
  String get volume => 'Volume';
  @override
  String get exitFullscreen => 'Exit full screen';
  @override
  String get fullscreen => 'Full screen';
  @override
  String get onePlusN => '1 large + small';
  @override
  String get immersive => 'Immersive mode';
  @override
  String get exitImmersive => 'Exit immersive mode';
  @override
  String get layout => 'Layout';
  @override
  String get addCell => 'Add a view';
  @override
  String capacityReached({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Limit reached: this device plays at most ${n} stream at once',
    other: 'Limit reached: this device plays at most ${n} streams at once',
  );
  @override
  String capacityHint({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'This device plays at most ${n} stream at once. Close a view before adding another.',
    other: 'This device plays at most ${n} streams at once. Close a view before adding another.',
  );
  @override
  String get unmuteAll => 'Unmute all';
  @override
  String get muteAll => 'Mute all';
  @override
  String get selectedVolume => 'Volume of the selected view';
  @override
  String pickRoomFor({required Object n}) => 'Choose a room · view ${n}';
  @override
  String get filterHint => 'Filter by streamer or title';
  @override
  String cell({required Object n}) => 'View ${n}';
  @override
  String get switchRoom => 'Change room';
  @override
  String lineN({required Object n}) => 'Line ${n}';
  @override
  String get cellIdle => 'Nothing is playing in this view';
  @override
  String get allMutedHint => 'Everything is muted. Volume is saved per room and applies when you unmute.';
  @override
  String get volumePerRoom => 'Volume is saved per room';
  @override
  String get volumeNotSource => 'Volume is saved per room and applies once this view is the sound source';
}

// Path: onboarding
class _Translations$onboarding$en implements Translations$onboarding$zh_Hans {
  _Translations$onboarding$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String welcome({required Object app}) => 'Welcome to ${app} v4';
  @override
  String get intro =>
      'The preview is a separate install and cannot read 3.x\'s data. Import your follows and settings from 3.x or another device, or just start.';
  @override
  String get fromFile => 'Import from a backup file';
  @override
  String get fromFileSubtitle => 'A file exported by 3.x\'s Backup and restore, or a v4 backup';
  @override
  String get fromWebdav => 'Import from WebDAV';
  @override
  String get fromWebdavSubtitle => 'A backup you uploaded to Jianguoyun, Nextcloud or another drive';
  @override
  String get fromDevice => 'Import from another device';
  @override
  String get fromDeviceSubtitle => 'Sent by another device on the same network with LAN sync';
  @override
  String get skip => 'Skip and start';
  @override
  String get laterHint => 'You can import any time later under Me › Backup and sync.';
  @override
  String get crashPrompt =>
      'Something went wrong last time. Export a diagnostics bundle and attach it to a problem report to help find the cause.';
}

// Path: quality
class _Translations$quality$en implements Translations$quality$zh_Hans {
  _Translations$quality$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get original => 'Original';
  @override
  String get bluRay8M => 'Blu-ray 8M';
  @override
  String get bluRay4M => 'Blu-ray 4M';
  @override
  String get superHigh => 'Super HD';
  @override
  String get smooth => 'Smooth';
}

// Path: recording
class _Translations$recording$en implements Translations$recording$zh_Hans {
  _Translations$recording$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$recording$notice$en notice = _Translations$recording$notice$en._(_root);
  @override
  String get cancelSchedule => 'Cancel scheduled recording';
  @override
  String get schedule => 'Schedule recording';
  @override
  late final _Translations$recording$state$en state = _Translations$recording$state$en._(_root);
  @override
  late final _Translations$recording$failure$en failure = _Translations$recording$failure$en._(_root);
  @override
  late final _Translations$recording$stage$en stage = _Translations$recording$stage$en._(_root);
  @override
  String get stopTitle => 'Stop recording';
  @override
  String stopConfirm({required Object name}) => 'Stop recording "${name}"? What was recorded is kept.';
  @override
  String get removeWatch => 'Stop watching';
  @override
  String removeWatchConfirm({required Object name}) =>
      'Stop waiting for "${name}" to go live? Recorded files are kept.';
  @override
  String get deleteTask => 'Delete recording task';
  @override
  String deleteTaskRunning({required Object name}) =>
      'Delete the recording task of "${name}"? A running recording stops first; recorded files are kept.';
  @override
  String deleteTaskConfirm({required Object name}) =>
      'Delete the recording task of "${name}"? Recorded files are kept.';
  @override
  String get recordFromRoomHint => 'You can also tap the record button in a room.';
  @override
  String get pickFromFollows => 'Choose from follows';
  @override
  String get settings => 'Recording settings';
  @override
  String get add => 'Add recording';
  @override
  String get noTasks => 'No recording tasks yet';
  @override
  String get noTasksHint =>
      'Tap Record in a room or add one from your follows. With live monitoring on, recording starts when the streamer goes live.';
  @override
  String get scheduled => 'Scheduled recordings';
  @override
  String get tasks => 'Recording tasks';
  @override
  String folderCopied({required Object path}) => 'Folder path copied: ${path}';
  @override
  String gaps({required Object n}) => 'Gaps ${n}';
  @override
  String problemWithStage({required Object problem, required Object stage}) => '${problem} · failed at: ${stage}';
  @override
  String nextCheck({required Object time}) => 'Next check ${time}';
  @override
  String get stopWatch => 'Stop watching';
  @override
  String get cancelQueue => 'Leave the queue';
  @override
  String get start => 'Start recording';
  @override
  String get restart => 'Record again';
  @override
  String get checkNow => 'Check for live now';
  @override
  String get forceStart => 'Start anyway';
  @override
  String get retryRemux => 'Retry remux';
  @override
  String get openFolder => 'Open folder';
  @override
  String get deleteKeepFiles => 'Delete task (keep files)';
  @override
  String get cancelScheduled => 'Cancel scheduled recording';
}

// Path: room
class _Translations$room$en implements Translations$room$zh_Hans {
  _Translations$room$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$room$failure$en failure = _Translations$room$failure$en._(_root);
  @override
  String autoLowered({required Object quality}) =>
      'Unstable network: switched to ${quality}. You can switch back under Quality.';
  @override
  String get audioOnlyFailed => 'Could not switch to audio only; the picture is back';
  @override
  String get restoreVideoFailed => 'Could not restore the picture; still audio only';
  @override
  String volumeHint({required Object percent}) => 'Volume ${percent}%';
  @override
  String get danmakuShown => 'Danmaku on';
  @override
  String get danmakuHidden => 'Danmaku off';
  @override
  String get pipNeedsVideo => 'Picture-in-picture is available once the video shows';
  @override
  String get noApp => 'The app was not found; opening in the browser';
  @override
  String brightnessHint({required Object percent}) => 'Brightness ${percent}%';
  @override
  late final _Translations$room$fit$en fit = _Translations$room$fit$en._(_root);
  @override
  String get noFrameToCapture => 'There is no picture to capture';
  @override
  String screenshotSaved({required Object path}) => 'Screenshot saved: ${path}';
  @override
  String screenshotFailed({required Object error}) => 'Screenshot failed: ${error}';
  @override
  late final _Translations$room$sleep$en sleep = _Translations$room$sleep$en._(_root);
  @override
  String get resumePlayback => 'Resume playback';
  @override
  String get lineFailedMany => 'This line failed. Retry or switch lines.';
  @override
  String get lineFailedOne => 'Try again later';
  @override
  String get switchLine => 'Switch line';
  @override
  String get unlock => 'Unlock';
  @override
  String get lock => 'Lock';
  @override
  String get switchRoom => 'Switch room';
  @override
  String get hideChat => 'Hide chat';
  @override
  String get chat => 'Chat';
  @override
  String get restoreVideo => 'Restore picture';
  @override
  String get audioOnly => 'Audio only';
  @override
  String get cast => 'Cast';
  @override
  String get danmakuOnKey => 'Turn on danmaku (D)';
  @override
  String get danmakuOffKey => 'Turn off danmaku (D)';
  @override
  String get unmuteKey => 'Unmute (M)';
  @override
  String get muteKey => 'Mute (M)';
  @override
  String get showWholePicture => 'Show the whole picture';
  @override
  String get fillScreen => 'Fill the screen';
  @override
  String get orientation => 'Picture orientation';
  @override
  String get orientationAuto => 'Detect automatically';
  @override
  String get orientationPortrait => 'Treat as portrait';
  @override
  String get orientationLandscape => 'Treat as landscape';
  @override
  String get aspect => 'Aspect ratio';
  @override
  String get exitTheaterKey => 'Exit theatre mode (T)';
  @override
  String get theaterKey => 'Theatre mode (T)';
  @override
  String get hideChatKey => 'Hide chat (C)';
  @override
  String get showChatKey => 'Show chat (C)';
  @override
  String get pipKey => 'Picture-in-picture (P)';
  @override
  String get exitFullscreenKey => 'Exit full screen (F)';
  @override
  String get fullscreenKey => 'Full screen (F)';
  @override
  String get audioOnlyPlaying => 'Playing audio only';
  @override
  String get enableMonitoringFirst => 'Turn on live monitoring in Recording settings first';
  @override
  String get goToSettings => 'Settings';
  @override
  String get recordWhenLive => 'Records automatically when live';
  @override
  String get stoppingRecording => 'Stopping the recording; recorded files are kept';
  @override
  String get taskRemoved => 'Recording task removed; recorded files are kept';
  @override
  String get record => 'Record';
  @override
  String get recordNow => 'Record now';
  @override
  String get recordOnLive => 'Record when live';
  @override
  String get removeTask => 'Remove recording task';
  @override
  late final _Translations$room$tab$en tab = _Translations$room$tab$en._(_root);
  @override
  String get forceLandscape => 'Landscape full screen';
  @override
  String platformLimited({required Object quality}) => 'Limited by the platform to ${quality}';
  @override
  String qualityLine({required Object quality, required Object n}) => '${quality} · line ${n}';
  @override
  String get quickPanelHint => 'Long-press the video for the quick panel; long-press a danmaku to copy or block it';
  @override
  String get screenshot => 'Screenshot';
  @override
  String get sleepTimer => 'Sleep timer';
  @override
  String get openInApp => 'Open in the app';
  @override
  String get share => 'Share';
  @override
  String get copyStreamUrl => 'Copy stream URL';
  @override
  String get roomVolume => 'Room volume';
  @override
  String get addToMultiview => 'Add to multi-view';
  @override
  String get shortcuts => 'Keyboard shortcuts';
  @override
  String get openInNewWindow => 'Open in a new window';
  @override
  String shareSubject({required Object name}) => '${name}\'s room';
  @override
  String get shareCodeCopied => 'Share code copied. Paste it in Pure Live to open the room.';
  @override
  String get noStreamYet => 'No stream yet';
  @override
  String get streamUrlCopied => 'Stream URL copied. It expires; copy it again later.';
  @override
  String get noLiveFollows => 'None of your follows are live';
  @override
  String get noRecordingRooms => 'No rooms are recording';
  @override
  String get noHistory => 'No watch history yet';
  @override
  String get volumeRemembered => 'This room remembers this volume';
  @override
  String get volumePlayerOnly => 'Only the player\'s volume changes, not your phone\'s media volume';
  @override
  String get setDefaultVolume => 'Set as default volume';
  @override
  String get setPhoneDefaultVolume => 'Set as phone default volume';
  @override
  late final _Translations$room$key$en key = _Translations$room$key$en._(_root);
  @override
  late final _Translations$room$tip$en tip = _Translations$room$tip$en._(_root);
  @override
  String get noRoomsToSwitch => 'No live rooms to switch to';
  @override
  String get firstRoom => 'This is the first one';
  @override
  String get lastRoom => 'This is the last one';
  @override
  String get swipeHint => 'You can turn on swiping between rooms in Settings › Playback';
  @override
  late final _Translations$room$tv$en tv = _Translations$room$tv$en._(_root);
}

// Path: rooms
class _Translations$rooms$en implements Translations$rooms$zh_Hans {
  _Translations$rooms$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get setGroups => 'Set groups';
  @override
  String get streamLink => 'Get stream URL';
  @override
  String get openInNewWindow => 'Open in a new window';
  @override
  String followedName({required Object name}) => 'Following ${name}';
  @override
  String get notLive => 'The streamer is not live, so there is no stream URL.';
  @override
  String get loadingLines => 'Getting lines';
  @override
  String get linesTapToCopy => 'Lines (tap to copy)';
  @override
  String get noLinesForQuality => 'No lines for this quality';
  @override
  String get clipboardFailed => 'Could not write to the clipboard. Try again.';
  @override
  String streamLinkFor({required Object title}) => 'Get stream URL · ${title}';
}

// Path: search
class _Translations$search$en implements Translations$search$zh_Hans {
  _Translations$search$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get voice => 'Voice search';
  @override
  String get clear => 'Clear';
  @override
  String get results => 'Search results';
  @override
  String get all => 'All';
  @override
  String get failedTag => 'Failed';
  @override
  String otherPlatforms({required Object n}) => 'Other platforms ${n}';
  @override
  String get allFailed => 'Search failed. Check your network and pull down to retry.';
  @override
  String someFailed({required Object platforms}) => 'Search failed on ${platforms}. Pull down to retry.';
  @override
  String get hint => 'Search streamers and rooms, or paste a room link';
  @override
  String get liveOnly => 'Live only';
  @override
  String get resolvingLink => 'Recognising the link';
  @override
  String get noLinkMatch => 'No room link found';
  @override
  String get empty => 'No matching rooms';
  @override
  late final _Translations$search$sort$en sort = _Translations$search$sort$en._(_root);
  @override
  late final _Translations$search$web$en web = _Translations$search$web$en._(_root);
  @override
  String get recent => 'Recent searches';
  @override
  String get clearHistory => 'Clear';
  @override
  String get removeFromHistory => 'Remove from search history';
  @override
  String historyRemoved({required Object keyword}) => 'Removed “${keyword}” from search history';
  @override
  String get historyCleared => 'Search history cleared';
  @override
  String get historyOffCleared => 'Search history turned off and cleared';
}

// Path: settings
class _Translations$settings$en implements Translations$settings$zh_Hans {
  _Translations$settings$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Follow system';
  @override
  late final _Translations$settings$group$en group = _Translations$settings$group$en._(_root);
  @override
  late final _Translations$settings$general$en general = _Translations$settings$general$en._(_root);
  @override
  late final _Translations$settings$appearance$en appearance = _Translations$settings$appearance$en._(_root);
  @override
  late final _Translations$settings$playback$en playback = _Translations$settings$playback$en._(_root);
  @override
  late final _Translations$settings$data$en data = _Translations$settings$data$en._(_root);
  @override
  late final _Translations$settings$accounts$en accounts = _Translations$settings$accounts$en._(_root);
  @override
  String get tvDarkOnly => 'TV mode is always dark';
  @override
  String get tvDarkOnlySubtitle => 'The pure black switch still applies';
  @override
  String historyEntries({required Object n}) => '${n} entries';
  @override
  late final _Translations$settings$output$en output = _Translations$settings$output$en._(_root);
  @override
  late final _Translations$settings$record$en record = _Translations$settings$record$en._(_root);
  @override
  late final _Translations$settings$audience$en audience = _Translations$settings$audience$en._(_root);
  @override
  late final _Translations$settings$network$en network = _Translations$settings$network$en._(_root);
  @override
  String get platformsHint =>
      'Tick the platforms to show in Discover, Search and Platform accounts, and drag to reorder; tap the star to make one Discover\'s default.';
  @override
  String get discoverDefault => 'Discover\'s default';
  @override
  String get setDiscoverDefault => 'Make it Discover\'s default';
  @override
  Map<String, String> get languageNames => {'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', 'en': 'English'};
  @override
  late final _Translations$settings$search$en search = _Translations$settings$search$en._(_root);
}

// Path: share
class _Translations$share$en implements Translations$share$zh_Hans {
  _Translations$share$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String roomN({required Object id}) => 'Room ${id}';
  @override
  String get shareCodeReceived => 'Share code received';
  @override
  String get roomLinkFound => 'Room link found';
  @override
  String get fromClipboard => 'From the clipboard. You can turn off clipboard detection in Settings › General.';
  @override
  String get enterRoom => 'Open room';
  @override
  String get codeCopied =>
      'Share code copied. Whoever copies it and opens Pure Live (3.x or v4) goes straight to this room.';
}

// Path: sites
class _Translations$sites$en implements Translations$sites$zh_Hans {
  _Translations$sites$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  Map<String, String> get names => {
    'bilibili': 'Bilibili',
    'douyu': 'Douyu',
    'huya': 'Huya',
    'douyin': 'Douyin',
    'kuaishou': 'Kuaishou',
    'cc': 'NetEase CC',
    'yy': 'YY',
    'soop': 'SOOP',
    'acfun': 'AcFun',
    'twitch': 'Twitch',
    'chzzk': 'CHZZK',
    'missevan': 'MissEvan',
    'kilakila': 'KilaKila',
    'inke': 'Inke',
    'picarto': 'Picarto',
    'twitcasting': 'TwitCasting',
    'showroom': 'SHOWROOM',
    'pandalive': 'PandaTV',
    '17live': '17LIVE',
    'liveme': 'LiveMe',
    'steambroadcast': 'Steam Broadcasting',
    'sixroom': '6.cn',
    'kugoulive': 'Kugou Live',
    'jdlive': 'JD Live',
    'baidulive': 'Baidu Live',
    'looklive': 'LOOK Live',
    'weibo': 'Weibo Live',
    'niconico': 'niconico',
    'xiaohongshu': 'REDnote',
    'youtube': 'YouTube Live',
    'tiktok': 'TikTok LIVE',
    'fc2live': 'FC2 Live',
    'bigo': 'Bigo Live',
    'iptv': 'IPTV',
  };
  @override
  Map<String, String> get otherNames => {'huajiao': 'Huajiao', 'kick': 'Kick'};
}

// Path: sync
class _Translations$sync$en implements Translations$sync$zh_Hans {
  _Translations$sync$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$device$en device = _Translations$sync$device$en._(_root);
  @override
  late final _Translations$sync$lan$en lan = _Translations$sync$lan$en._(_root);
  @override
  late final _Translations$sync$webdav$en webdav = _Translations$sync$webdav$en._(_root);
}

// Path: system
class _Translations$system$en implements Translations$system$zh_Hans {
  _Translations$system$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get backgroundChannelDescription => 'Shown while a room\'s sound plays in the background';
  @override
  String get closeWindow => 'Close window';
  @override
  String get closeQuestion => 'Quit Pure Live or keep it running in the system tray?';
  @override
  String get dontAskAgain => 'Don\'t ask again';
  @override
  String get changeInSettings => 'You can change this in Settings › General';
  @override
  String get minimizeToTray => 'Minimise to tray';
  @override
  String get askEveryTime => 'Ask every time';
  @override
  String get quitApp => 'Quit the app';
  @override
  String get onClose => 'When closing the window';
  @override
  String get showWindow => 'Show window';
  @override
  String get hideWindow => 'Hide window';
  @override
  String get playbackError => 'Playback error';
  @override
  String get backToRoom => 'Back to the room';
  @override
  String get closeMini => 'Close the mini player';
  @override
  String get restoreWindowFailed => 'Could not restore the window. Resize it yourself.';
  @override
  String get exitPip => 'Exit picture-in-picture (double-click the video)';
  @override
  String get launchAtStartup => 'Start with Windows';
  @override
  String get launchAtStartupSubtitle => 'Open Pure Live when you sign in to Windows';
  @override
  String get miniOnLeave => 'Keep playing in a mini player when leaving a room';
  @override
  String get miniOnLeaveSubtitle => 'The mini player keeps using memory and data';
  @override
  String get autoPip => 'Picture-in-picture when leaving the app';
  @override
  String get autoPipSubtitle => 'Enter picture-in-picture when you press Home in a room';
  @override
  String get pipOnTop => 'Keep the picture-in-picture window on top';
}

// Path: tv
class _Translations$tv$en implements Translations$tv$zh_Hans {
  _Translations$tv$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get speechPrompt => 'Say a streamer or room name';
}

// Path: ui
class _Translations$ui$en implements Translations$ui$zh_Hans {
  _Translations$ui$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get live => 'LIVE';
  @override
  String liveFor({required Object duration}) => 'LIVE ${duration}';
  @override
  String get liveNow => 'live';
  @override
  String get offline => 'offline';
  @override
  String get recording => 'Recording';
  @override
  String get separator => ', ';
  @override
  String get retry => 'Retry';
  @override
  String get ok => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get justNow => 'just now';
  @override
  String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} minute ago',
    other: '${n} minutes ago',
  );
  @override
  String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} hour ago',
    other: '${n} hours ago',
  );
  @override
  String daysAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} day ago', other: '${n} days ago');
  @override
  String get countBase => '1000';
  @override
  List<String> get countUnits => ['K', 'M', 'B'];
}

// Path: web
class _Translations$web$en implements Translations$web$zh_Hans {
  _Translations$web$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get webView2Title => 'WebView2 Runtime required';
  @override
  String get webView2Body =>
      'Web sign-in and web search use Microsoft Edge WebView2 Runtime, which is not installed on this computer. Windows 11 and up-to-date Windows 10 usually include it.\n\nTo install it, open Microsoft\'s download page, download the Evergreen Bootstrapper and run it, then reopen Pure Live.';
  @override
  String get openDownloadPage => 'Open download page';
}

// Path: accounts.cookieTip
class _Translations$accounts$cookieTip$en implements Translations$accounts$cookieTip$zh_Hans {
  _Translations$accounts$cookieTip$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get douyu =>
      'Sign in to www.douyu.com in a desktop browser, copy the Cookie request header from the developer tools and paste it below. To allow renewal, also paste the cookie of a passport.douyu.com request (with LTP0); the app keeps LTP0 and dy_did from it.';
  @override
  String get twitch =>
      'Sign in to twitch.tv in a desktop browser and copy the cookie. Only its auth-token is used, for subscriber-only streams and no ads.';
  @override
  String get soop =>
      'Sign in to sooplive.co.kr in a desktop browser and copy the cookie. It is only sent with stream requests for 19+ streams.';
  @override
  String get other =>
      'Sign in to the platform\'s website in a desktop browser, copy the Cookie request header from the developer tools and paste it below.';
}

// Path: app.tabs
class _Translations$app$tabs$en implements Translations$app$tabs$zh_Hans {
  _Translations$app$tabs$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get follows => 'Following';
  @override
  String get discover => 'Discover';
  @override
  String get search => 'Search';
  @override
  String get me => 'Me';
}

// Path: backup.section
class _Translations$backup$section$en implements Translations$backup$section$zh_Hans {
  _Translations$backup$section$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get follows => 'Follows';
  @override
  String get followAreas => 'Followed categories';
  @override
  String get tags => 'Groups';
  @override
  String get roomTags => 'Group members';
  @override
  String get history => 'Watch history';
  @override
  String get blockRules => 'Blocked words';
  @override
  String get settings => 'Settings';
  @override
  String get roomPrefs => 'Room preferences';
  @override
  String get recordTasks => 'Recording tasks';
  @override
  String get secrets => 'Platform sign-ins';
  @override
  String get searchHistory => 'Search history';
}

// Path: cast.failure
class _Translations$cast$failure$en implements Translations$cast$failure$zh_Hans {
  _Translations$cast$failure$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get unreachable => 'Cannot reach this device. Make sure it is on and on the same Wi-Fi as your phone.';
  @override
  String get busy => 'The device is busy. Try again later.';
  @override
  String get format => 'The device does not support this stream format. Try another line.';
  @override
  String get unplayable => 'The device cannot open this stream. Try another line.';
  @override
  String refused({required Object code}) => 'The device refused to cast (error ${code})';
  @override
  String http({required Object status}) => 'The device returned an error (HTTP ${status})';
  @override
  String get protocol => 'The device\'s reply was not understood';
  @override
  String get generic => 'Cast failed';
}

// Path: cast.tv
class _Translations$cast$tv$en implements Translations$cast$tv$zh_Hans {
  _Translations$cast$tv$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get playing => 'Playing on the TV';
  @override
  String get loading => 'Loading on the TV';
  @override
  String get paused => 'Paused on the TV';
  @override
  String get stopped => 'Stopped on the TV';
}

// Path: danmaku.preset
class _Translations$danmaku$preset$en implements Translations$danmaku$preset$zh_Hans {
  _Translations$danmaku$preset$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get best => 'Best view';
  @override
  String get comfort => 'Comfortable';
  @override
  String get dense => 'Dense';
  @override
  String get reset => 'Defaults';
}

// Path: danmaku.audience
class _Translations$danmaku$audience$en implements Translations$danmaku$audience$zh_Hans {
  _Translations$danmaku$audience$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get online => 'Online';
  @override
  String get popularity => 'Popularity';
  @override
  String get cumulative => 'Views';
}

// Path: follows.sort
class _Translations$follows$sort$en implements Translations$follows$sort$zh_Hans {
  _Translations$follows$sort$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get audience => 'By viewers';
  @override
  String get liveTime => 'By live time';
  @override
  String get platform => 'By platform';
  @override
  String get custom => 'Custom order';
}

// Path: follows.tag
class _Translations$follows$tag$en implements Translations$follows$tag$zh_Hans {
  _Translations$follows$tag$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get unsupported => 'Unsupported';
  @override
  String get unknown => 'Status unknown';
  @override
  String get missing => 'Room not found';
  @override
  String get replay => 'Rerun';
}

// Path: follows.filter
class _Translations$follows$filter$en implements Translations$follows$filter$zh_Hans {
  _Translations$follows$filter$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get live => 'Live';
  @override
  String liveCount({required Object n}) => 'Live ${n}';
  @override
  String get groups => 'Groups';
}

// Path: iptv.error
class _Translations$iptv$error$en implements Translations$iptv$error$zh_Hans {
  _Translations$iptv$error$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get noGuide => 'No TV guide found. Make sure it is XMLTV or JSON.';
  @override
  String get noChannels => 'No channels found. Make sure it is an M3U, TXT or JSON playlist.';
  @override
  String get badUrl => 'Enter a URL that starts with http or https';
  @override
  String get xtreamMissing => 'The sign-in of this Xtream account is missing. Delete it and sign in again.';
  @override
  String get notFound => 'Not found (404). Check that the URL still works.';
  @override
  String get network => 'Network error. Check your network or proxy and try again.';
  @override
  String get file => 'Could not read the file. Import it again.';
  @override
  String get format => 'Wrong file format';
  @override
  String get generic => 'Sync failed';
  @override
  String get notXtream => 'The server\'s reply is not an Xtream API. Check the server address.';
}

// Path: iptv.xtream
class _Translations$iptv$xtream$en implements Translations$iptv$xtream$zh_Hans {
  _Translations$iptv$xtream$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get wrongCredentials => 'Wrong user name or password';
  @override
  String get expired => 'The account has expired';
  @override
  String get banned => 'The account is banned';
  @override
  String get disabled => 'The account is disabled';
  @override
  String unavailable({required Object status}) => 'The account is unavailable (${status})';
  @override
  String get unknownStatus => 'unknown status';
}

// Path: recording.notice
class _Translations$recording$notice$en implements Translations$recording$notice$zh_Hans {
  _Translations$recording$notice$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get finishingTitle => 'Finishing recordings';
  @override
  String finishingText({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} recording is finishing. This notice goes away when it is done.',
    other: '${n} recordings are finishing. This notice goes away when they are done.',
  );
  @override
  String namesAndMore({required Object names}) => '${names} and more';
  @override
  String recordingTitle({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Recording ${n} room',
    other: 'Recording ${n} rooms',
  );
  @override
  String recordingText({required num n, required Object shown}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, other: '${shown}; ${n} finishing');
}

// Path: recording.state
class _Translations$recording$state$en implements Translations$recording$state$zh_Hans {
  _Translations$recording$state$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get queued => 'Queued';
  @override
  String get resolving => 'Preparing';
  @override
  String get recording => 'Recording';
  @override
  String get reconnecting => 'Reconnecting';
  @override
  String get finalizing => 'Processing';
  @override
  String remuxing({required Object percent}) => 'Remuxing ${percent}%';
  @override
  String get waitingLive => 'Waiting for live';
  @override
  String get completed => 'Done';
  @override
  String get failed => 'Failed';
  @override
  String get stoppedPollingOff => 'Stopped (live monitoring is off)';
  @override
  String get stoppedAppExit => 'Stopped (the app quit)';
  @override
  String get stopped => 'Stopped';
}

// Path: recording.failure
class _Translations$recording$failure$en implements Translations$recording$failure$zh_Hans {
  _Translations$recording$failure$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get offline => 'The stream ended';
  @override
  String get banned => 'The room is banned';
  @override
  String get missing => 'The room does not exist';
  @override
  String get unsupported => 'Recording is not supported on this platform yet';
  @override
  String get needsLogin => 'Sign in to the platform';
  @override
  String get region => 'Not available in your region';
  @override
  String get noStream => 'No recordable stream';
  @override
  String get unsupportedFormat =>
      'This stream\'s format cannot be recorded yet (such as RTSP or UDP addresses, SAMPLE-AES encryption, or HLS with separate audio)';
  @override
  String get diskFull => 'Not enough storage';
  @override
  String get noPermission => 'No permission to write to the recording folder';
  @override
  String get directory => 'The recording folder is unavailable';
  @override
  String get writeStalled => 'Writing to disk stalled';
  @override
  String get background => 'The system ended the background time';
  @override
  String get remux => 'Converting to MP4 failed; the original file is kept';
  @override
  String get corrupt => 'The recording is damaged';
  @override
  String get retries => 'Several retries failed';
  @override
  String get stream => 'Network or stream error';
}

// Path: recording.stage
class _Translations$recording$stage$en implements Translations$recording$stage$zh_Hans {
  _Translations$recording$stage$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get check => 'Room check';
  @override
  String get quality => 'Quality choice';
  @override
  String get resolve => 'Stream lookup';
  @override
  String get connect => 'Connection';
  @override
  String get write => 'File writing';
  @override
  String get remux => 'Remux';
  @override
  String get queue => 'Queue';
  @override
  String get background => 'Background';
  @override
  String get poll => 'Live check';
}

// Path: room.failure
class _Translations$room$failure$en implements Translations$room$failure$zh_Hans {
  _Translations$room$failure$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get network => 'The network dropped';
  @override
  String get source => 'The stream will not open. Try another line.';
  @override
  String get buffering => 'Buffering too long. Try another line or a lower quality.';
  @override
  String get ended => 'The stream ended';
  @override
  String get paused => 'Playback stopped unexpectedly';
  @override
  String get frozen => 'The picture froze';
  @override
  String get videoDecode => 'Video decoding failed. Try turning off hardware decoding in Settings.';
  @override
  String get audioDecode => 'Audio decoding failed';
  @override
  String get engine => 'Player error';
  @override
  String get unavailable => 'No stream available';
  @override
  String get exhausted => 'Several retries failed';
}

// Path: room.fit
class _Translations$room$fit$en implements Translations$room$fit$zh_Hans {
  _Translations$room$fit$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get cover => 'Fill';
  @override
  String get fill => 'Stretch';
  @override
  String get contain => 'Fit';
}

// Path: room.sleep
class _Translations$room$sleep$en implements Translations$room$sleep$zh_Hans {
  _Translations$room$sleep$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get exiting => 'Sleep timer: quitting the app';
  @override
  String get paused => 'Sleep timer: playback paused';
  @override
  String exitIn({required Object time}) => 'Quit the app in ${time}';
  @override
  String pauseIn({required Object time}) => 'Pause in ${time}';
  @override
  String get cancel => 'Cancel timer';
  @override
  String get hint => 'Pauses playback and background sound when the time is up';
  @override
  String get custom => 'Custom';
  @override
  String get pause => 'Pause playback';
  @override
  String get exit => 'Quit the app';
  @override
  String get audioOnly => 'Also switch to audio only';
  @override
  String get audioOnlySubtitle => 'For sleep: keep only the sound';
  @override
  String invalidMinutes({required Object max}) => 'Enter a number of minutes from 1 to ${max}';
  @override
  String get customTitle => 'Custom duration';
  @override
  String get minutesSuffix => 'min';
}

// Path: room.tab
class _Translations$room$tab$en implements Translations$room$tab$zh_Hans {
  _Translations$room$tab$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get danmaku => 'Danmaku';
  @override
  String get room => 'Room';
}

// Path: room.key
class _Translations$room$key$en implements Translations$room$key$zh_Hans {
  _Translations$room$key$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get space => 'Space';
  @override
  String get playPause => 'Play / pause';
  @override
  String get fullscreenKeys => 'F, double-click';
  @override
  String get fullscreen => 'Full screen on / off';
  @override
  String get escape => 'Close a panel → leave full screen or theatre mode → leave the room';
  @override
  String get theater => 'Theatre mode';
  @override
  String get chat => 'Show / hide chat';
  @override
  String get mute => 'Mute';
  @override
  String get volumeKeys => '↑ ↓, mouse wheel';
  @override
  String get volume => 'Volume ±5%';
  @override
  String get danmaku => 'Danmaku on / off';
  @override
  String get qualityLine => 'Quality / line';
  @override
  String get help => 'Shortcut help';
  @override
  String get refreshKeys => 'R, F5, Ctrl+R';
}

// Path: room.tip
class _Translations$room$tip$en implements Translations$room$tip$zh_Hans {
  _Translations$room$tip$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get desktop => 'Press C to show or hide chat, T for theatre mode and ? for all shortcuts';
  @override
  String get touch => 'Pinch to change the aspect ratio; long-press the video for the quick panel';
}

// Path: room.tv
class _Translations$room$tv$en implements Translations$room$tv$zh_Hans {
  _Translations$room$tv$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get hint =>
      'Up and down change rooms, left opens the room list, right the playback settings, OK shows the controls';
  @override
  String get roomList => 'Room list';
  @override
  String get playbackSettings => 'Playback settings';
  @override
  String get qualityLine => 'Quality and line';
  @override
  String get noLiveRooms => 'No live rooms';
  @override
  String get watching => 'Watching';
}

// Path: search.sort
class _Translations$search$sort$en implements Translations$search$sort$zh_Hans {
  _Translations$search$sort$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get smart => 'Smart';
  @override
  String get platform => 'By platform';
  @override
  String get audience => 'By viewers';
  @override
  String get followers => 'By followers';
}

// Path: search.web
class _Translations$search$web$en implements Translations$search$web$zh_Hans {
  _Translations$search$web$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Web search';
  @override
  String get enterKeyword => 'Enter a keyword first';
  @override
  String get pickPlatform => 'Which platform\'s website to search';
  @override
  String get roomFound => 'Room found';
  @override
  String get stay => 'Stay on the page';
  @override
  String titleFor({required Object name}) => 'Web search · ${name}';
  @override
  String get pageRooms => 'Rooms on this page';
  @override
  String get unavailable => 'Web search is not available here';
  @override
  String get notOpened => 'The page did not open';
  @override
  String get scanning => 'Looking for rooms on this page';
  @override
  String get noRooms => 'No room links found on this page';
  @override
  String get pageRoomsTitle => 'Rooms on this page';
}

// Path: settings.group
class _Translations$settings$group$en implements Translations$settings$group$zh_Hans {
  _Translations$settings$group$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get general => 'General';
  @override
  String get playback => 'Playback';
  @override
  String get danmaku => 'Danmaku';
  @override
  String get recording => 'Recording';
  @override
  String get accounts => 'Platforms and accounts';
  @override
  String get network => 'Network';
  @override
  String get data => 'Data and sync';
}

// Path: settings.general
class _Translations$settings$general$en implements Translations$settings$general$zh_Hans {
  _Translations$settings$general$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get startPage => 'Start page';
  @override
  String get keepScreenOn => 'Keep the screen on while playing';
  @override
  String get refreshRate => 'Refresh rate';
  @override
  String get refreshPowerSaving => 'Power saving';
  @override
  String get refreshBalanced => 'Balanced';
  @override
  String get refreshHighest => 'Highest';
  @override
  String get autoCheckUpdate => 'Check for updates automatically';
  @override
  String get tv => 'TV';
  @override
  String get tvMode => 'TV mode';
  @override
  String get tvModeAuto => 'Auto (on when a TV is detected)';
  @override
  String get tvFocusOutline => 'Outline-only TV focus';
  @override
  String get tvFocusOutlineSubtitle => 'For performance: focus does not enlarge, for low-end TV boxes';
  @override
  String get followRefresh => 'Follow refresh';
  @override
  String get autoRefreshFollows => 'Refresh the live status of follows on a timer';
  @override
  String get refreshOnResume => 'Refresh follows when returning to the app';
  @override
  String get refreshInterval => 'Refresh interval';
  @override
  String get maxConcurrentRefresh => 'Rooms refreshed at once';
  @override
  String get refreshCovers => 'Refresh covers on a timer';
  @override
  String get refreshCoversSubtitle => 'Covers of live cards are downloaded again at the interval, so they stay current';
  @override
  String get coverInterval => 'Cover refresh interval';
  @override
  String get notifications => 'Notifications';
}

// Path: settings.appearance
class _Translations$settings$appearance$en implements Translations$settings$appearance$zh_Hans {
  _Translations$settings$appearance$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get theme => 'Theme';
  @override
  String get denseSubtitle => 'Streamer name and title on one line';
  @override
  String get textSize => 'Text size';
  @override
  String get accentColor => 'Use the system accent colour';
  @override
  String get accentColorSubtitle => 'The theme colour follows the Windows accent colour';
  @override
  String get wallpaperColor => 'Use wallpaper colours';
  @override
  String get wallpaperColorSubtitle => 'Android 12 and later: the theme colour comes from the wallpaper';
  @override
  String get compactCardsPhone => 'Compact cards in Discover and Search (phone)';
  @override
  String get compactCardsDesktop => 'Compact cards in Discover and Search (desktop)';
  @override
  String get fontsSubtitle => 'Download open-source fonts for the interface or danmaku';
}

// Path: settings.playback
class _Translations$settings$playback$en implements Translations$settings$playback$zh_Hans {
  _Translations$settings$playback$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get qualityWifi => 'Default quality (Wi-Fi)';
  @override
  String get qualityMobile => 'Default quality (mobile data)';
  @override
  String get autoLower => 'Lower the quality on an unstable network';
  @override
  String get autoLowerSubtitle =>
      'Three stalls within a minute drop one step; no automatic change after you pick a quality yourself';
  @override
  String get fitCover => 'Fill (crop)';
  @override
  String get autoFullscreen => 'Full screen when a room opens';
  @override
  String get swipeRooms => 'Swipe up and down to switch rooms in portrait full screen';
  @override
  String get swipeRoomsSubtitle =>
      'Swipe up for the next room and down for the previous one; brightness and volume no longer follow vertical swipes in portrait full screen';
  @override
  String get portrait => 'Portrait streams';
  @override
  String get portraitAdaptation => 'Portrait stream layout';
  @override
  String get portraitAdaptationSubtitle =>
      'Detect portrait streams and use portrait full screen with a draggable info panel on phones';
  @override
  String get fullscreenOrientation => 'Full screen orientation';
  @override
  String get orientationSource => 'Follow the picture (portrait streams stay portrait)';
  @override
  String get orientationSystem => 'Follow the phone';
  @override
  String get orientationLandscape => 'Always landscape';
  @override
  String get portraitFit => 'Portrait full screen picture';
  @override
  String get portraitFitContain => 'Show all';
  @override
  String get portraitFitCover => 'Fill the screen (crop the edges)';
  @override
  String get portraitDanmaku => 'Portrait full screen danmaku area';
  @override
  String get danmakuFollow => 'Follow the danmaku settings';
  @override
  String get danmakuUpperQuarter => 'Top quarter only';
  @override
  String get danmakuHalf => 'Half';
  @override
  String get danmakuHidden => 'Hidden';
  @override
  String get rememberOrientation => 'Remember each room\'s picture orientation';
  @override
  String get rememberOrientationSubtitle => 'A room\'s Treat as portrait / landscape choice still applies next time';
  @override
  String get background => 'Background playback';
  @override
  String get backgroundSubtitle => 'Keep playing the sound after leaving the app';
  @override
  String get sleep => 'Sleep';
  @override
  String get sleepMode => 'Sleep mode';
  @override
  String get sleepModeSubtitle =>
      'Rooms open with sound only and start the sleep timer; restoring the picture cancels that timer';
  @override
  String get sleepMinutes => 'Sleep timer length';
  @override
  String get phoneVolume => 'Default volume on phones';
}

// Path: settings.data
class _Translations$settings$data$en implements Translations$settings$data$zh_Hans {
  _Translations$settings$data$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get historyLimit => 'Keep watch history up to';
  @override
  String get searchHistory => 'Keep search history';
  @override
  String get searchHistorySubtitle =>
      'Lists your last 20 searches when the search box is empty; turning it off clears them';
}

// Path: settings.accounts
class _Translations$settings$accounts$en implements Translations$settings$accounts$zh_Hans {
  _Translations$settings$accounts$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get platforms => 'Platforms';
  @override
  String get platformsSubtitle => 'Which platforms show, their order and Discover\'s default platform';
  @override
  String get audience => 'Viewer counts';
  @override
  String get audienceSubtitle => 'Whether cards show heat or viewers, and what each platform\'s figures mean';
  @override
  String get accountsSubtitle => 'Sign in to or out of each platform';
}

// Path: settings.output
class _Translations$settings$output$en implements Translations$settings$output$zh_Hans {
  _Translations$settings$output$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get volume => 'Volume';
  @override
  String get startMuted => 'Mute when a room opens';
  @override
  String get startMutedSubtitle => 'Every room starts muted';
  @override
  String get defaultVolume => 'Default volume';
  @override
  String get defaultVolumeDesktop => 'Default volume (rooms without a saved volume)';
  @override
  String get decoding => 'Decoding and output';
  @override
  String get hardwareDecoding => 'Hardware decoding';
  @override
  String get hardwareDecodingSubtitle => 'Turn it off if the picture looks wrong';
  @override
  String get decoder => 'Hardware decoder';
  @override
  String get mediacodecCopy => 'MediaCodec (copy)';
  @override
  String get d3d11Copy => 'D3D11 (copy)';
  @override
  String get nvdec => 'NVDEC (NVIDIA)';
  @override
  String get compatibility => 'Compatibility mode';
  @override
  String get compatibilitySubtitle => 'Turn on if some devices show black or garbled video or freeze';
  @override
  String get lowLatency => 'Low latency';
  @override
  String get lowLatencySubtitle => 'Less buffering and delay; stalls more on a poor network';
  @override
  String get audio => 'Audio output';
}

// Path: settings.record
class _Translations$settings$record$en implements Translations$settings$record$zh_Hans {
  _Translations$settings$record$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get centerSubtitle => 'View and manage recording tasks';
  @override
  String get quality => 'Default recording quality';
  @override
  String get monitoring => 'Live monitoring';
  @override
  String get monitoringSubtitle => 'Start recording when the streamer goes live';
  @override
  String get pollInterval => 'Live check interval (seconds)';
  @override
  String get reconnect => 'Reconnection';
  @override
  String get autoReconnect => 'Reconnect automatically';
  @override
  String get retries => 'Retries';
  @override
  String get retryInterval => 'Retry interval (seconds)';
  @override
  String get backoff => 'Wait longer after each failure';
  @override
  String get backoffSubtitle => 'Each failed retry or live check doubles the wait, up to the longest interval';
  @override
  String get maxBackoff => 'Longest wait';
  @override
  String get readTimeout => 'Read timeout (how long without data counts as disconnected)';
  @override
  String get files => 'Files';
  @override
  String get maxConcurrent => 'Recordings at once';
  @override
  String get splitDuration => 'Split by duration (minutes, 0 for no split)';
  @override
  String get splitSize => 'Split by size';
  @override
  String get saveDanmaku => 'Save danmaku too';
  @override
  String get saveDanmakuSubtitle => 'An XML file named like the video';
  @override
  String get remuxMp4 => 'Convert to MP4 when done';
  @override
  String get keepSource => 'Keep the original recording after converting';
  @override
  String get pinyinFolders => 'Pinyin folder names';
  @override
  String get pinyinFoldersSubtitle => 'Use streamer names in pinyin for folders, for devices that cannot show Chinese';
  @override
  String get resumeOnStart => 'Resume unfinished recordings at start';
  @override
  String get space => 'Storage';
  @override
  String get limitSize => 'Limit the recording folder size';
  @override
  String get limitSizeSubtitle =>
      'Above the limit, the oldest recordings are deleted first; recordings in progress are kept';
  @override
  String get sizeLimit => 'Recording folder limit';
  @override
  String get noSplit => 'No split';
  @override
  String get directory => 'Recording folder';
  @override
  String get directoryDefault => 'Default location';
  @override
  String get directoryReset => 'Reset to default';
  @override
  String get directoryPick => 'Choose the recording folder';
}

// Path: settings.audience
class _Translations$settings$audience$en implements Translations$settings$audience$zh_Hans {
  _Translations$settings$audience$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get shown => 'Cards show';
  @override
  String get heatFirst => 'Platform heat first';
  @override
  String get heatFirstSubtitle => 'Shows each platform\'s public heat or total views, which are not concurrent viewers';
  @override
  String get onlineFirst => 'Viewers first';
  @override
  String get onlineFirstSubtitle =>
      'Shows concurrent viewers when the platform gives them, otherwise heat or total views';
  @override
  String get meaning => 'What each platform\'s figures mean';
}

// Path: settings.network
class _Translations$settings$network$en implements Translations$settings$network$zh_Hans {
  _Translations$settings$network$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get useProxy => 'Use a proxy';
  @override
  String get useProxySubtitle => 'An HTTP proxy, such as Clash on port 7897; when on, the system proxy is not used';
  @override
  String get proxyHost => 'Proxy address';
  @override
  String get proxyHostUnset => 'Not set (for example 127.0.0.1)';
  @override
  String get proxyPort => 'Proxy port';
  @override
  String get proxyPlatforms => 'Platforms using the proxy';
  @override
  String get proxyAll => 'Every platform uses the proxy now. Once you select platforms below, only those use it.';
  @override
  String get proxySelected => 'Only the selected platforms use the proxy.';
  @override
  String get systemProxy => 'Use the system proxy';
  @override
  String get systemProxyManual => 'Not used while the manual proxy is on';
  @override
  String get systemProxyNone => 'The system has no proxy; connecting directly';
  @override
  String systemProxyIs({required Object host, required Object port}) => 'System proxy: ${host}:${port}';
}

// Path: settings.search
class _Translations$settings$search$en implements Translations$settings$search$zh_Hans {
  _Translations$settings$search$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'Search settings';
  @override
  String get noResults => 'No matching settings';
  @override
  String legacyName({required Object name}) => '3.x: ${name}';
  @override
  Map<String, String> get legacy => {
    'theme_locale': 'Change language|Language & Region',
    'app_refreshRateMode': 'Interface refresh rate',
    'exit_choice': 'Exit Without Prompt|No Exit Confirm',
    'startup_enabled': 'Start on Boot',
    'refresh_autoRefreshFavorite': 'Auto refresh follow list',
    'refresh_refreshFavoriteOnResume': 'Refresh favorites on resume',
    'refresh_autoRefreshInterval': 'Refresh Interval',
    'refresh_maxConcurrentRefresh': 'Concurrent home refresh tasks',
    'refresh_autoRefreshThumbnails': 'Auto refresh live thumbnails',
    'refresh_thumbnailRefreshInterval': 'Thumbnail Refresh Interval',
    'theme_mode': 'Theme Mode',
    'theme_dynamicColor': 'Dynamic Color',
    'app_denseFavorites': 'Dense Mode',
    'roomCard': 'Room Card Settings|Card layout',
    'fonts': 'Change System Font|Font Family Settings',
    'theme_textScale': 'Global Font Scaling|Font Size Settings',
    'player_preferResolution': 'Resolution Preference',
    'player_preferResolutionCellular': 'Mobile Network Quality',
    'volume_globalVolumeMute': 'Global Mute',
    'volume_defaultMobileVolume': 'Mobile Default Volume',
    'volume_defaultDesktopVolume': 'Desktop Default Volume',
    'player_hardwareDecoding': 'Enable hardcodec',
    'player_hardwareDecoder': 'Hardware Decoder|hwdec',
    'player_audioOutput': 'Audio Output Driver',
    'player_fit': 'Aspect ratio',
    'app_fullScreenDefault': 'Auto Full Screen',
    'player_portraitAdaptation': 'Detect portrait live sources',
    'player_portraitFullscreenPolicy': 'Fullscreen orientation',
    'player_portraitFit': 'Portrait fullscreen display',
    'player_portraitDanmakuArea': 'Portrait danmaku layout',
    'player_rememberPortraitOverride': 'Remember room orientation',
    'player_asmrSleepMode': 'Auto-start sleep audio for new rooms',
    'player_asmrSleepMinutes': 'Auto sleep playback duration',
    'player_miniPlayerOnLeave': 'Exit Floating Window|Play by float window',
    'player_pipAlwaysOnTop': 'Keep Windows mini player on top',
    'danmaku_area': 'Top-screen height used',
    'danmaku_topArea': 'Top inset',
    'danmaku_bottomArea': 'Bottom inset in area',
    'danmaku_speed': 'Scroll speed',
    'danmaku_fontSize': 'Font Size',
    'danmaku_fontWeight': 'Font Weight',
    'danmaku_stroke': 'Danmaku Stroke',
    'danmaku_strokeWidth': 'Stroke width',
    'danmaku_noEmoji': 'Pure text mode',
    'danmaku_autoFps': 'Follow interface refresh policy|Danmaku FPS',
    'danmaku_tapInteraction': 'Tap an on-screen danmaku for actions',
    'danmaku_longPressInteraction': 'Long-press an on-screen danmaku for block actions',
    'danmaku_blockList': 'Block List|Danmaku Keyword Block|Danmaku Filter',
    'danmaku_collapseRepeated': 'Collapse identical danmaku bursts|Repeated danmaku filter',
    'danmaku_similarityFilter': 'Similar Danmaku Filter',
    'danmaku_filterDouyuAutomated': 'Filter Suspected Automated Douyu Chat',
    'danmaku_pipEnabled': 'Show Danmaku in PiP|PiP Danmaku',
    'record_defaultQuality': 'Default Recording Quality',
    'record_polling': 'Enable Live Detection|Polling Detection',
    'record_liveCheckInterval': 'Check Interval',
    'record_autoReconnect': 'Auto Reconnect',
    'record_maxRetries': 'Maximum Retry Count',
    'record_retryDelay': 'Reconnect Delay',
    'record_maxCheckInterval': 'Maximum Check Interval',
    'record_readTimeout': 'Read/Write Timeout',
    'record_maxConcurrent': 'Maximum Concurrent Recording Tasks',
    'record_danmaku': 'Record chat',
    'record_pinyinFolders': 'Use Pinyin Folder Name',
    'record_resumeOnLaunch': 'Resume unfinished tasks on app launch',
    'record_cacheLimitEnabled': 'Enable Cache Limit',
    'record_cacheLimitMB': 'Cache Limit',
    'accounts_platforms': 'Platform Display|Platform Preference',
    'accounts_audience': 'Audience data and ranking',
    'accounts_accounts': 'Third-party Authentication',
    'network_proxyEnabled': 'Enable App Proxy|Enable Player Proxy|Proxy Settings',
    'network_proxyHost': 'Proxy Host',
    'history_limit': 'Watch History Retention',
    'data_cache': 'Clear Local Cache|Storage & Cache',
    'data_diagnostics': 'Local Config Preview',
  };
}

// Path: sync.device
class _Translations$sync$device$en implements Translations$sync$device$zh_Hans {
  _Translations$sync$device$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get android => 'Android device';
  @override
  String get windows => 'Windows PC';
  @override
  String get linux => 'Linux PC';
}

// Path: sync.lan
class _Translations$sync$lan$en implements Translations$sync$lan$zh_Hans {
  _Translations$sync$lan$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get applied => 'The other device confirmed and imported it';
  @override
  String get wrongCode =>
      'Wrong pairing code. Check the code on the other screen (it changes after a few wrong tries).';
  @override
  String get rejected => 'The other device declined or did not confirm in time';
  @override
  String get busy => 'The other device is busy with another sync. Try again later.';
  @override
  String get unsupported =>
      'The other version cannot receive v4 data (3.x only receives 3.x data). Use a backup file or WebDAV instead.';
  @override
  String get unreachable =>
      'Cannot reach the other device. Check that both are on the same network, it is receiving, and the address and port are right.';
  @override
  String get timeout => 'Timed out waiting for confirmation';
  @override
  String get failed => 'The other device failed to import';
  @override
  String get networkNote =>
      'From Android 17 the system may ask to allow the Local network / Nearby devices permission; if the devices cannot connect, allow it under Settings › Apps › Pure Live › Permissions.\nWindows shows a firewall prompt the first time it receives; allow access on private networks.\nBoth devices need to be on the same Wi-Fi (or local network).';
  @override
  String cannotReceive({required Object error}) => 'Could not start receiving: ${error}';
  @override
  String from({required Object from}) => 'From ${from}';
  @override
  String get received => 'Sync data received';
  @override
  String declined({required Object from}) => 'Declined the data from ${from}';
  @override
  String imported({required Object from}) => 'Imported the data from ${from}';
  @override
  String get enterAddress => 'Enter the address shown on the other screen, for example 192.168.1.5:39888';
  @override
  String get enterCode => 'Enter the 6-digit pairing code shown on the other screen';
  @override
  String get sendTo => 'Send to the other device';
  @override
  String get waiting => 'Waiting for confirmation…';
  @override
  String sendFailed({required Object error}) => 'Sending failed: ${error}';
  @override
  String get receive => 'Receive';
  @override
  String get receiveHint =>
      'Start receiving on the device that gets the data, then enter the address and pairing code shown here under Send on the other device. You confirm before anything is written.';
  @override
  String get starting => 'Starting…';
  @override
  String get startReceiving => 'Start receiving';
  @override
  String get receiving => 'Receiving';
  @override
  String get noAddress => 'No local network address found. Connect to Wi-Fi first.';
  @override
  String get address => 'Address';
  @override
  String get code => 'Pairing code';
  @override
  String get codeOnce => 'A pairing code works once: it changes after one transfer or a few wrong tries.';
  @override
  String get qr => 'Sync QR code';
  @override
  String get qrHint => '3.x can scan this QR code to send data';
  @override
  String get stopReceiving => 'Stop receiving';
  @override
  String get sendHint =>
      'First open LAN sync › Receive on the other device, then enter the address and pairing code it shows. Send a full backup or follows only; platform sign-ins are only sent, encrypted, when you set a passphrase.';
  @override
  String get otherAddress => 'Other device\'s address';
  @override
  String get awaiting => 'Waiting for confirmation…';
  @override
  String senderWithAddress({required Object name, required Object address}) => '${name} (${address})';
}

// Path: sync.webdav
class _Translations$sync$webdav$en implements Translations$sync$webdav$zh_Hans {
  _Translations$sync$webdav$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$webdav$error$en error = _Translations$sync$webdav$error$en._(_root);
  @override
  String get noDirectory => 'The folder does not exist yet; the first upload creates it';
  @override
  String get test => 'Test connection';
  @override
  String get connected => 'Connected';
  @override
  String get connectedNoDirectory => 'Connected; the backup folder does not exist yet and the first upload creates it';
  @override
  String get uploadBackup => 'Upload backup';
  @override
  String get upload => 'Upload';
  @override
  String get uploaded => 'Uploaded';
  @override
  String get restore => 'Restore';
  @override
  String fromWebdav({required Object name}) => 'From WebDAV: ${name}';
  @override
  String get deleteRemote => 'Delete remote file';
  @override
  String deleteRemoteConfirm({required Object name}) => 'Delete ${name}? This cannot be undone.';
  @override
  String get deleted => 'Deleted';
  @override
  String get deleteAccount => 'Delete account';
  @override
  String deleteAccountConfirm({required Object name}) =>
      'Delete "${name}" and its saved password? Backups on the server are not affected.';
  @override
  String get help => 'Help';
  @override
  String get addAccount => 'Add account';
  @override
  String get noAccounts => 'No WebDAV accounts yet';
  @override
  String get noAccountsHint =>
      'Add Jianguoyun, Nextcloud, Synology or another WebDAV drive to keep backups in the cloud.';
  @override
  String get account => 'Account';
  @override
  String switchTo({required Object name}) => 'Switch to ${name}';
  @override
  String remoteFiles({required Object path}) => 'Remote files ${path}';
  @override
  String get remoteFilesHint => 'Tap a file to restore or delete it; 3.x purelive_*.txt backups can be restored too';
  @override
  String get up => 'Up';
  @override
  String get noBackups => 'No backups here yet';
  @override
  String get actions => 'Actions';
  @override
  String get helpTitle => 'WebDAV help';
  @override
  String get helpBody =>
      'Jianguoyun: use https://dav.jianguoyun.com/dav/, your sign-in email as the user name, and an app password generated under Account info › Security options.\n\nNextcloud / ownCloud: use https://your-domain/remote.php/dav/files/username/.\n\nSynology: install WebDAV Server from the Package Center and use https://nas-address:5006/.\n\nAlist and similar: usually https://domain/dav/.\n\nThe backup folder is pure_live by default and is created by the first upload. Passwords are stored encrypted on this device and never go into regular backups.';
  @override
  String get defaultName => 'My drive';
  @override
  String get nameRequired => 'Enter a name';
  @override
  String get nameTaken => 'An account with this name exists';
  @override
  String get badUrl => 'The address must start with http:// or https:// and cannot contain a user name, query or #';
  @override
  String get addTitle => 'Add WebDAV account';
  @override
  String get editTitle => 'Edit WebDAV account';
  @override
  String get passwordStored => 'Stored encrypted on this device';
  @override
  String get passwordKeep => 'Leave empty to keep it';
  @override
  String get directory => 'Backup folder';
  @override
  String get directoryRoot => 'Leave empty for the root folder';
}

// Path: sync.webdav.error
class _Translations$sync$webdav$error$en implements Translations$sync$webdav$error$zh_Hans {
  _Translations$sync$webdav$error$en._(this._root);

  final TranslationsEn _root; // ignore: unused_field

  // Translations
  @override
  String get unauthorized => 'Wrong user name or password';
  @override
  String get forbidden => 'This account cannot access that location';
  @override
  String get notFound => 'The file or folder does not exist on the server';
  @override
  String get storage => 'The drive is full';
  @override
  String get network => 'Cannot reach the server. Check the address and network.';
  @override
  String get invalid => 'The server\'s reply is not WebDAV. Check the address.';
  @override
  String http({required Object status}) => 'Server error (HTTP ${status})';
}
