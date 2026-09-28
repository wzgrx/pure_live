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
class TranslationsZhHant with BaseTranslations<AppLocale, Translations> implements Translations {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsZhHant({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.zhHant,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <zh-Hant>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsZhHant _root = this; // ignore: unused_field

  @override
  TranslationsZhHant $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) =>
      TranslationsZhHant(meta: meta ?? this.$meta);

  // Translations
  @override
  late final Translations$about$zh_Hant about = Translations$about$zh_Hant.internal(_root);
  @override
  late final Translations$accounts$zh_Hant accounts = Translations$accounts$zh_Hant.internal(_root);
  @override
  late final Translations$alerts$zh_Hant alerts = Translations$alerts$zh_Hant.internal(_root);
  @override
  late final Translations$app$zh_Hant app = Translations$app$zh_Hant.internal(_root);
  @override
  late final Translations$audience$zh_Hant audience = Translations$audience$zh_Hant.internal(_root);
  @override
  late final Translations$backup$zh_Hant backup = Translations$backup$zh_Hant.internal(_root);
  @override
  late final Translations$cast$zh_Hant cast = Translations$cast$zh_Hant.internal(_root);
  @override
  late final Translations$common$zh_Hant common = Translations$common$zh_Hant.internal(_root);
  @override
  late final Translations$danmaku$zh_Hant danmaku = Translations$danmaku$zh_Hant.internal(_root);
  @override
  late final Translations$diagnostics$zh_Hant diagnostics = Translations$diagnostics$zh_Hant.internal(_root);
  @override
  late final Translations$discover$zh_Hant discover = Translations$discover$zh_Hant.internal(_root);
  @override
  late final Translations$errors$zh_Hant errors = Translations$errors$zh_Hant.internal(_root);
  @override
  late final Translations$follows$zh_Hant follows = Translations$follows$zh_Hant.internal(_root);
  @override
  late final Translations$fonts$zh_Hant fonts = Translations$fonts$zh_Hant.internal(_root);
  @override
  late final Translations$health$zh_Hant health = Translations$health$zh_Hant.internal(_root);
  @override
  late final Translations$iptv$zh_Hant iptv = Translations$iptv$zh_Hant.internal(_root);
  @override
  late final Translations$me$zh_Hant me = Translations$me$zh_Hant.internal(_root);
  @override
  late final Translations$multiview$zh_Hant multiview = Translations$multiview$zh_Hant.internal(_root);
  @override
  late final Translations$onboarding$zh_Hant onboarding = Translations$onboarding$zh_Hant.internal(_root);
  @override
  late final Translations$quality$zh_Hant quality = Translations$quality$zh_Hant.internal(_root);
  @override
  late final Translations$recording$zh_Hant recording = Translations$recording$zh_Hant.internal(_root);
  @override
  late final Translations$room$zh_Hant room = Translations$room$zh_Hant.internal(_root);
  @override
  late final Translations$rooms$zh_Hant rooms = Translations$rooms$zh_Hant.internal(_root);
  @override
  late final Translations$search$zh_Hant search = Translations$search$zh_Hant.internal(_root);
  @override
  late final Translations$settings$zh_Hant settings = Translations$settings$zh_Hant.internal(_root);
  @override
  late final Translations$share$zh_Hant share = Translations$share$zh_Hant.internal(_root);
  @override
  late final Translations$sites$zh_Hant sites = Translations$sites$zh_Hant.internal(_root);
  @override
  late final Translations$sync$zh_Hant sync = Translations$sync$zh_Hant.internal(_root);
  @override
  late final Translations$system$zh_Hant system = Translations$system$zh_Hant.internal(_root);
  @override
  late final Translations$tv$zh_Hant tv = Translations$tv$zh_Hant.internal(_root);
  @override
  late final Translations$ui$zh_Hant ui = Translations$ui$zh_Hant.internal(_root);
  @override
  late final Translations$web$zh_Hant web = Translations$web$zh_Hant.internal(_root);
}

// Path: about
class Translations$about$zh_Hant implements Translations$about$zh_Hans {
  Translations$about$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get versionAndUpdates => '版本與更新';
  @override
  String get versionSubtitle => '查看更新說明、下載安裝檔';
  @override
  String newVersion({required Object version}) => '發現新版本 ${version}';
  @override
  String get platformStatus => '平台狀態';
  @override
  String get platformStatusSubtitle => '檢查各平台現在能不能存取';
  @override
  String get projectPage => '專案首頁';
  @override
  String get feedback => '問題回報';
  @override
  String get feedbackSubtitle => '回報問題時可以附上 設定 › 資料與同步 › 診斷與記錄 裡匯出的診斷包';
  @override
  String get releases => '發布紀錄';
  @override
  String get licenses => '開放原始碼授權';
  @override
  String get licensesSubtitle => '本應用程式以 AGPL-3.0 發布；這裡列出所用元件的授權條款';
  @override
  String get privacy => '隱私';
  @override
  String get privacyBody =>
      '純粹直播不收集、不回傳任何資料。平台 Cookie 和密碼加密儲存在本機，預設不會進入備份；區域網路同步需要配對碼並由接收方確認；當機報告預設關閉，開啟後也只在本機提示匯出診斷包。';
  @override
  String get trademarks => '商標聲明';
  @override
  String get trademarksBody => '各平台名稱和標誌歸其所有者所有，僅用於標明內容來源。';
  @override
  String get pickInstaller => '選擇下載好的安裝檔';
  @override
  String verifyMatch({required Object file, required Object asset}) => '驗證通過：${file} 與 ${asset} 完全一致。';
  @override
  String verifyMismatch({required Object file}) => '驗證失敗：${file} 的 SHA-256 與發布頁公布的不一致，請重新下載，不要安裝。';
  @override
  String verifyNoHashes({required Object hash}) => '這個版本沒有公布 SHA-256，無法驗證。檔案的 SHA-256 是 ${hash}';
  @override
  String verifyUnknown({required Object file, required Object hash}) =>
      '找不到對應的檔案：${file} 的 SHA-256 是 ${hash}，與這個版本的任何檔案都不一致。';
  @override
  String readFileFailed({required Object message}) => '讀取檔案失敗：${message}';
  @override
  String currentVersion({required Object version}) => '目前版本 ${version}';
  @override
  String get channelPreview => '預覽版：檢查更新時也包含預覽版';
  @override
  String get channelStable => '正式版：只檢查正式版';
  @override
  String get checkForUpdates => '檢查更新';
  @override
  String get openReleasePage => '開啟發布頁';
  @override
  String get upToDate => '已是最新版本';
  @override
  String get olderReleases => '歷史版本';
  @override
  String get noNotes => '（沒有更新說明）';
  @override
  String get preview => '預覽版';
  @override
  String newRelease({required Object version}) => '新版本 ${version}';
  @override
  String get releasePage => '發布頁';
  @override
  String get recommendedDownloads => '適合本機的下載';
  @override
  String get otherDownloads => '其他平台和檔案';
  @override
  String get calculating => '正在計算…';
  @override
  String get verifyDownload => '驗證下載的檔案';
  @override
  String get androidPreviewNote => 'Android 預覽版的套件名稱帶 .next，可以和 3.x 同時安裝；下載後在系統裡開啟安裝檔即可覆蓋安裝。';
  @override
  String get releaseNotes => '更新說明';
  @override
  String get androidUniversal => 'Android · 通用';
  @override
  String get windowsSetup => 'Windows · 安裝檔';
  @override
  String get windowsPortable => 'Windows · 可攜版';
  @override
  String get checksums => '驗證值清單';
  @override
  String get otherFile => '其他檔案';
  @override
  String get downloadLinkCopied => '已複製下載連結';
  @override
  String get hashCopied => '已複製 SHA-256';
  @override
  String get copyDownloadLink => '複製下載連結';
  @override
  String get copyHash => '複製 SHA-256';
  @override
  String get errorRateLimited => 'GitHub 限制了檢查頻率，請稍後再試';
  @override
  String get errorNetwork => '連不上 GitHub，請檢查網路或 Proxy';
  @override
  String errorServer({required Object detail}) => '檢查更新失敗（${detail}）';
  @override
  String get unknownError => '未知錯誤';
  @override
  String newPreviewVersion({required Object version}) => '發現新版本 ${version}（預覽版）';
  @override
  String get view => '查看';
}

// Path: accounts
class Translations$accounts$zh_Hant implements Translations$accounts$zh_Hans {
  Translations$accounts$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get sessionExpired => '登入已失效，請重新登入';
  @override
  String get signedOut => '未登入';
  @override
  String get guestCookie => '已填入 Cookie，但裡面沒有登入資訊';
  @override
  String get validUnknown => '已登入 · 有效期限未知';
  @override
  String validUntil({required Object end}) => '已登入 · 有效期限到 ${end}';
  @override
  String validUntilRenewable({required Object end}) => '已登入 · 有效期限到 ${end}，到期前可續期';
  @override
  String expiredRenewable({required Object end}) => '已在 ${end} 過期，可以續期';
  @override
  String get expired => '已過期，請重新登入';
  @override
  String signedInAs({required Object name}) => '已登入 · ${name}';
  @override
  String signedInAsWithUid({required Object name, required Object uid}) => '已登入 · ${name}（UID ${uid}）';
  @override
  String get verifying => '已登入 · 正在驗證';
  @override
  String get cookieExpired => 'Cookie 已失效，請重新登入';
  @override
  String verifyFailed({required Object reason}) => '已登入 · 驗證失敗：${reason}';
  @override
  String get cookieSaved => '已填入 Cookie';
  @override
  String signedInUid({required Object uid}) => '已登入 · UID ${uid}';
  @override
  String get storageNote => '登入資訊用本機的系統金鑰加密儲存，不會上傳，預設也不會寫進備份檔。';
  @override
  String qrFetchFailed({required Object reason}) => '取得 QR 碼失敗：${reason}';
  @override
  String qrPollFailed({required Object reason}) => '檢查掃描狀態失敗：${reason}';
  @override
  String get qrVerifyRejected => '登入驗證沒有通過，請重新整理 QR 碼再掃一次';
  @override
  String qrVerifyFailed({required Object reason}) => '登入驗證失敗：${reason}';
  @override
  String get qrLoading => '正在取得 QR 碼';
  @override
  String get qrWaiting => '用嗶哩嗶哩手機 App 掃描 QR 碼';
  @override
  String get qrScanned => '已掃描，請在手機上確認登入';
  @override
  String get qrExpired => 'QR 碼已過期';
  @override
  String get verifyingSignIn => '正在驗證登入';
  @override
  String signedInName({required Object name}) => '已登入：${name}';
  @override
  String get signInFailed => '登入失敗';
  @override
  String get qrLabel => '嗶哩嗶哩登入 QR 碼';
  @override
  String get qrRefresh => '重新整理 QR 碼';
  @override
  late final Translations$accounts$cookieTip$zh_Hant cookieTip = Translations$accounts$cookieTip$zh_Hant.internal(
    _root,
  );
  @override
  String get pasteCookieFirst => '請先貼上 Cookie';
  @override
  String get cookieSavedRejoin => '已儲存，重新進入直播間後生效';
  @override
  String get saveFailed => '儲存失敗，請重試';
  @override
  String get cookieHidden => '已儲存的 Cookie 不顯示；貼上新的會取代它';
  @override
  String get ltp0Label => 'LTP0（續期用）';
  @override
  String get keptIfEmpty => '已儲存；留空則維持不變';
  @override
  String get didLabel => 'dy_did（裝置識別碼）';
  @override
  String get nothingToSave => '沒有要儲存的內容';
  @override
  String get douyuKeysSaved => '已儲存續期用的 LTP0 和 dy_did';
  @override
  String get passportKept => '這是 passport 請求的 Cookie：已儲存 LTP0 和 dy_did，原本的登入保留';
  @override
  String get passportNeedsLogin => '這是 passport 請求的 Cookie：已儲存 LTP0 和 dy_did。還要貼上 www.douyu.com 頁面的 Cookie 才算登入';
  @override
  String get noLoginKept => '貼上的 Cookie 裡沒有登入資訊，原本的登入保留';
  @override
  String savedWith({required Object summary}) => '已儲存。${summary}';
  @override
  String get noDouyuCookie => '還沒有儲存鬥魚 Cookie';
  @override
  String get renewMissingKeys => '缺少 LTP0 或 dy_did，無法續期';
  @override
  String get renewNoLogin => 'Cookie 裡沒有登入資訊，無法續期';
  @override
  String get renewNoResult => '鬥魚沒有回傳新的登入資訊，續期沒有生效';
  @override
  String get renewed => '已續期';
  @override
  String renewedUntil({required Object end}) => '已續期，新的有效期限到 ${end}';
  @override
  String renewFailed({required Object reason}) => '續期失敗：${reason}';
  @override
  String signOutTitle({required Object name}) => '登出${name}帳號？';
  @override
  String get signOutBody => '會刪除本機儲存的登入資訊。';
  @override
  String get signOutBodyBrowser => '會刪除本機儲存的登入資訊，並清除內建瀏覽器裡的登入狀態。';
  @override
  String get signOut => '登出';
  @override
  String get signedOutToast => '已登出';
  @override
  String accountTitle({required Object name}) => '${name}帳號';
  @override
  String get verify => '驗證';
  @override
  String get renewNow => '立即續期';
  @override
  String get signOutAction => '登出';
  @override
  String get switchAccount => '換個帳號登入';
  @override
  String get signIn => '登入';
  @override
  String get signedInToast => '已登入';
  @override
  String get qrSignIn => '掃描 QR 碼登入';
  @override
  String get qrSignInSubtitle => '用嗶哩嗶哩手機 App 掃描';
  @override
  String get webSignIn => '網頁登入';
  @override
  String get webSignInSubtitle => '在內建網頁裡用帳號密碼或簡訊登入';
  @override
  String get manualCookie => '手動填入 Cookie';
  @override
  String get replaceCookie => '更換 Cookie';
  @override
  String get enterCookie => '填入 Cookie';
  @override
  String get storageNoteFull => '登入資訊用本機的系統金鑰加密儲存，不會上傳，介面和記錄裡都不顯示；預設也不寫進備份檔。';
  @override
  String get webReadFailed => '讀取登入資訊失敗，請重新登入';
  @override
  String get webNoCookie => '沒有取得登入資訊，請重新登入';
  @override
  String get webRejected => '登入驗證沒有通過，請重新登入';
  @override
  String webTitle({required Object name}) => '網頁登入 · ${name}';
  @override
  String get webUnavailable => '這裡無法使用網頁登入';
  @override
  String get webUnavailableHint => '請改用掃描 QR 碼登入或手動填入 Cookie。';
  @override
  String get reload => '重新載入';
}

// Path: alerts
class Translations$alerts$zh_Hant implements Translations$alerts$zh_Hans {
  Translations$alerts$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get notificationsDenied => '沒有通知權限，開播提醒維持關閉。可以在系統設定裡允許本應用程式的通知後再開啟';
  @override
  String get liveAlerts => '開播提醒';
  @override
  String get liveAlertsSubtitle => '追蹤的主播開播時傳送通知，應用程式在背景執行時按重新整理間隔檢查；可在追蹤頁對單一主播關閉';
  @override
  String get notificationsUnsupported => '這個系統不支援通知';
  @override
  String get enableAlertsFirst => '請先在 設定 › 一般 開啟開播提醒';
  @override
  String get roomAlertOff => '這個主播開播時不提醒';
  @override
  String get roomAlertOn => '開播時傳送通知';
  @override
  String get reminderSet => '已提醒';
  @override
  String get remindMe => '提醒我';
  @override
  String get cannotRemind => '無法提醒';
  @override
  String get reminderDenied => '沒有通知權限。可以在系統設定裡允許本應用程式的通知後再設定節目提醒。';
  @override
  String wentLive({required Object name}) => '${name} 開播了';
  @override
  String manyWentLive({required Object first, required Object n}) => '${first}等 ${n} 位主播開播了';
  @override
  String namesAndMore({required Object names}) => '${names} 等';
  @override
  String get liveChannelDescription => '追蹤的主播開播時提醒';
  @override
  String get programmeReminders => '節目提醒';
  @override
  String get programmeChannelDescription => '網路電視節目開始前 1 分鐘提醒';
  @override
  String programmeStarting({required Object title}) => '${title} 即將開始';
  @override
  String programmeBody({required Object channel, required Object time}) => '${channel} · ${time} 開始';
}

// Path: app
class Translations$app$zh_Hant implements Translations$app$zh_Hans {
  Translations$app$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get name => '純粹直播';
  @override
  String get previewName => '純粹直播 預覽版';
  @override
  late final Translations$app$tabs$zh_Hant tabs = Translations$app$tabs$zh_Hant.internal(_root);
  @override
  String get history => '觀看紀錄';
  @override
  String get recordings => '錄製中心';
  @override
  String get multiview => '多畫面';
  @override
  String get accounts => '平台帳號';
  @override
  String get backup => '備份與同步';
  @override
  String get settings => '設定';
  @override
  String get about => '關於';
  @override
  String get comingSoon => '預覽版尚未開放';
  @override
  String get appearance => '外觀';
  @override
  String get themeSystem => '跟隨系統';
  @override
  String get themeLight => '淺色';
  @override
  String get themeDark => '深色';
  @override
  String get themeBlack => '純黑';
  @override
  String get version => '版本';
  @override
  String get previewNotice => '這是 v4 預覽版，可以和 3.x 同時安裝。';
  @override
  String get offlineBanner => '網路已中斷，恢復後列表和播放會重新載入';
}

// Path: audience
class Translations$audience$zh_Hant implements Translations$audience$zh_Hans {
  Translations$audience$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  Map<String, String> get notes => {
    'bilibili': '列表和彈幕心跳給的是人氣值，本場累計觀看另計，都不是同時線上人數',
    'douyu': '公開列表的數字按熱度處理，不是真實人數',
    'huya': '列表、詳情和直播間裡的人數實測都是熱度，沒有單獨的線上人數',
    'douyin': '線上人數取自房間資料；累計觀看另計',
    'kuaishou': '目前觀看人數',
    'cc': '熱度和線上人數分開：webcc 熱度與 vision 線上人數',
    'yy': '公開的人數按平台熱度顯示，沒有單獨的線上人數',
    'soop': 'PC 和行動裝置的線上總人數',
    'acfun': '線上人數；按讚和粉絲數另計',
    'twitch': '目前同時觀看人數',
    'iptv': '網路電視沒有人數',
  };
}

// Path: backup
class Translations$backup$zh_Hant implements Translations$backup$zh_Hans {
  Translations$backup$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get exportTitle => '匯出備份';
  @override
  String passphraseTooShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '加密密碼至少 ${n} 個字元');
  @override
  String get passphraseMismatch => '兩次輸入的加密密碼不一樣';
  @override
  String get scopeFull => '完整備份';
  @override
  String get scopeFollows => '僅追蹤';
  @override
  String get scopeFullDetail => '追蹤、群組、紀錄、封鎖字詞、直播間偏好設定和設定';
  @override
  String get scopeFollowsDetail => '只有追蹤的直播間和追蹤的分區';
  @override
  String get includeAccounts => '包含平台登入資訊';
  @override
  String get includeAccountsDetail => 'Cookie 和 WebDAV 密碼會用加密密碼加密；匯入時要輸入同一個加密密碼';
  @override
  String get passphrase => '加密密碼';
  @override
  String get passphraseRepeat => '再輸入一次';
  @override
  String get passphraseRemember => '請記住這個加密密碼，忘記後帳號資訊將無法還原。';
  @override
  String get pickBackupFile => '選擇備份檔';
  @override
  String get saveBackup => '儲存備份';
  @override
  String get errorTooNew => '這個備份來自較新的版本，請先更新應用程式';
  @override
  String get errorFollowsOnly => '這是只含追蹤的備份，請使用「僅還原追蹤」';
  @override
  String get errorUnknownFile => '不是可以辨識的備份檔';
  @override
  String get errorBusy => '另一個還原正在進行，請稍後再試';
  @override
  String get confirmImport => '確認匯入';
  @override
  String get wrongPassphrase => '加密密碼不正確';
  @override
  String get skipAccountsQuestion => '平台登入資訊不會匯入。要繼續匯入其餘內容嗎？';
  @override
  String get continueImport => '繼續匯入';
  @override
  String get importDone => '匯入完成';
  @override
  String get restoreFull => '完整還原';
  @override
  String get restoreFollows => '僅還原追蹤';
  @override
  String get restoreFullDetail => '備份裡有的部分會取代本機的對應資料，備份裡沒有的部分維持不變。';
  @override
  String get restoreFollowsDetail => '只取代追蹤的直播間和追蹤的分區，其他資料不變。';
  @override
  String get encryptedAccountsHint => '備份裡有加密的平台登入資訊。輸入匯出時設定的加密密碼可以一併匯入，不填則略過。';
  @override
  String get passphraseOptional => '加密密碼（選填）';
  @override
  String get plainAccountsHint => '備份裡有平台登入資訊，會一併匯入，並在本機加密儲存。';
  @override
  late final Translations$backup$section$zh_Hant section = Translations$backup$section$zh_Hant.internal(_root);
  @override
  String format({required Object format}) => '備份格式：${format}';
  @override
  String get nothingToImport => '檔案裡沒有可以匯入的內容';
  @override
  String get accountsSkipped => '這次沒有匯入平台登入資訊。';
  @override
  String readCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '讀到 ${n} 項');
  @override
  String writtenCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '寫入 ${n} 項');
  @override
  String skippedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '，略過 ${n} 項');
  @override
  String sectionLine({required Object section, required Object counts}) => '${section}：${counts}';
  @override
  String get saved => '備份已儲存';
  @override
  String get localFiles => '本機檔案';
  @override
  String get exportSubtitle => '完整備份或僅追蹤；平台登入資訊預設不包含，需要時用加密密碼加密';
  @override
  String get restoreFollowsSubtitle => '支援 v4 和 3.x 的備份檔，只匯入追蹤和追蹤的分區';
  @override
  String get restoreFullSubtitle => '匯入備份裡的全部內容，備份裡沒有的部分維持不變';
  @override
  String get webdavSubtitle => '把備份上傳到堅果雲、Nextcloud、Synology 等雲端硬碟，在其他裝置上還原';
  @override
  String get lanSync => '區域網路同步';
  @override
  String get lanSyncSubtitle => '同一網路下的兩台裝置直接傳輸，接收方確認後才會匯入';
  @override
  String get backupAndRestore => '備份與還原';
  @override
  String get backupAndRestoreSubtitle => '匯出或匯入備份檔，支援 3.x 的備份';
  @override
  String get diagnostics => '診斷與記錄';
  @override
  String get diagnosticsSubtitle => '匯出診斷包，查看最近的記錄';
  @override
  String get crashReports => '當機報告';
  @override
  String get crashReportsSubtitle => '出錯後，下次啟動時提示匯出診斷包；不會自動上傳';
  @override
  String get clipboardRooms => '辨識剪貼簿裡的直播間';
  @override
  String get clipboardRoomsSubtitle => '回到應用程式時，辨識複製的分享碼或直播間連結並詢問是否開啟';
  @override
  String get okay => '好';
}

// Path: cast
class Translations$cast$zh_Hant implements Translations$cast$zh_Hans {
  Translations$cast$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get noAddressYet => '還沒有取得直播位址，等畫面出來後再投放';
  @override
  String get notHttp => '目前線路不是 http(s) 位址，電視無法開啟';
  @override
  String get invalidAddress => '目前線路的位址無效';
  @override
  String get localAddress => '目前線路是本機位址，電視無法存取';
  @override
  String get defaultTitle => '直播';
  @override
  late final Translations$cast$failure$zh_Hant failure = Translations$cast$failure$zh_Hant.internal(_root);
  @override
  late final Translations$cast$tv$zh_Hant tv = Translations$cast$tv$zh_Hant.internal(_root);
  @override
  String get stopNotDelivered => '停止指令沒有送達，電視可能還在播放';
  @override
  String get title => '投放';
  @override
  String get searchAgain => '重新搜尋';
  @override
  String get cannotCast => '目前位址無法投放';
  @override
  String get headersHint => '這個平台的直播串流可能需要特殊的請求標頭，電視上不一定能播放';
  @override
  String get expiresHint => '直播位址有時效，過期後電視會停止播放，重新投放即可';
  @override
  String failedWith({required Object reason}) => '投放失敗：${reason}';
  @override
  String get searching => '正在搜尋同一個 Wi-Fi 下的電視和盒子…';
  @override
  String get searchInterrupted => '搜尋中斷，清單可能不完整';
  @override
  String get searchFailed => '搜尋失敗';
  @override
  String get searchFailedHint => '檢查手機是否連著 Wi-Fi，然後重試';
  @override
  String get noDevices => '沒有找到可投放的裝置';
  @override
  String get noDevicesHint => '確認電視或盒子已開機、開啟了投放（DLNA）功能，並且和手機連著同一個 Wi-Fi';
  @override
  String get castingThisRoom => '正在投放這個直播間';
  @override
  String castingOther({required Object title}) => '正在投放：${title}';
  @override
  String castTo({required Object device}) => '已投放到 ${device}';
  @override
  String get stop => '停止投放';
}

// Path: common
class Translations$common$zh_Hant implements Translations$common$zh_Hans {
  Translations$common$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get retry => '重試';
  @override
  String get ok => '確定';
  @override
  String get cancel => '取消';
  @override
  String get save => '儲存';
  @override
  String get delete => '刪除';
  @override
  String get remove => '移除';
  @override
  String get undo => '復原';
  @override
  String get close => '關閉';
  @override
  String get refresh => '重新整理';
  @override
  String get more => '更多';
  @override
  String get copy => '複製';
  @override
  String get copied => '已複製';
  @override
  String get add => '新增';
  @override
  String get edit => '編輯';
  @override
  String get rename => '重新命名';
  @override
  String get import => '匯入';
  @override
  String get export => '匯出';
  @override
  String get send => '傳送';
  @override
  String get start => '開始';
  @override
  String get stop => '停止';
  @override
  String get play => '播放';
  @override
  String get pause => '暫停';
  @override
  String get resume => '繼續';
  @override
  String get back => '返回';
  @override
  String get gotIt => '知道了';
  @override
  String get clear => '清除';
  @override
  String get done => '完成';
  @override
  String get exit => '結束';
  @override
  String get all => '全部';
  @override
  String get sync => '同步';
  @override
  String get paste => '貼上';
  @override
  String get name => '名稱';
  @override
  String get username => '使用者名稱';
  @override
  String get password => '密碼';
  @override
  String get loadFailed => '讀取失敗';
  @override
  String get loadMoreFailed => '載入失敗，點一下重試';
  @override
  String get noMore => '沒有更多了';
  @override
  String get noRooms => '這裡還沒有直播間';
  @override
  String get openRoom => '開啟直播間';
  @override
  String get follow => '追蹤';
  @override
  String get followed => '已追蹤';
  @override
  String get unfollow => '取消追蹤';
  @override
  String get openSite => '開啟原網站';
  @override
  String get copyLink => '複製連結';
  @override
  String get linkCopied => '已複製連結';
  @override
  String get offline => '未開播';
  @override
  String get replay => '重播中';
  @override
  String get unsupported => '暫不支援';
  @override
  String get couldNotOpenLink => '無法開啟連結';
  @override
  String get couldNotOpenWindow => '無法開啟新視窗';
  @override
  String seconds({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 秒');
  @override
  String minutes({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分鐘');
  @override
  String items({required Object n}) => '${n} 則';
  @override
  String get unlimited => '不限';
  @override
  String get auto => '自動';
  @override
  String get on => '開啟';
  @override
  String get off => '關閉';
  @override
  String get listSeparator => '、';
  @override
  String error({required Object error}) => '操作失敗：${error}';
  @override
  String monthDay({required Object month, required Object day}) => '${month}月${day}日';
}

// Path: danmaku
class Translations$danmaku$zh_Hant implements Translations$danmaku$zh_Hans {
  Translations$danmaku$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get blockListTitle => '封鎖字詞和封鎖使用者';
  @override
  String get blockKeywords => '關鍵字';
  @override
  String get blockUsers => '使用者';
  @override
  String alreadyBlocked({required Object value}) => '「${value}」已經在清單裡';
  @override
  String unblocked({required Object value}) => '已移除「${value}」';
  @override
  String get keywordHint => '輸入要封鎖的字詞';
  @override
  String get userHint => '輸入要封鎖的使用者名稱';
  @override
  String get keywordHelper => '包含這個字詞的彈幕不顯示';
  @override
  String get userHelper => '按使用者名稱完全比對';
  @override
  String get blockListLoadFailed => '讀取封鎖清單失敗';
  @override
  String get noBlockedKeywords => '還沒有封鎖字詞';
  @override
  String get noBlockedUsers => '還沒有封鎖使用者';
  @override
  String get blockFromRoomHint => '也可以在直播間裡點一則彈幕來封鎖';
  @override
  String get blockKeyword => '封鎖關鍵字';
  @override
  String get blockUser => '封鎖使用者';
  @override
  String keywordBlocked({required Object keyword}) => '已封鎖關鍵字「${keyword}」';
  @override
  String userBlocked({required Object user}) => '已封鎖使用者「${user}」';
  @override
  String get blockKeywordHint => '包含這個字詞的彈幕都會被隱藏';
  @override
  String get caseInsensitive => '不區分大小寫';
  @override
  String get block => '封鎖';
  @override
  String get off => '彈幕已關閉';
  @override
  String get offHint => '開啟後會連線彈幕，並在畫面上顯示';
  @override
  String get turnOn => '開啟彈幕';
  @override
  String get offlineNoDanmaku => '未開播時沒有彈幕';
  @override
  String get localHint => '發一則本機彈幕';
  @override
  String get localSend => '傳送（只在本機顯示）';
  @override
  String get reconnect => '重新連線';
  @override
  String get settings => '彈幕設定';
  @override
  String newMessages({required Object n}) => '新訊息 ${n}';
  @override
  String get jumpToLatest => '回到最新';
  @override
  late final Translations$danmaku$preset$zh_Hant preset = Translations$danmaku$preset$zh_Hant.internal(_root);
  @override
  String get show => '顯示彈幕';
  @override
  String get showSubtitle => '關閉後不再連線彈幕';
  @override
  String get style => '樣式';
  @override
  String get fontSize => '字體大小';
  @override
  String get fontWeight => '字重';
  @override
  String get opacity => '不透明度';
  @override
  String get speedHint => '速度（越大越快）';
  @override
  String get area => '顯示區域';
  @override
  String get topMargin => '頂部留白';
  @override
  String get bottomMargin => '底部留白';
  @override
  String get stroke => '描邊';
  @override
  String get strokeWidth => '描邊粗細';
  @override
  String get hideEmoji => '隱藏表情';
  @override
  String get hideEmojiSubtitle => '只有表情的彈幕不顯示';
  @override
  String get autoFps => '自動影格率';
  @override
  String get autoFpsSubtitle => '跟隨「一般 › 重新整理率」';
  @override
  String get fps => '影格率';
  @override
  String get videoTaps => '畫面彈幕的點擊';
  @override
  String get tapDanmaku => '點一下彈幕';
  @override
  String get opensActions => '開啟複製和封鎖';
  @override
  String get longPressDanmaku => '長按彈幕';
  @override
  String get filters => '過濾';
  @override
  String get collapseRepeated => '合併重複彈幕';
  @override
  String get collapseWindow => '合併時間範圍';
  @override
  String get filterSimilar => '過濾相似彈幕';
  @override
  String get filterSimilarSubtitle => '熱門房間裡的短彈幕可能被過濾';
  @override
  String get similarityThreshold => '相似度門檻';
  @override
  String get compareRecent => '比較最近';
  @override
  String get compareMost => '最多比較';
  @override
  String get douyuBots => '過濾鬥魚疑似機器人彈幕';
  @override
  String get douyuBotsSubtitle => '預設關閉，可能誤擋正常彈幕';
  @override
  String presetApplied({required Object name}) => '已套用「${name}」';
  @override
  String get saveMyStyle => '儲存為我的樣式';
  @override
  String get styleSaved => '已儲存目前的彈幕樣式';
  @override
  String get restoreMyStyle => '還原我的樣式';
  @override
  String get styleRestored => '已還原儲存的彈幕樣式';
  @override
  String get styleBroken => '儲存的樣式已損壞，無法還原';
  @override
  String get pip => '子母畫面彈幕';
  @override
  String get pipShow => '在子母畫面裡顯示彈幕';
  @override
  String get speed => '速度';
  @override
  String get maxOnScreen => '同一畫面最多';
  @override
  String get noEmoji => '不顯示表情';
  @override
  String get connecting => '正在連線彈幕…';
  @override
  String get reconnecting => '彈幕連線中斷，正在重新連線…';
  @override
  String get disconnected => '彈幕已中斷';
  @override
  String get unsupported => '這個平台暫不支援彈幕';
  @override
  String get replayMode => '正在播放錄影，彈幕來自錄影';
  @override
  String get bilibiliGuest => '未登入 B 站帳號，觀眾暱稱會被平台隱藏';
  @override
  String get timeout => '彈幕連線逾時';
  @override
  String get noCredentials => '彈幕連線失敗：取不到平台憑證';
  @override
  String get rejected => '彈幕連線被平台拒絕';
  @override
  String get retriesFailed => '彈幕多次重新連線都失敗';
  @override
  late final Translations$danmaku$audience$zh_Hant audience = Translations$danmaku$audience$zh_Hant.internal(_root);
  @override
  String giftMany({required Object gift, required Object count}) => '送出 ${gift} ×${count}';
  @override
  String gift({required Object gift}) => '送出 ${gift}';
  @override
  String get localSender => '我';
  @override
  String chatName({required Object name}) => '${name}：';
}

// Path: diagnostics
class Translations$diagnostics$zh_Hant implements Translations$diagnostics$zh_Hans {
  Translations$diagnostics$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get saveBundle => '儲存診斷包';
  @override
  String get bundleSaved => '診斷包已儲存';
  @override
  String exportFailed({required Object error}) => '匯出失敗：${error}';
  @override
  String get exportBundle => '匯出診斷包';
  @override
  String get exportBundleSubtitle => '版本、裝置資訊、設定和最近的記錄，儲存為一個 JSON 檔案；不含 Cookie、密碼等帳號資訊';
  @override
  String get crashReportsSubtitle => '出錯後，下次啟動時提示匯出診斷包。不會自動上傳任何資料';
  @override
  String get recentLogs => '最近的記錄';
  @override
  String get recentLogsSubtitle => '只儲存在本機，最多約 768 KB，Cookie 和權杖寫入前已去除';
  @override
  String get noLogs => '這次執行還沒有記錄';
}

// Path: discover
class Translations$discover$zh_Hant implements Translations$discover$zh_Hans {
  Translations$discover$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get unfollowArea => '取消收藏分區';
  @override
  String get followArea => '收藏分區';
  @override
  String get areaGone => '分區資訊已失效';
  @override
  String get savedAreas => '已收藏';
  @override
  String get recommended => '推薦';
  @override
  String get areas => '分區';
}

// Path: errors
class Translations$errors$zh_Hant implements Translations$errors$zh_Hans {
  Translations$errors$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get channelMissing => '頻道不存在';
  @override
  String get channelMissingDetail => '播放清單裡已經沒有這個頻道，可能改名或被刪除了。';
  @override
  String get roomMissing => '直播間不存在';
  @override
  String get roomMissingDetail => '房間號碼可能已經失效，或是主播換了房間。';
  @override
  String get needsLogin => '需要登入';
  @override
  String get needsLoginDetail => '這個內容要登入平台帳號後才能看，可以在「我的 → 平台帳號」裡登入。';
  @override
  String get rateLimited => '請求太頻繁';
  @override
  String get rateLimitedDetail => '平台限制了存取頻率，等一下再試。';
  @override
  String get riskControl => '被平台風控攔截';
  @override
  String get riskControlDetail => '平台暫時拒絕了請求，稍後重試，或換個網路。';
  @override
  String get regionBlocked => '目前地區無法觀看';
  @override
  String get regionBlockedDetail => '平台限制了這個地區的存取，可以在設定裡為這個平台設定 Proxy。';
  @override
  String get noStream => '拿不到直播串流';
  @override
  String get noStreamDetail => '平台暫時沒有提供可以播放的線路，稍後再試。';
  @override
  String get unsupportedLink => '不支援這個連結';
  @override
  String get unsupportedLinkDetail => '目前支援鬥魚、虎牙、嗶哩嗶哩、抖音和快手的直播間連結。';
  @override
  String get apiChanged => '平台介面變了';
  @override
  String get apiChangedDetail => '需要更新應用程式才能繼續使用這個平台。';
  @override
  String get network => '網路連線失敗';
  @override
  String get networkDetail => '檢查網路或 Proxy 設定後重試。';
  @override
  String get platformUnsupported => '平台暫不支援';
  @override
  String platformUnsupportedDetail({required Object name}) => '${name}已下線或這個版本還不支援，追蹤和觀看紀錄會一直保留。';
  @override
  String get generic => '發生錯誤';
}

// Path: follows
class Translations$follows$zh_Hant implements Translations$follows$zh_Hans {
  Translations$follows$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get followFailed => '追蹤失敗，沒有儲存，請重試';
  @override
  String get unfollowFailed => '取消追蹤失敗，追蹤還在，請重試';
  @override
  String unfollowed({required Object name}) => '已取消追蹤 ${name}';
  @override
  String get undoFailed => '復原失敗，無法恢復追蹤';
  @override
  String get emptyTitle => '還沒有追蹤的主播';
  @override
  String get emptyMessage => '在探索或搜尋裡找到主播，進入直播間後點「追蹤」。';
  @override
  String get goDiscover => '去探索';
  @override
  String get orderNotSaved => '順序沒有儲存，請重試';
  @override
  String get reorder => '調整順序';
  @override
  late final Translations$follows$sort$zh_Hant sort = Translations$follows$sort$zh_Hant.internal(_root);
  @override
  String get sortTooltip => '排序';
  @override
  String get editCustomOrder => '調整自訂順序';
  @override
  String get openMultiview => '一鍵多畫面';
  @override
  String get refreshStatus => '重新整理開播狀態';
  @override
  String get loadFailed => '讀取追蹤失敗';
  @override
  String get liveFollows => '開播的追蹤';
  @override
  String platformRetired({required Object name}) => '${name}已下線或這個版本還不支援，追蹤會一直保留';
  @override
  String lastLive({required Object ago}) => '上次開播 ${ago}';
  @override
  late final Translations$follows$tag$zh_Hant tag = Translations$follows$tag$zh_Hant.internal(_root);
  @override
  String unsupportedPlatform({required Object name}) => '${name} · 暫不支援';
  @override
  String get unknownDetail => '無法取得開播狀態';
  @override
  String get missingDetail => '平台找不到這個房間';
  @override
  String get replayDetail => '正在輪播';
  @override
  String get checking => '正在檢查開播狀態';
  @override
  String refreshFailed({required Object platforms}) => '${platforms} 重新整理失敗，這些主播的狀態暫時未知';
  @override
  late final Translations$follows$filter$zh_Hant filter = Translations$follows$filter$zh_Hant.internal(_root);
  @override
  String get manageGroups => '管理群組';
  @override
  String get noneLive => '追蹤的主播都沒開播';
  @override
  String allCount({required Object n}) => '全部追蹤 ${n}';
  @override
  String offlineCount({required Object n}) => '未開播 ${n}';
  @override
  String get ungrouped => '未分組';
  @override
  String get noGroups => '還沒有群組';
  @override
  String get noGroupsHint => '在「管理群組」新增群組，再從主播的更多選單裡設定群組';
  @override
  String get groupEmpty => '這個群組還沒有主播';
  @override
  String get newGroup => '新增群組';
  @override
  String get groupName => '群組名稱';
  @override
  String get groupDescription => '描述（選填）';
  @override
  String get groupDescriptionHint => '例如：晚上常看的';
  @override
  String groupExists({required Object name}) => '已經有叫「${name}」的群組了';
  @override
  String get groupNameEmpty => '群組名稱不能是空的';
  @override
  String get editGroup => '編輯群組';
  @override
  String get groupNotSaved => '群組沒有儲存，請重試';
  @override
  String setGroupsFor({required Object title}) => '設定群組 · ${title}';
  @override
  String get groupsHint => '群組可以把追蹤的主播分類，在追蹤頁按群組查看。';
  @override
  String get renameAndDescribe => '重新命名和描述';
  @override
  String groupDeleted({required Object name}) => '已刪除群組「${name}」';
}

// Path: fonts
class Translations$fonts$zh_Hant implements Translations$fonts$zh_Hans {
  Translations$fonts$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String downloadFailed({required Object font}) => '「${font}」下載失敗，檢查網路或 Proxy 後重試';
  @override
  String downloaded({required Object name}) => '「${name}」已下載';
  @override
  String deleted({required Object name}) => '已刪除「${name}」，重新啟動後不再佔用記憶體';
  @override
  String get title => '字型';
  @override
  String get listFailed => '讀不到字型清單';
  @override
  String get systemFont => '系統字型';
  @override
  String get inUse => '使用中';
  @override
  String get appFont => '介面字型';
  @override
  String get danmakuFont => '彈幕字型';
  @override
  String get resetAppFont => '介面改回系統字型';
  @override
  String get resetDanmakuFont => '彈幕改回系統字型';
  @override
  String get downloadable => '可下載的字型';
  @override
  String get downloadableNote => '只列出允許自由使用和散布的字型（SIL OFL 1.1、IPA 字型授權）。字型檔案較大，建議在 Wi-Fi 下下載。';
  @override
  String get useInterface => '介面';
  @override
  String get useDanmaku => '彈幕';
  @override
  String usedFor({required Object uses}) => '用於${uses}';
  @override
  String get and => '和';
  @override
  String get download => '下載';
  @override
  String get use => '使用';
  @override
  String get useForInterface => '用作介面字型';
  @override
  String get useForDanmaku => '用作彈幕字型';
}

// Path: health
class Translations$health$zh_Hant implements Translations$health$zh_Hans {
  Translations$health$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get imageCacheCleared => '圖片快取已清除';
  @override
  String get clearImageCache => '清除圖片快取';
  @override
  String get calculating => '正在計算';
  @override
  String imageCacheSize({required Object size}) => '封面和頭像快取 ${size} MB；追蹤、紀錄和錄製不受影響';
  @override
  String get timeout => '15 秒內沒有回應';
  @override
  String get checkAgain => '重新檢查';
  @override
  String get checkingAll => '正在檢查各平台';
  @override
  String get checkFailed => '檢查失敗';
  @override
  String ok({required Object ms}) => '正常 · ${ms} ms';
  @override
  String get failed => '異常';
  @override
  String get method => '檢查方式：請求各平台的分區清單。某個平台異常時，追蹤頁和探索頁會顯示上次的內容，直播間可能打不開。';
}

// Path: iptv
class Translations$iptv$zh_Hant implements Translations$iptv$zh_Hans {
  Translations$iptv$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get notSynced => '未同步';
  @override
  String get syncedJustNow => '剛剛同步';
  @override
  String syncedMinutesAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分鐘前同步');
  @override
  String syncedHoursAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 小時前同步');
  @override
  String syncedAt({required Object date, required Object time}) => '${date} ${time} 同步';
  @override
  String get url => '網址';
  @override
  String get nameOptional => '名稱（選填）';
  @override
  String guideSummary({required Object channels, required Object programmes}) => '${channels} 個頻道，${programmes} 個節目';
  @override
  String get addGuide => '新增節目表';
  @override
  String guideAdded({required Object summary}) => '已新增：${summary}';
  @override
  String get pickGuide => '選擇節目表（XMLTV、JSON，可以是 .gz）';
  @override
  String guideSynced({required Object summary}) => '已同步：${summary}';
  @override
  String get sourceCopied => '已複製來源位址';
  @override
  String get deleteGuide => '刪除節目表';
  @override
  String deleteGuideConfirm({required Object name}) => '刪除「${name}」和它的節目？';
  @override
  String get guide => '節目表';
  @override
  String get guideHint => '選一個節目表作為目前的節目表；頻道會按 tvg-id 和名稱自動比對。節目表只保留前後兩天的節目。';
  @override
  String get guideSources => '節目表來源';
  @override
  String get noGuide => '不使用節目表';
  @override
  String get noGuides => '還沒有節目表';
  @override
  String get guideFormats => '支援 XMLTV（.xml、.xml.gz）和 JSON 節目表';
  @override
  String get playlistGuide => '播放清單提供的節目表';
  @override
  String get addFromUrl => '從網址新增';
  @override
  String get addFromFile => '從檔案新增';
  @override
  String channelsAndSynced({required num n, required Object synced}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 個頻道 · ${synced}');
  @override
  String lastSyncFailed({required Object error}) => '上次同步失敗：${error}';
  @override
  String get autoSync => '自動同步';
  @override
  String get copySource => '複製來源位址';
  @override
  String get noPlaylists => '還沒有播放清單';
  @override
  String get noPlaylistsHint => '匯入 M3U、TXT 或 JSON 播放清單後，頻道會按群組出現在這裡，可以像直播間一樣追蹤。';
  @override
  String get importPlaylist => '匯入播放清單';
  @override
  String get allChannels => '全部頻道';
  @override
  String get groups => '群組';
  @override
  String get ungrouped => '未分組';
  @override
  String get managePlaylists => '管理播放清單';
  @override
  String get noChannels => '播放清單裡還沒有頻道';
  @override
  String get playlistNotSynced => '這個播放清單還沒有同步';
  @override
  String importSummary({required Object name, required Object channels, required Object lines}) =>
      '「${name}」：${channels} 個頻道，${lines} 條線路';
  @override
  String importSummarySkipped({
    required Object name,
    required Object channels,
    required Object lines,
    required Object skipped,
  }) => '「${name}」：${channels} 個頻道，${lines} 條線路，略過 ${skipped} 行';
  @override
  String get importFromUrl => '從網址匯入';
  @override
  String imported({required Object summary}) => '已匯入${summary}';
  @override
  String signedInAndImported({required Object summary}) => '已登入並匯入${summary}';
  @override
  String get pickPlaylist => '選擇播放清單（M3U、TXT、JSON）';
  @override
  String get sharedFileName => '分享的播放清單.m3u';
  @override
  String get importShared => '匯入分享的播放清單';
  @override
  String get allSynced => '全部同步完成';
  @override
  String syncedWithFailures({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '同步完成，${n} 個來源失敗');
  @override
  String syncedPlaylist({required Object summary}) => '已同步${summary}';
  @override
  String get playlistUserAgent => '這個清單的 User-Agent';
  @override
  String get userAgentEmpty => '留空則使用全域設定';
  @override
  String get playlistUserAgentHint => '下載清單和播放頻道時傳送；頻道自己指定的優先';
  @override
  String get deletePlaylist => '刪除播放清單';
  @override
  String deletePlaylistConfirm({required num n, required Object name}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '刪除「${name}」和它的 ${n} 個頻道？追蹤的頻道會保留，但會顯示「頻道不存在」。',
      );
  @override
  String get title => '網路電視';
  @override
  String get syncAll => '全部同步';
  @override
  String get playlists => '播放清單';
  @override
  String get playlistsHint => '從檔案或網址匯入 M3U、TXT、JSON 播放清單，頻道會出現在「探索 › 網路電視」裡';
  @override
  String get playlistsLoadFailed => '讀取播放清單失敗';
  @override
  String get importFromFile => '從檔案匯入';
  @override
  String get xtreamAccount => 'Xtream 帳號';
  @override
  String get noGuideAdded => '未新增，匯入 XMLTV 或 JSON 節目表後可以看節目和回看';
  @override
  String get noGuideSelected => '未選擇';
  @override
  String currentGuide({required Object name}) => '目前：${name}';
  @override
  String get autoSyncHint => '啟動 3 秒後同步到期的網址清單和節目表';
  @override
  String get syncInterval => '同步間隔';
  @override
  String get every6h => '每 6 小時';
  @override
  String get every12h => '每 12 小時';
  @override
  String get daily => '每天';
  @override
  String get every2d => '每 2 天';
  @override
  String get every3d => '每 3 天';
  @override
  String get weekly => '每週';
  @override
  String get customUserAgent => '自訂 User-Agent';
  @override
  String get userAgentUnset => '未設定（使用播放器預設值）';
  @override
  String get userAgentExample => '例如 okhttp/4.12.0';
  @override
  String get userAgentHint => '下載清單、節目表和播放頻道時傳送；清單或頻道自己指定的優先';
  @override
  String get notSyncedHint => '未同步，點「同步」取得頻道';
  @override
  String get noAutoSync => '不參與自動同步';
  @override
  String get xtreamHint => '填寫伺服器位址（例如 http://example.com:8080）、使用者名稱和密碼';
  @override
  String get xtreamSignIn => '登入 Xtream 帳號';
  @override
  String get serverAddress => '伺服器位址';
  @override
  String get showPassword => '顯示密碼';
  @override
  String get hidePassword => '隱藏密碼';
  @override
  String get xtreamStorageNote => '使用者名稱和密碼只加密儲存在本機，備份和同步裡不含明文。';
  @override
  String get signInAndImport => '登入並匯入';
  @override
  String get backToLive => '已回到直播';
  @override
  String get backToLiveFailed => '回到直播失敗，可以點畫面上的重試';
  @override
  String get notStarted => '節目還沒開始';
  @override
  String catchingUp({required Object title}) => '正在回看：${title}';
  @override
  String get noCatchUp => '這個節目無法回看';
  @override
  String get channelNoCatchUp => '這個頻道沒有開放回看';
  @override
  String get outOfCatchUpWindow => '超出回看的時間範圍';
  @override
  String get onAir => '正在播出';
  @override
  String get catchUp => '回看中';
  @override
  String lines({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 條線路');
  @override
  String upNext({required Object time, required Object title}) => '接下來 ${time} ${title}';
  @override
  String get loadingGuide => '正在讀取節目表…';
  @override
  String get noGuideMatch => '沒有比對到節目表：新增或更換節目表來源後會自動比對';
  @override
  String get noProgrammeNow => '節目表裡暫時沒有這個時段的節目';
  @override
  String get returnToLive => '回到直播';
  @override
  String get today => '今天';
  @override
  String get yesterday => '昨天';
  @override
  String get dayBeforeYesterday => '前天';
  @override
  String get tomorrow => '明天';
  @override
  String dayWithDate({required Object label, required Object date}) => '${label} ${date}';
  @override
  String get guideLoadFailed => '讀取節目表失敗';
  @override
  String get noProgrammes => '沒有節目';
  @override
  String get noProgrammesHint => '節目表裡沒有這個頻道前後兩天的節目。';
  @override
  String get noCatchUpTag => '不可回看';
  @override
  late final Translations$iptv$error$zh_Hant error = Translations$iptv$error$zh_Hant.internal(_root);
  @override
  String xtreamGuideName({required Object title}) => '${title} 節目表';
  @override
  String get defaultPlaylistName => '播放清單';
  @override
  late final Translations$iptv$xtream$zh_Hant xtream = Translations$iptv$xtream$zh_Hant.internal(_root);
}

// Path: me
class Translations$me$zh_Hant implements Translations$me$zh_Hans {
  Translations$me$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get pureBlackSubtitle => '深色時使用純黑背景，適合 OLED 螢幕';
  @override
  String get denseFollows => '追蹤頁緊湊卡片';
  @override
  String get denseFollowsSubtitle => '主播名稱和標題放在同一行，一個畫面顯示更多直播間';
  @override
  String get historyCleared => '已清除觀看紀錄';
  @override
  String get noHistory => '還沒有觀看紀錄';
  @override
  String get iptvSubtitle => 'IPTV 播放清單、節目表和自動同步';
  @override
  String get backupSubtitle => '備份檔、WebDAV、區域網路同步；可以匯入 3.x 的備份';
  @override
  String aboutSubtitle({required Object version}) => '版本 ${version} · 更新、開放原始碼授權';
}

// Path: multiview
class Translations$multiview$zh_Hant implements Translations$multiview$zh_Hans {
  Translations$multiview$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get addRoom => '新增直播間';
  @override
  String offlineCell({required Object name}) => '${name} 未開播\n點這裡換一個';
  @override
  String get interrupted => '播放中斷';
  @override
  String get danmakuOff => '關閉彈幕';
  @override
  String get danmakuOn => '開啟彈幕';
  @override
  String get quality => '畫質';
  @override
  String get line => '線路';
  @override
  String get volume => '音量';
  @override
  String get exitFullscreen => '結束全螢幕';
  @override
  String get fullscreen => '全螢幕';
  @override
  String get onePlusN => '一大多小';
  @override
  String get immersive => '沉浸模式';
  @override
  String get exitImmersive => '結束沉浸模式';
  @override
  String get layout => '版面配置';
  @override
  String get addCell => '新增畫面';
  @override
  String capacityReached({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '已達上限：本裝置最多同時播放 ${n} 路');
  @override
  String capacityHint({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '本裝置最多同時播放 ${n} 路畫面，先關掉一格再新增');
  @override
  String get unmuteAll => '取消全部靜音';
  @override
  String get muteAll => '全部靜音';
  @override
  String get selectedVolume => '所選畫面音量';
  @override
  String pickRoomFor({required Object n}) => '選擇直播間 · 放到第 ${n} 格';
  @override
  String get filterHint => '按主播名稱或標題篩選';
  @override
  String get pickTarget => '放到這裡';
  @override
  String cell({required Object n}) => '第 ${n} 格';
  @override
  String get switchRoom => '換房';
  @override
  String lineN({required Object n}) => '線路 ${n}';
  @override
  String get cellIdle => '這一格沒有在播放';
  @override
  String get allMutedHint => '已全部靜音；音量按直播間儲存，取消靜音後生效';
  @override
  String get volumePerRoom => '音量按直播間儲存';
  @override
  String get volumeNotSource => '音量按直播間儲存；這一格成為聲音來源後生效';
}

// Path: onboarding
class Translations$onboarding$zh_Hant implements Translations$onboarding$zh_Hans {
  Translations$onboarding$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String welcome({required Object app}) => '歡迎使用${app} v4';
  @override
  String get intro => '預覽版是另外安裝的，讀不到 3.x 裡的資料。可以把 3.x 或其他裝置上的追蹤和設定匯入進來，也可以直接開始。';
  @override
  String get fromFile => '從備份檔匯入';
  @override
  String get fromFileSubtitle => '3.x 的「備份與還原」匯出的檔案，或 v4 的備份檔';
  @override
  String get fromWebdav => '從 WebDAV 匯入';
  @override
  String get fromWebdavSubtitle => '之前上傳到堅果雲、Nextcloud 等雲端硬碟的備份';
  @override
  String get fromDevice => '從另一台裝置匯入';
  @override
  String get fromDeviceSubtitle => '在同一網路下，由另一台裝置透過區域網路同步傳送過來';
  @override
  String get skip => '略過，直接開始';
  @override
  String get laterHint => '之後可以在 我的 › 備份與同步 裡隨時匯入。';
  @override
  String get crashPrompt => '上次執行時發生了錯誤。匯出診斷包附在問題回報裡，可以協助找出原因';
}

// Path: quality
class Translations$quality$zh_Hant implements Translations$quality$zh_Hans {
  Translations$quality$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get original => '原畫';
  @override
  String get bluRay8M => '藍光 8M';
  @override
  String get bluRay4M => '藍光 4M';
  @override
  String get superHigh => '超高畫質';
  @override
  String get smooth => '流暢';
}

// Path: recording
class Translations$recording$zh_Hant implements Translations$recording$zh_Hans {
  Translations$recording$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  late final Translations$recording$notice$zh_Hant notice = Translations$recording$notice$zh_Hant.internal(_root);
  @override
  String get cancelSchedule => '取消預約錄製';
  @override
  String get schedule => '預約錄製';
  @override
  late final Translations$recording$state$zh_Hant state = Translations$recording$state$zh_Hant.internal(_root);
  @override
  late final Translations$recording$failure$zh_Hant failure = Translations$recording$failure$zh_Hant.internal(_root);
  @override
  late final Translations$recording$stage$zh_Hant stage = Translations$recording$stage$zh_Hant.internal(_root);
  @override
  String get stopTitle => '停止錄製';
  @override
  String stopConfirm({required Object name}) => '停止錄製「${name}」？已錄的部分會儲存。';
  @override
  String get removeWatch => '移除監控';
  @override
  String removeWatchConfirm({required Object name}) => '不再等待「${name}」開播？已錄的檔案會保留。';
  @override
  String get deleteTask => '刪除錄製任務';
  @override
  String deleteTaskRunning({required Object name}) => '刪除「${name}」的錄製任務？正在進行的錄製會先停止，已錄的檔案會保留。';
  @override
  String deleteTaskConfirm({required Object name}) => '刪除「${name}」的錄製任務？已錄的檔案會保留。';
  @override
  String get recordFromRoomHint => '也可以在直播間裡點錄製按鈕。';
  @override
  String get pickFromFollows => '從追蹤裡選擇';
  @override
  String get settings => '錄製設定';
  @override
  String get add => '新增錄製';
  @override
  String get noTasks => '還沒有錄製任務';
  @override
  String get noTasksHint => '在直播間點錄製，或從追蹤裡新增。開啟開播監控後，主播開播會自動開始錄製。';
  @override
  String get scheduled => '定時錄製';
  @override
  String get tasks => '錄製任務';
  @override
  String folderCopied({required Object path}) => '已複製資料夾路徑：${path}';
  @override
  String gaps({required Object n}) => '缺口 ${n}';
  @override
  String problemWithStage({required Object problem, required Object stage}) => '${problem} · 出錯環節：${stage}';
  @override
  String nextCheck({required Object time}) => '下次檢查 ${time}';
  @override
  String get stopWatch => '停止監控';
  @override
  String get cancelQueue => '取消排隊';
  @override
  String get start => '開始錄製';
  @override
  String get restart => '重新錄製';
  @override
  String get checkNow => '立即檢查開播';
  @override
  String get forceStart => '強制開始';
  @override
  String get retryRemux => '重試轉封裝';
  @override
  String get openFolder => '開啟資料夾';
  @override
  String get deleteKeepFiles => '刪除任務（保留檔案）';
  @override
  String get cancelScheduled => '取消定時錄製';
}

// Path: room
class Translations$room$zh_Hant implements Translations$room$zh_Hans {
  Translations$room$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  late final Translations$room$failure$zh_Hant failure = Translations$room$failure$zh_Hant.internal(_root);
  @override
  String autoLowered({required Object quality}) => '網路不穩，已切換到${quality}，可以在畫質裡換回來';
  @override
  String get audioOnlyFailed => '切換純音訊失敗，已恢復畫面';
  @override
  String get restoreVideoFailed => '恢復畫面失敗，仍為純音訊';
  @override
  String volumeHint({required Object percent}) => '音量 ${percent}%';
  @override
  String get danmakuShown => '彈幕已開啟';
  @override
  String get danmakuHidden => '彈幕已關閉';
  @override
  String get pipNeedsVideo => '畫面出來後才能進入子母畫面';
  @override
  String get noApp => '找不到對應的 App，改用瀏覽器開啟';
  @override
  String brightnessHint({required Object percent}) => '亮度 ${percent}%';
  @override
  late final Translations$room$fit$zh_Hant fit = Translations$room$fit$zh_Hant.internal(_root);
  @override
  String get noFrameToCapture => '目前沒有畫面可以截圖';
  @override
  String screenshotSaved({required Object path}) => '截圖已儲存：${path}';
  @override
  String screenshotFailed({required Object error}) => '截圖失敗：${error}';
  @override
  late final Translations$room$sleep$zh_Hant sleep = Translations$room$sleep$zh_Hant.internal(_root);
  @override
  String get resumePlayback => '繼續播放';
  @override
  String get lineFailedMany => '目前線路出錯，可以重試或換線路';
  @override
  String get lineFailedOne => '可以稍後重試';
  @override
  String get switchLine => '換線路';
  @override
  String get unlock => '解鎖';
  @override
  String get lock => '鎖定';
  @override
  String get switchRoom => '切換直播間';
  @override
  String get hideChat => '收起聊天';
  @override
  String get chat => '聊天';
  @override
  String get restoreVideo => '恢復畫面';
  @override
  String get audioOnly => '純音訊';
  @override
  String get cast => '投放';
  @override
  String get danmakuOnKey => '開啟彈幕 (D)';
  @override
  String get danmakuOffKey => '關閉彈幕 (D)';
  @override
  String get unmuteKey => '取消靜音 (M)';
  @override
  String get muteKey => '靜音 (M)';
  @override
  String get showWholePicture => '完整顯示畫面';
  @override
  String get fillScreen => '填滿螢幕';
  @override
  String get orientation => '畫面方向';
  @override
  String get orientationAuto => '自動辨識';
  @override
  String get orientationPortrait => '當作直向';
  @override
  String get orientationLandscape => '當作橫向';
  @override
  String get aspect => '畫面比例';
  @override
  String get exitTheaterKey => '結束劇院模式 (T)';
  @override
  String get theaterKey => '劇院模式 (T)';
  @override
  String get hideChatKey => '收起聊天欄 (C)';
  @override
  String get showChatKey => '顯示聊天欄 (C)';
  @override
  String get pipKey => '子母畫面 (P)';
  @override
  String get exitFullscreenKey => '結束全螢幕 (F)';
  @override
  String get fullscreenKey => '全螢幕 (F)';
  @override
  String get audioOnlyPlaying => '純音訊播放中';
  @override
  String get enableMonitoringFirst => '要先在錄製設定裡開啟「定時檢查開播」';
  @override
  String get goToSettings => '前往設定';
  @override
  String get recordWhenLive => '開播後自動錄製';
  @override
  String get stoppingRecording => '正在停止錄製，已錄的檔案會保留';
  @override
  String get taskRemoved => '已移除錄製任務，已錄的檔案會保留';
  @override
  String get record => '錄製';
  @override
  String get recordNow => '立即錄製';
  @override
  String get recordOnLive => '開播時自動錄製';
  @override
  String get removeTask => '移除錄製任務';
  @override
  late final Translations$room$tab$zh_Hant tab = Translations$room$tab$zh_Hant.internal(_root);
  @override
  String get forceLandscape => '橫向全螢幕';
  @override
  String platformLimited({required Object quality}) => '平台限制為 ${quality}';
  @override
  String qualityLine({required Object quality, required Object n}) => '${quality} · 線路 ${n}';
  @override
  String get quickPanelHint => '長按畫面開啟快速面板；長按彈幕可以複製或封鎖';
  @override
  String get screenshot => '截圖';
  @override
  String get sleepTimer => '定時關閉';
  @override
  String get openInApp => '在 App 中開啟';
  @override
  String get share => '分享';
  @override
  String get copyStreamUrl => '複製直連網址';
  @override
  String get roomVolume => '房間音量';
  @override
  String get addToMultiview => '加入多畫面';
  @override
  String get shortcuts => '快速鍵';
  @override
  String get openInNewWindow => '在新視窗開啟';
  @override
  String shareSubject({required Object name}) => '${name}的直播間';
  @override
  String get shareCodeCopied => '分享碼已複製，對方在純粹直播裡貼上即可開啟';
  @override
  String get noStreamYet => '還沒有取得直播串流';
  @override
  String get streamUrlCopied => '已複製直連網址，有時效，過期後需要重新複製';
  @override
  String get noLiveFollows => '沒有開播的追蹤';
  @override
  String get noRecordingRooms => '沒有正在錄製的直播間';
  @override
  String get noHistory => '還沒有觀看紀錄';
  @override
  String get volumeRemembered => '這個直播間會記住這個音量';
  @override
  String get volumePlayerOnly => '只調整播放器音量，不會改動手機的媒體音量';
  @override
  String get setDefaultVolume => '設為預設音量';
  @override
  String get setPhoneDefaultVolume => '設為手機預設音量';
  @override
  late final Translations$room$key$zh_Hant key = Translations$room$key$zh_Hant.internal(_root);
  @override
  late final Translations$room$tip$zh_Hant tip = Translations$room$tip$zh_Hant.internal(_root);
  @override
  String get noRoomsToSwitch => '沒有可以切換的開播直播間';
  @override
  String get firstRoom => '已經是第一個了';
  @override
  String get lastRoom => '已經是最後一個了';
  @override
  String get swipeHint => '可以在 設定 › 播放 裡開啟上下滑動切換直播間';
  @override
  late final Translations$room$tv$zh_Hant tv = Translations$room$tv$zh_Hant.internal(_root);
}

// Path: rooms
class Translations$rooms$zh_Hant implements Translations$rooms$zh_Hans {
  Translations$rooms$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get setGroups => '設定群組';
  @override
  String get streamLink => '取得直連網址';
  @override
  String get openInNewWindow => '在新視窗開啟';
  @override
  String followedName({required Object name}) => '已追蹤 ${name}';
  @override
  String get notLive => '主播現在沒有開播，拿不到直連網址。';
  @override
  String get loadingLines => '正在取得線路';
  @override
  String get linesTapToCopy => '線路（點一下複製）';
  @override
  String get noLinesForQuality => '這個畫質沒有可用的線路';
  @override
  String get clipboardFailed => '無法寫入剪貼簿，請再試一次';
  @override
  String streamLinkFor({required Object title}) => '取得直連網址 · ${title}';
}

// Path: search
class Translations$search$zh_Hant implements Translations$search$zh_Hans {
  Translations$search$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get voice => '語音搜尋';
  @override
  String get clear => '清除';
  @override
  String get results => '搜尋結果';
  @override
  String get all => '綜合';
  @override
  String get failedTag => '失敗';
  @override
  String get allFailed => '搜尋失敗，檢查網路後下拉重試';
  @override
  String someFailed({required Object platforms}) => '${platforms} 搜尋失敗，下拉可以重試';
  @override
  String get hint => '搜尋主播、直播間，或貼上直播間連結';
  @override
  String get liveOnly => '只看開播';
  @override
  String get resolvingLink => '正在辨識連結';
  @override
  String get noLinkMatch => '沒有辨識出直播間連結';
  @override
  String get empty => '沒有找到相關的直播間';
  @override
  late final Translations$search$sort$zh_Hant sort = Translations$search$sort$zh_Hant.internal(_root);
  @override
  late final Translations$search$web$zh_Hant web = Translations$search$web$zh_Hant.internal(_root);
}

// Path: settings
class Translations$settings$zh_Hant implements Translations$settings$zh_Hans {
  Translations$settings$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get language => '語言';
  @override
  String get languageSystem => '跟隨系統';
  @override
  late final Translations$settings$group$zh_Hant group = Translations$settings$group$zh_Hant.internal(_root);
  @override
  late final Translations$settings$general$zh_Hant general = Translations$settings$general$zh_Hant.internal(_root);
  @override
  late final Translations$settings$appearance$zh_Hant appearance = Translations$settings$appearance$zh_Hant.internal(
    _root,
  );
  @override
  late final Translations$settings$playback$zh_Hant playback = Translations$settings$playback$zh_Hant.internal(_root);
  @override
  late final Translations$settings$data$zh_Hant data = Translations$settings$data$zh_Hant.internal(_root);
  @override
  late final Translations$settings$accounts$zh_Hant accounts = Translations$settings$accounts$zh_Hant.internal(_root);
  @override
  String get tvDarkOnly => '電視模式下只使用深色';
  @override
  String get tvDarkOnlySubtitle => '純黑背景開關仍然有效';
  @override
  String historyEntries({required Object n}) => '${n} 筆';
  @override
  late final Translations$settings$output$zh_Hant output = Translations$settings$output$zh_Hant.internal(_root);
  @override
  late final Translations$settings$record$zh_Hant record = Translations$settings$record$zh_Hant.internal(_root);
  @override
  late final Translations$settings$audience$zh_Hant audience = Translations$settings$audience$zh_Hant.internal(_root);
  @override
  late final Translations$settings$network$zh_Hant network = Translations$settings$network$zh_Hant.internal(_root);
  @override
  String get platformsHint => '勾選要在探索、搜尋和平台帳號裡顯示的平台，拖動調整順序；點星號設為探索頁預設開啟的平台。';
  @override
  String get discoverDefault => '探索頁預設開啟';
  @override
  String get setDiscoverDefault => '設為探索頁預設開啟';
  @override
  Map<String, String> get languageNames => {'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', 'en': 'English'};
}

// Path: share
class Translations$share$zh_Hant implements Translations$share$zh_Hans {
  Translations$share$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String roomN({required Object id}) => '房間 ${id}';
  @override
  String get shareCodeReceived => '收到分享碼';
  @override
  String get roomLinkFound => '發現直播間連結';
  @override
  String get fromClipboard => '來自剪貼簿。可以在 設定 › 一般 裡關閉剪貼簿辨識。';
  @override
  String get enterRoom => '進入直播間';
  @override
  String get codeCopied => '分享碼已複製。對方複製後開啟純粹直播（3.x 或 v4），即可進入這個直播間';
}

// Path: sites
class Translations$sites$zh_Hant implements Translations$sites$zh_Hans {
  Translations$sites$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  Map<String, String> get names => {
    'bilibili': '嗶哩嗶哩',
    'douyu': '鬥魚',
    'huya': '虎牙',
    'douyin': '抖音',
    'kuaishou': '快手',
    'cc': '網易CC',
    'yy': 'YY',
    'soop': 'SOOP',
    'acfun': 'AcFun',
    'twitch': 'Twitch',
    'chzzk': 'CHZZK',
    'missevan': '貓耳 FM',
    'kilakila': '克拉克拉',
    'inke': '映客',
    'picarto': 'Picarto',
    'twitcasting': 'TwitCasting',
    'showroom': 'SHOWROOM',
    'pandalive': 'PandaTV',
    '17live': '17LIVE',
    'liveme': 'LiveMe',
    'steambroadcast': 'Steam 直播',
    'sixroom': '六間房直播',
    'kugoulive': '酷狗直播',
    'jdlive': '京東直播',
    'baidulive': '百度直播',
    'looklive': 'LOOK 直播',
    'weibo': '微博直播',
    'niconico': 'niconico',
    'xiaohongshu': '小紅書',
    'youtube': 'YouTube Live',
    'tiktok': 'TikTok LIVE',
    'fc2live': 'FC2 Live',
    'bigo': 'Bigo Live',
    'iptv': '網路電視',
  };
  @override
  Map<String, String> get otherNames => {'huajiao': '花椒', 'kick': 'Kick'};
}

// Path: sync
class Translations$sync$zh_Hant implements Translations$sync$zh_Hans {
  Translations$sync$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  late final Translations$sync$device$zh_Hant device = Translations$sync$device$zh_Hant.internal(_root);
  @override
  late final Translations$sync$lan$zh_Hant lan = Translations$sync$lan$zh_Hant.internal(_root);
  @override
  late final Translations$sync$webdav$zh_Hant webdav = Translations$sync$webdav$zh_Hant.internal(_root);
}

// Path: system
class Translations$system$zh_Hant implements Translations$system$zh_Hans {
  Translations$system$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get backgroundChannelDescription => '背景播放直播間聲音時的通知';
  @override
  String get closeWindow => '關閉視窗';
  @override
  String get closeQuestion => '要結束純粹直播，還是最小化到系統匣繼續執行？';
  @override
  String get dontAskAgain => '不再詢問';
  @override
  String get changeInSettings => '可以在 設定 › 一般 裡修改';
  @override
  String get minimizeToTray => '最小化到系統匣';
  @override
  String get askEveryTime => '每次詢問';
  @override
  String get quitApp => '結束應用程式';
  @override
  String get onClose => '關閉視窗時';
  @override
  String get showWindow => '顯示視窗';
  @override
  String get hideWindow => '隱藏視窗';
  @override
  String get playbackError => '播放出錯了';
  @override
  String get backToRoom => '回到直播間';
  @override
  String get closeMini => '關閉小視窗';
  @override
  String get restoreWindowFailed => '無法恢復視窗，請手動調整視窗大小';
  @override
  String get exitPip => '結束子母畫面（按兩下畫面）';
  @override
  String get launchAtStartup => '開機時自動啟動';
  @override
  String get launchAtStartupSubtitle => '登入 Windows 後自動開啟純粹直播';
  @override
  String get miniOnLeave => '離開直播間時以小視窗播放';
  @override
  String get miniOnLeaveSubtitle => '小視窗會繼續佔用記憶體和流量';
  @override
  String get autoPip => '離開應用程式時自動進入子母畫面';
  @override
  String get autoPipSubtitle => '在直播間按主畫面鍵時進入子母畫面';
  @override
  String get pipOnTop => '子母畫面視窗置頂';
}

// Path: tv
class Translations$tv$zh_Hant implements Translations$tv$zh_Hans {
  Translations$tv$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get speechPrompt => '說出主播名稱或直播間';
}

// Path: ui
class Translations$ui$zh_Hant implements Translations$ui$zh_Hans {
  Translations$ui$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get live => '直播';
  @override
  String liveFor({required Object duration}) => '直播 ${duration}';
  @override
  String get liveNow => '直播中';
  @override
  String get offline => '未開播';
  @override
  String get recording => '錄製中';
  @override
  String get separator => '，';
  @override
  String get retry => '重試';
  @override
  String get ok => '確定';
  @override
  String get cancel => '取消';
  @override
  String get justNow => '剛剛';
  @override
  String minutesAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分鐘前');
  @override
  String hoursAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 小時前');
  @override
  String daysAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 天前');
  @override
  String get countBase => '10000';
  @override
  List<String> get countUnits => ['萬', '億'];
}

// Path: web
class Translations$web$zh_Hant implements Translations$web$zh_Hans {
  Translations$web$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get webView2Title => '需要 WebView2 執行階段';
  @override
  String get webView2Body =>
      '網頁登入和網頁搜尋要用微軟的 Microsoft Edge WebView2 執行階段，這台電腦上找不到它。Windows 11 和更新過的 Windows 10 通常已經內建。\n\n安裝方法：開啟微軟的下載頁面，下載「常青版啟動載入器」（Evergreen Bootstrapper）並執行，裝好後重新開啟純粹直播。';
  @override
  String get openDownloadPage => '開啟下載頁面';
}

// Path: accounts.cookieTip
class Translations$accounts$cookieTip$zh_Hant implements Translations$accounts$cookieTip$zh_Hans {
  Translations$accounts$cookieTip$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get douyu =>
      '在電腦瀏覽器登入 www.douyu.com 後，從開發人員工具裡複製請求標頭中的 Cookie 貼到下面。要能續期，再複製 passport.douyu.com 請求的 Cookie（含 LTP0）貼進來，應用程式會取出 LTP0 和 dy_did。';
  @override
  String get twitch => '在電腦瀏覽器登入 twitch.tv 後複製 Cookie。只會用到其中的 auth-token，用於訂閱專屬直播和免廣告。';
  @override
  String get soop => '在電腦瀏覽器登入 sooplive.co.kr 後複製 Cookie。只在開啟 19 禁直播時隨取流請求傳送。';
  @override
  String get other => '在電腦瀏覽器登入該平台網頁版後，從開發人員工具裡複製請求標頭中的 Cookie，貼到下面。';
}

// Path: app.tabs
class Translations$app$tabs$zh_Hant implements Translations$app$tabs$zh_Hans {
  Translations$app$tabs$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get follows => '追蹤';
  @override
  String get discover => '探索';
  @override
  String get search => '搜尋';
  @override
  String get me => '我的';
}

// Path: backup.section
class Translations$backup$section$zh_Hant implements Translations$backup$section$zh_Hans {
  Translations$backup$section$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get follows => '追蹤';
  @override
  String get followAreas => '追蹤的分區';
  @override
  String get tags => '群組';
  @override
  String get roomTags => '群組成員';
  @override
  String get history => '觀看紀錄';
  @override
  String get blockRules => '封鎖字詞';
  @override
  String get settings => '設定';
  @override
  String get roomPrefs => '直播間偏好設定';
  @override
  String get recordTasks => '錄製任務';
  @override
  String get secrets => '平台登入資訊';
}

// Path: cast.failure
class Translations$cast$failure$zh_Hant implements Translations$cast$failure$zh_Hans {
  Translations$cast$failure$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get unreachable => '連不上這台裝置，請確認它已開啟，並且和手機連著同一個 Wi-Fi';
  @override
  String get busy => '裝置正忙，稍後再試';
  @override
  String get format => '裝置不支援這種直播串流格式，換一條線路試試';
  @override
  String get unplayable => '裝置無法開啟這個直播位址，換一條線路試試';
  @override
  String refused({required Object code}) => '裝置拒絕了投放（錯誤碼 ${code}）';
  @override
  String http({required Object status}) => '裝置回傳了錯誤（HTTP ${status}）';
  @override
  String get protocol => '無法辨識裝置的回應';
  @override
  String get generic => '投放失敗';
}

// Path: cast.tv
class Translations$cast$tv$zh_Hant implements Translations$cast$tv$zh_Hans {
  Translations$cast$tv$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get playing => '電視正在播放';
  @override
  String get loading => '電視正在載入';
  @override
  String get paused => '電視已暫停';
  @override
  String get stopped => '電視已停止播放';
}

// Path: danmaku.preset
class Translations$danmaku$preset$zh_Hant implements Translations$danmaku$preset$zh_Hans {
  Translations$danmaku$preset$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get best => '最佳觀感';
  @override
  String get comfort => '舒適';
  @override
  String get dense => '密集';
  @override
  String get reset => '恢復預設';
}

// Path: danmaku.audience
class Translations$danmaku$audience$zh_Hant implements Translations$danmaku$audience$zh_Hans {
  Translations$danmaku$audience$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get online => '線上';
  @override
  String get popularity => '人氣';
  @override
  String get cumulative => '看過';
}

// Path: follows.sort
class Translations$follows$sort$zh_Hant implements Translations$follows$sort$zh_Hans {
  Translations$follows$sort$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get audience => '按人數';
  @override
  String get liveTime => '按開播時間';
  @override
  String get platform => '按平台';
  @override
  String get custom => '自訂順序';
}

// Path: follows.tag
class Translations$follows$tag$zh_Hant implements Translations$follows$tag$zh_Hans {
  Translations$follows$tag$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get unsupported => '未支援';
  @override
  String get unknown => '狀態未知';
  @override
  String get missing => '房間不存在';
  @override
  String get replay => '輪播';
}

// Path: follows.filter
class Translations$follows$filter$zh_Hant implements Translations$follows$filter$zh_Hans {
  Translations$follows$filter$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get live => '開播';
  @override
  String liveCount({required Object n}) => '開播 ${n}';
  @override
  String get groups => '群組';
}

// Path: iptv.error
class Translations$iptv$error$zh_Hant implements Translations$iptv$error$zh_Hans {
  Translations$iptv$error$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get noGuide => '沒有辨識出節目表，請確認是 XMLTV 或 JSON 格式';
  @override
  String get noChannels => '沒有辨識出頻道，請確認是 M3U、TXT 或 JSON 播放清單';
  @override
  String get badUrl => '請輸入 http 或 https 開頭的網址';
  @override
  String get xtreamMissing => '找不到這個 Xtream 帳號的登入資訊，刪除後重新登入';
  @override
  String get notFound => '位址不存在（404），請檢查網址是否還有效';
  @override
  String get network => '網路連線失敗，檢查網路或 Proxy 後重試';
  @override
  String get file => '讀不到檔案，請重新匯入一次';
  @override
  String get format => '檔案格式不對';
  @override
  String get generic => '同步失敗';
  @override
  String get notXtream => '伺服器的回應不是 Xtream 介面，請檢查伺服器位址';
}

// Path: iptv.xtream
class Translations$iptv$xtream$zh_Hant implements Translations$iptv$xtream$zh_Hans {
  Translations$iptv$xtream$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get wrongCredentials => '使用者名稱或密碼不對';
  @override
  String get expired => '帳號已過期';
  @override
  String get banned => '帳號被停權';
  @override
  String get disabled => '帳號已停用';
  @override
  String unavailable({required Object status}) => '帳號無法使用（${status}）';
  @override
  String get unknownStatus => '未知狀態';
}

// Path: recording.notice
class Translations$recording$notice$zh_Hant implements Translations$recording$notice$zh_Hans {
  Translations$recording$notice$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get finishingTitle => '正在處理錄製檔案';
  @override
  String finishingText({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 個錄製正在收尾，完成後通知會消失');
  @override
  String namesAndMore({required Object names}) => '${names} 等';
  @override
  String recordingTitle({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '正在錄製 ${n} 個直播間');
  @override
  String recordingText({required num n, required Object shown}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${shown}；${n} 個正在收尾');
}

// Path: recording.state
class Translations$recording$state$zh_Hant implements Translations$recording$state$zh_Hans {
  Translations$recording$state$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get queued => '排隊中';
  @override
  String get resolving => '準備中';
  @override
  String get recording => '錄製中';
  @override
  String get reconnecting => '重新連線中';
  @override
  String get finalizing => '處理中';
  @override
  String remuxing({required Object percent}) => '轉封裝 ${percent}%';
  @override
  String get waitingLive => '等待開播';
  @override
  String get completed => '已完成';
  @override
  String get failed => '失敗';
  @override
  String get stoppedPollingOff => '已停止（開播監控已關閉）';
  @override
  String get stoppedAppExit => '已停止（應用程式結束）';
  @override
  String get stopped => '已停止';
}

// Path: recording.failure
class Translations$recording$failure$zh_Hant implements Translations$recording$failure$zh_Hans {
  Translations$recording$failure$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get offline => '主播已下播';
  @override
  String get banned => '直播間被封鎖';
  @override
  String get missing => '直播間不存在';
  @override
  String get unsupported => '這個平台暫不支援錄製';
  @override
  String get needsLogin => '需要登入平台帳號';
  @override
  String get region => '目前地區無法觀看';
  @override
  String get noStream => '拿不到可錄製的直播串流';
  @override
  String get unsupportedFormat => '直播串流的格式暫不支援錄製（如 RTSP、UDP 位址，SAMPLE-AES 加密，影音分開的 HLS）';
  @override
  String get diskFull => '儲存空間不足';
  @override
  String get noPermission => '沒有錄製目錄的寫入權限';
  @override
  String get directory => '錄製目錄無法使用';
  @override
  String get writeStalled => '磁碟寫入卡住了';
  @override
  String get background => '背景執行時間被系統用盡';
  @override
  String get remux => '轉成 MP4 失敗，原始檔案已保留';
  @override
  String get corrupt => '錄製檔案損壞';
  @override
  String get retries => '多次重試都沒有成功';
  @override
  String get stream => '網路或直播串流出錯';
}

// Path: recording.stage
class Translations$recording$stage$zh_Hant implements Translations$recording$stage$zh_Hans {
  Translations$recording$stage$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get check => '房間檢查';
  @override
  String get quality => '選畫質';
  @override
  String get resolve => '取流';
  @override
  String get connect => '連線';
  @override
  String get write => '寫檔案';
  @override
  String get remux => '轉封裝';
  @override
  String get queue => '排隊排程';
  @override
  String get background => '背景執行';
  @override
  String get poll => '開播檢查';
}

// Path: room.failure
class Translations$room$failure$zh_Hant implements Translations$room$failure$zh_Hans {
  Translations$room$failure$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get network => '網路中斷了';
  @override
  String get source => '直播串流打不開，可以換條線路試試';
  @override
  String get buffering => '緩衝太久了，可以換條線路或降低畫質';
  @override
  String get ended => '直播串流中斷了';
  @override
  String get paused => '播放意外停止了';
  @override
  String get frozen => '畫面卡住了';
  @override
  String get videoDecode => '影片解碼失敗，可以在設定裡關閉硬體解碼';
  @override
  String get audioDecode => '音訊解碼失敗';
  @override
  String get engine => '播放器出錯了';
  @override
  String get unavailable => '拿不到直播串流';
  @override
  String get exhausted => '多次重試都沒有成功';
}

// Path: room.fit
class Translations$room$fit$zh_Hant implements Translations$room$fit$zh_Hans {
  Translations$room$fit$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get cover => '填滿';
  @override
  String get fill => '拉伸';
  @override
  String get contain => '符合';
}

// Path: room.sleep
class Translations$room$sleep$zh_Hant implements Translations$room$sleep$zh_Hans {
  Translations$room$sleep$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get exiting => '定時關閉：正在結束應用程式';
  @override
  String get paused => '定時關閉：已暫停播放';
  @override
  String exitIn({required Object time}) => '${time} 後結束應用程式';
  @override
  String pauseIn({required Object time}) => '${time} 後暫停播放';
  @override
  String get cancel => '取消定時';
  @override
  String get hint => '時間到後暫停播放，並停止背景聲音';
  @override
  String get custom => '自訂';
  @override
  String get pause => '暫停播放';
  @override
  String get exit => '結束應用程式';
  @override
  String get audioOnly => '同時切換為純音訊';
  @override
  String get audioOnlySubtitle => '助眠：只保留聲音';
  @override
  String invalidMinutes({required Object max}) => '請輸入 1 到 ${max} 之間的分鐘數';
  @override
  String get customTitle => '自訂時長';
  @override
  String get minutesSuffix => '分鐘';
}

// Path: room.tab
class Translations$room$tab$zh_Hant implements Translations$room$tab$zh_Hans {
  Translations$room$tab$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get danmaku => '彈幕';
  @override
  String get room => '直播間';
}

// Path: room.key
class Translations$room$key$zh_Hant implements Translations$room$key$zh_Hans {
  Translations$room$key$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get space => '空白鍵';
  @override
  String get playPause => '播放 / 暫停';
  @override
  String get fullscreenKeys => 'F、按兩下';
  @override
  String get fullscreen => '全螢幕 / 結束全螢幕';
  @override
  String get escape => '關閉浮層 → 結束全螢幕或劇院模式 → 離開直播間';
  @override
  String get theater => '劇院模式';
  @override
  String get chat => '顯示 / 收起聊天欄';
  @override
  String get mute => '靜音';
  @override
  String get volumeKeys => '↑ ↓、滾輪';
  @override
  String get volume => '音量 ±5%';
  @override
  String get danmaku => '彈幕開關';
  @override
  String get qualityLine => '畫質 / 線路';
  @override
  String get help => '快速鍵說明';
  @override
  String get refreshKeys => 'R、F5、Ctrl+R';
}

// Path: room.tip
class Translations$room$tip$zh_Hant implements Translations$room$tip$zh_Hans {
  Translations$room$tip$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get desktop => '按 C 收起或展開聊天欄，按 T 進入劇院模式，按 ? 查看全部快速鍵';
  @override
  String get touch => '雙指縮放切換畫面比例，長按畫面開啟快速面板';
}

// Path: room.tv
class Translations$room$tv$zh_Hant implements Translations$room$tv$zh_Hans {
  Translations$room$tv$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get hint => '上下鍵換台，左鍵開啟直播間清單，右鍵開啟播放設定，確認鍵顯示控制項';
  @override
  String get roomList => '直播間清單';
  @override
  String get playbackSettings => '播放設定';
  @override
  String get qualityLine => '畫質線路';
  @override
  String get noLiveRooms => '沒有開播的直播間';
  @override
  String get watching => '正在看';
}

// Path: search.sort
class Translations$search$sort$zh_Hant implements Translations$search$sort$zh_Hans {
  Translations$search$sort$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get smart => '智慧';
  @override
  String get platform => '按平台';
  @override
  String get audience => '按人數';
  @override
  String get followers => '按粉絲';
}

// Path: search.web
class Translations$search$web$zh_Hant implements Translations$search$web$zh_Hans {
  Translations$search$web$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get title => '網頁搜尋';
  @override
  String get enterKeyword => '請先輸入要搜尋的關鍵字';
  @override
  String get pickPlatform => '在哪個平台的網頁裡搜尋';
  @override
  String get roomFound => '辨識到直播間';
  @override
  String get stay => '留在網頁';
  @override
  String titleFor({required Object name}) => '網頁搜尋 · ${name}';
  @override
  String get pageRooms => '本頁的房間';
  @override
  String get unavailable => '這裡無法使用網頁搜尋';
  @override
  String get notOpened => '網頁沒有開啟';
  @override
  String get scanning => '正在辨識本頁的直播間';
  @override
  String get noRooms => '本頁沒有辨識出直播間連結';
  @override
  String get pageRoomsTitle => '本頁的直播間';
}

// Path: settings.group
class Translations$settings$group$zh_Hant implements Translations$settings$group$zh_Hans {
  Translations$settings$group$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get general => '一般';
  @override
  String get playback => '播放';
  @override
  String get danmaku => '彈幕';
  @override
  String get recording => '錄製';
  @override
  String get accounts => '平台與帳號';
  @override
  String get network => '網路';
  @override
  String get data => '資料與同步';
}

// Path: settings.general
class Translations$settings$general$zh_Hant implements Translations$settings$general$zh_Hans {
  Translations$settings$general$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get startPage => '啟動頁面';
  @override
  String get keepScreenOn => '播放時螢幕保持開啟';
  @override
  String get refreshRate => '重新整理率';
  @override
  String get refreshPowerSaving => '省電';
  @override
  String get refreshBalanced => '均衡';
  @override
  String get refreshHighest => '最高';
  @override
  String get autoCheckUpdate => '自動檢查更新';
  @override
  String get tv => '電視';
  @override
  String get tvMode => '電視模式';
  @override
  String get tvModeAuto => '自動（偵測到電視時開啟）';
  @override
  String get tvFocusOutline => '電視焦點只顯示外框';
  @override
  String get tvFocusOutlineSubtitle => '效能優先：焦點不放大，適合低階電視盒';
  @override
  String get followRefresh => '追蹤重新整理';
  @override
  String get autoRefreshFollows => '定時重新整理追蹤的開播狀態';
  @override
  String get refreshOnResume => '回到應用程式時重新整理追蹤';
  @override
  String get refreshInterval => '定時重新整理間隔';
  @override
  String get maxConcurrentRefresh => '同時重新整理的直播間數';
  @override
  String get refreshCovers => '定時重新整理封面';
  @override
  String get refreshCoversSubtitle => '開播卡片的封面按間隔重新下載，看到的畫面會更新';
  @override
  String get coverInterval => '封面重新整理間隔';
  @override
  String get notifications => '通知';
}

// Path: settings.appearance
class Translations$settings$appearance$zh_Hant implements Translations$settings$appearance$zh_Hans {
  Translations$settings$appearance$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get theme => '主題';
  @override
  String get denseSubtitle => '主播名稱和標題放在同一行';
  @override
  String get textSize => '文字大小';
  @override
  String get accentColor => '跟隨系統強調色';
  @override
  String get accentColorSubtitle => '主題色改用 Windows 的強調色';
  @override
  String get wallpaperColor => '跟隨桌布取色';
  @override
  String get wallpaperColorSubtitle => 'Android 12 以上，主題色取自桌布';
  @override
  String get compactCardsPhone => '探索和搜尋使用緊湊卡片（手機）';
  @override
  String get compactCardsDesktop => '探索和搜尋使用緊湊卡片（桌面）';
  @override
  String get fontsSubtitle => '下載開源字型，用作介面或彈幕字型';
}

// Path: settings.playback
class Translations$settings$playback$zh_Hant implements Translations$settings$playback$zh_Hans {
  Translations$settings$playback$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get qualityWifi => '預設畫質（Wi-Fi）';
  @override
  String get qualityMobile => '預設畫質（行動網路）';
  @override
  String get autoLower => '網路不穩時自動降低畫質';
  @override
  String get autoLowerSubtitle => '一分鐘內卡頓 3 次就降一級；手動選過畫質後不再自動調整';
  @override
  String get fitCover => '填滿（裁切）';
  @override
  String get autoFullscreen => '進入直播間自動全螢幕';
  @override
  String get swipeRooms => '直向全螢幕上下滑動切換直播間';
  @override
  String get swipeRoomsSubtitle => '上滑下一個、下滑上一個；開啟後直向全螢幕裡不再上下滑動調整亮度和音量';
  @override
  String get portrait => '直向直播';
  @override
  String get portraitAdaptation => '直向直播適配';
  @override
  String get portraitAdaptationSubtitle => '自動辨識直向直播，手機上使用直向全螢幕和可拖動的資訊面板';
  @override
  String get fullscreenOrientation => '全螢幕方向';
  @override
  String get orientationSource => '跟隨畫面（直向直播直向全螢幕）';
  @override
  String get orientationSystem => '跟隨手機方向';
  @override
  String get orientationLandscape => '一律橫向';
  @override
  String get portraitFit => '直向全螢幕畫面';
  @override
  String get portraitFitContain => '完整顯示';
  @override
  String get portraitFitCover => '填滿螢幕（裁掉邊緣）';
  @override
  String get portraitDanmaku => '直向全螢幕彈幕區域';
  @override
  String get danmakuFollow => '跟隨彈幕設定';
  @override
  String get danmakuUpperQuarter => '只在上方四分之一';
  @override
  String get danmakuHalf => '減半';
  @override
  String get danmakuHidden => '不顯示';
  @override
  String get rememberOrientation => '記住每個直播間的畫面方向';
  @override
  String get rememberOrientationSubtitle => '在直播間手動選的「當作直向/橫向」下次進入仍然生效';
  @override
  String get background => '背景播放';
  @override
  String get backgroundSubtitle => '離開應用程式後繼續播放聲音';
  @override
  String get sleep => '助眠';
  @override
  String get sleepMode => '助眠模式';
  @override
  String get sleepModeSubtitle => '進入直播間自動只播放聲音並開始定時關閉；恢復畫面時取消這次定時';
  @override
  String get sleepMinutes => '助眠定時';
  @override
  String get phoneVolume => '手機預設音量';
}

// Path: settings.data
class Translations$settings$data$zh_Hant implements Translations$settings$data$zh_Hans {
  Translations$settings$data$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get historyLimit => '觀看紀錄最多保留';
}

// Path: settings.accounts
class Translations$settings$accounts$zh_Hant implements Translations$settings$accounts$zh_Hans {
  Translations$settings$accounts$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get platforms => '首頁平台';
  @override
  String get platformsSubtitle => '顯示哪些平台、順序和探索頁預設開啟的平台';
  @override
  String get audience => '觀眾數計算方式';
  @override
  String get audienceSubtitle => '卡片顯示熱度還是線上人數，以及各平台數字的含義';
  @override
  String get accountsSubtitle => '登入或登出各平台帳號';
}

// Path: settings.output
class Translations$settings$output$zh_Hant implements Translations$settings$output$zh_Hans {
  Translations$settings$output$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get volume => '音量';
  @override
  String get startMuted => '進入直播間時靜音';
  @override
  String get startMutedSubtitle => '所有直播間都從靜音開始';
  @override
  String get defaultVolume => '預設音量';
  @override
  String get defaultVolumeDesktop => '預設音量（沒有記住音量的直播間）';
  @override
  String get decoding => '解碼與輸出';
  @override
  String get hardwareDecoding => '硬體解碼';
  @override
  String get hardwareDecodingSubtitle => '畫面異常時試著關閉';
  @override
  String get decoder => '硬體解碼方式';
  @override
  String get mediacodecCopy => 'MediaCodec（複製）';
  @override
  String get d3d11Copy => 'D3D11（複製）';
  @override
  String get nvdec => 'NVDEC（NVIDIA）';
  @override
  String get compatibility => '相容模式';
  @override
  String get compatibilitySubtitle => '部分機型黑畫面、花屏或卡住時開啟';
  @override
  String get lowLatency => '低延遲';
  @override
  String get lowLatencySubtitle => '緩衝更少、延遲更低，網路差時更容易卡頓';
  @override
  String get audio => '音訊輸出';
}

// Path: settings.record
class Translations$settings$record$zh_Hant implements Translations$settings$record$zh_Hans {
  Translations$settings$record$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get centerSubtitle => '查看和管理錄製任務';
  @override
  String get quality => '預設錄製畫質';
  @override
  String get monitoring => '開播監控';
  @override
  String get monitoringSubtitle => '主播開播後自動開始錄製';
  @override
  String get pollInterval => '開播檢查間隔（秒）';
  @override
  String get reconnect => '斷線重新連線';
  @override
  String get autoReconnect => '斷線自動重新連線';
  @override
  String get retries => '重試次數';
  @override
  String get retryInterval => '重試間隔（秒）';
  @override
  String get backoff => '失敗後逐次延長等待';
  @override
  String get backoffSubtitle => '重試和開播檢查每失敗一次，等待時間加倍，直到最長間隔';
  @override
  String get maxBackoff => '最長等待間隔';
  @override
  String get readTimeout => '讀取逾時（直播串流多久沒有資料算斷線）';
  @override
  String get files => '檔案';
  @override
  String get maxConcurrent => '同時錄製的數量';
  @override
  String get splitDuration => '按時長分段（分鐘，0 為不分段）';
  @override
  String get splitSize => '按大小分段';
  @override
  String get saveDanmaku => '同時儲存彈幕';
  @override
  String get saveDanmakuSubtitle => '與影片同名的 XML 檔案';
  @override
  String get remuxMp4 => '錄完轉成 MP4';
  @override
  String get keepSource => '轉成 MP4 後保留原始錄製檔案';
  @override
  String get pinyinFolders => '資料夾名稱使用拼音';
  @override
  String get pinyinFoldersSubtitle => '主播名稱轉成拼音作為資料夾名稱，方便在不支援中文的裝置上查看';
  @override
  String get resumeOnStart => '啟動時繼續未完成的錄製';
  @override
  String get space => '空間';
  @override
  String get limitSize => '限制錄製目錄大小';
  @override
  String get limitSizeSubtitle => '超過上限時從最早的錄製檔案開始刪除，正在錄製和處理的不刪';
  @override
  String get sizeLimit => '錄製目錄上限';
  @override
  String get noSplit => '不分段';
  @override
  String get directory => '錄製儲存位置';
  @override
  String get directoryDefault => '預設位置';
  @override
  String get directoryReset => '恢復預設';
  @override
  String get directoryPick => '選擇錄製儲存位置';
}

// Path: settings.audience
class Translations$settings$audience$zh_Hant implements Translations$settings$audience$zh_Hans {
  Translations$settings$audience$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get shown => '卡片顯示';
  @override
  String get heatFirst => '平台熱度優先';
  @override
  String get heatFirstSubtitle => '顯示各平台公開的熱度或累計觀看，這些數字不等於同時線上人數';
  @override
  String get onlineFirst => '線上人數優先';
  @override
  String get onlineFirstSubtitle => '平台提供同時線上人數時顯示它，沒有時再顯示熱度或累計觀看';
  @override
  String get meaning => '各平台的數字是什麼';
}

// Path: settings.network
class Translations$settings$network$zh_Hant implements Translations$settings$network$zh_Hans {
  Translations$settings$network$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get useProxy => '使用 Proxy';
  @override
  String get useProxySubtitle => 'HTTP Proxy，例如 Clash 的 7897 連接埠；開啟後不再跟隨系統 Proxy';
  @override
  String get proxyHost => 'Proxy 位址';
  @override
  String get proxyHostUnset => '未設定（例如 127.0.0.1）';
  @override
  String get proxyPort => 'Proxy 連接埠';
  @override
  String get proxyPlatforms => '使用 Proxy 的平台';
  @override
  String get proxyAll => '目前所有平台都使用 Proxy。勾選下面的平台後，只有勾選的平台使用 Proxy。';
  @override
  String get proxySelected => '只有勾選的平台使用 Proxy。';
  @override
  String get systemProxy => '跟隨系統 Proxy';
  @override
  String get systemProxyManual => '手動 Proxy 開啟時不使用系統 Proxy';
  @override
  String get systemProxyNone => '系統目前沒有設定 Proxy，直接連線';
  @override
  String systemProxyIs({required Object host, required Object port}) => '系統 Proxy：${host}:${port}';
}

// Path: sync.device
class Translations$sync$device$zh_Hant implements Translations$sync$device$zh_Hans {
  Translations$sync$device$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get android => 'Android 裝置';
  @override
  String get windows => 'Windows 電腦';
  @override
  String get linux => 'Linux 電腦';
}

// Path: sync.lan
class Translations$sync$lan$zh_Hant implements Translations$sync$lan$zh_Hans {
  Translations$sync$lan$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get applied => '對方已確認並匯入';
  @override
  String get wrongCode => '配對碼不對，請核對對方螢幕上的配對碼（連續輸錯幾次後對方會換一個新的）';
  @override
  String get rejected => '對方拒絕了這次同步，或沒有及時確認';
  @override
  String get busy => '對方正在處理另一次同步，請稍後再試';
  @override
  String get unsupported => '對方的版本無法接收 v4 的資料（3.x 只能接收 3.x 的資料），請改用備份檔或 WebDAV';
  @override
  String get unreachable => '連不上對方：請確認兩台裝置在同一網路、對方已開始接收，位址和連接埠正確';
  @override
  String get timeout => '等待對方確認逾時';
  @override
  String get failed => '對方匯入失敗';
  @override
  String get networkNote =>
      'Android 17 起，系統可能要求允許「區域網路 / 附近的裝置」權限；連不上時請到 系統設定 › 應用程式 › 純粹直播 › 權限 中允許。\nWindows 第一次接收時會跳出防火牆提示，請允許在私人網路上存取。\n兩台裝置需要連在同一個 Wi-Fi（或同一區域網路）下。';
  @override
  String cannotReceive({required Object error}) => '無法開始接收：${error}';
  @override
  String from({required Object from}) => '來自 ${from}';
  @override
  String get received => '收到同步資料';
  @override
  String declined({required Object from}) => '已拒絕來自 ${from} 的資料';
  @override
  String imported({required Object from}) => '已匯入來自 ${from} 的資料';
  @override
  String get enterAddress => '請填寫對方螢幕上顯示的位址，例如 192.168.1.5:39888';
  @override
  String get enterCode => '請填寫對方螢幕上的 6 位數配對碼';
  @override
  String get sendTo => '傳送到對方';
  @override
  String get waiting => '正在等待對方確認…';
  @override
  String sendFailed({required Object error}) => '傳送失敗：${error}';
  @override
  String get receive => '接收';
  @override
  String get receiveHint => '在要接收資料的裝置上開始接收，然後在另一台裝置的「傳送」裡填寫這裡顯示的位址和配對碼。收到資料後會先讓你確認，確認前不會寫入任何內容。';
  @override
  String get starting => '正在開始…';
  @override
  String get startReceiving => '開始接收';
  @override
  String get receiving => '正在接收';
  @override
  String get noAddress => '找不到本機的區域網路位址，請先連上 Wi-Fi。';
  @override
  String get address => '位址';
  @override
  String get code => '配對碼';
  @override
  String get codeOnce => '配對碼只能用一次：收到一次資料或輸錯幾次後會自動更換。';
  @override
  String get qr => '同步 QR 碼';
  @override
  String get qrHint => '3.x 版本可以掃描這個 QR 碼傳送資料';
  @override
  String get stopReceiving => '停止接收';
  @override
  String get sendHint => '先在另一台裝置上開啟「區域網路同步 › 接收」，再填寫它顯示的位址和配對碼。可以選擇完整備份或僅追蹤；平台登入資訊只有設定加密密碼後才會加密傳送。';
  @override
  String get otherAddress => '對方位址';
  @override
  String get awaiting => '等待對方確認…';
  @override
  String senderWithAddress({required Object name, required Object address}) => '${name}（${address}）';
}

// Path: sync.webdav
class Translations$sync$webdav$zh_Hant implements Translations$sync$webdav$zh_Hans {
  Translations$sync$webdav$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  late final Translations$sync$webdav$error$zh_Hant error = Translations$sync$webdav$error$zh_Hant.internal(_root);
  @override
  String get noDirectory => '遠端目錄還不存在，第一次上傳時會自動建立';
  @override
  String get test => '測試連線';
  @override
  String get connected => '連線成功';
  @override
  String get connectedNoDirectory => '連線成功；備份目錄還不存在，第一次上傳時會自動建立';
  @override
  String get uploadBackup => '上傳備份';
  @override
  String get upload => '上傳';
  @override
  String get uploaded => '已上傳';
  @override
  String get restore => '還原';
  @override
  String fromWebdav({required Object name}) => '來自 WebDAV：${name}';
  @override
  String get deleteRemote => '刪除遠端檔案';
  @override
  String deleteRemoteConfirm({required Object name}) => '確定刪除 ${name}？刪除後無法復原。';
  @override
  String get deleted => '已刪除';
  @override
  String get deleteAccount => '刪除帳號';
  @override
  String deleteAccountConfirm({required Object name}) => '刪除「${name}」和儲存的密碼？遠端的備份檔不受影響。';
  @override
  String get help => '說明';
  @override
  String get addAccount => '新增帳號';
  @override
  String get noAccounts => '還沒有 WebDAV 帳號';
  @override
  String get noAccountsHint => '新增堅果雲、Nextcloud、Synology 等支援 WebDAV 的雲端硬碟，把備份存到雲端。';
  @override
  String get account => '帳號';
  @override
  String switchTo({required Object name}) => '切換到 ${name}';
  @override
  String remoteFiles({required Object path}) => '遠端檔案 ${path}';
  @override
  String get remoteFilesHint => '點檔案可以還原或刪除；3.x 的 purelive_*.txt 備份也能還原';
  @override
  String get up => '上一層';
  @override
  String get noBackups => '這裡還沒有備份';
  @override
  String get actions => '操作';
  @override
  String get helpTitle => 'WebDAV 說明';
  @override
  String get helpBody =>
      '堅果雲：位址填 https://dav.jianguoyun.com/dav/，使用者名稱是登入電子郵件，密碼要用「帳戶資訊 › 安全選項」裡產生的第三方應用程式密碼。\n\nNextcloud / ownCloud：位址填 https://你的網域/remote.php/dav/files/使用者名稱/。\n\nSynology：在套件中心安裝 WebDAV Server，位址填 https://NAS位址:5006/。\n\nAlist 等：位址一般是 https://網域/dav/。\n\n備份目錄預設是 pure_live，第一次上傳時自動建立。密碼加密儲存在本機，不會進入一般備份。';
  @override
  String get defaultName => '我的雲端硬碟';
  @override
  String get nameRequired => '請填寫名稱';
  @override
  String get nameTaken => '已經有同名的帳號';
  @override
  String get badUrl => '位址要以 http:// 或 https:// 開頭，不能包含使用者名稱、問號參數或 #';
  @override
  String get addTitle => '新增 WebDAV 帳號';
  @override
  String get editTitle => '編輯 WebDAV 帳號';
  @override
  String get passwordStored => '加密儲存在本機';
  @override
  String get passwordKeep => '不修改請留空';
  @override
  String get directory => '備份目錄';
  @override
  String get directoryRoot => '留空表示根目錄';
}

// Path: sync.webdav.error
class Translations$sync$webdav$error$zh_Hant implements Translations$sync$webdav$error$zh_Hans {
  Translations$sync$webdav$error$zh_Hant.internal(this._root);

  final TranslationsZhHant _root; // ignore: unused_field

  // Translations
  @override
  String get unauthorized => '使用者名稱或密碼不對';
  @override
  String get forbidden => '這個帳號沒有權限存取該位置';
  @override
  String get notFound => '遠端沒有這個檔案或目錄';
  @override
  String get storage => '雲端硬碟空間不足';
  @override
  String get network => '連不上伺服器，請檢查位址和網路';
  @override
  String get invalid => '伺服器的回應不是 WebDAV 格式，請檢查位址';
  @override
  String http({required Object status}) => '伺服器出錯（HTTP ${status}）';
}
