///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZhHans = Translations; // ignore: unused_element

class Translations with BaseTranslations<AppLocale, Translations> {
  /// Returns the current translations of the given [context].
  ///
  /// Usage:
  /// final t = Translations.of(context);
  static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  Translations({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.zhHans,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <zh-Hans>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final Translations _root = this; // ignore: unused_field

  Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) =>
      Translations(meta: meta ?? this.$meta);

  // Translations
  late final Translations$about$zh_Hans about = Translations$about$zh_Hans.internal(_root);
  late final Translations$accounts$zh_Hans accounts = Translations$accounts$zh_Hans.internal(_root);
  late final Translations$alerts$zh_Hans alerts = Translations$alerts$zh_Hans.internal(_root);
  late final Translations$app$zh_Hans app = Translations$app$zh_Hans.internal(_root);
  late final Translations$audience$zh_Hans audience = Translations$audience$zh_Hans.internal(_root);
  late final Translations$backup$zh_Hans backup = Translations$backup$zh_Hans.internal(_root);
  late final Translations$cast$zh_Hans cast = Translations$cast$zh_Hans.internal(_root);
  late final Translations$common$zh_Hans common = Translations$common$zh_Hans.internal(_root);
  late final Translations$danmaku$zh_Hans danmaku = Translations$danmaku$zh_Hans.internal(_root);
  late final Translations$diagnostics$zh_Hans diagnostics = Translations$diagnostics$zh_Hans.internal(_root);
  late final Translations$discover$zh_Hans discover = Translations$discover$zh_Hans.internal(_root);
  late final Translations$errors$zh_Hans errors = Translations$errors$zh_Hans.internal(_root);
  late final Translations$follows$zh_Hans follows = Translations$follows$zh_Hans.internal(_root);
  late final Translations$fonts$zh_Hans fonts = Translations$fonts$zh_Hans.internal(_root);
  late final Translations$health$zh_Hans health = Translations$health$zh_Hans.internal(_root);
  late final Translations$iptv$zh_Hans iptv = Translations$iptv$zh_Hans.internal(_root);
  late final Translations$me$zh_Hans me = Translations$me$zh_Hans.internal(_root);
  late final Translations$multiview$zh_Hans multiview = Translations$multiview$zh_Hans.internal(_root);
  late final Translations$onboarding$zh_Hans onboarding = Translations$onboarding$zh_Hans.internal(_root);
  late final Translations$quality$zh_Hans quality = Translations$quality$zh_Hans.internal(_root);
  late final Translations$recording$zh_Hans recording = Translations$recording$zh_Hans.internal(_root);
  late final Translations$room$zh_Hans room = Translations$room$zh_Hans.internal(_root);
  late final Translations$rooms$zh_Hans rooms = Translations$rooms$zh_Hans.internal(_root);
  late final Translations$search$zh_Hans search = Translations$search$zh_Hans.internal(_root);
  late final Translations$settings$zh_Hans settings = Translations$settings$zh_Hans.internal(_root);
  late final Translations$share$zh_Hans share = Translations$share$zh_Hans.internal(_root);
  late final Translations$sites$zh_Hans sites = Translations$sites$zh_Hans.internal(_root);
  late final Translations$sync$zh_Hans sync = Translations$sync$zh_Hans.internal(_root);
  late final Translations$system$zh_Hans system = Translations$system$zh_Hans.internal(_root);
  late final Translations$tv$zh_Hans tv = Translations$tv$zh_Hans.internal(_root);
  late final Translations$ui$zh_Hans ui = Translations$ui$zh_Hans.internal(_root);
  late final Translations$web$zh_Hans web = Translations$web$zh_Hans.internal(_root);
}

// Path: about
class Translations$about$zh_Hans {
  Translations$about$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '版本与更新'
  String get versionAndUpdates => '版本与更新';

  /// zh-Hans: '查看更新说明、下载安装包'
  String get versionSubtitle => '查看更新说明、下载安装包';

  /// zh-Hans: '发现新版本 {version}'
  String newVersion({required Object version}) => '发现新版本 ${version}';

  /// zh-Hans: '平台状态'
  String get platformStatus => '平台状态';

  /// zh-Hans: '检查各平台现在能不能访问'
  String get platformStatusSubtitle => '检查各平台现在能不能访问';

  /// zh-Hans: '项目主页'
  String get projectPage => '项目主页';

  /// zh-Hans: '问题反馈'
  String get feedback => '问题反馈';

  /// zh-Hans: '反馈问题时可以附上 设置 › 数据与同步 › 诊断与日志 里导出的诊断包'
  String get feedbackSubtitle => '反馈问题时可以附上 设置 › 数据与同步 › 诊断与日志 里导出的诊断包';

  /// zh-Hans: '发布记录'
  String get releases => '发布记录';

  /// zh-Hans: '开源许可'
  String get licenses => '开源许可';

  /// zh-Hans: '本应用以 AGPL-3.0 发布；这里列出所用组件的许可证'
  String get licensesSubtitle => '本应用以 AGPL-3.0 发布；这里列出所用组件的许可证';

  /// zh-Hans: '隐私'
  String get privacy => '隐私';

  /// zh-Hans: '纯粹直播不收集、不上报任何数据。平台 Cookie 和密码加密保存在本机，默认不进入备份；局域网同步需要配对码并由接收方确认；崩溃报告默认关闭，打开后也只在本机提示导出诊断包。'
  String get privacyBody => '纯粹直播不收集、不上报任何数据。平台 Cookie 和密码加密保存在本机，默认不进入备份；局域网同步需要配对码并由接收方确认；崩溃报告默认关闭，打开后也只在本机提示导出诊断包。';

  /// zh-Hans: '商标声明'
  String get trademarks => '商标声明';

  /// zh-Hans: '各平台名称和标识归其所有者所有，仅用于标明内容来源。'
  String get trademarksBody => '各平台名称和标识归其所有者所有，仅用于标明内容来源。';

  /// zh-Hans: '选择下载好的安装包'
  String get pickInstaller => '选择下载好的安装包';

  /// zh-Hans: '校验通过：{file} 与 {asset} 完全一致。'
  String verifyMatch({required Object file, required Object asset}) => '校验通过：${file} 与 ${asset} 完全一致。';

  /// zh-Hans: '校验失败：{file} 的 SHA-256 与发布页公布的不一致，请重新下载，不要安装。'
  String verifyMismatch({required Object file}) => '校验失败：${file} 的 SHA-256 与发布页公布的不一致，请重新下载，不要安装。';

  /// zh-Hans: '这个版本没有公布 SHA-256，无法校验。文件的 SHA-256 是 {hash}'
  String verifyNoHashes({required Object hash}) => '这个版本没有公布 SHA-256，无法校验。文件的 SHA-256 是 ${hash}';

  /// zh-Hans: '没有找到对应的文件：{file} 的 SHA-256 是 {hash}，与这个版本的任何文件都不一致。'
  String verifyUnknown({required Object file, required Object hash}) =>
      '没有找到对应的文件：${file} 的 SHA-256 是 ${hash}，与这个版本的任何文件都不一致。';

  /// zh-Hans: '读取文件失败：{message}'
  String readFileFailed({required Object message}) => '读取文件失败：${message}';

  /// zh-Hans: '当前版本 {version}'
  String currentVersion({required Object version}) => '当前版本 ${version}';

  /// zh-Hans: '预览版：检查更新时也包含预览版'
  String get channelPreview => '预览版：检查更新时也包含预览版';

  /// zh-Hans: '正式版：只检查正式版'
  String get channelStable => '正式版：只检查正式版';

  /// zh-Hans: '检查更新'
  String get checkForUpdates => '检查更新';

  /// zh-Hans: '打开发布页'
  String get openReleasePage => '打开发布页';

  /// zh-Hans: '已是最新版本'
  String get upToDate => '已是最新版本';

  /// zh-Hans: '历史版本'
  String get olderReleases => '历史版本';

  /// zh-Hans: '（没有更新说明）'
  String get noNotes => '（没有更新说明）';

  /// zh-Hans: '预览版'
  String get preview => '预览版';

  /// zh-Hans: '新版本 {version}'
  String newRelease({required Object version}) => '新版本 ${version}';

  /// zh-Hans: '发布页'
  String get releasePage => '发布页';

  /// zh-Hans: '适合本机的下载'
  String get recommendedDownloads => '适合本机的下载';

  /// zh-Hans: '其它平台和文件'
  String get otherDownloads => '其它平台和文件';

  /// zh-Hans: '正在计算…'
  String get calculating => '正在计算…';

  /// zh-Hans: '校验下载的文件'
  String get verifyDownload => '校验下载的文件';

  /// zh-Hans: 'Android 预览版的包名带 .next，可以和 3.x 同时安装；下载后在系统里打开安装包即可覆盖安装。'
  String get androidPreviewNote => 'Android 预览版的包名带 .next，可以和 3.x 同时安装；下载后在系统里打开安装包即可覆盖安装。';

  /// zh-Hans: '更新说明'
  String get releaseNotes => '更新说明';

  /// zh-Hans: 'Android · 通用'
  String get androidUniversal => 'Android · 通用';

  /// zh-Hans: 'Windows · 安装包'
  String get windowsSetup => 'Windows · 安装包';

  /// zh-Hans: 'Windows · 便携版'
  String get windowsPortable => 'Windows · 便携版';

  /// zh-Hans: '校验值列表'
  String get checksums => '校验值列表';

  /// zh-Hans: '其它文件'
  String get otherFile => '其它文件';

  /// zh-Hans: '下载链接已复制'
  String get downloadLinkCopied => '下载链接已复制';

  /// zh-Hans: 'SHA-256 已复制'
  String get hashCopied => 'SHA-256 已复制';

  /// zh-Hans: '复制下载链接'
  String get copyDownloadLink => '复制下载链接';

  /// zh-Hans: '复制 SHA-256'
  String get copyHash => '复制 SHA-256';

  /// zh-Hans: 'GitHub 限制了检查频率，请过一会儿再试'
  String get errorRateLimited => 'GitHub 限制了检查频率，请过一会儿再试';

  /// zh-Hans: '连不上 GitHub，请检查网络或代理'
  String get errorNetwork => '连不上 GitHub，请检查网络或代理';

  /// zh-Hans: '检查更新失败（{detail}）'
  String errorServer({required Object detail}) => '检查更新失败（${detail}）';

  /// zh-Hans: '未知错误'
  String get unknownError => '未知错误';

  /// zh-Hans: '发现新版本 {version}（预览版）'
  String newPreviewVersion({required Object version}) => '发现新版本 ${version}（预览版）';

  /// zh-Hans: '查看'
  String get view => '查看';
}

// Path: accounts
class Translations$accounts$zh_Hans {
  Translations$accounts$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '登录已失效，请重新登录'
  String get sessionExpired => '登录已失效，请重新登录';

  /// zh-Hans: '未登录'
  String get signedOut => '未登录';

  /// zh-Hans: '已填 Cookie，但里面没有登录信息'
  String get guestCookie => '已填 Cookie，但里面没有登录信息';

  /// zh-Hans: '已登录 · 有效期未知'
  String get validUnknown => '已登录 · 有效期未知';

  /// zh-Hans: '已登录 · 有效期到 {end}'
  String validUntil({required Object end}) => '已登录 · 有效期到 ${end}';

  /// zh-Hans: '已登录 · 有效期到 {end}，到期前可续期'
  String validUntilRenewable({required Object end}) => '已登录 · 有效期到 ${end}，到期前可续期';

  /// zh-Hans: '已在 {end} 过期，可以续期'
  String expiredRenewable({required Object end}) => '已在 ${end} 过期，可以续期';

  /// zh-Hans: '已过期，请重新登录'
  String get expired => '已过期，请重新登录';

  /// zh-Hans: '已登录 · {name}'
  String signedInAs({required Object name}) => '已登录 · ${name}';

  /// zh-Hans: '已登录 · {name}（UID {uid}）'
  String signedInAsWithUid({required Object name, required Object uid}) => '已登录 · ${name}（UID ${uid}）';

  /// zh-Hans: '已登录 · 正在校验'
  String get verifying => '已登录 · 正在校验';

  /// zh-Hans: 'Cookie 已失效，请重新登录'
  String get cookieExpired => 'Cookie 已失效，请重新登录';

  /// zh-Hans: '已登录 · 校验失败：{reason}'
  String verifyFailed({required Object reason}) => '已登录 · 校验失败：${reason}';

  /// zh-Hans: '已填 Cookie'
  String get cookieSaved => '已填 Cookie';

  /// zh-Hans: '已登录 · UID {uid}'
  String signedInUid({required Object uid}) => '已登录 · UID ${uid}';

  /// zh-Hans: '登录信息用本机的系统密钥加密保存，不会上传，默认也不会写进备份文件。'
  String get storageNote => '登录信息用本机的系统密钥加密保存，不会上传，默认也不会写进备份文件。';

  /// zh-Hans: '获取二维码失败：{reason}'
  String qrFetchFailed({required Object reason}) => '获取二维码失败：${reason}';

  /// zh-Hans: '检查扫码状态失败：{reason}'
  String qrPollFailed({required Object reason}) => '检查扫码状态失败：${reason}';

  /// zh-Hans: '登录校验没有通过，请刷新二维码重新扫码'
  String get qrVerifyRejected => '登录校验没有通过，请刷新二维码重新扫码';

  /// zh-Hans: '登录校验失败：{reason}'
  String qrVerifyFailed({required Object reason}) => '登录校验失败：${reason}';

  /// zh-Hans: '正在获取二维码'
  String get qrLoading => '正在获取二维码';

  /// zh-Hans: '用哔哩哔哩手机客户端扫描二维码'
  String get qrWaiting => '用哔哩哔哩手机客户端扫描二维码';

  /// zh-Hans: '已扫码，请在手机上确认登录'
  String get qrScanned => '已扫码，请在手机上确认登录';

  /// zh-Hans: '二维码已过期'
  String get qrExpired => '二维码已过期';

  /// zh-Hans: '正在校验登录'
  String get verifyingSignIn => '正在校验登录';

  /// zh-Hans: '已登录：{name}'
  String signedInName({required Object name}) => '已登录：${name}';

  /// zh-Hans: '登录失败'
  String get signInFailed => '登录失败';

  /// zh-Hans: '哔哩哔哩登录二维码'
  String get qrLabel => '哔哩哔哩登录二维码';

  /// zh-Hans: '刷新二维码'
  String get qrRefresh => '刷新二维码';

  late final Translations$accounts$cookieTip$zh_Hans cookieTip = Translations$accounts$cookieTip$zh_Hans.internal(
    _root,
  );

  /// zh-Hans: '先粘贴 Cookie'
  String get pasteCookieFirst => '先粘贴 Cookie';

  /// zh-Hans: '已保存，重新进入直播间后生效'
  String get cookieSavedRejoin => '已保存，重新进入直播间后生效';

  /// zh-Hans: '保存失败，请重试'
  String get saveFailed => '保存失败，请重试';

  /// zh-Hans: '已保存的 Cookie 不显示；粘贴新的会替换它'
  String get cookieHidden => '已保存的 Cookie 不显示；粘贴新的会替换它';

  /// zh-Hans: 'LTP0（续期用）'
  String get ltp0Label => 'LTP0（续期用）';

  /// zh-Hans: '已保存；留空保持不变'
  String get keptIfEmpty => '已保存；留空保持不变';

  /// zh-Hans: 'dy_did（设备标识）'
  String get didLabel => 'dy_did（设备标识）';

  /// zh-Hans: '没有要保存的内容'
  String get nothingToSave => '没有要保存的内容';

  /// zh-Hans: '已保存续期用的 LTP0 和 dy_did'
  String get douyuKeysSaved => '已保存续期用的 LTP0 和 dy_did';

  /// zh-Hans: '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did，原来的登录保留'
  String get passportKept => '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did，原来的登录保留';

  /// zh-Hans: '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did。还要粘贴 www.douyu.com 页面的 Cookie 才算登录'
  String get passportNeedsLogin => '这是 passport 请求的 Cookie：已保存 LTP0 和 dy_did。还要粘贴 www.douyu.com 页面的 Cookie 才算登录';

  /// zh-Hans: '粘贴的 Cookie 里没有登录信息，原来的登录保留'
  String get noLoginKept => '粘贴的 Cookie 里没有登录信息，原来的登录保留';

  /// zh-Hans: '已保存。{summary}'
  String savedWith({required Object summary}) => '已保存。${summary}';

  /// zh-Hans: '还没有保存斗鱼 Cookie'
  String get noDouyuCookie => '还没有保存斗鱼 Cookie';

  /// zh-Hans: '缺少 LTP0 或 dy_did，没法续期'
  String get renewMissingKeys => '缺少 LTP0 或 dy_did，没法续期';

  /// zh-Hans: 'Cookie 里没有登录信息，没法续期'
  String get renewNoLogin => 'Cookie 里没有登录信息，没法续期';

  /// zh-Hans: '斗鱼没有返回新的登录信息，续期没有生效'
  String get renewNoResult => '斗鱼没有返回新的登录信息，续期没有生效';

  /// zh-Hans: '已续期'
  String get renewed => '已续期';

  /// zh-Hans: '已续期，新的有效期到 {end}'
  String renewedUntil({required Object end}) => '已续期，新的有效期到 ${end}';

  /// zh-Hans: '续期失败：{reason}'
  String renewFailed({required Object reason}) => '续期失败：${reason}';

  /// zh-Hans: '退出{name}账号？'
  String signOutTitle({required Object name}) => '退出${name}账号？';

  /// zh-Hans: '会删除本机保存的登录信息。'
  String get signOutBody => '会删除本机保存的登录信息。';

  /// zh-Hans: '会删除本机保存的登录信息，并清除内置浏览器里的登录状态。'
  String get signOutBodyBrowser => '会删除本机保存的登录信息，并清除内置浏览器里的登录状态。';

  /// zh-Hans: '退出'
  String get signOut => '退出';

  /// zh-Hans: '已退出登录'
  String get signedOutToast => '已退出登录';

  /// zh-Hans: '{name}账号'
  String accountTitle({required Object name}) => '${name}账号';

  /// zh-Hans: '校验'
  String get verify => '校验';

  /// zh-Hans: '立即续期'
  String get renewNow => '立即续期';

  /// zh-Hans: '退出登录'
  String get signOutAction => '退出登录';

  /// zh-Hans: '换个账号登录'
  String get switchAccount => '换个账号登录';

  /// zh-Hans: '登录'
  String get signIn => '登录';

  /// zh-Hans: '已登录'
  String get signedInToast => '已登录';

  /// zh-Hans: '扫码登录'
  String get qrSignIn => '扫码登录';

  /// zh-Hans: '用哔哩哔哩手机客户端扫码'
  String get qrSignInSubtitle => '用哔哩哔哩手机客户端扫码';

  /// zh-Hans: '网页登录'
  String get webSignIn => '网页登录';

  /// zh-Hans: '在内置网页里用账号密码或短信登录'
  String get webSignInSubtitle => '在内置网页里用账号密码或短信登录';

  /// zh-Hans: '手动填写 Cookie'
  String get manualCookie => '手动填写 Cookie';

  /// zh-Hans: '更换 Cookie'
  String get replaceCookie => '更换 Cookie';

  /// zh-Hans: '填写 Cookie'
  String get enterCookie => '填写 Cookie';

  /// zh-Hans: '登录信息用本机的系统密钥加密保存，不会上传，界面和日志里都不显示；默认也不写进备份文件。'
  String get storageNoteFull => '登录信息用本机的系统密钥加密保存，不会上传，界面和日志里都不显示；默认也不写进备份文件。';

  /// zh-Hans: '读取登录信息失败，请重新登录'
  String get webReadFailed => '读取登录信息失败，请重新登录';

  /// zh-Hans: '没有拿到登录信息，请重新登录'
  String get webNoCookie => '没有拿到登录信息，请重新登录';

  /// zh-Hans: '登录校验没有通过，请重新登录'
  String get webRejected => '登录校验没有通过，请重新登录';

  /// zh-Hans: '网页登录 · {name}'
  String webTitle({required Object name}) => '网页登录 · ${name}';

  /// zh-Hans: '这里用不了网页登录'
  String get webUnavailable => '这里用不了网页登录';

  /// zh-Hans: '请改用扫码登录或手动填写 Cookie。'
  String get webUnavailableHint => '请改用扫码登录或手动填写 Cookie。';

  /// zh-Hans: '重新加载'
  String get reload => '重新加载';
}

// Path: alerts
class Translations$alerts$zh_Hans {
  Translations$alerts$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '没有通知权限，开播提醒保持关闭。可以在系统设置里允许本应用的通知后再打开'
  String get notificationsDenied => '没有通知权限，开播提醒保持关闭。可以在系统设置里允许本应用的通知后再打开';

  /// zh-Hans: '开播提醒'
  String get liveAlerts => '开播提醒';

  /// zh-Hans: '关注的主播开播时发通知，应用在后台运行时按刷新间隔检查；可在关注页对单个主播关闭'
  String get liveAlertsSubtitle => '关注的主播开播时发通知，应用在后台运行时按刷新间隔检查；可在关注页对单个主播关闭';

  /// zh-Hans: '这个系统上不支持通知'
  String get notificationsUnsupported => '这个系统上不支持通知';

  /// zh-Hans: '先在 设置 › 通用 打开开播提醒'
  String get enableAlertsFirst => '先在 设置 › 通用 打开开播提醒';

  /// zh-Hans: '这个主播开播时不提醒'
  String get roomAlertOff => '这个主播开播时不提醒';

  /// zh-Hans: '开播时发通知'
  String get roomAlertOn => '开播时发通知';

  /// zh-Hans: '已提醒'
  String get reminderSet => '已提醒';

  /// zh-Hans: '提醒我'
  String get remindMe => '提醒我';

  /// zh-Hans: '无法提醒'
  String get cannotRemind => '无法提醒';

  /// zh-Hans: '没有通知权限。可以在系统设置里允许本应用的通知后再设置节目提醒。'
  String get reminderDenied => '没有通知权限。可以在系统设置里允许本应用的通知后再设置节目提醒。';

  /// zh-Hans: '{name} 开播了'
  String wentLive({required Object name}) => '${name} 开播了';

  /// zh-Hans: '{first}等 {n} 位主播开播了'
  String manyWentLive({required Object first, required Object n}) => '${first}等 ${n} 位主播开播了';

  /// zh-Hans: '{names} 等'
  String namesAndMore({required Object names}) => '${names} 等';

  /// zh-Hans: '关注的主播开播时提醒'
  String get liveChannelDescription => '关注的主播开播时提醒';

  /// zh-Hans: '节目提醒'
  String get programmeReminders => '节目提醒';

  /// zh-Hans: '网络电视节目开始前 1 分钟提醒'
  String get programmeChannelDescription => '网络电视节目开始前 1 分钟提醒';

  /// zh-Hans: '{title} 即将开始'
  String programmeStarting({required Object title}) => '${title} 即将开始';

  /// zh-Hans: '{channel} · {time} 开始'
  String programmeBody({required Object channel, required Object time}) => '${channel} · ${time} 开始';
}

// Path: app
class Translations$app$zh_Hans {
  Translations$app$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '纯粹直播'
  String get name => '纯粹直播';

  /// zh-Hans: '纯粹直播 预览'
  String get previewName => '纯粹直播 预览';

  late final Translations$app$tabs$zh_Hans tabs = Translations$app$tabs$zh_Hans.internal(_root);

  /// zh-Hans: '展开导航栏'
  String get expandNavigation => '展开导航栏';

  /// zh-Hans: '收起导航栏'
  String get collapseNavigation => '收起导航栏';

  /// zh-Hans: '观看历史'
  String get history => '观看历史';

  /// zh-Hans: '录制中心'
  String get recordings => '录制中心';

  /// zh-Hans: '多画面'
  String get multiview => '多画面';

  /// zh-Hans: '平台账号'
  String get accounts => '平台账号';

  /// zh-Hans: '备份与同步'
  String get backup => '备份与同步';

  /// zh-Hans: '设置'
  String get settings => '设置';

  /// zh-Hans: '关于'
  String get about => '关于';

  /// zh-Hans: '预览版暂未开放'
  String get comingSoon => '预览版暂未开放';

  /// zh-Hans: '外观'
  String get appearance => '外观';

  /// zh-Hans: '跟随系统'
  String get themeSystem => '跟随系统';

  /// zh-Hans: '浅色'
  String get themeLight => '浅色';

  /// zh-Hans: '深色'
  String get themeDark => '深色';

  /// zh-Hans: '纯黑'
  String get themeBlack => '纯黑';

  /// zh-Hans: '版本'
  String get version => '版本';

  /// zh-Hans: '这是 v4 预览版，可以和 3.x 同时安装。'
  String get previewNotice => '这是 v4 预览版，可以和 3.x 同时安装。';

  /// zh-Hans: '网络已断开，恢复后列表和播放会重新加载'
  String get offlineBanner => '网络已断开，恢复后列表和播放会重新加载';
}

// Path: audience
class Translations$audience$zh_Hans {
  Translations$audience$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  Map<String, String> get notes => {
    'bilibili': '列表和弹幕心跳给的是人气值，本场累计看过另算，都不是同时在线人数',
    'douyu': '公开列表的数字按热度处理，不是真实人数',
    'huya': '列表、详情和直播间里的人数实测都是热度，没有单独的在线人数',
    'douyin': '在线人数取自房间数据；累计观看另算',
    'kuaishou': '当前观看人数',
    'cc': '热度和在线人数分开：webcc 热度与 vision 在线人数',
    'yy': '公开的人数按平台热度显示，没有单独的在线人数',
    'soop': 'PC 和移动端在线总人数',
    'acfun': '在线人数；点赞和粉丝数另算',
    'twitch': '当前同时观看人数',
    'iptv': '网络电视没有人数',
  };
}

// Path: backup
class Translations$backup$zh_Hans {
  Translations$backup$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '导出备份'
  String get exportTitle => '导出备份';

  /// zh-Hans: '(other) {口令至少 {n} 个字符}'
  String passphraseTooShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '口令至少 ${n} 个字符');

  /// zh-Hans: '两次输入的口令不一样'
  String get passphraseMismatch => '两次输入的口令不一样';

  /// zh-Hans: '完整备份'
  String get scopeFull => '完整备份';

  /// zh-Hans: '仅关注'
  String get scopeFollows => '仅关注';

  /// zh-Hans: '关注、分组、历史、屏蔽词、直播间偏好和设置'
  String get scopeFullDetail => '关注、分组、历史、屏蔽词、直播间偏好和设置';

  /// zh-Hans: '只有关注的直播间和关注的分区'
  String get scopeFollowsDetail => '只有关注的直播间和关注的分区';

  /// zh-Hans: '包含平台登录信息'
  String get includeAccounts => '包含平台登录信息';

  /// zh-Hans: 'Cookie 和 WebDAV 密码会用口令加密；导入时要输入同一个口令'
  String get includeAccountsDetail => 'Cookie 和 WebDAV 密码会用口令加密；导入时要输入同一个口令';

  /// zh-Hans: '口令'
  String get passphrase => '口令';

  /// zh-Hans: '再输入一次'
  String get passphraseRepeat => '再输入一次';

  /// zh-Hans: '请记住这个口令，忘记后账号信息无法恢复。'
  String get passphraseRemember => '请记住这个口令，忘记后账号信息无法恢复。';

  /// zh-Hans: '选择备份文件'
  String get pickBackupFile => '选择备份文件';

  /// zh-Hans: '保存备份'
  String get saveBackup => '保存备份';

  /// zh-Hans: '这个备份来自更新的版本，请先升级应用'
  String get errorTooNew => '这个备份来自更新的版本，请先升级应用';

  /// zh-Hans: '这是只含关注的备份，请用“仅恢复关注”'
  String get errorFollowsOnly => '这是只含关注的备份，请用“仅恢复关注”';

  /// zh-Hans: '不是可以识别的备份文件'
  String get errorUnknownFile => '不是可以识别的备份文件';

  /// zh-Hans: '另一个恢复正在进行，请稍后再试'
  String get errorBusy => '另一个恢复正在进行，请稍后再试';

  /// zh-Hans: '确认导入'
  String get confirmImport => '确认导入';

  /// zh-Hans: '口令不正确'
  String get wrongPassphrase => '口令不正确';

  /// zh-Hans: '平台登录信息不会导入。要继续导入其余内容吗？'
  String get skipAccountsQuestion => '平台登录信息不会导入。要继续导入其余内容吗？';

  /// zh-Hans: '继续导入'
  String get continueImport => '继续导入';

  /// zh-Hans: '导入完成'
  String get importDone => '导入完成';

  /// zh-Hans: '完整恢复'
  String get restoreFull => '完整恢复';

  /// zh-Hans: '仅恢复关注'
  String get restoreFollows => '仅恢复关注';

  /// zh-Hans: '备份里有的部分会替换本机的对应数据，备份里没有的部分保持不变。'
  String get restoreFullDetail => '备份里有的部分会替换本机的对应数据，备份里没有的部分保持不变。';

  /// zh-Hans: '只替换关注的直播间和关注的分区，其它数据不变。'
  String get restoreFollowsDetail => '只替换关注的直播间和关注的分区，其它数据不变。';

  /// zh-Hans: '备份里有加密的平台登录信息。输入导出时设置的口令可以一并导入，不填则跳过。'
  String get encryptedAccountsHint => '备份里有加密的平台登录信息。输入导出时设置的口令可以一并导入，不填则跳过。';

  /// zh-Hans: '口令（可选）'
  String get passphraseOptional => '口令（可选）';

  /// zh-Hans: '备份里有平台登录信息，会一并导入，并在本机加密保存。'
  String get plainAccountsHint => '备份里有平台登录信息，会一并导入，并在本机加密保存。';

  late final Translations$backup$section$zh_Hans section = Translations$backup$section$zh_Hans.internal(_root);

  /// zh-Hans: '备份格式：{format}'
  String format({required Object format}) => '备份格式：${format}';

  /// zh-Hans: '文件里没有可以导入的内容'
  String get nothingToImport => '文件里没有可以导入的内容';

  /// zh-Hans: '平台登录信息这次没有导入。'
  String get accountsSkipped => '平台登录信息这次没有导入。';

  /// zh-Hans: '(other) {读到 {n} 项}'
  String readCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '读到 ${n} 项');

  /// zh-Hans: '(other) {写入 {n} 项}'
  String writtenCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '写入 ${n} 项');

  /// zh-Hans: '(other) {，跳过 {n} 项}'
  String skippedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '，跳过 ${n} 项');

  /// zh-Hans: '{section}：{counts}'
  String sectionLine({required Object section, required Object counts}) => '${section}：${counts}';

  /// zh-Hans: '备份已保存'
  String get saved => '备份已保存';

  /// zh-Hans: '本地文件'
  String get localFiles => '本地文件';

  /// zh-Hans: '完整备份或仅关注；平台登录信息默认不包含，需要时用口令加密'
  String get exportSubtitle => '完整备份或仅关注；平台登录信息默认不包含，需要时用口令加密';

  /// zh-Hans: '支持 v4 和 3.x 的备份文件，只导入关注和关注的分区'
  String get restoreFollowsSubtitle => '支持 v4 和 3.x 的备份文件，只导入关注和关注的分区';

  /// zh-Hans: '导入备份里的全部内容，备份里没有的部分保持不变'
  String get restoreFullSubtitle => '导入备份里的全部内容，备份里没有的部分保持不变';

  /// zh-Hans: '把备份上传到坚果云、Nextcloud、群晖等网盘，在其它设备上恢复'
  String get webdavSubtitle => '把备份上传到坚果云、Nextcloud、群晖等网盘，在其它设备上恢复';

  /// zh-Hans: '局域网同步'
  String get lanSync => '局域网同步';

  /// zh-Hans: '同一网络下的两台设备直接传输，接收方确认后才会导入'
  String get lanSyncSubtitle => '同一网络下的两台设备直接传输，接收方确认后才会导入';

  /// zh-Hans: '备份与恢复'
  String get backupAndRestore => '备份与恢复';

  /// zh-Hans: '导出或导入备份文件，支持 3.x 的备份'
  String get backupAndRestoreSubtitle => '导出或导入备份文件，支持 3.x 的备份';

  /// zh-Hans: '诊断与日志'
  String get diagnostics => '诊断与日志';

  /// zh-Hans: '导出诊断包，查看最近的日志'
  String get diagnosticsSubtitle => '导出诊断包，查看最近的日志';

  /// zh-Hans: '崩溃报告'
  String get crashReports => '崩溃报告';

  /// zh-Hans: '出错后，下次启动时提示导出诊断包；不会自动上传'
  String get crashReportsSubtitle => '出错后，下次启动时提示导出诊断包；不会自动上传';

  /// zh-Hans: '识别剪贴板里的直播间'
  String get clipboardRooms => '识别剪贴板里的直播间';

  /// zh-Hans: '回到应用时，识别复制的分享口令或直播间链接并询问是否打开'
  String get clipboardRoomsSubtitle => '回到应用时，识别复制的分享口令或直播间链接并询问是否打开';

  /// zh-Hans: '好'
  String get okay => '好';
}

// Path: cast
class Translations$cast$zh_Hans {
  Translations$cast$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '还没有拿到直播地址，等画面出来后再投屏'
  String get noAddressYet => '还没有拿到直播地址，等画面出来后再投屏';

  /// zh-Hans: '当前线路不是 http(s) 地址，电视打不开'
  String get notHttp => '当前线路不是 http(s) 地址，电视打不开';

  /// zh-Hans: '当前线路的地址无效'
  String get invalidAddress => '当前线路的地址无效';

  /// zh-Hans: '当前线路是本机地址，电视访问不到'
  String get localAddress => '当前线路是本机地址，电视访问不到';

  /// zh-Hans: '直播'
  String get defaultTitle => '直播';

  late final Translations$cast$failure$zh_Hans failure = Translations$cast$failure$zh_Hans.internal(_root);
  late final Translations$cast$tv$zh_Hans tv = Translations$cast$tv$zh_Hans.internal(_root);

  /// zh-Hans: '停止命令没有送达，电视可能还在播放'
  String get stopNotDelivered => '停止命令没有送达，电视可能还在播放';

  /// zh-Hans: '投屏'
  String get title => '投屏';

  /// zh-Hans: '重新搜索'
  String get searchAgain => '重新搜索';

  /// zh-Hans: '当前地址不能投屏'
  String get cannotCast => '当前地址不能投屏';

  /// zh-Hans: '这个平台的直播流可能需要特殊请求头，电视上不一定能播'
  String get headersHint => '这个平台的直播流可能需要特殊请求头，电视上不一定能播';

  /// zh-Hans: '直播地址有时效，过期后电视会停止播放，重新投屏即可'
  String get expiresHint => '直播地址有时效，过期后电视会停止播放，重新投屏即可';

  /// zh-Hans: '投屏失败：{reason}'
  String failedWith({required Object reason}) => '投屏失败：${reason}';

  /// zh-Hans: '正在搜索同一 Wi-Fi 下的电视和盒子…'
  String get searching => '正在搜索同一 Wi-Fi 下的电视和盒子…';

  /// zh-Hans: '搜索中断，列表可能不完整'
  String get searchInterrupted => '搜索中断，列表可能不完整';

  /// zh-Hans: '搜索失败'
  String get searchFailed => '搜索失败';

  /// zh-Hans: '检查手机是否连着 Wi-Fi，然后重试'
  String get searchFailedHint => '检查手机是否连着 Wi-Fi，然后重试';

  /// zh-Hans: '没有找到可投屏的设备'
  String get noDevices => '没有找到可投屏的设备';

  /// zh-Hans: '确认电视或盒子已开机、打开了投屏（DLNA）功能，并且和手机连着同一个 Wi-Fi'
  String get noDevicesHint => '确认电视或盒子已开机、打开了投屏（DLNA）功能，并且和手机连着同一个 Wi-Fi';

  /// zh-Hans: '正在投这个直播间'
  String get castingThisRoom => '正在投这个直播间';

  /// zh-Hans: '正在投：{title}'
  String castingOther({required Object title}) => '正在投：${title}';

  /// zh-Hans: '已投到 {device}'
  String castTo({required Object device}) => '已投到 ${device}';

  /// zh-Hans: '停止投屏'
  String get stop => '停止投屏';
}

// Path: common
class Translations$common$zh_Hans {
  Translations$common$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '重试'
  String get retry => '重试';

  /// zh-Hans: '确定'
  String get ok => '确定';

  /// zh-Hans: '取消'
  String get cancel => '取消';

  /// zh-Hans: '保存'
  String get save => '保存';

  /// zh-Hans: '删除'
  String get delete => '删除';

  /// zh-Hans: '移除'
  String get remove => '移除';

  /// zh-Hans: '撤销'
  String get undo => '撤销';

  /// zh-Hans: '关闭'
  String get close => '关闭';

  /// zh-Hans: '刷新'
  String get refresh => '刷新';

  /// zh-Hans: '更多'
  String get more => '更多';

  /// zh-Hans: '复制'
  String get copy => '复制';

  /// zh-Hans: '已复制'
  String get copied => '已复制';

  /// zh-Hans: '添加'
  String get add => '添加';

  /// zh-Hans: '编辑'
  String get edit => '编辑';

  /// zh-Hans: '重命名'
  String get rename => '重命名';

  /// zh-Hans: '导入'
  String get import => '导入';

  /// zh-Hans: '导出'
  String get export => '导出';

  /// zh-Hans: '发送'
  String get send => '发送';

  /// zh-Hans: '开始'
  String get start => '开始';

  /// zh-Hans: '停止'
  String get stop => '停止';

  /// zh-Hans: '播放'
  String get play => '播放';

  /// zh-Hans: '暂停'
  String get pause => '暂停';

  /// zh-Hans: '继续'
  String get resume => '继续';

  /// zh-Hans: '返回'
  String get back => '返回';

  /// zh-Hans: '知道了'
  String get gotIt => '知道了';

  /// zh-Hans: '清空'
  String get clear => '清空';

  /// zh-Hans: '完成'
  String get done => '完成';

  /// zh-Hans: '退出'
  String get exit => '退出';

  /// zh-Hans: '全部'
  String get all => '全部';

  /// zh-Hans: '同步'
  String get sync => '同步';

  /// zh-Hans: '粘贴'
  String get paste => '粘贴';

  /// zh-Hans: '名称'
  String get name => '名称';

  /// zh-Hans: '用户名'
  String get username => '用户名';

  /// zh-Hans: '密码'
  String get password => '密码';

  /// zh-Hans: '读取失败'
  String get loadFailed => '读取失败';

  /// zh-Hans: '加载失败，点击重试'
  String get loadMoreFailed => '加载失败，点击重试';

  /// zh-Hans: '没有更多了'
  String get noMore => '没有更多了';

  /// zh-Hans: '这里还没有直播间'
  String get noRooms => '这里还没有直播间';

  /// zh-Hans: '打开直播间'
  String get openRoom => '打开直播间';

  /// zh-Hans: '关注'
  String get follow => '关注';

  /// zh-Hans: '已关注'
  String get followed => '已关注';

  /// zh-Hans: '取消关注'
  String get unfollow => '取消关注';

  /// zh-Hans: '打开原站'
  String get openSite => '打开原站';

  /// zh-Hans: '复制链接'
  String get copyLink => '复制链接';

  /// zh-Hans: '链接已复制'
  String get linkCopied => '链接已复制';

  /// zh-Hans: '未开播'
  String get offline => '未开播';

  /// zh-Hans: '回放中'
  String get replay => '回放中';

  /// zh-Hans: '暂不支持'
  String get unsupported => '暂不支持';

  /// zh-Hans: '无法打开链接'
  String get couldNotOpenLink => '无法打开链接';

  /// zh-Hans: '没能打开新窗口'
  String get couldNotOpenWindow => '没能打开新窗口';

  /// zh-Hans: '(other) {{n} 秒}'
  String seconds({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 秒');

  /// zh-Hans: '(other) {{n} 分钟}'
  String minutes({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分钟');

  /// zh-Hans: '{n} 条'
  String items({required Object n}) => '${n} 条';

  /// zh-Hans: '不限'
  String get unlimited => '不限';

  /// zh-Hans: '自动'
  String get auto => '自动';

  /// zh-Hans: '开启'
  String get on => '开启';

  /// zh-Hans: '关闭'
  String get off => '关闭';

  /// zh-Hans: '、'
  String get listSeparator => '、';

  /// zh-Hans: '操作失败：{error}'
  String error({required Object error}) => '操作失败：${error}';

  /// zh-Hans: '{month}月{day}日'
  String monthDay({required Object month, required Object day}) => '${month}月${day}日';
}

// Path: danmaku
class Translations$danmaku$zh_Hans {
  Translations$danmaku$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '屏蔽词和屏蔽用户'
  String get blockListTitle => '屏蔽词和屏蔽用户';

  /// zh-Hans: '关键词'
  String get blockKeywords => '关键词';

  /// zh-Hans: '用户'
  String get blockUsers => '用户';

  /// zh-Hans: '“{value}”已经在列表里'
  String alreadyBlocked({required Object value}) => '“${value}”已经在列表里';

  /// zh-Hans: '已移除“{value}”'
  String unblocked({required Object value}) => '已移除“${value}”';

  /// zh-Hans: '输入要屏蔽的词'
  String get keywordHint => '输入要屏蔽的词';

  /// zh-Hans: '输入要屏蔽的用户名'
  String get userHint => '输入要屏蔽的用户名';

  /// zh-Hans: '包含这个词的弹幕不显示'
  String get keywordHelper => '包含这个词的弹幕不显示';

  /// zh-Hans: '按用户名完全匹配'
  String get userHelper => '按用户名完全匹配';

  /// zh-Hans: '读取屏蔽列表失败'
  String get blockListLoadFailed => '读取屏蔽列表失败';

  /// zh-Hans: '还没有屏蔽词'
  String get noBlockedKeywords => '还没有屏蔽词';

  /// zh-Hans: '还没有屏蔽用户'
  String get noBlockedUsers => '还没有屏蔽用户';

  /// zh-Hans: '也可以在直播间里点一条弹幕来屏蔽'
  String get blockFromRoomHint => '也可以在直播间里点一条弹幕来屏蔽';

  /// zh-Hans: '屏蔽关键词'
  String get blockKeyword => '屏蔽关键词';

  /// zh-Hans: '屏蔽用户'
  String get blockUser => '屏蔽用户';

  /// zh-Hans: '已屏蔽关键词“{keyword}”'
  String keywordBlocked({required Object keyword}) => '已屏蔽关键词“${keyword}”';

  /// zh-Hans: '已屏蔽用户“{user}”'
  String userBlocked({required Object user}) => '已屏蔽用户“${user}”';

  /// zh-Hans: '包含这个词的弹幕都会被隐藏'
  String get blockKeywordHint => '包含这个词的弹幕都会被隐藏';

  /// zh-Hans: '不区分大小写'
  String get caseInsensitive => '不区分大小写';

  /// zh-Hans: '屏蔽'
  String get block => '屏蔽';

  /// zh-Hans: '弹幕已关闭'
  String get off => '弹幕已关闭';

  /// zh-Hans: '打开后连接弹幕，并在画面上显示'
  String get offHint => '打开后连接弹幕，并在画面上显示';

  /// zh-Hans: '打开弹幕'
  String get turnOn => '打开弹幕';

  /// zh-Hans: '未开播时没有弹幕'
  String get offlineNoDanmaku => '未开播时没有弹幕';

  /// zh-Hans: '发条本地弹幕'
  String get localHint => '发条本地弹幕';

  /// zh-Hans: '发送（只在本机显示）'
  String get localSend => '发送（只在本机显示）';

  /// zh-Hans: '重新连接'
  String get reconnect => '重新连接';

  /// zh-Hans: '弹幕设置'
  String get settings => '弹幕设置';

  /// zh-Hans: '新消息 {n}'
  String newMessages({required Object n}) => '新消息 ${n}';

  /// zh-Hans: '回到最新'
  String get jumpToLatest => '回到最新';

  late final Translations$danmaku$preset$zh_Hans preset = Translations$danmaku$preset$zh_Hans.internal(_root);

  /// zh-Hans: '显示弹幕'
  String get show => '显示弹幕';

  /// zh-Hans: '关闭后不再连接弹幕'
  String get showSubtitle => '关闭后不再连接弹幕';

  /// zh-Hans: '样式'
  String get style => '样式';

  /// zh-Hans: '字号'
  String get fontSize => '字号';

  /// zh-Hans: '字重'
  String get fontWeight => '字重';

  /// zh-Hans: '不透明度'
  String get opacity => '不透明度';

  /// zh-Hans: '速度（越大越快）'
  String get speedHint => '速度（越大越快）';

  /// zh-Hans: '显示区域'
  String get area => '显示区域';

  /// zh-Hans: '顶部留白'
  String get topMargin => '顶部留白';

  /// zh-Hans: '底部留白'
  String get bottomMargin => '底部留白';

  /// zh-Hans: '描边'
  String get stroke => '描边';

  /// zh-Hans: '描边粗细'
  String get strokeWidth => '描边粗细';

  /// zh-Hans: '隐藏表情'
  String get hideEmoji => '隐藏表情';

  /// zh-Hans: '只有表情的弹幕不显示'
  String get hideEmojiSubtitle => '只有表情的弹幕不显示';

  /// zh-Hans: '帧率自动'
  String get autoFps => '帧率自动';

  /// zh-Hans: '跟随“通用 › 刷新率”'
  String get autoFpsSubtitle => '跟随“通用 › 刷新率”';

  /// zh-Hans: '帧率'
  String get fps => '帧率';

  /// zh-Hans: '画面弹幕的点击'
  String get videoTaps => '画面弹幕的点击';

  /// zh-Hans: '点击弹幕'
  String get tapDanmaku => '点击弹幕';

  /// zh-Hans: '打开复制和屏蔽'
  String get opensActions => '打开复制和屏蔽';

  /// zh-Hans: '长按弹幕'
  String get longPressDanmaku => '长按弹幕';

  /// zh-Hans: '过滤'
  String get filters => '过滤';

  /// zh-Hans: '合并重复弹幕'
  String get collapseRepeated => '合并重复弹幕';

  /// zh-Hans: '合并窗口'
  String get collapseWindow => '合并窗口';

  /// zh-Hans: '过滤相似弹幕'
  String get filterSimilar => '过滤相似弹幕';

  /// zh-Hans: '热门房间里短弹幕可能被过滤'
  String get filterSimilarSubtitle => '热门房间里短弹幕可能被过滤';

  /// zh-Hans: '相似度阈值'
  String get similarityThreshold => '相似度阈值';

  /// zh-Hans: '比较最近'
  String get compareRecent => '比较最近';

  /// zh-Hans: '最多比较'
  String get compareMost => '最多比较';

  /// zh-Hans: '过滤斗鱼疑似机器人弹幕'
  String get douyuBots => '过滤斗鱼疑似机器人弹幕';

  /// zh-Hans: '默认关闭，可能误伤正常弹幕'
  String get douyuBotsSubtitle => '默认关闭，可能误伤正常弹幕';

  /// zh-Hans: '已应用“{name}”'
  String presetApplied({required Object name}) => '已应用“${name}”';

  /// zh-Hans: '保存为我的样式'
  String get saveMyStyle => '保存为我的样式';

  /// zh-Hans: '已保存当前弹幕样式'
  String get styleSaved => '已保存当前弹幕样式';

  /// zh-Hans: '恢复我的样式'
  String get restoreMyStyle => '恢复我的样式';

  /// zh-Hans: '已恢复保存的弹幕样式'
  String get styleRestored => '已恢复保存的弹幕样式';

  /// zh-Hans: '保存的样式已损坏，没能恢复'
  String get styleBroken => '保存的样式已损坏，没能恢复';

  /// zh-Hans: '画中画弹幕'
  String get pip => '画中画弹幕';

  /// zh-Hans: '画中画里显示弹幕'
  String get pipShow => '画中画里显示弹幕';

  /// zh-Hans: '速度'
  String get speed => '速度';

  /// zh-Hans: '同屏最多'
  String get maxOnScreen => '同屏最多';

  /// zh-Hans: '不显示表情'
  String get noEmoji => '不显示表情';

  /// zh-Hans: '正在连接弹幕…'
  String get connecting => '正在连接弹幕…';

  /// zh-Hans: '弹幕连接断开，正在重连…'
  String get reconnecting => '弹幕连接断开，正在重连…';

  /// zh-Hans: '弹幕已断开'
  String get disconnected => '弹幕已断开';

  /// zh-Hans: '这个平台暂不支持弹幕'
  String get unsupported => '这个平台暂不支持弹幕';

  /// zh-Hans: '正在播放录像，弹幕来自录像'
  String get replayMode => '正在播放录像，弹幕来自录像';

  /// zh-Hans: '未登录 B 站账号，观众昵称会被平台隐藏'
  String get bilibiliGuest => '未登录 B 站账号，观众昵称会被平台隐藏';

  /// zh-Hans: '弹幕连接超时'
  String get timeout => '弹幕连接超时';

  /// zh-Hans: '弹幕连接失败：取不到平台凭据'
  String get noCredentials => '弹幕连接失败：取不到平台凭据';

  /// zh-Hans: '弹幕连接被平台拒绝'
  String get rejected => '弹幕连接被平台拒绝';

  /// zh-Hans: '弹幕多次重连失败'
  String get retriesFailed => '弹幕多次重连失败';

  late final Translations$danmaku$audience$zh_Hans audience = Translations$danmaku$audience$zh_Hans.internal(_root);

  /// zh-Hans: '送出 {gift} ×{count}'
  String giftMany({required Object gift, required Object count}) => '送出 ${gift} ×${count}';

  /// zh-Hans: '送出 {gift}'
  String gift({required Object gift}) => '送出 ${gift}';

  /// zh-Hans: '我'
  String get localSender => '我';

  /// zh-Hans: '{name}：'
  String chatName({required Object name}) => '${name}：';
}

// Path: diagnostics
class Translations$diagnostics$zh_Hans {
  Translations$diagnostics$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '保存诊断包'
  String get saveBundle => '保存诊断包';

  /// zh-Hans: '诊断包已保存'
  String get bundleSaved => '诊断包已保存';

  /// zh-Hans: '导出失败：{error}'
  String exportFailed({required Object error}) => '导出失败：${error}';

  /// zh-Hans: '导出诊断包'
  String get exportBundle => '导出诊断包';

  /// zh-Hans: '版本、设备信息、设置和最近的日志，保存为一个 JSON 文件；不含 Cookie、密码等账号信息'
  String get exportBundleSubtitle => '版本、设备信息、设置和最近的日志，保存为一个 JSON 文件；不含 Cookie、密码等账号信息';

  /// zh-Hans: '出错后，下次启动时提示导出诊断包。不会自动上传任何数据'
  String get crashReportsSubtitle => '出错后，下次启动时提示导出诊断包。不会自动上传任何数据';

  /// zh-Hans: '最近的日志'
  String get recentLogs => '最近的日志';

  /// zh-Hans: '只保存在本机，最多约 768 KB，Cookie 和令牌写入前已去除'
  String get recentLogsSubtitle => '只保存在本机，最多约 768 KB，Cookie 和令牌写入前已去除';

  /// zh-Hans: '本次运行还没有日志'
  String get noLogs => '本次运行还没有日志';
}

// Path: discover
class Translations$discover$zh_Hans {
  Translations$discover$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '取消收藏分区'
  String get unfollowArea => '取消收藏分区';

  /// zh-Hans: '收藏分区'
  String get followArea => '收藏分区';

  /// zh-Hans: '分区信息已失效'
  String get areaGone => '分区信息已失效';

  /// zh-Hans: '已收藏'
  String get savedAreas => '已收藏';

  /// zh-Hans: '推荐'
  String get recommended => '推荐';

  /// zh-Hans: '分区'
  String get areas => '分区';
}

// Path: errors
class Translations$errors$zh_Hans {
  Translations$errors$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '频道不存在'
  String get channelMissing => '频道不存在';

  /// zh-Hans: '播放列表里已经没有这个频道，可能改名或被删除了。'
  String get channelMissingDetail => '播放列表里已经没有这个频道，可能改名或被删除了。';

  /// zh-Hans: '直播间不存在'
  String get roomMissing => '直播间不存在';

  /// zh-Hans: '房间号可能已经失效，或者主播换了房间。'
  String get roomMissingDetail => '房间号可能已经失效，或者主播换了房间。';

  /// zh-Hans: '需要登录'
  String get needsLogin => '需要登录';

  /// zh-Hans: '这个内容要登录平台账号后才能看，可以在“我的 → 平台账号”里登录。'
  String get needsLoginDetail => '这个内容要登录平台账号后才能看，可以在“我的 → 平台账号”里登录。';

  /// zh-Hans: '请求太频繁'
  String get rateLimited => '请求太频繁';

  /// zh-Hans: '平台限制了访问频率，等一会儿再试。'
  String get rateLimitedDetail => '平台限制了访问频率，等一会儿再试。';

  /// zh-Hans: '被平台风控拦截'
  String get riskControl => '被平台风控拦截';

  /// zh-Hans: '平台暂时拒绝了请求，稍后重试，或换个网络。'
  String get riskControlDetail => '平台暂时拒绝了请求，稍后重试，或换个网络。';

  /// zh-Hans: '当前地区看不了'
  String get regionBlocked => '当前地区看不了';

  /// zh-Hans: '平台限制了这个地区的访问，可以在设置里给这个平台配置代理。'
  String get regionBlockedDetail => '平台限制了这个地区的访问，可以在设置里给这个平台配置代理。';

  /// zh-Hans: '拿不到直播流'
  String get noStream => '拿不到直播流';

  /// zh-Hans: '平台暂时没有给出可以播放的线路，稍后再试。'
  String get noStreamDetail => '平台暂时没有给出可以播放的线路，稍后再试。';

  /// zh-Hans: '不支持这个链接'
  String get unsupportedLink => '不支持这个链接';

  /// zh-Hans: '目前支持斗鱼、虎牙、哔哩哔哩、抖音和快手的直播间链接。'
  String get unsupportedLinkDetail => '目前支持斗鱼、虎牙、哔哩哔哩、抖音和快手的直播间链接。';

  /// zh-Hans: '平台接口变了'
  String get apiChanged => '平台接口变了';

  /// zh-Hans: '需要更新应用才能继续使用这个平台。'
  String get apiChangedDetail => '需要更新应用才能继续使用这个平台。';

  /// zh-Hans: '网络连接失败'
  String get network => '网络连接失败';

  /// zh-Hans: '检查网络或代理设置后重试。'
  String get networkDetail => '检查网络或代理设置后重试。';

  /// zh-Hans: '平台暂不支持'
  String get platformUnsupported => '平台暂不支持';

  /// zh-Hans: '{name}已下线或这个版本还不支持，关注和观看历史会一直保留。'
  String platformUnsupportedDetail({required Object name}) => '${name}已下线或这个版本还不支持，关注和观看历史会一直保留。';

  /// zh-Hans: '出错了'
  String get generic => '出错了';

  /// zh-Hans: '原因还没有归类。可以重试；一直出现时，在“诊断与日志”里导出诊断包，附在问题反馈里。'
  String get genericDetail => '原因还没有归类。可以重试；一直出现时，在“诊断与日志”里导出诊断包，附在问题反馈里。';
}

// Path: follows
class Translations$follows$zh_Hans {
  Translations$follows$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '关注失败，没有保存，请重试'
  String get followFailed => '关注失败，没有保存，请重试';

  /// zh-Hans: '取消关注失败，关注还在，请重试'
  String get unfollowFailed => '取消关注失败，关注还在，请重试';

  /// zh-Hans: '已取消关注 {name}'
  String unfollowed({required Object name}) => '已取消关注 ${name}';

  /// zh-Hans: '撤销失败，没能恢复关注'
  String get undoFailed => '撤销失败，没能恢复关注';

  /// zh-Hans: '还没有关注的主播'
  String get emptyTitle => '还没有关注的主播';

  /// zh-Hans: '在发现或搜索里找到主播，进入直播间后点“关注”。'
  String get emptyMessage => '在发现或搜索里找到主播，进入直播间后点“关注”。';

  /// zh-Hans: '去发现'
  String get goDiscover => '去发现';

  /// zh-Hans: '粘贴链接'
  String get pasteLink => '粘贴链接';

  /// zh-Hans: '导入旧数据或备份'
  String get importData => '导入旧数据或备份';

  /// zh-Hans: '顺序没有保存，请重试'
  String get orderNotSaved => '顺序没有保存，请重试';

  /// zh-Hans: '调整顺序'
  String get reorder => '调整顺序';

  late final Translations$follows$sort$zh_Hans sort = Translations$follows$sort$zh_Hans.internal(_root);

  /// zh-Hans: '排序'
  String get sortTooltip => '排序';

  /// zh-Hans: '调整自定义顺序'
  String get editCustomOrder => '调整自定义顺序';

  /// zh-Hans: '一键多画面'
  String get openMultiview => '一键多画面';

  /// zh-Hans: '刷新开播状态'
  String get refreshStatus => '刷新开播状态';

  /// zh-Hans: '读取关注失败'
  String get loadFailed => '读取关注失败';

  /// zh-Hans: '开播的关注'
  String get liveFollows => '开播的关注';

  /// zh-Hans: '{name}已下线或这个版本还不支持，关注会一直保留'
  String platformRetired({required Object name}) => '${name}已下线或这个版本还不支持，关注会一直保留';

  /// zh-Hans: '上次开播 {ago}'
  String lastLive({required Object ago}) => '上次开播 ${ago}';

  late final Translations$follows$tag$zh_Hans tag = Translations$follows$tag$zh_Hans.internal(_root);

  /// zh-Hans: '{name} · 暂不支持'
  String unsupportedPlatform({required Object name}) => '${name} · 暂不支持';

  /// zh-Hans: '没能获取开播状态'
  String get unknownDetail => '没能获取开播状态';

  /// zh-Hans: '平台找不到这个房间'
  String get missingDetail => '平台找不到这个房间';

  /// zh-Hans: '正在轮播'
  String get replayDetail => '正在轮播';

  /// zh-Hans: '正在检查开播状态'
  String get checking => '正在检查开播状态';

  /// zh-Hans: '{platforms}刷新失败，这些主播的状态暂时未知'
  String refreshFailed({required Object platforms}) => '${platforms}刷新失败，这些主播的状态暂时未知';

  /// zh-Hans: '查看状态'
  String get viewStatus => '查看状态';

  late final Translations$follows$filter$zh_Hans filter = Translations$follows$filter$zh_Hans.internal(_root);

  /// zh-Hans: '管理分组'
  String get manageGroups => '管理分组';

  /// zh-Hans: '关注的主播都没开播'
  String get noneLive => '关注的主播都没开播';

  /// zh-Hans: '开播后会出现在这里；打开“开播提醒”可以第一时间知道。'
  String get noneLiveMessage => '开播后会出现在这里；打开“开播提醒”可以第一时间知道。';

  /// zh-Hans: '看全部关注'
  String get showAll => '看全部关注';

  /// zh-Hans: '全部关注 {n}'
  String allCount({required Object n}) => '全部关注 ${n}';

  /// zh-Hans: '未开播 {n}'
  String offlineCount({required Object n}) => '未开播 ${n}';

  /// zh-Hans: '未分组'
  String get ungrouped => '未分组';

  /// zh-Hans: '还没有分组'
  String get noGroups => '还没有分组';

  /// zh-Hans: '在“管理分组”新建分组，再从主播的更多菜单里设置分组'
  String get noGroupsHint => '在“管理分组”新建分组，再从主播的更多菜单里设置分组';

  /// zh-Hans: '这个分组还没有主播'
  String get groupEmpty => '这个分组还没有主播';

  /// zh-Hans: '新建分组'
  String get newGroup => '新建分组';

  /// zh-Hans: '分组名称'
  String get groupName => '分组名称';

  /// zh-Hans: '描述（可选）'
  String get groupDescription => '描述（可选）';

  /// zh-Hans: '比如：晚上常看的'
  String get groupDescriptionHint => '比如：晚上常看的';

  /// zh-Hans: '已经有叫“{name}”的分组了'
  String groupExists({required Object name}) => '已经有叫“${name}”的分组了';

  /// zh-Hans: '分组名称不能为空'
  String get groupNameEmpty => '分组名称不能为空';

  /// zh-Hans: '编辑分组'
  String get editGroup => '编辑分组';

  /// zh-Hans: '分组没有保存，请重试'
  String get groupNotSaved => '分组没有保存，请重试';

  /// zh-Hans: '设置分组 · {title}'
  String setGroupsFor({required Object title}) => '设置分组 · ${title}';

  /// zh-Hans: '分组可以把关注的主播归类，在关注页按分组查看。'
  String get groupsHint => '分组可以把关注的主播归类，在关注页按分组查看。';

  /// zh-Hans: '改名和描述'
  String get renameAndDescribe => '改名和描述';

  /// zh-Hans: '已删除分组“{name}”'
  String groupDeleted({required Object name}) => '已删除分组“${name}”';
}

// Path: fonts
class Translations$fonts$zh_Hans {
  Translations$fonts$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '“{font}”下载失败，检查网络或代理后重试'
  String downloadFailed({required Object font}) => '“${font}”下载失败，检查网络或代理后重试';

  /// zh-Hans: '“{name}”已下载'
  String downloaded({required Object name}) => '“${name}”已下载';

  /// zh-Hans: '已删除“{name}”，重启后不再占用内存'
  String deleted({required Object name}) => '已删除“${name}”，重启后不再占用内存';

  /// zh-Hans: '字体'
  String get title => '字体';

  /// zh-Hans: '读不到字体列表'
  String get listFailed => '读不到字体列表';

  /// zh-Hans: '系统字体'
  String get systemFont => '系统字体';

  /// zh-Hans: '正在使用'
  String get inUse => '正在使用';

  /// zh-Hans: '界面字体'
  String get appFont => '界面字体';

  /// zh-Hans: '弹幕字体'
  String get danmakuFont => '弹幕字体';

  /// zh-Hans: '界面改回系统字体'
  String get resetAppFont => '界面改回系统字体';

  /// zh-Hans: '弹幕改回系统字体'
  String get resetDanmakuFont => '弹幕改回系统字体';

  /// zh-Hans: '可下载的字体'
  String get downloadable => '可下载的字体';

  /// zh-Hans: '只列出允许自由使用和分发的字体（SIL OFL 1.1、IPA 字体许可）。字体文件较大，建议在 Wi-Fi 下下载。'
  String get downloadableNote => '只列出允许自由使用和分发的字体（SIL OFL 1.1、IPA 字体许可）。字体文件较大，建议在 Wi-Fi 下下载。';

  /// zh-Hans: '界面'
  String get useInterface => '界面';

  /// zh-Hans: '弹幕'
  String get useDanmaku => '弹幕';

  /// zh-Hans: '用于{uses}'
  String usedFor({required Object uses}) => '用于${uses}';

  /// zh-Hans: '和'
  String get and => '和';

  /// zh-Hans: '下载'
  String get download => '下载';

  /// zh-Hans: '使用'
  String get use => '使用';

  /// zh-Hans: '用作界面字体'
  String get useForInterface => '用作界面字体';

  /// zh-Hans: '用作弹幕字体'
  String get useForDanmaku => '用作弹幕字体';
}

// Path: health
class Translations$health$zh_Hans {
  Translations$health$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '图片缓存已清理'
  String get imageCacheCleared => '图片缓存已清理';

  /// zh-Hans: '清理图片缓存'
  String get clearImageCache => '清理图片缓存';

  /// zh-Hans: '正在计算'
  String get calculating => '正在计算';

  /// zh-Hans: '封面和头像缓存 {size} MB；关注、历史和录制不受影响'
  String imageCacheSize({required Object size}) => '封面和头像缓存 ${size} MB；关注、历史和录制不受影响';

  /// zh-Hans: '15 秒内没有响应'
  String get timeout => '15 秒内没有响应';

  /// zh-Hans: '重新检查'
  String get checkAgain => '重新检查';

  /// zh-Hans: '正在检查各平台'
  String get checkingAll => '正在检查各平台';

  /// zh-Hans: '检查失败'
  String get checkFailed => '检查失败';

  /// zh-Hans: '正常 · {ms} ms'
  String ok({required Object ms}) => '正常 · ${ms} ms';

  /// zh-Hans: '异常'
  String get failed => '异常';

  /// zh-Hans: '检查方式：请求各平台的分区列表。某个平台异常时，关注页和发现页会显示上次的内容，直播间可能打不开。'
  String get method => '检查方式：请求各平台的分区列表。某个平台异常时，关注页和发现页会显示上次的内容，直播间可能打不开。';
}

// Path: iptv
class Translations$iptv$zh_Hans {
  Translations$iptv$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '未同步'
  String get notSynced => '未同步';

  /// zh-Hans: '刚刚同步'
  String get syncedJustNow => '刚刚同步';

  /// zh-Hans: '(other) {{n} 分钟前同步}'
  String syncedMinutesAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分钟前同步');

  /// zh-Hans: '(other) {{n} 小时前同步}'
  String syncedHoursAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 小时前同步');

  /// zh-Hans: '{date} {time} 同步'
  String syncedAt({required Object date, required Object time}) => '${date} ${time} 同步';

  /// zh-Hans: '网址'
  String get url => '网址';

  /// zh-Hans: '名称（可不填）'
  String get nameOptional => '名称（可不填）';

  /// zh-Hans: '{channels} 个频道，{programmes} 个节目'
  String guideSummary({required Object channels, required Object programmes}) => '${channels} 个频道，${programmes} 个节目';

  /// zh-Hans: '添加节目单'
  String get addGuide => '添加节目单';

  /// zh-Hans: '已添加：{summary}'
  String guideAdded({required Object summary}) => '已添加：${summary}';

  /// zh-Hans: '选择节目单（XMLTV、JSON，可以是 .gz）'
  String get pickGuide => '选择节目单（XMLTV、JSON，可以是 .gz）';

  /// zh-Hans: '已同步：{summary}'
  String guideSynced({required Object summary}) => '已同步：${summary}';

  /// zh-Hans: '已复制来源地址'
  String get sourceCopied => '已复制来源地址';

  /// zh-Hans: '删除节目单'
  String get deleteGuide => '删除节目单';

  /// zh-Hans: '删除“{name}”和它的节目？'
  String deleteGuideConfirm({required Object name}) => '删除“${name}”和它的节目？';

  /// zh-Hans: '节目单'
  String get guide => '节目单';

  /// zh-Hans: '选一个节目单作为当前节目单；频道会按 tvg-id 和名称自动匹配。节目单只保存前后两天的节目。'
  String get guideHint => '选一个节目单作为当前节目单；频道会按 tvg-id 和名称自动匹配。节目单只保存前后两天的节目。';

  /// zh-Hans: '节目单源'
  String get guideSources => '节目单源';

  /// zh-Hans: '不使用节目单'
  String get noGuide => '不使用节目单';

  /// zh-Hans: '还没有节目单'
  String get noGuides => '还没有节目单';

  /// zh-Hans: '支持 XMLTV（.xml、.xml.gz）和 JSON 节目单'
  String get guideFormats => '支持 XMLTV（.xml、.xml.gz）和 JSON 节目单';

  /// zh-Hans: '播放列表提供的节目单'
  String get playlistGuide => '播放列表提供的节目单';

  /// zh-Hans: '从网址添加'
  String get addFromUrl => '从网址添加';

  /// zh-Hans: '从文件添加'
  String get addFromFile => '从文件添加';

  /// zh-Hans: '(other) {{n} 个频道 · {synced}}'
  String channelsAndSynced({required num n, required Object synced}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 个频道 · ${synced}');

  /// zh-Hans: '上次同步失败：{error}'
  String lastSyncFailed({required Object error}) => '上次同步失败：${error}';

  /// zh-Hans: '自动同步'
  String get autoSync => '自动同步';

  /// zh-Hans: '复制来源地址'
  String get copySource => '复制来源地址';

  /// zh-Hans: '还没有播放列表'
  String get noPlaylists => '还没有播放列表';

  /// zh-Hans: '导入 M3U、TXT 或 JSON 播放列表后，频道会按分组出现在这里，可以像直播间一样关注。'
  String get noPlaylistsHint => '导入 M3U、TXT 或 JSON 播放列表后，频道会按分组出现在这里，可以像直播间一样关注。';

  /// zh-Hans: '导入播放列表'
  String get importPlaylist => '导入播放列表';

  /// zh-Hans: '全部频道'
  String get allChannels => '全部频道';

  /// zh-Hans: '分组'
  String get groups => '分组';

  /// zh-Hans: '未分组'
  String get ungrouped => '未分组';

  /// zh-Hans: '管理播放列表'
  String get managePlaylists => '管理播放列表';

  /// zh-Hans: '播放列表里还没有频道'
  String get noChannels => '播放列表里还没有频道';

  /// zh-Hans: '这个播放列表还没有同步'
  String get playlistNotSynced => '这个播放列表还没有同步';

  /// zh-Hans: '“{name}”：{channels} 个频道，{lines} 条线路'
  String importSummary({required Object name, required Object channels, required Object lines}) =>
      '“${name}”：${channels} 个频道，${lines} 条线路';

  /// zh-Hans: '“{name}”：{channels} 个频道，{lines} 条线路，跳过 {skipped} 行'
  String importSummarySkipped({
    required Object name,
    required Object channels,
    required Object lines,
    required Object skipped,
  }) => '“${name}”：${channels} 个频道，${lines} 条线路，跳过 ${skipped} 行';

  /// zh-Hans: '从网址导入'
  String get importFromUrl => '从网址导入';

  /// zh-Hans: '已导入{summary}'
  String imported({required Object summary}) => '已导入${summary}';

  /// zh-Hans: '已登录并导入{summary}'
  String signedInAndImported({required Object summary}) => '已登录并导入${summary}';

  /// zh-Hans: '选择播放列表（M3U、TXT、JSON）'
  String get pickPlaylist => '选择播放列表（M3U、TXT、JSON）';

  /// zh-Hans: '分享的播放列表.m3u'
  String get sharedFileName => '分享的播放列表.m3u';

  /// zh-Hans: '导入分享的播放列表'
  String get importShared => '导入分享的播放列表';

  /// zh-Hans: '全部同步完成'
  String get allSynced => '全部同步完成';

  /// zh-Hans: '(other) {同步完成，{n} 个来源失败}'
  String syncedWithFailures({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '同步完成，${n} 个来源失败');

  /// zh-Hans: '已同步{summary}'
  String syncedPlaylist({required Object summary}) => '已同步${summary}';

  /// zh-Hans: '这个列表的 User-Agent'
  String get playlistUserAgent => '这个列表的 User-Agent';

  /// zh-Hans: '留空则用全局设置'
  String get userAgentEmpty => '留空则用全局设置';

  /// zh-Hans: '下载列表和播放频道时发送；频道自己指定的优先'
  String get playlistUserAgentHint => '下载列表和播放频道时发送；频道自己指定的优先';

  /// zh-Hans: '删除播放列表'
  String get deletePlaylist => '删除播放列表';

  /// zh-Hans: '(other) {删除“{name}”和它的 {n} 个频道？关注的频道会保留，但会显示“频道不存在”。}'
  String deletePlaylistConfirm({required num n, required Object name}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '删除“${name}”和它的 ${n} 个频道？关注的频道会保留，但会显示“频道不存在”。',
      );

  /// zh-Hans: '网络电视'
  String get title => '网络电视';

  /// zh-Hans: '全部同步'
  String get syncAll => '全部同步';

  /// zh-Hans: '播放列表'
  String get playlists => '播放列表';

  /// zh-Hans: '从文件或网址导入 M3U、TXT、JSON 播放列表，频道会出现在“发现 › 网络电视”里'
  String get playlistsHint => '从文件或网址导入 M3U、TXT、JSON 播放列表，频道会出现在“发现 › 网络电视”里';

  /// zh-Hans: '读取播放列表失败'
  String get playlistsLoadFailed => '读取播放列表失败';

  /// zh-Hans: '从文件导入'
  String get importFromFile => '从文件导入';

  /// zh-Hans: 'Xtream 账号'
  String get xtreamAccount => 'Xtream 账号';

  /// zh-Hans: '未添加，导入 XMLTV 或 JSON 节目单后可以看节目和回看'
  String get noGuideAdded => '未添加，导入 XMLTV 或 JSON 节目单后可以看节目和回看';

  /// zh-Hans: '未选择'
  String get noGuideSelected => '未选择';

  /// zh-Hans: '当前：{name}'
  String currentGuide({required Object name}) => '当前：${name}';

  /// zh-Hans: '启动 3 秒后同步到期的网址列表和节目单'
  String get autoSyncHint => '启动 3 秒后同步到期的网址列表和节目单';

  /// zh-Hans: '同步间隔'
  String get syncInterval => '同步间隔';

  /// zh-Hans: '每 6 小时'
  String get every6h => '每 6 小时';

  /// zh-Hans: '每 12 小时'
  String get every12h => '每 12 小时';

  /// zh-Hans: '每天'
  String get daily => '每天';

  /// zh-Hans: '每 2 天'
  String get every2d => '每 2 天';

  /// zh-Hans: '每 3 天'
  String get every3d => '每 3 天';

  /// zh-Hans: '每周'
  String get weekly => '每周';

  /// zh-Hans: '自定义 User-Agent'
  String get customUserAgent => '自定义 User-Agent';

  /// zh-Hans: '未设置（使用播放器默认值）'
  String get userAgentUnset => '未设置（使用播放器默认值）';

  /// zh-Hans: '例如 okhttp/4.12.0'
  String get userAgentExample => '例如 okhttp/4.12.0';

  /// zh-Hans: '下载列表、节目单和播放频道时发送；列表或频道自己指定的优先'
  String get userAgentHint => '下载列表、节目单和播放频道时发送；列表或频道自己指定的优先';

  /// zh-Hans: '未同步，点同步获取频道'
  String get notSyncedHint => '未同步，点同步获取频道';

  /// zh-Hans: '不参与自动同步'
  String get noAutoSync => '不参与自动同步';

  /// zh-Hans: '填写服务器地址（例如 http://example.com:8080）、用户名和密码'
  String get xtreamHint => '填写服务器地址（例如 http://example.com:8080）、用户名和密码';

  /// zh-Hans: '登录 Xtream 账号'
  String get xtreamSignIn => '登录 Xtream 账号';

  /// zh-Hans: '服务器地址'
  String get serverAddress => '服务器地址';

  /// zh-Hans: '显示密码'
  String get showPassword => '显示密码';

  /// zh-Hans: '隐藏密码'
  String get hidePassword => '隐藏密码';

  /// zh-Hans: '用户名和密码只加密保存在本机，备份和同步里不含明文。'
  String get xtreamStorageNote => '用户名和密码只加密保存在本机，备份和同步里不含明文。';

  /// zh-Hans: '登录并导入'
  String get signInAndImport => '登录并导入';

  /// zh-Hans: '已回到直播'
  String get backToLive => '已回到直播';

  /// zh-Hans: '回到直播失败，可以点画面上的重试'
  String get backToLiveFailed => '回到直播失败，可以点画面上的重试';

  /// zh-Hans: '节目还没开始'
  String get notStarted => '节目还没开始';

  /// zh-Hans: '正在回看：{title}'
  String catchingUp({required Object title}) => '正在回看：${title}';

  /// zh-Hans: '这个节目不能回看'
  String get noCatchUp => '这个节目不能回看';

  /// zh-Hans: '这个频道没有开放回看'
  String get channelNoCatchUp => '这个频道没有开放回看';

  /// zh-Hans: '超出了回看的时间范围'
  String get outOfCatchUpWindow => '超出了回看的时间范围';

  /// zh-Hans: '正在播出'
  String get onAir => '正在播出';

  /// zh-Hans: '回看中'
  String get catchUp => '回看中';

  /// zh-Hans: '(other) {{n} 条线路}'
  String lines({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 条线路');

  /// zh-Hans: '接下来 {time} {title}'
  String upNext({required Object time, required Object title}) => '接下来 ${time} ${title}';

  /// zh-Hans: '正在读取节目单…'
  String get loadingGuide => '正在读取节目单…';

  /// zh-Hans: '没有匹配到节目单：添加或更换节目单源后会自动匹配'
  String get noGuideMatch => '没有匹配到节目单：添加或更换节目单源后会自动匹配';

  /// zh-Hans: '节目单里暂时没有这个时段的节目'
  String get noProgrammeNow => '节目单里暂时没有这个时段的节目';

  /// zh-Hans: '回到直播'
  String get returnToLive => '回到直播';

  /// zh-Hans: '今天'
  String get today => '今天';

  /// zh-Hans: '昨天'
  String get yesterday => '昨天';

  /// zh-Hans: '前天'
  String get dayBeforeYesterday => '前天';

  /// zh-Hans: '明天'
  String get tomorrow => '明天';

  /// zh-Hans: '{label} {date}'
  String dayWithDate({required Object label, required Object date}) => '${label} ${date}';

  /// zh-Hans: '读取节目单失败'
  String get guideLoadFailed => '读取节目单失败';

  /// zh-Hans: '没有节目'
  String get noProgrammes => '没有节目';

  /// zh-Hans: '节目单里没有这个频道前后两天的节目。'
  String get noProgrammesHint => '节目单里没有这个频道前后两天的节目。';

  /// zh-Hans: '不可回看'
  String get noCatchUpTag => '不可回看';

  late final Translations$iptv$error$zh_Hans error = Translations$iptv$error$zh_Hans.internal(_root);

  /// zh-Hans: '{title} 节目单'
  String xtreamGuideName({required Object title}) => '${title} 节目单';

  /// zh-Hans: '播放列表'
  String get defaultPlaylistName => '播放列表';

  late final Translations$iptv$xtream$zh_Hans xtream = Translations$iptv$xtream$zh_Hans.internal(_root);
}

// Path: me
class Translations$me$zh_Hans {
  Translations$me$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '深色时用纯黑背景，适合 OLED 屏幕'
  String get pureBlackSubtitle => '深色时用纯黑背景，适合 OLED 屏幕';

  /// zh-Hans: '关注页紧凑卡片'
  String get denseFollows => '关注页紧凑卡片';

  /// zh-Hans: '主播名和标题放在一行，一屏显示更多直播间'
  String get denseFollowsSubtitle => '主播名和标题放在一行，一屏显示更多直播间';

  /// zh-Hans: '已清空观看历史'
  String get historyCleared => '已清空观看历史';

  /// zh-Hans: '还没有观看记录'
  String get noHistory => '还没有观看记录';

  /// zh-Hans: 'IPTV 播放列表、节目单和自动同步'
  String get iptvSubtitle => 'IPTV 播放列表、节目单和自动同步';

  /// zh-Hans: '备份文件、WebDAV、局域网同步；可以导入 3.x 的备份'
  String get backupSubtitle => '备份文件、WebDAV、局域网同步；可以导入 3.x 的备份';

  /// zh-Hans: '版本 {version} · 更新、开源许可'
  String aboutSubtitle({required Object version}) => '版本 ${version} · 更新、开源许可';
}

// Path: multiview
class Translations$multiview$zh_Hans {
  Translations$multiview$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '添加直播间'
  String get addRoom => '添加直播间';

  /// zh-Hans: '{name} 未开播 点这里换一个'
  String offlineCell({required Object name}) => '${name} 未开播\n点这里换一个';

  /// zh-Hans: '播放中断'
  String get interrupted => '播放中断';

  /// zh-Hans: '关闭弹幕'
  String get danmakuOff => '关闭弹幕';

  /// zh-Hans: '开启弹幕'
  String get danmakuOn => '开启弹幕';

  /// zh-Hans: '画质'
  String get quality => '画质';

  /// zh-Hans: '线路'
  String get line => '线路';

  /// zh-Hans: '音量'
  String get volume => '音量';

  /// zh-Hans: '退出全屏'
  String get exitFullscreen => '退出全屏';

  /// zh-Hans: '全屏'
  String get fullscreen => '全屏';

  /// zh-Hans: '一大多小'
  String get onePlusN => '一大多小';

  /// zh-Hans: '沉浸模式'
  String get immersive => '沉浸模式';

  /// zh-Hans: '退出沉浸模式'
  String get exitImmersive => '退出沉浸模式';

  /// zh-Hans: '布局'
  String get layout => '布局';

  /// zh-Hans: '添加画面'
  String get addCell => '添加画面';

  /// zh-Hans: '(other) {已达上限：本设备最多同时播放 {n} 路}'
  String capacityReached({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '已达上限：本设备最多同时播放 ${n} 路');

  /// zh-Hans: '(other) {本设备最多同时播放 {n} 路画面，先关掉一格再添加}'
  String capacityHint({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '本设备最多同时播放 ${n} 路画面，先关掉一格再添加');

  /// zh-Hans: '取消全部静音'
  String get unmuteAll => '取消全部静音';

  /// zh-Hans: '全部静音'
  String get muteAll => '全部静音';

  /// zh-Hans: '所选画面音量'
  String get selectedVolume => '所选画面音量';

  /// zh-Hans: '选择直播间 · 放到第 {n} 格'
  String pickRoomFor({required Object n}) => '选择直播间 · 放到第 ${n} 格';

  /// zh-Hans: '按主播名或标题筛选'
  String get filterHint => '按主播名或标题筛选';

  /// zh-Hans: '放到这里'
  String get pickTarget => '放到这里';

  /// zh-Hans: '第 {n} 格'
  String cell({required Object n}) => '第 ${n} 格';

  /// zh-Hans: '换房'
  String get switchRoom => '换房';

  /// zh-Hans: '线路 {n}'
  String lineN({required Object n}) => '线路 ${n}';

  /// zh-Hans: '这一格没有在播放'
  String get cellIdle => '这一格没有在播放';

  /// zh-Hans: '已全部静音；音量按直播间保存，取消静音后生效'
  String get allMutedHint => '已全部静音；音量按直播间保存，取消静音后生效';

  /// zh-Hans: '音量按直播间保存'
  String get volumePerRoom => '音量按直播间保存';

  /// zh-Hans: '音量按直播间保存；这一格成为声音来源后生效'
  String get volumeNotSource => '音量按直播间保存；这一格成为声音来源后生效';
}

// Path: onboarding
class Translations$onboarding$zh_Hans {
  Translations$onboarding$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '欢迎使用{app} v4'
  String welcome({required Object app}) => '欢迎使用${app} v4';

  /// zh-Hans: '预览版是单独安装的，读不到 3.x 里的数据。可以把 3.x 或其它设备上的关注和设置导入进来，也可以直接开始。'
  String get intro => '预览版是单独安装的，读不到 3.x 里的数据。可以把 3.x 或其它设备上的关注和设置导入进来，也可以直接开始。';

  /// zh-Hans: '从备份文件导入'
  String get fromFile => '从备份文件导入';

  /// zh-Hans: '3.x 的“备份与恢复”导出的文件，或 v4 的备份文件'
  String get fromFileSubtitle => '3.x 的“备份与恢复”导出的文件，或 v4 的备份文件';

  /// zh-Hans: '从 WebDAV 导入'
  String get fromWebdav => '从 WebDAV 导入';

  /// zh-Hans: '之前上传到坚果云、Nextcloud 等网盘的备份'
  String get fromWebdavSubtitle => '之前上传到坚果云、Nextcloud 等网盘的备份';

  /// zh-Hans: '从另一台设备导入'
  String get fromDevice => '从另一台设备导入';

  /// zh-Hans: '同一网络下，由另一台设备通过局域网同步发送过来'
  String get fromDeviceSubtitle => '同一网络下，由另一台设备通过局域网同步发送过来';

  /// zh-Hans: '跳过，直接开始'
  String get skip => '跳过，直接开始';

  /// zh-Hans: '以后可以在 我的 › 备份与同步 里随时导入。'
  String get laterHint => '以后可以在 我的 › 备份与同步 里随时导入。';

  /// zh-Hans: '上次运行时出现了错误。导出诊断包附在问题反馈里，可以帮助定位原因'
  String get crashPrompt => '上次运行时出现了错误。导出诊断包附在问题反馈里，可以帮助定位原因';
}

// Path: quality
class Translations$quality$zh_Hans {
  Translations$quality$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '原画'
  String get original => '原画';

  /// zh-Hans: '蓝光 8M'
  String get bluRay8M => '蓝光 8M';

  /// zh-Hans: '蓝光 4M'
  String get bluRay4M => '蓝光 4M';

  /// zh-Hans: '超清'
  String get superHigh => '超清';

  /// zh-Hans: '流畅'
  String get smooth => '流畅';
}

// Path: recording
class Translations$recording$zh_Hans {
  Translations$recording$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$recording$notice$zh_Hans notice = Translations$recording$notice$zh_Hans.internal(_root);

  /// zh-Hans: '取消预约录制'
  String get cancelSchedule => '取消预约录制';

  /// zh-Hans: '预约录制'
  String get schedule => '预约录制';

  late final Translations$recording$state$zh_Hans state = Translations$recording$state$zh_Hans.internal(_root);
  late final Translations$recording$failure$zh_Hans failure = Translations$recording$failure$zh_Hans.internal(_root);
  late final Translations$recording$stage$zh_Hans stage = Translations$recording$stage$zh_Hans.internal(_root);

  /// zh-Hans: '停止录制'
  String get stopTitle => '停止录制';

  /// zh-Hans: '停止录制“{name}”？已录的部分会保存。'
  String stopConfirm({required Object name}) => '停止录制“${name}”？已录的部分会保存。';

  /// zh-Hans: '移除监控'
  String get removeWatch => '移除监控';

  /// zh-Hans: '不再等待“{name}”开播？已录的文件会保留。'
  String removeWatchConfirm({required Object name}) => '不再等待“${name}”开播？已录的文件会保留。';

  /// zh-Hans: '删除录制任务'
  String get deleteTask => '删除录制任务';

  /// zh-Hans: '删除“{name}”的录制任务？正在进行的录制会先停止，已录的文件会保留。'
  String deleteTaskRunning({required Object name}) => '删除“${name}”的录制任务？正在进行的录制会先停止，已录的文件会保留。';

  /// zh-Hans: '删除“{name}”的录制任务？已录的文件会保留。'
  String deleteTaskConfirm({required Object name}) => '删除“${name}”的录制任务？已录的文件会保留。';

  /// zh-Hans: '也可以在直播间里点录制按钮。'
  String get recordFromRoomHint => '也可以在直播间里点录制按钮。';

  /// zh-Hans: '从关注里选择'
  String get pickFromFollows => '从关注里选择';

  /// zh-Hans: '录制设置'
  String get settings => '录制设置';

  /// zh-Hans: '添加录制'
  String get add => '添加录制';

  /// zh-Hans: '还没有录制任务'
  String get noTasks => '还没有录制任务';

  /// zh-Hans: '在直播间点录制，或者从关注里添加。开启开播监控后，主播开播会自动开始录制。'
  String get noTasksHint => '在直播间点录制，或者从关注里添加。开启开播监控后，主播开播会自动开始录制。';

  /// zh-Hans: '定时录制'
  String get scheduled => '定时录制';

  /// zh-Hans: '录制任务'
  String get tasks => '录制任务';

  /// zh-Hans: '文件夹路径已复制：{path}'
  String folderCopied({required Object path}) => '文件夹路径已复制：${path}';

  /// zh-Hans: '缺口 {n}'
  String gaps({required Object n}) => '缺口 ${n}';

  /// zh-Hans: '{problem} · 出错环节：{stage}'
  String problemWithStage({required Object problem, required Object stage}) => '${problem} · 出错环节：${stage}';

  /// zh-Hans: '下次检查 {time}'
  String nextCheck({required Object time}) => '下次检查 ${time}';

  /// zh-Hans: '停止监控'
  String get stopWatch => '停止监控';

  /// zh-Hans: '取消排队'
  String get cancelQueue => '取消排队';

  /// zh-Hans: '开始录制'
  String get start => '开始录制';

  /// zh-Hans: '重新录制'
  String get restart => '重新录制';

  /// zh-Hans: '立即检查开播'
  String get checkNow => '立即检查开播';

  /// zh-Hans: '强制开始'
  String get forceStart => '强制开始';

  /// zh-Hans: '重试转封装'
  String get retryRemux => '重试转封装';

  /// zh-Hans: '打开文件夹'
  String get openFolder => '打开文件夹';

  /// zh-Hans: '删除任务（保留文件）'
  String get deleteKeepFiles => '删除任务（保留文件）';

  /// zh-Hans: '取消定时录制'
  String get cancelScheduled => '取消定时录制';
}

// Path: room
class Translations$room$zh_Hans {
  Translations$room$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$room$failure$zh_Hans failure = Translations$room$failure$zh_Hans.internal(_root);

  /// zh-Hans: '网络不稳，已切到{quality}，可以在画质里换回'
  String autoLowered({required Object quality}) => '网络不稳，已切到${quality}，可以在画质里换回';

  /// zh-Hans: '切换纯音频失败，已恢复画面'
  String get audioOnlyFailed => '切换纯音频失败，已恢复画面';

  /// zh-Hans: '恢复画面失败，仍为纯音频'
  String get restoreVideoFailed => '恢复画面失败，仍为纯音频';

  /// zh-Hans: '音量 {percent}%'
  String volumeHint({required Object percent}) => '音量 ${percent}%';

  /// zh-Hans: '弹幕已打开'
  String get danmakuShown => '弹幕已打开';

  /// zh-Hans: '弹幕已关闭'
  String get danmakuHidden => '弹幕已关闭';

  /// zh-Hans: '画面出来后才能进入画中画'
  String get pipNeedsVideo => '画面出来后才能进入画中画';

  /// zh-Hans: '没有找到对应的 App，改用浏览器打开'
  String get noApp => '没有找到对应的 App，改用浏览器打开';

  /// zh-Hans: '亮度 {percent}%'
  String brightnessHint({required Object percent}) => '亮度 ${percent}%';

  late final Translations$room$fit$zh_Hans fit = Translations$room$fit$zh_Hans.internal(_root);

  /// zh-Hans: '当前没有画面可以截图'
  String get noFrameToCapture => '当前没有画面可以截图';

  /// zh-Hans: '截图已保存：{path}'
  String screenshotSaved({required Object path}) => '截图已保存：${path}';

  /// zh-Hans: '截图失败：{error}'
  String screenshotFailed({required Object error}) => '截图失败：${error}';

  late final Translations$room$sleep$zh_Hans sleep = Translations$room$sleep$zh_Hans.internal(_root);

  /// zh-Hans: '继续播放'
  String get resumePlayback => '继续播放';

  /// zh-Hans: '当前线路出错，可以重试或换线路'
  String get lineFailedMany => '当前线路出错，可以重试或换线路';

  /// zh-Hans: '可以稍后重试'
  String get lineFailedOne => '可以稍后重试';

  /// zh-Hans: '换线路'
  String get switchLine => '换线路';

  /// zh-Hans: '解锁'
  String get unlock => '解锁';

  /// zh-Hans: '锁定'
  String get lock => '锁定';

  /// zh-Hans: '切换直播间'
  String get switchRoom => '切换直播间';

  /// zh-Hans: '收起聊天'
  String get hideChat => '收起聊天';

  /// zh-Hans: '聊天'
  String get chat => '聊天';

  /// zh-Hans: '恢复画面'
  String get restoreVideo => '恢复画面';

  /// zh-Hans: '纯音频'
  String get audioOnly => '纯音频';

  /// zh-Hans: '投屏'
  String get cast => '投屏';

  /// zh-Hans: '打开弹幕 (D)'
  String get danmakuOnKey => '打开弹幕 (D)';

  /// zh-Hans: '关闭弹幕 (D)'
  String get danmakuOffKey => '关闭弹幕 (D)';

  /// zh-Hans: '取消静音 (M)'
  String get unmuteKey => '取消静音 (M)';

  /// zh-Hans: '静音 (M)'
  String get muteKey => '静音 (M)';

  /// zh-Hans: '完整显示画面'
  String get showWholePicture => '完整显示画面';

  /// zh-Hans: '铺满屏幕'
  String get fillScreen => '铺满屏幕';

  /// zh-Hans: '画面方向'
  String get orientation => '画面方向';

  /// zh-Hans: '自动识别'
  String get orientationAuto => '自动识别';

  /// zh-Hans: '按竖屏处理'
  String get orientationPortrait => '按竖屏处理';

  /// zh-Hans: '按横屏处理'
  String get orientationLandscape => '按横屏处理';

  /// zh-Hans: '画面比例'
  String get aspect => '画面比例';

  /// zh-Hans: '退出剧场 (T)'
  String get exitTheaterKey => '退出剧场 (T)';

  /// zh-Hans: '剧场模式 (T)'
  String get theaterKey => '剧场模式 (T)';

  /// zh-Hans: '收起聊天栏 (C)'
  String get hideChatKey => '收起聊天栏 (C)';

  /// zh-Hans: '显示聊天栏 (C)'
  String get showChatKey => '显示聊天栏 (C)';

  /// zh-Hans: '画中画 (P)'
  String get pipKey => '画中画 (P)';

  /// zh-Hans: '退出全屏 (F)'
  String get exitFullscreenKey => '退出全屏 (F)';

  /// zh-Hans: '全屏 (F)'
  String get fullscreenKey => '全屏 (F)';

  /// zh-Hans: '纯音频播放中'
  String get audioOnlyPlaying => '纯音频播放中';

  /// zh-Hans: '要先在录制设置里打开“定时检查开播”'
  String get enableMonitoringFirst => '要先在录制设置里打开“定时检查开播”';

  /// zh-Hans: '去设置'
  String get goToSettings => '去设置';

  /// zh-Hans: '开播后自动录制'
  String get recordWhenLive => '开播后自动录制';

  /// zh-Hans: '正在停止录制，已录的文件会保留'
  String get stoppingRecording => '正在停止录制，已录的文件会保留';

  /// zh-Hans: '已移除录制任务，已录的文件会保留'
  String get taskRemoved => '已移除录制任务，已录的文件会保留';

  /// zh-Hans: '录制'
  String get record => '录制';

  /// zh-Hans: '立即录制'
  String get recordNow => '立即录制';

  /// zh-Hans: '开播时自动录制'
  String get recordOnLive => '开播时自动录制';

  /// zh-Hans: '移除录制任务'
  String get removeTask => '移除录制任务';

  late final Translations$room$tab$zh_Hans tab = Translations$room$tab$zh_Hans.internal(_root);

  /// zh-Hans: '横屏全屏'
  String get forceLandscape => '横屏全屏';

  /// zh-Hans: '平台限制为 {quality}'
  String platformLimited({required Object quality}) => '平台限制为 ${quality}';

  /// zh-Hans: '{quality} · 线路 {n}'
  String qualityLine({required Object quality, required Object n}) => '${quality} · 线路 ${n}';

  /// zh-Hans: '长按画面打开快捷面板；长按弹幕可以复制或屏蔽'
  String get quickPanelHint => '长按画面打开快捷面板；长按弹幕可以复制或屏蔽';

  /// zh-Hans: '截图'
  String get screenshot => '截图';

  /// zh-Hans: '定时关闭'
  String get sleepTimer => '定时关闭';

  /// zh-Hans: '在 App 中打开'
  String get openInApp => '在 App 中打开';

  /// zh-Hans: '分享'
  String get share => '分享';

  /// zh-Hans: '复制直链'
  String get copyStreamUrl => '复制直链';

  /// zh-Hans: '房间音量'
  String get roomVolume => '房间音量';

  /// zh-Hans: '加入多画面'
  String get addToMultiview => '加入多画面';

  /// zh-Hans: '快捷键'
  String get shortcuts => '快捷键';

  /// zh-Hans: '新窗口打开'
  String get openInNewWindow => '新窗口打开';

  /// zh-Hans: '{name}的直播间'
  String shareSubject({required Object name}) => '${name}的直播间';

  /// zh-Hans: '分享口令已复制，对方在纯粹直播里粘贴即可打开'
  String get shareCodeCopied => '分享口令已复制，对方在纯粹直播里粘贴即可打开';

  /// zh-Hans: '还没有拿到直播流'
  String get noStreamYet => '还没有拿到直播流';

  /// zh-Hans: '直链已复制，有时效，过期后需要重新复制'
  String get streamUrlCopied => '直链已复制，有时效，过期后需要重新复制';

  /// zh-Hans: '没有开播的关注'
  String get noLiveFollows => '没有开播的关注';

  /// zh-Hans: '没有正在录制的直播间'
  String get noRecordingRooms => '没有正在录制的直播间';

  /// zh-Hans: '还没有观看历史'
  String get noHistory => '还没有观看历史';

  /// zh-Hans: '这个直播间会记住这个音量'
  String get volumeRemembered => '这个直播间会记住这个音量';

  /// zh-Hans: '只调节播放器音量，不改动手机的媒体音量'
  String get volumePlayerOnly => '只调节播放器音量，不改动手机的媒体音量';

  /// zh-Hans: '设为默认音量'
  String get setDefaultVolume => '设为默认音量';

  /// zh-Hans: '设为手机默认音量'
  String get setPhoneDefaultVolume => '设为手机默认音量';

  late final Translations$room$key$zh_Hans key = Translations$room$key$zh_Hans.internal(_root);
  late final Translations$room$tip$zh_Hans tip = Translations$room$tip$zh_Hans.internal(_root);

  /// zh-Hans: '没有可以切换的开播直播间'
  String get noRoomsToSwitch => '没有可以切换的开播直播间';

  /// zh-Hans: '已经是第一个了'
  String get firstRoom => '已经是第一个了';

  /// zh-Hans: '已经是最后一个了'
  String get lastRoom => '已经是最后一个了';

  /// zh-Hans: '可以在 设置 › 播放 里开启上下滑切换直播间'
  String get swipeHint => '可以在 设置 › 播放 里开启上下滑切换直播间';

  late final Translations$room$tv$zh_Hans tv = Translations$room$tv$zh_Hans.internal(_root);
}

// Path: rooms
class Translations$rooms$zh_Hans {
  Translations$rooms$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '设置分组'
  String get setGroups => '设置分组';

  /// zh-Hans: '获取直链'
  String get streamLink => '获取直链';

  /// zh-Hans: '在新窗口打开'
  String get openInNewWindow => '在新窗口打开';

  /// zh-Hans: '已关注 {name}'
  String followedName({required Object name}) => '已关注 ${name}';

  /// zh-Hans: '主播现在没有开播，拿不到直链。'
  String get notLive => '主播现在没有开播，拿不到直链。';

  /// zh-Hans: '正在获取线路'
  String get loadingLines => '正在获取线路';

  /// zh-Hans: '线路（点一下复制）'
  String get linesTapToCopy => '线路（点一下复制）';

  /// zh-Hans: '这个画质没有可用的线路'
  String get noLinesForQuality => '这个画质没有可用的线路';

  /// zh-Hans: '没能写入剪贴板，再试一次'
  String get clipboardFailed => '没能写入剪贴板，再试一次';

  /// zh-Hans: '获取直链 · {title}'
  String streamLinkFor({required Object title}) => '获取直链 · ${title}';
}

// Path: search
class Translations$search$zh_Hans {
  Translations$search$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '语音搜索'
  String get voice => '语音搜索';

  /// zh-Hans: '清除'
  String get clear => '清除';

  /// zh-Hans: '搜索结果'
  String get results => '搜索结果';

  /// zh-Hans: '综合'
  String get all => '综合';

  /// zh-Hans: '失败'
  String get failedTag => '失败';

  /// zh-Hans: '其它平台 {n}'
  String otherPlatforms({required Object n}) => '其它平台 ${n}';

  /// zh-Hans: '搜索失败，检查网络后下拉重试'
  String get allFailed => '搜索失败，检查网络后下拉重试';

  /// zh-Hans: '{platforms}搜索失败，下拉可以重试'
  String someFailed({required Object platforms}) => '${platforms}搜索失败，下拉可以重试';

  /// zh-Hans: '搜索主播、直播间，或粘贴直播间链接'
  String get hint => '搜索主播、直播间，或粘贴直播间链接';

  /// zh-Hans: '只看开播'
  String get liveOnly => '只看开播';

  /// zh-Hans: '正在识别链接'
  String get resolvingLink => '正在识别链接';

  /// zh-Hans: '没有识别出直播间链接'
  String get noLinkMatch => '没有识别出直播间链接';

  /// zh-Hans: '没有找到相关的直播间'
  String get empty => '没有找到相关的直播间';

  /// zh-Hans: '检查关键词有没有错字，或换个平台再搜；有直播间链接时，直接粘贴就能打开。'
  String get emptyHint => '检查关键词有没有错字，或换个平台再搜；有直播间链接时，直接粘贴就能打开。';

  /// zh-Hans: '剪贴板里没有文字，先复制直播间链接或分享口令'
  String get clipboardEmpty => '剪贴板里没有文字，先复制直播间链接或分享口令';

  late final Translations$search$sort$zh_Hans sort = Translations$search$sort$zh_Hans.internal(_root);
  late final Translations$search$web$zh_Hans web = Translations$search$web$zh_Hans.internal(_root);
}

// Path: settings
class Translations$settings$zh_Hans {
  Translations$settings$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '语言'
  String get language => '语言';

  /// zh-Hans: '跟随系统'
  String get languageSystem => '跟随系统';

  late final Translations$settings$group$zh_Hans group = Translations$settings$group$zh_Hans.internal(_root);
  late final Translations$settings$general$zh_Hans general = Translations$settings$general$zh_Hans.internal(_root);
  late final Translations$settings$appearance$zh_Hans appearance = Translations$settings$appearance$zh_Hans.internal(
    _root,
  );
  late final Translations$settings$playback$zh_Hans playback = Translations$settings$playback$zh_Hans.internal(_root);
  late final Translations$settings$data$zh_Hans data = Translations$settings$data$zh_Hans.internal(_root);
  late final Translations$settings$accounts$zh_Hans accounts = Translations$settings$accounts$zh_Hans.internal(_root);

  /// zh-Hans: '电视模式下只用深色'
  String get tvDarkOnly => '电视模式下只用深色';

  /// zh-Hans: '纯黑背景开关仍然有效'
  String get tvDarkOnlySubtitle => '纯黑背景开关仍然有效';

  /// zh-Hans: '{n} 条'
  String historyEntries({required Object n}) => '${n} 条';

  late final Translations$settings$output$zh_Hans output = Translations$settings$output$zh_Hans.internal(_root);
  late final Translations$settings$record$zh_Hans record = Translations$settings$record$zh_Hans.internal(_root);
  late final Translations$settings$audience$zh_Hans audience = Translations$settings$audience$zh_Hans.internal(_root);
  late final Translations$settings$network$zh_Hans network = Translations$settings$network$zh_Hans.internal(_root);

  /// zh-Hans: '勾选要在发现、搜索和平台账号里显示的平台，拖动调整顺序；点星标设为发现页默认打开的平台。'
  String get platformsHint => '勾选要在发现、搜索和平台账号里显示的平台，拖动调整顺序；点星标设为发现页默认打开的平台。';

  /// zh-Hans: '发现页默认打开'
  String get discoverDefault => '发现页默认打开';

  /// zh-Hans: '设为发现页默认打开'
  String get setDiscoverDefault => '设为发现页默认打开';

  Map<String, String> get languageNames => {'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', 'en': 'English'};
  late final Translations$settings$search$zh_Hans search = Translations$settings$search$zh_Hans.internal(_root);
}

// Path: share
class Translations$share$zh_Hans {
  Translations$share$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '房间 {id}'
  String roomN({required Object id}) => '房间 ${id}';

  /// zh-Hans: '收到分享口令'
  String get shareCodeReceived => '收到分享口令';

  /// zh-Hans: '发现直播间链接'
  String get roomLinkFound => '发现直播间链接';

  /// zh-Hans: '来自剪贴板。可以在 设置 › 通用 里关闭剪贴板识别。'
  String get fromClipboard => '来自剪贴板。可以在 设置 › 通用 里关闭剪贴板识别。';

  /// zh-Hans: '进入直播间'
  String get enterRoom => '进入直播间';

  /// zh-Hans: '分享口令已复制。对方复制后打开纯粹直播（3.x 或 v4），即可进入这个直播间'
  String get codeCopied => '分享口令已复制。对方复制后打开纯粹直播（3.x 或 v4），即可进入这个直播间';
}

// Path: sites
class Translations$sites$zh_Hans {
  Translations$sites$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  Map<String, String> get names => {
    'bilibili': '哔哩哔哩',
    'douyu': '斗鱼',
    'huya': '虎牙',
    'douyin': '抖音',
    'kuaishou': '快手',
    'cc': '网易CC',
    'yy': 'YY',
    'soop': 'SOOP',
    'acfun': 'AcFun',
    'twitch': 'Twitch',
    'chzzk': 'CHZZK',
    'missevan': '猫耳 FM',
    'kilakila': '克拉克拉',
    'inke': '映客',
    'picarto': 'Picarto',
    'twitcasting': 'TwitCasting',
    'showroom': 'SHOWROOM',
    'pandalive': 'PandaTV',
    '17live': '17LIVE',
    'liveme': 'LiveMe',
    'steambroadcast': 'Steam 直播',
    'sixroom': '六间房直播',
    'kugoulive': '酷狗直播',
    'jdlive': '京东直播',
    'baidulive': '百度直播',
    'looklive': 'LOOK 直播',
    'weibo': '微博直播',
    'niconico': 'niconico',
    'xiaohongshu': '小红书',
    'youtube': 'YouTube Live',
    'tiktok': 'TikTok LIVE',
    'fc2live': 'FC2 Live',
    'bigo': 'Bigo Live',
    'iptv': '网络电视',
  };
  Map<String, String> get otherNames => {'huajiao': '花椒', 'kick': 'Kick'};
}

// Path: sync
class Translations$sync$zh_Hans {
  Translations$sync$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$sync$device$zh_Hans device = Translations$sync$device$zh_Hans.internal(_root);
  late final Translations$sync$lan$zh_Hans lan = Translations$sync$lan$zh_Hans.internal(_root);
  late final Translations$sync$webdav$zh_Hans webdav = Translations$sync$webdav$zh_Hans.internal(_root);
}

// Path: system
class Translations$system$zh_Hans {
  Translations$system$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '后台播放直播间声音时的通知'
  String get backgroundChannelDescription => '后台播放直播间声音时的通知';

  /// zh-Hans: '关闭窗口'
  String get closeWindow => '关闭窗口';

  /// zh-Hans: '退出纯粹直播，还是最小化到托盘继续运行？'
  String get closeQuestion => '退出纯粹直播，还是最小化到托盘继续运行？';

  /// zh-Hans: '不再询问'
  String get dontAskAgain => '不再询问';

  /// zh-Hans: '可以在 设置 › 通用 里修改'
  String get changeInSettings => '可以在 设置 › 通用 里修改';

  /// zh-Hans: '最小化到托盘'
  String get minimizeToTray => '最小化到托盘';

  /// zh-Hans: '每次询问'
  String get askEveryTime => '每次询问';

  /// zh-Hans: '退出应用'
  String get quitApp => '退出应用';

  /// zh-Hans: '关闭窗口时'
  String get onClose => '关闭窗口时';

  /// zh-Hans: '显示窗口'
  String get showWindow => '显示窗口';

  /// zh-Hans: '隐藏窗口'
  String get hideWindow => '隐藏窗口';

  /// zh-Hans: '播放出错了'
  String get playbackError => '播放出错了';

  /// zh-Hans: '回到直播间'
  String get backToRoom => '回到直播间';

  /// zh-Hans: '关闭小窗'
  String get closeMini => '关闭小窗';

  /// zh-Hans: '没能恢复窗口，请手动调整窗口大小'
  String get restoreWindowFailed => '没能恢复窗口，请手动调整窗口大小';

  /// zh-Hans: '退出画中画（双击画面）'
  String get exitPip => '退出画中画（双击画面）';

  /// zh-Hans: '开机自启'
  String get launchAtStartup => '开机自启';

  /// zh-Hans: '登录 Windows 后自动打开纯粹直播'
  String get launchAtStartupSubtitle => '登录 Windows 后自动打开纯粹直播';

  /// zh-Hans: '离开直播间时小窗播放'
  String get miniOnLeave => '离开直播间时小窗播放';

  /// zh-Hans: '小窗会继续占用内存和流量'
  String get miniOnLeaveSubtitle => '小窗会继续占用内存和流量';

  /// zh-Hans: '离开应用时自动画中画'
  String get autoPip => '离开应用时自动画中画';

  /// zh-Hans: '在直播间按主屏幕键时进入画中画'
  String get autoPipSubtitle => '在直播间按主屏幕键时进入画中画';

  /// zh-Hans: '画中画窗口置顶'
  String get pipOnTop => '画中画窗口置顶';
}

// Path: tv
class Translations$tv$zh_Hans {
  Translations$tv$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '说出主播名或直播间'
  String get speechPrompt => '说出主播名或直播间';
}

// Path: ui
class Translations$ui$zh_Hans {
  Translations$ui$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '直播'
  String get live => '直播';

  /// zh-Hans: '直播 {duration}'
  String liveFor({required Object duration}) => '直播 ${duration}';

  /// zh-Hans: '直播中'
  String get liveNow => '直播中';

  /// zh-Hans: '未开播'
  String get offline => '未开播';

  /// zh-Hans: '录制中'
  String get recording => '录制中';

  /// zh-Hans: '，'
  String get separator => '，';

  /// zh-Hans: '重试'
  String get retry => '重试';

  /// zh-Hans: '确定'
  String get ok => '确定';

  /// zh-Hans: '取消'
  String get cancel => '取消';

  /// zh-Hans: '正在加载'
  String get loading => '正在加载';

  /// zh-Hans: '刚刚'
  String get justNow => '刚刚';

  /// zh-Hans: '(other) {{n} 分钟前}'
  String minutesAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 分钟前');

  /// zh-Hans: '(other) {{n} 小时前}'
  String hoursAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 小时前');

  /// zh-Hans: '(other) {{n} 天前}'
  String daysAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 天前');

  /// zh-Hans: '10000'
  String get countBase => '10000';

  List<String> get countUnits => ['万', '亿'];
}

// Path: web
class Translations$web$zh_Hans {
  Translations$web$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '需要 WebView2 运行时'
  String get webView2Title => '需要 WebView2 运行时';

  /// zh-Hans: '网页登录和网页搜索要用微软的 Microsoft Edge WebView2 运行时，这台电脑上没有找到它。Windows 11 和更新过的 Windows 10 一般已经自带。 安装方法：打开微软的下载页，下载“常青版引导程序”（Evergreen Bootstrapper）并运行，装好后重新打开纯粹直播。'
  String get webView2Body =>
      '网页登录和网页搜索要用微软的 Microsoft Edge WebView2 运行时，这台电脑上没有找到它。Windows 11 和更新过的 Windows 10 一般已经自带。\n\n安装方法：打开微软的下载页，下载“常青版引导程序”（Evergreen Bootstrapper）并运行，装好后重新打开纯粹直播。';

  /// zh-Hans: '打开下载页'
  String get openDownloadPage => '打开下载页';
}

// Path: accounts.cookieTip
class Translations$accounts$cookieTip$zh_Hans {
  Translations$accounts$cookieTip$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '在电脑浏览器登录 www.douyu.com 后，从开发者工具里复制请求头中的 Cookie 粘贴到下面。要能续期，再复制 passport.douyu.com 请求的 Cookie（含 LTP0）粘贴进来，应用会取出 LTP0 和 dy_did。'
  String get douyu =>
      '在电脑浏览器登录 www.douyu.com 后，从开发者工具里复制请求头中的 Cookie 粘贴到下面。要能续期，再复制 passport.douyu.com 请求的 Cookie（含 LTP0）粘贴进来，应用会取出 LTP0 和 dy_did。';

  /// zh-Hans: '在电脑浏览器登录 twitch.tv 后复制 Cookie。只会用到其中的 auth-token，用于订阅专属直播和免广告。'
  String get twitch => '在电脑浏览器登录 twitch.tv 后复制 Cookie。只会用到其中的 auth-token，用于订阅专属直播和免广告。';

  /// zh-Hans: '在电脑浏览器登录 sooplive.co.kr 后复制 Cookie。只在打开 19 禁直播时随取流请求发送。'
  String get soop => '在电脑浏览器登录 sooplive.co.kr 后复制 Cookie。只在打开 19 禁直播时随取流请求发送。';

  /// zh-Hans: '在电脑浏览器登录该平台网页版后，从开发者工具里复制请求头中的 Cookie，粘贴到下面。'
  String get other => '在电脑浏览器登录该平台网页版后，从开发者工具里复制请求头中的 Cookie，粘贴到下面。';
}

// Path: app.tabs
class Translations$app$tabs$zh_Hans {
  Translations$app$tabs$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '关注'
  String get follows => '关注';

  /// zh-Hans: '发现'
  String get discover => '发现';

  /// zh-Hans: '搜索'
  String get search => '搜索';

  /// zh-Hans: '我的'
  String get me => '我的';
}

// Path: backup.section
class Translations$backup$section$zh_Hans {
  Translations$backup$section$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '关注'
  String get follows => '关注';

  /// zh-Hans: '关注的分区'
  String get followAreas => '关注的分区';

  /// zh-Hans: '分组'
  String get tags => '分组';

  /// zh-Hans: '分组成员'
  String get roomTags => '分组成员';

  /// zh-Hans: '观看历史'
  String get history => '观看历史';

  /// zh-Hans: '屏蔽词'
  String get blockRules => '屏蔽词';

  /// zh-Hans: '设置'
  String get settings => '设置';

  /// zh-Hans: '直播间偏好'
  String get roomPrefs => '直播间偏好';

  /// zh-Hans: '录制任务'
  String get recordTasks => '录制任务';

  /// zh-Hans: '平台登录信息'
  String get secrets => '平台登录信息';
}

// Path: cast.failure
class Translations$cast$failure$zh_Hans {
  Translations$cast$failure$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '连不上这台设备，确认它开着，并且和手机连着同一个 Wi-Fi'
  String get unreachable => '连不上这台设备，确认它开着，并且和手机连着同一个 Wi-Fi';

  /// zh-Hans: '设备正忙，稍后再试'
  String get busy => '设备正忙，稍后再试';

  /// zh-Hans: '设备不支持这种直播流格式，换一条线路试试'
  String get format => '设备不支持这种直播流格式，换一条线路试试';

  /// zh-Hans: '设备打不开这个直播地址，换一条线路试试'
  String get unplayable => '设备打不开这个直播地址，换一条线路试试';

  /// zh-Hans: '设备拒绝了投屏（错误码 {code}）'
  String refused({required Object code}) => '设备拒绝了投屏（错误码 ${code}）';

  /// zh-Hans: '设备返回了错误（HTTP {status}）'
  String http({required Object status}) => '设备返回了错误（HTTP ${status}）';

  /// zh-Hans: '设备的回应无法识别'
  String get protocol => '设备的回应无法识别';

  /// zh-Hans: '投屏失败'
  String get generic => '投屏失败';
}

// Path: cast.tv
class Translations$cast$tv$zh_Hans {
  Translations$cast$tv$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '电视正在播放'
  String get playing => '电视正在播放';

  /// zh-Hans: '电视正在加载'
  String get loading => '电视正在加载';

  /// zh-Hans: '电视已暂停'
  String get paused => '电视已暂停';

  /// zh-Hans: '电视已停止播放'
  String get stopped => '电视已停止播放';
}

// Path: danmaku.preset
class Translations$danmaku$preset$zh_Hans {
  Translations$danmaku$preset$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '最佳观感'
  String get best => '最佳观感';

  /// zh-Hans: '舒适'
  String get comfort => '舒适';

  /// zh-Hans: '密集'
  String get dense => '密集';

  /// zh-Hans: '恢复默认'
  String get reset => '恢复默认';
}

// Path: danmaku.audience
class Translations$danmaku$audience$zh_Hans {
  Translations$danmaku$audience$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '在线'
  String get online => '在线';

  /// zh-Hans: '人气'
  String get popularity => '人气';

  /// zh-Hans: '看过'
  String get cumulative => '看过';
}

// Path: follows.sort
class Translations$follows$sort$zh_Hans {
  Translations$follows$sort$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '按人数'
  String get audience => '按人数';

  /// zh-Hans: '按开播时间'
  String get liveTime => '按开播时间';

  /// zh-Hans: '按平台'
  String get platform => '按平台';

  /// zh-Hans: '自定义顺序'
  String get custom => '自定义顺序';
}

// Path: follows.tag
class Translations$follows$tag$zh_Hans {
  Translations$follows$tag$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '未支持'
  String get unsupported => '未支持';

  /// zh-Hans: '状态未知'
  String get unknown => '状态未知';

  /// zh-Hans: '房间不存在'
  String get missing => '房间不存在';

  /// zh-Hans: '轮播'
  String get replay => '轮播';
}

// Path: follows.filter
class Translations$follows$filter$zh_Hans {
  Translations$follows$filter$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '开播'
  String get live => '开播';

  /// zh-Hans: '开播 {n}'
  String liveCount({required Object n}) => '开播 ${n}';

  /// zh-Hans: '分组'
  String get groups => '分组';
}

// Path: iptv.error
class Translations$iptv$error$zh_Hans {
  Translations$iptv$error$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '没有识别出节目单，确认是 XMLTV 或 JSON 格式'
  String get noGuide => '没有识别出节目单，确认是 XMLTV 或 JSON 格式';

  /// zh-Hans: '没有识别出频道，确认是 M3U、TXT 或 JSON 播放列表'
  String get noChannels => '没有识别出频道，确认是 M3U、TXT 或 JSON 播放列表';

  /// zh-Hans: '请输入 http 或 https 开头的网址'
  String get badUrl => '请输入 http 或 https 开头的网址';

  /// zh-Hans: '找不到这个 Xtream 账号的登录信息，删除后重新登录'
  String get xtreamMissing => '找不到这个 Xtream 账号的登录信息，删除后重新登录';

  /// zh-Hans: '地址不存在（404），检查网址是否还有效'
  String get notFound => '地址不存在（404），检查网址是否还有效';

  /// zh-Hans: '网络连接失败，检查网络或代理后重试'
  String get network => '网络连接失败，检查网络或代理后重试';

  /// zh-Hans: '读不到文件，重新导入一次'
  String get file => '读不到文件，重新导入一次';

  /// zh-Hans: '文件格式不对'
  String get format => '文件格式不对';

  /// zh-Hans: '同步失败'
  String get generic => '同步失败';

  /// zh-Hans: '服务器的回应不是 Xtream 接口，检查服务器地址'
  String get notXtream => '服务器的回应不是 Xtream 接口，检查服务器地址';
}

// Path: iptv.xtream
class Translations$iptv$xtream$zh_Hans {
  Translations$iptv$xtream$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '用户名或密码不对'
  String get wrongCredentials => '用户名或密码不对';

  /// zh-Hans: '账号已过期'
  String get expired => '账号已过期';

  /// zh-Hans: '账号被封禁'
  String get banned => '账号被封禁';

  /// zh-Hans: '账号已停用'
  String get disabled => '账号已停用';

  /// zh-Hans: '账号不可用（{status}）'
  String unavailable({required Object status}) => '账号不可用（${status}）';

  /// zh-Hans: '未知状态'
  String get unknownStatus => '未知状态';
}

// Path: recording.notice
class Translations$recording$notice$zh_Hans {
  Translations$recording$notice$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '正在处理录制文件'
  String get finishingTitle => '正在处理录制文件';

  /// zh-Hans: '(other) {{n} 个录制正在收尾，完成后通知会消失}'
  String finishingText({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${n} 个录制正在收尾，完成后通知会消失');

  /// zh-Hans: '{names} 等'
  String namesAndMore({required Object names}) => '${names} 等';

  /// zh-Hans: '(other) {正在录制 {n} 个直播间}'
  String recordingTitle({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '正在录制 ${n} 个直播间');

  /// zh-Hans: '(other) {{shown}；{n} 个正在收尾}'
  String recordingText({required num n, required Object shown}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(n, other: '${shown}；${n} 个正在收尾');
}

// Path: recording.state
class Translations$recording$state$zh_Hans {
  Translations$recording$state$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '排队中'
  String get queued => '排队中';

  /// zh-Hans: '准备中'
  String get resolving => '准备中';

  /// zh-Hans: '录制中'
  String get recording => '录制中';

  /// zh-Hans: '重连中'
  String get reconnecting => '重连中';

  /// zh-Hans: '处理中'
  String get finalizing => '处理中';

  /// zh-Hans: '转封装 {percent}%'
  String remuxing({required Object percent}) => '转封装 ${percent}%';

  /// zh-Hans: '等待开播'
  String get waitingLive => '等待开播';

  /// zh-Hans: '已完成'
  String get completed => '已完成';

  /// zh-Hans: '失败'
  String get failed => '失败';

  /// zh-Hans: '已停止（开播监控已关闭）'
  String get stoppedPollingOff => '已停止（开播监控已关闭）';

  /// zh-Hans: '已停止（应用退出）'
  String get stoppedAppExit => '已停止（应用退出）';

  /// zh-Hans: '已停止'
  String get stopped => '已停止';
}

// Path: recording.failure
class Translations$recording$failure$zh_Hans {
  Translations$recording$failure$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '主播已下播'
  String get offline => '主播已下播';

  /// zh-Hans: '直播间被封禁'
  String get banned => '直播间被封禁';

  /// zh-Hans: '直播间不存在'
  String get missing => '直播间不存在';

  /// zh-Hans: '这个平台暂不支持录制'
  String get unsupported => '这个平台暂不支持录制';

  /// zh-Hans: '需要登录平台账号'
  String get needsLogin => '需要登录平台账号';

  /// zh-Hans: '当前地区无法观看'
  String get region => '当前地区无法观看';

  /// zh-Hans: '拿不到可录制的直播流'
  String get noStream => '拿不到可录制的直播流';

  /// zh-Hans: '直播流的格式暂不支持录制（如 RTSP、UDP 地址，SAMPLE-AES 加密，音视频分开的 HLS）'
  String get unsupportedFormat => '直播流的格式暂不支持录制（如 RTSP、UDP 地址，SAMPLE-AES 加密，音视频分开的 HLS）';

  /// zh-Hans: '存储空间不足'
  String get diskFull => '存储空间不足';

  /// zh-Hans: '没有录制目录的写入权限'
  String get noPermission => '没有录制目录的写入权限';

  /// zh-Hans: '录制目录不可用'
  String get directory => '录制目录不可用';

  /// zh-Hans: '磁盘写入卡住了'
  String get writeStalled => '磁盘写入卡住了';

  /// zh-Hans: '后台运行时间被系统用尽'
  String get background => '后台运行时间被系统用尽';

  /// zh-Hans: '转成 MP4 失败，原始文件已保留'
  String get remux => '转成 MP4 失败，原始文件已保留';

  /// zh-Hans: '录制文件损坏'
  String get corrupt => '录制文件损坏';

  /// zh-Hans: '多次重试都没有成功'
  String get retries => '多次重试都没有成功';

  /// zh-Hans: '网络或直播流出错'
  String get stream => '网络或直播流出错';
}

// Path: recording.stage
class Translations$recording$stage$zh_Hans {
  Translations$recording$stage$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '房间检查'
  String get check => '房间检查';

  /// zh-Hans: '选画质'
  String get quality => '选画质';

  /// zh-Hans: '取流'
  String get resolve => '取流';

  /// zh-Hans: '连接'
  String get connect => '连接';

  /// zh-Hans: '写文件'
  String get write => '写文件';

  /// zh-Hans: '转封装'
  String get remux => '转封装';

  /// zh-Hans: '排队调度'
  String get queue => '排队调度';

  /// zh-Hans: '后台运行'
  String get background => '后台运行';

  /// zh-Hans: '开播检查'
  String get poll => '开播检查';
}

// Path: room.failure
class Translations$room$failure$zh_Hans {
  Translations$room$failure$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '网络中断了'
  String get network => '网络中断了';

  /// zh-Hans: '直播流打不开，可以换条线路试试'
  String get source => '直播流打不开，可以换条线路试试';

  /// zh-Hans: '缓冲太久了，可以换条线路或降低画质'
  String get buffering => '缓冲太久了，可以换条线路或降低画质';

  /// zh-Hans: '直播流中断了'
  String get ended => '直播流中断了';

  /// zh-Hans: '播放意外停止了'
  String get paused => '播放意外停止了';

  /// zh-Hans: '画面卡住了'
  String get frozen => '画面卡住了';

  /// zh-Hans: '视频解码失败，可以在设置里关闭硬件解码'
  String get videoDecode => '视频解码失败，可以在设置里关闭硬件解码';

  /// zh-Hans: '音频解码失败'
  String get audioDecode => '音频解码失败';

  /// zh-Hans: '播放器出错了'
  String get engine => '播放器出错了';

  /// zh-Hans: '拿不到直播流'
  String get unavailable => '拿不到直播流';

  /// zh-Hans: '多次重试都没有成功'
  String get exhausted => '多次重试都没有成功';
}

// Path: room.fit
class Translations$room$fit$zh_Hans {
  Translations$room$fit$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '填充'
  String get cover => '填充';

  /// zh-Hans: '拉伸'
  String get fill => '拉伸';

  /// zh-Hans: '适应'
  String get contain => '适应';
}

// Path: room.sleep
class Translations$room$sleep$zh_Hans {
  Translations$room$sleep$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '定时关闭：正在退出应用'
  String get exiting => '定时关闭：正在退出应用';

  /// zh-Hans: '定时关闭：已暂停播放'
  String get paused => '定时关闭：已暂停播放';

  /// zh-Hans: '{time} 后退出应用'
  String exitIn({required Object time}) => '${time} 后退出应用';

  /// zh-Hans: '{time} 后暂停播放'
  String pauseIn({required Object time}) => '${time} 后暂停播放';

  /// zh-Hans: '取消定时'
  String get cancel => '取消定时';

  /// zh-Hans: '到时间后暂停播放，并停止后台声音'
  String get hint => '到时间后暂停播放，并停止后台声音';

  /// zh-Hans: '自定义'
  String get custom => '自定义';

  /// zh-Hans: '暂停播放'
  String get pause => '暂停播放';

  /// zh-Hans: '退出应用'
  String get exit => '退出应用';

  /// zh-Hans: '同时切换为纯音频'
  String get audioOnly => '同时切换为纯音频';

  /// zh-Hans: '助眠：只保留声音'
  String get audioOnlySubtitle => '助眠：只保留声音';

  /// zh-Hans: '请输入 1 到 {max} 之间的分钟数'
  String invalidMinutes({required Object max}) => '请输入 1 到 ${max} 之间的分钟数';

  /// zh-Hans: '自定义时长'
  String get customTitle => '自定义时长';

  /// zh-Hans: '分钟'
  String get minutesSuffix => '分钟';
}

// Path: room.tab
class Translations$room$tab$zh_Hans {
  Translations$room$tab$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '弹幕'
  String get danmaku => '弹幕';

  /// zh-Hans: '直播间'
  String get room => '直播间';
}

// Path: room.key
class Translations$room$key$zh_Hans {
  Translations$room$key$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '空格'
  String get space => '空格';

  /// zh-Hans: '播放 / 暂停'
  String get playPause => '播放 / 暂停';

  /// zh-Hans: 'F、双击'
  String get fullscreenKeys => 'F、双击';

  /// zh-Hans: '全屏 / 退出全屏'
  String get fullscreen => '全屏 / 退出全屏';

  /// zh-Hans: '关闭弹层 → 退出全屏或剧场 → 离开直播间'
  String get escape => '关闭弹层 → 退出全屏或剧场 → 离开直播间';

  /// zh-Hans: '剧场模式'
  String get theater => '剧场模式';

  /// zh-Hans: '显示 / 收起聊天栏'
  String get chat => '显示 / 收起聊天栏';

  /// zh-Hans: '静音'
  String get mute => '静音';

  /// zh-Hans: '↑ ↓、滚轮'
  String get volumeKeys => '↑ ↓、滚轮';

  /// zh-Hans: '音量 ±5%'
  String get volume => '音量 ±5%';

  /// zh-Hans: '弹幕开关'
  String get danmaku => '弹幕开关';

  /// zh-Hans: '画质 / 线路'
  String get qualityLine => '画质 / 线路';

  /// zh-Hans: '快捷键帮助'
  String get help => '快捷键帮助';

  /// zh-Hans: 'R、F5、Ctrl+R'
  String get refreshKeys => 'R、F5、Ctrl+R';
}

// Path: room.tip
class Translations$room$tip$zh_Hans {
  Translations$room$tip$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '按 C 收起或展开聊天栏，按 T 进入剧场模式，按 ? 查看全部快捷键'
  String get desktop => '按 C 收起或展开聊天栏，按 T 进入剧场模式，按 ? 查看全部快捷键';

  /// zh-Hans: '双指缩放切换画面比例，长按画面打开快捷面板'
  String get touch => '双指缩放切换画面比例，长按画面打开快捷面板';
}

// Path: room.tv
class Translations$room$tv$zh_Hans {
  Translations$room$tv$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '上下键换台，左键直播间列表，右键播放设置，确认键显示控制'
  String get hint => '上下键换台，左键直播间列表，右键播放设置，确认键显示控制';

  /// zh-Hans: '直播间列表'
  String get roomList => '直播间列表';

  /// zh-Hans: '播放设置'
  String get playbackSettings => '播放设置';

  /// zh-Hans: '画质线路'
  String get qualityLine => '画质线路';

  /// zh-Hans: '没有开播的直播间'
  String get noLiveRooms => '没有开播的直播间';

  /// zh-Hans: '正在看'
  String get watching => '正在看';
}

// Path: search.sort
class Translations$search$sort$zh_Hans {
  Translations$search$sort$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '智能'
  String get smart => '智能';

  /// zh-Hans: '按平台'
  String get platform => '按平台';

  /// zh-Hans: '按人数'
  String get audience => '按人数';

  /// zh-Hans: '按粉丝'
  String get followers => '按粉丝';
}

// Path: search.web
class Translations$search$web$zh_Hans {
  Translations$search$web$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '网页搜索'
  String get title => '网页搜索';

  /// zh-Hans: '先输入要搜索的关键词'
  String get enterKeyword => '先输入要搜索的关键词';

  /// zh-Hans: '在哪个平台的网页里搜索'
  String get pickPlatform => '在哪个平台的网页里搜索';

  /// zh-Hans: '识别到直播间'
  String get roomFound => '识别到直播间';

  /// zh-Hans: '留在网页'
  String get stay => '留在网页';

  /// zh-Hans: '网页搜索 · {name}'
  String titleFor({required Object name}) => '网页搜索 · ${name}';

  /// zh-Hans: '本页的房间'
  String get pageRooms => '本页的房间';

  /// zh-Hans: '这里用不了网页搜索'
  String get unavailable => '这里用不了网页搜索';

  /// zh-Hans: '网页没有打开'
  String get notOpened => '网页没有打开';

  /// zh-Hans: '正在识别本页的直播间'
  String get scanning => '正在识别本页的直播间';

  /// zh-Hans: '本页没有识别出直播间链接'
  String get noRooms => '本页没有识别出直播间链接';

  /// zh-Hans: '本页的直播间'
  String get pageRoomsTitle => '本页的直播间';
}

// Path: settings.group
class Translations$settings$group$zh_Hans {
  Translations$settings$group$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '通用'
  String get general => '通用';

  /// zh-Hans: '播放'
  String get playback => '播放';

  /// zh-Hans: '弹幕'
  String get danmaku => '弹幕';

  /// zh-Hans: '录制'
  String get recording => '录制';

  /// zh-Hans: '平台与账号'
  String get accounts => '平台与账号';

  /// zh-Hans: '网络'
  String get network => '网络';

  /// zh-Hans: '数据与同步'
  String get data => '数据与同步';
}

// Path: settings.general
class Translations$settings$general$zh_Hans {
  Translations$settings$general$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '启动页'
  String get startPage => '启动页';

  /// zh-Hans: '播放时屏幕常亮'
  String get keepScreenOn => '播放时屏幕常亮';

  /// zh-Hans: '刷新率'
  String get refreshRate => '刷新率';

  /// zh-Hans: '省电'
  String get refreshPowerSaving => '省电';

  /// zh-Hans: '均衡'
  String get refreshBalanced => '均衡';

  /// zh-Hans: '最高'
  String get refreshHighest => '最高';

  /// zh-Hans: '自动检查更新'
  String get autoCheckUpdate => '自动检查更新';

  /// zh-Hans: '电视'
  String get tv => '电视';

  /// zh-Hans: '电视模式'
  String get tvMode => '电视模式';

  /// zh-Hans: '自动（检测到电视时开启）'
  String get tvModeAuto => '自动（检测到电视时开启）';

  /// zh-Hans: '电视焦点只描边'
  String get tvFocusOutline => '电视焦点只描边';

  /// zh-Hans: '性能优先：焦点不放大，适合低端电视盒子'
  String get tvFocusOutlineSubtitle => '性能优先：焦点不放大，适合低端电视盒子';

  /// zh-Hans: '关注刷新'
  String get followRefresh => '关注刷新';

  /// zh-Hans: '定时刷新关注的开播状态'
  String get autoRefreshFollows => '定时刷新关注的开播状态';

  /// zh-Hans: '回到应用时刷新关注'
  String get refreshOnResume => '回到应用时刷新关注';

  /// zh-Hans: '定时刷新间隔'
  String get refreshInterval => '定时刷新间隔';

  /// zh-Hans: '同时刷新的直播间数'
  String get maxConcurrentRefresh => '同时刷新的直播间数';

  /// zh-Hans: '定时刷新封面'
  String get refreshCovers => '定时刷新封面';

  /// zh-Hans: '开播卡片的封面按间隔重新下载，看到的画面更新'
  String get refreshCoversSubtitle => '开播卡片的封面按间隔重新下载，看到的画面更新';

  /// zh-Hans: '封面刷新间隔'
  String get coverInterval => '封面刷新间隔';

  /// zh-Hans: '通知'
  String get notifications => '通知';
}

// Path: settings.appearance
class Translations$settings$appearance$zh_Hans {
  Translations$settings$appearance$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '主题'
  String get theme => '主题';

  /// zh-Hans: '主播名和标题放在一行'
  String get denseSubtitle => '主播名和标题放在一行';

  /// zh-Hans: '文字大小'
  String get textSize => '文字大小';

  /// zh-Hans: '跟随系统强调色'
  String get accentColor => '跟随系统强调色';

  /// zh-Hans: '主题色改用 Windows 的强调色'
  String get accentColorSubtitle => '主题色改用 Windows 的强调色';

  /// zh-Hans: '跟随壁纸取色'
  String get wallpaperColor => '跟随壁纸取色';

  /// zh-Hans: 'Android 12 及以上，主题色取自壁纸'
  String get wallpaperColorSubtitle => 'Android 12 及以上，主题色取自壁纸';

  /// zh-Hans: '发现和搜索用紧凑卡片（手机）'
  String get compactCardsPhone => '发现和搜索用紧凑卡片（手机）';

  /// zh-Hans: '发现和搜索用紧凑卡片（桌面）'
  String get compactCardsDesktop => '发现和搜索用紧凑卡片（桌面）';

  /// zh-Hans: '下载开源字体，用作界面或弹幕字体'
  String get fontsSubtitle => '下载开源字体，用作界面或弹幕字体';
}

// Path: settings.playback
class Translations$settings$playback$zh_Hans {
  Translations$settings$playback$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '默认画质（Wi-Fi）'
  String get qualityWifi => '默认画质（Wi-Fi）';

  /// zh-Hans: '默认画质（移动网络）'
  String get qualityMobile => '默认画质（移动网络）';

  /// zh-Hans: '网络不稳时自动降低画质'
  String get autoLower => '网络不稳时自动降低画质';

  /// zh-Hans: '一分钟内卡顿 3 次就降一档；手动选过画质后不再自动调整'
  String get autoLowerSubtitle => '一分钟内卡顿 3 次就降一档；手动选过画质后不再自动调整';

  /// zh-Hans: '填充（裁切）'
  String get fitCover => '填充（裁切）';

  /// zh-Hans: '进入直播间自动全屏'
  String get autoFullscreen => '进入直播间自动全屏';

  /// zh-Hans: '竖屏全屏上下滑切换直播间'
  String get swipeRooms => '竖屏全屏上下滑切换直播间';

  /// zh-Hans: '上滑下一个、下滑上一个；开启后竖屏全屏里不再上下滑调亮度和音量'
  String get swipeRoomsSubtitle => '上滑下一个、下滑上一个；开启后竖屏全屏里不再上下滑调亮度和音量';

  /// zh-Hans: '竖屏直播'
  String get portrait => '竖屏直播';

  /// zh-Hans: '竖屏直播适配'
  String get portraitAdaptation => '竖屏直播适配';

  /// zh-Hans: '自动识别竖屏直播，手机上用竖屏全屏和可拖动的信息面板'
  String get portraitAdaptationSubtitle => '自动识别竖屏直播，手机上用竖屏全屏和可拖动的信息面板';

  /// zh-Hans: '全屏方向'
  String get fullscreenOrientation => '全屏方向';

  /// zh-Hans: '跟随画面（竖屏直播竖着全屏）'
  String get orientationSource => '跟随画面（竖屏直播竖着全屏）';

  /// zh-Hans: '跟随手机方向'
  String get orientationSystem => '跟随手机方向';

  /// zh-Hans: '总是横屏'
  String get orientationLandscape => '总是横屏';

  /// zh-Hans: '竖屏全屏画面'
  String get portraitFit => '竖屏全屏画面';

  /// zh-Hans: '完整显示'
  String get portraitFitContain => '完整显示';

  /// zh-Hans: '铺满屏幕（裁掉边缘）'
  String get portraitFitCover => '铺满屏幕（裁掉边缘）';

  /// zh-Hans: '竖屏全屏弹幕区域'
  String get portraitDanmaku => '竖屏全屏弹幕区域';

  /// zh-Hans: '跟随弹幕设置'
  String get danmakuFollow => '跟随弹幕设置';

  /// zh-Hans: '只在上方四分之一'
  String get danmakuUpperQuarter => '只在上方四分之一';

  /// zh-Hans: '减半'
  String get danmakuHalf => '减半';

  /// zh-Hans: '不显示'
  String get danmakuHidden => '不显示';

  /// zh-Hans: '记住每个直播间的画面方向'
  String get rememberOrientation => '记住每个直播间的画面方向';

  /// zh-Hans: '在直播间手动选的“按竖屏/横屏处理”下次进房仍然生效'
  String get rememberOrientationSubtitle => '在直播间手动选的“按竖屏/横屏处理”下次进房仍然生效';

  /// zh-Hans: '后台播放'
  String get background => '后台播放';

  /// zh-Hans: '离开应用后继续播放声音'
  String get backgroundSubtitle => '离开应用后继续播放声音';

  /// zh-Hans: '助眠'
  String get sleep => '助眠';

  /// zh-Hans: '助眠模式'
  String get sleepMode => '助眠模式';

  /// zh-Hans: '进入直播间自动只播声音并开始定时关闭；恢复画面时取消这次定时'
  String get sleepModeSubtitle => '进入直播间自动只播声音并开始定时关闭；恢复画面时取消这次定时';

  /// zh-Hans: '助眠定时'
  String get sleepMinutes => '助眠定时';

  /// zh-Hans: '手机默认音量'
  String get phoneVolume => '手机默认音量';
}

// Path: settings.data
class Translations$settings$data$zh_Hans {
  Translations$settings$data$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '观看历史最多保留'
  String get historyLimit => '观看历史最多保留';
}

// Path: settings.accounts
class Translations$settings$accounts$zh_Hans {
  Translations$settings$accounts$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '首页平台'
  String get platforms => '首页平台';

  /// zh-Hans: '显示哪些平台、顺序和发现页默认打开的平台'
  String get platformsSubtitle => '显示哪些平台、顺序和发现页默认打开的平台';

  /// zh-Hans: '观众数口径'
  String get audience => '观众数口径';

  /// zh-Hans: '卡片显示热度还是在线人数，以及各平台数字的含义'
  String get audienceSubtitle => '卡片显示热度还是在线人数，以及各平台数字的含义';

  /// zh-Hans: '登录或退出各平台账号'
  String get accountsSubtitle => '登录或退出各平台账号';
}

// Path: settings.output
class Translations$settings$output$zh_Hans {
  Translations$settings$output$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '音量'
  String get volume => '音量';

  /// zh-Hans: '进入直播间时静音'
  String get startMuted => '进入直播间时静音';

  /// zh-Hans: '所有直播间都从静音开始'
  String get startMutedSubtitle => '所有直播间都从静音开始';

  /// zh-Hans: '默认音量'
  String get defaultVolume => '默认音量';

  /// zh-Hans: '默认音量（没有记住音量的直播间）'
  String get defaultVolumeDesktop => '默认音量（没有记住音量的直播间）';

  /// zh-Hans: '解码与输出'
  String get decoding => '解码与输出';

  /// zh-Hans: '硬件解码'
  String get hardwareDecoding => '硬件解码';

  /// zh-Hans: '画面异常时关闭试试'
  String get hardwareDecodingSubtitle => '画面异常时关闭试试';

  /// zh-Hans: '硬件解码方式'
  String get decoder => '硬件解码方式';

  /// zh-Hans: 'MediaCodec（复制）'
  String get mediacodecCopy => 'MediaCodec（复制）';

  /// zh-Hans: 'D3D11（复制）'
  String get d3d11Copy => 'D3D11（复制）';

  /// zh-Hans: 'NVDEC（英伟达）'
  String get nvdec => 'NVDEC（英伟达）';

  /// zh-Hans: '兼容模式'
  String get compatibility => '兼容模式';

  /// zh-Hans: '部分机型黑屏、花屏或卡住时打开'
  String get compatibilitySubtitle => '部分机型黑屏、花屏或卡住时打开';

  /// zh-Hans: '低延迟'
  String get lowLatency => '低延迟';

  /// zh-Hans: '缓冲更少、延迟更低，网络差时更容易卡'
  String get lowLatencySubtitle => '缓冲更少、延迟更低，网络差时更容易卡';

  /// zh-Hans: '音频输出'
  String get audio => '音频输出';
}

// Path: settings.record
class Translations$settings$record$zh_Hans {
  Translations$settings$record$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '查看和管理录制任务'
  String get centerSubtitle => '查看和管理录制任务';

  /// zh-Hans: '默认录制画质'
  String get quality => '默认录制画质';

  /// zh-Hans: '开播监控'
  String get monitoring => '开播监控';

  /// zh-Hans: '主播开播后自动开始录制'
  String get monitoringSubtitle => '主播开播后自动开始录制';

  /// zh-Hans: '开播检查间隔（秒）'
  String get pollInterval => '开播检查间隔（秒）';

  /// zh-Hans: '断线重连'
  String get reconnect => '断线重连';

  /// zh-Hans: '断线自动重连'
  String get autoReconnect => '断线自动重连';

  /// zh-Hans: '重试次数'
  String get retries => '重试次数';

  /// zh-Hans: '重试间隔（秒）'
  String get retryInterval => '重试间隔（秒）';

  /// zh-Hans: '失败后逐次加长等待'
  String get backoff => '失败后逐次加长等待';

  /// zh-Hans: '重试和开播检查每失败一次，等待时间翻倍，直到最长间隔'
  String get backoffSubtitle => '重试和开播检查每失败一次，等待时间翻倍，直到最长间隔';

  /// zh-Hans: '最长等待间隔'
  String get maxBackoff => '最长等待间隔';

  /// zh-Hans: '读取超时（直播流多久没有数据算断线）'
  String get readTimeout => '读取超时（直播流多久没有数据算断线）';

  /// zh-Hans: '文件'
  String get files => '文件';

  /// zh-Hans: '同时录制的数量'
  String get maxConcurrent => '同时录制的数量';

  /// zh-Hans: '按时长分段（分钟，0 为不分段）'
  String get splitDuration => '按时长分段（分钟，0 为不分段）';

  /// zh-Hans: '按大小分段'
  String get splitSize => '按大小分段';

  /// zh-Hans: '同时保存弹幕'
  String get saveDanmaku => '同时保存弹幕';

  /// zh-Hans: '与视频同名的 XML 文件'
  String get saveDanmakuSubtitle => '与视频同名的 XML 文件';

  /// zh-Hans: '录完转成 MP4'
  String get remuxMp4 => '录完转成 MP4';

  /// zh-Hans: '转成 MP4 后保留原始录制文件'
  String get keepSource => '转成 MP4 后保留原始录制文件';

  /// zh-Hans: '文件夹名用拼音'
  String get pinyinFolders => '文件夹名用拼音';

  /// zh-Hans: '主播名转成拼音作文件夹名，方便在不支持中文的设备上查看'
  String get pinyinFoldersSubtitle => '主播名转成拼音作文件夹名，方便在不支持中文的设备上查看';

  /// zh-Hans: '启动时继续未完成的录制'
  String get resumeOnStart => '启动时继续未完成的录制';

  /// zh-Hans: '空间'
  String get space => '空间';

  /// zh-Hans: '限制录制目录大小'
  String get limitSize => '限制录制目录大小';

  /// zh-Hans: '超过上限时从最早的录制文件开始删除，正在录制和处理的不删'
  String get limitSizeSubtitle => '超过上限时从最早的录制文件开始删除，正在录制和处理的不删';

  /// zh-Hans: '录制目录上限'
  String get sizeLimit => '录制目录上限';

  /// zh-Hans: '不分段'
  String get noSplit => '不分段';

  /// zh-Hans: '录制保存位置'
  String get directory => '录制保存位置';

  /// zh-Hans: '默认位置'
  String get directoryDefault => '默认位置';

  /// zh-Hans: '恢复默认'
  String get directoryReset => '恢复默认';

  /// zh-Hans: '选择录制保存位置'
  String get directoryPick => '选择录制保存位置';
}

// Path: settings.audience
class Translations$settings$audience$zh_Hans {
  Translations$settings$audience$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '卡片显示'
  String get shown => '卡片显示';

  /// zh-Hans: '平台热度优先'
  String get heatFirst => '平台热度优先';

  /// zh-Hans: '显示各平台公开的热度或累计观看，这些数字不等于同时在线人数'
  String get heatFirstSubtitle => '显示各平台公开的热度或累计观看，这些数字不等于同时在线人数';

  /// zh-Hans: '在线人数优先'
  String get onlineFirst => '在线人数优先';

  /// zh-Hans: '平台给出同时在线人数时显示它，没有时再显示热度或累计观看'
  String get onlineFirstSubtitle => '平台给出同时在线人数时显示它，没有时再显示热度或累计观看';

  /// zh-Hans: '各平台的数字是什么'
  String get meaning => '各平台的数字是什么';
}

// Path: settings.network
class Translations$settings$network$zh_Hans {
  Translations$settings$network$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '使用代理'
  String get useProxy => '使用代理';

  /// zh-Hans: 'HTTP 代理，例如 Clash 的 7897 端口；打开后不再跟随系统代理'
  String get useProxySubtitle => 'HTTP 代理，例如 Clash 的 7897 端口；打开后不再跟随系统代理';

  /// zh-Hans: '代理地址'
  String get proxyHost => '代理地址';

  /// zh-Hans: '未设置（例如 127.0.0.1）'
  String get proxyHostUnset => '未设置（例如 127.0.0.1）';

  /// zh-Hans: '代理端口'
  String get proxyPort => '代理端口';

  /// zh-Hans: '走代理的平台'
  String get proxyPlatforms => '走代理的平台';

  /// zh-Hans: '现在所有平台都走代理。选中下面的平台后，只有选中的平台走代理。'
  String get proxyAll => '现在所有平台都走代理。选中下面的平台后，只有选中的平台走代理。';

  /// zh-Hans: '只有选中的平台走代理。'
  String get proxySelected => '只有选中的平台走代理。';

  /// zh-Hans: '跟随系统代理'
  String get systemProxy => '跟随系统代理';

  /// zh-Hans: '手动代理打开时不使用系统代理'
  String get systemProxyManual => '手动代理打开时不使用系统代理';

  /// zh-Hans: '系统当前没有设置代理，直接连接'
  String get systemProxyNone => '系统当前没有设置代理，直接连接';

  /// zh-Hans: '系统代理：{host}:{port}'
  String systemProxyIs({required Object host, required Object port}) => '系统代理：${host}:${port}';
}

// Path: settings.search
class Translations$settings$search$zh_Hans {
  Translations$settings$search$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '搜索设置'
  String get hint => '搜索设置';

  /// zh-Hans: '没有找到相关设置'
  String get noResults => '没有找到相关设置';

  /// zh-Hans: '3.x：{name}'
  String legacyName({required Object name}) => '3.x：${name}';

  Map<String, String> get legacy => {
    'theme_locale': '切换语言|区域与语言',
    'app_refreshRateMode': '界面刷新率',
    'exit_choice': '退出不再询问',
    'startup_enabled': '开机启动',
    'refresh_autoRefreshFavorite': '开启关注自动刷新|定时刷新时间',
    'refresh_refreshFavoriteOnResume': '返回应用时刷新收藏',
    'refresh_autoRefreshInterval': '刷新间隔时间',
    'refresh_maxConcurrentRefresh': '首页并发刷新任务',
    'refresh_autoRefreshThumbnails': '自动刷新直播缩略图',
    'refresh_thumbnailRefreshInterval': '缩略图刷新间隔',
    'theme_mode': '主题模式',
    'theme_dynamicColor': '动态取色',
    'app_denseFavorites': '紧凑模式',
    'roomCard': '房间卡片设置|卡片布局',
    'fonts': '更换系统默认字体|字体样式设置',
    'theme_textScale': '全局字体缩放比例|界面字号调节',
    'player_preferResolution': '首选清晰度',
    'player_preferResolutionCellular': '移动网络清晰度',
    'volume_globalVolumeMute': '全局静音',
    'volume_defaultMobileVolume': '手机端默认音量',
    'volume_defaultDesktopVolume': '电脑端默认音量',
    'player_hardwareDecoding': '开启硬解码',
    'player_hardwareDecoder': '硬件解码器|hwdec',
    'player_audioOutput': '音频输出驱动',
    'player_fit': '屏幕比例',
    'app_fullScreenDefault': '自动全屏',
    'player_portraitAdaptation': '智能识别竖屏直播源',
    'player_portraitFullscreenPolicy': '进入全屏时的方向',
    'player_portraitFit': '竖屏全屏画面模式',
    'player_portraitDanmakuArea': '竖屏弹幕布局',
    'player_rememberPortraitOverride': '记住单个直播间方向',
    'player_asmrSleepMode': '新直播间自动助眠',
    'player_asmrSleepMinutes': '自动助眠播放时长',
    'player_miniPlayerOnLeave': '退出小窗播放|小窗播放',
    'player_pipAlwaysOnTop': 'Windows 小窗始终置顶',
    'danmaku_area': '画面顶部占用高度',
    'danmaku_topArea': '顶部留白',
    'danmaku_bottomArea': '区域底部留白',
    'danmaku_speed': '滚动速度',
    'danmaku_fontSize': '字体大小',
    'danmaku_fontWeight': '字体粗细',
    'danmaku_stroke': '弹幕描边',
    'danmaku_strokeWidth': '描边宽度',
    'danmaku_noEmoji': '纯文字模式',
    'danmaku_autoFps': '跟随界面刷新率策略|弹幕帧率',
    'danmaku_tapInteraction': '点击画面弹幕查看操作',
    'danmaku_longPressInteraction': '长按画面弹幕打开屏蔽操作',
    'danmaku_blockList': '屏蔽管理|弹幕关键词屏蔽|弹幕关键词过滤',
    'danmaku_collapseRepeated': '合并短时间内的相同弹幕|重复弹幕过滤',
    'danmaku_similarityFilter': '相似弹幕过滤',
    'danmaku_filterDouyuAutomated': '过滤斗鱼疑似自动弹幕',
    'danmaku_pipEnabled': '小窗显示弹幕|小窗弹幕',
    'record_defaultQuality': '默认录制清晰度',
    'record_polling': '启用开播检测|挂机轮询检测',
    'record_liveCheckInterval': '检测间隔时间',
    'record_autoReconnect': '自动断线重连',
    'record_maxRetries': '最大重试次数',
    'record_retryDelay': '重连间隔时间',
    'record_maxCheckInterval': '最大检测间隔',
    'record_readTimeout': '录制读写超时',
    'record_maxConcurrent': '最大同时录制任务数',
    'record_danmaku': '同时录制弹幕',
    'record_pinyinFolders': '使用拼音文件夹名',
    'record_resumeOnLaunch': '应用启动时恢复待录任务',
    'record_cacheLimitEnabled': '启用缓存限制',
    'record_cacheLimitMB': '缓存限制',
    'accounts_platforms': '平台显示|首选直播平台',
    'accounts_audience': '观看数据与排行口径',
    'accounts_accounts': '三方认证',
    'network_proxyEnabled': '启用应用层代理|启用播放代理|网络代理设置',
    'network_proxyHost': '代理主机',
    'history_limit': '观看记录保留数量',
    'data_cache': '清空本地缓存|缓存与数据管理',
    'data_diagnostics': '本地配置预览',
  };
}

// Path: sync.device
class Translations$sync$device$zh_Hans {
  Translations$sync$device$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: 'Android 设备'
  String get android => 'Android 设备';

  /// zh-Hans: 'Windows 电脑'
  String get windows => 'Windows 电脑';

  /// zh-Hans: 'Linux 电脑'
  String get linux => 'Linux 电脑';
}

// Path: sync.lan
class Translations$sync$lan$zh_Hans {
  Translations$sync$lan$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '对方已确认并导入'
  String get applied => '对方已确认并导入';

  /// zh-Hans: '配对码不对，请核对对方屏幕上的配对码（连续输错几次后对方会换一个新的）'
  String get wrongCode => '配对码不对，请核对对方屏幕上的配对码（连续输错几次后对方会换一个新的）';

  /// zh-Hans: '对方拒绝了这次同步，或没有及时确认'
  String get rejected => '对方拒绝了这次同步，或没有及时确认';

  /// zh-Hans: '对方正在处理另一次同步，请稍后再试'
  String get busy => '对方正在处理另一次同步，请稍后再试';

  /// zh-Hans: '对方的版本不能接收 v4 的数据（3.x 只能接收 3.x 的数据），请改用备份文件或 WebDAV'
  String get unsupported => '对方的版本不能接收 v4 的数据（3.x 只能接收 3.x 的数据），请改用备份文件或 WebDAV';

  /// zh-Hans: '连不上对方：请确认两台设备在同一网络、对方已开始接收，地址和端口正确'
  String get unreachable => '连不上对方：请确认两台设备在同一网络、对方已开始接收，地址和端口正确';

  /// zh-Hans: '等待对方确认超时'
  String get timeout => '等待对方确认超时';

  /// zh-Hans: '对方导入失败'
  String get failed => '对方导入失败';

  /// zh-Hans: 'Android 17 起，系统可能要求允许“本地网络 / 附近的设备”权限；连不上时请到系统设置 › 应用 › 纯粹直播 › 权限中允许。 Windows 第一次接收时会弹出防火墙提示，请允许在专用网络上访问。 两台设备需要连在同一个 Wi-Fi（或同一局域网）下。'
  String get networkNote =>
      'Android 17 起，系统可能要求允许“本地网络 / 附近的设备”权限；连不上时请到系统设置 › 应用 › 纯粹直播 › 权限中允许。\nWindows 第一次接收时会弹出防火墙提示，请允许在专用网络上访问。\n两台设备需要连在同一个 Wi-Fi（或同一局域网）下。';

  /// zh-Hans: '无法开始接收：{error}'
  String cannotReceive({required Object error}) => '无法开始接收：${error}';

  /// zh-Hans: '来自 {from}'
  String from({required Object from}) => '来自 ${from}';

  /// zh-Hans: '收到同步数据'
  String get received => '收到同步数据';

  /// zh-Hans: '已拒绝来自 {from} 的数据'
  String declined({required Object from}) => '已拒绝来自 ${from} 的数据';

  /// zh-Hans: '已导入来自 {from} 的数据'
  String imported({required Object from}) => '已导入来自 ${from} 的数据';

  /// zh-Hans: '请填写对方屏幕上显示的地址，例如 192.168.1.5:39888'
  String get enterAddress => '请填写对方屏幕上显示的地址，例如 192.168.1.5:39888';

  /// zh-Hans: '请填写对方屏幕上的 6 位配对码'
  String get enterCode => '请填写对方屏幕上的 6 位配对码';

  /// zh-Hans: '发送到对方'
  String get sendTo => '发送到对方';

  /// zh-Hans: '正在等待对方确认…'
  String get waiting => '正在等待对方确认…';

  /// zh-Hans: '发送失败：{error}'
  String sendFailed({required Object error}) => '发送失败：${error}';

  /// zh-Hans: '接收'
  String get receive => '接收';

  /// zh-Hans: '在要接收数据的设备上开始接收，然后在另一台设备的“发送”里填写这里显示的地址和配对码。收到数据后会先让你确认，确认前不会写入任何内容。'
  String get receiveHint => '在要接收数据的设备上开始接收，然后在另一台设备的“发送”里填写这里显示的地址和配对码。收到数据后会先让你确认，确认前不会写入任何内容。';

  /// zh-Hans: '正在开始…'
  String get starting => '正在开始…';

  /// zh-Hans: '开始接收'
  String get startReceiving => '开始接收';

  /// zh-Hans: '正在接收'
  String get receiving => '正在接收';

  /// zh-Hans: '没有找到本机的局域网地址，请先连接 Wi-Fi。'
  String get noAddress => '没有找到本机的局域网地址，请先连接 Wi-Fi。';

  /// zh-Hans: '地址'
  String get address => '地址';

  /// zh-Hans: '配对码'
  String get code => '配对码';

  /// zh-Hans: '配对码只能用一次：收到一次数据或输错几次后会自动更换。'
  String get codeOnce => '配对码只能用一次：收到一次数据或输错几次后会自动更换。';

  /// zh-Hans: '同步二维码'
  String get qr => '同步二维码';

  /// zh-Hans: '3.x 版本可以扫这个二维码发送数据'
  String get qrHint => '3.x 版本可以扫这个二维码发送数据';

  /// zh-Hans: '停止接收'
  String get stopReceiving => '停止接收';

  /// zh-Hans: '先在另一台设备上打开“局域网同步 › 接收”，再填写它显示的地址和配对码。可以选择完整备份或仅关注；平台登录信息只有设置口令后才会加密发送。'
  String get sendHint => '先在另一台设备上打开“局域网同步 › 接收”，再填写它显示的地址和配对码。可以选择完整备份或仅关注；平台登录信息只有设置口令后才会加密发送。';

  /// zh-Hans: '对方地址'
  String get otherAddress => '对方地址';

  /// zh-Hans: '等待对方确认…'
  String get awaiting => '等待对方确认…';

  /// zh-Hans: '{name}（{address}）'
  String senderWithAddress({required Object name, required Object address}) => '${name}（${address}）';
}

// Path: sync.webdav
class Translations$sync$webdav$zh_Hans {
  Translations$sync$webdav$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$sync$webdav$error$zh_Hans error = Translations$sync$webdav$error$zh_Hans.internal(_root);

  /// zh-Hans: '远端目录还不存在，第一次上传时会自动创建'
  String get noDirectory => '远端目录还不存在，第一次上传时会自动创建';

  /// zh-Hans: '测试连接'
  String get test => '测试连接';

  /// zh-Hans: '连接成功'
  String get connected => '连接成功';

  /// zh-Hans: '连接成功；备份目录还不存在，第一次上传时会自动创建'
  String get connectedNoDirectory => '连接成功；备份目录还不存在，第一次上传时会自动创建';

  /// zh-Hans: '上传备份'
  String get uploadBackup => '上传备份';

  /// zh-Hans: '上传'
  String get upload => '上传';

  /// zh-Hans: '已上传'
  String get uploaded => '已上传';

  /// zh-Hans: '恢复'
  String get restore => '恢复';

  /// zh-Hans: '来自 WebDAV：{name}'
  String fromWebdav({required Object name}) => '来自 WebDAV：${name}';

  /// zh-Hans: '删除远端文件'
  String get deleteRemote => '删除远端文件';

  /// zh-Hans: '确定删除 {name}？删除后无法恢复。'
  String deleteRemoteConfirm({required Object name}) => '确定删除 ${name}？删除后无法恢复。';

  /// zh-Hans: '已删除'
  String get deleted => '已删除';

  /// zh-Hans: '删除账号'
  String get deleteAccount => '删除账号';

  /// zh-Hans: '删除“{name}”和保存的密码？远端的备份文件不受影响。'
  String deleteAccountConfirm({required Object name}) => '删除“${name}”和保存的密码？远端的备份文件不受影响。';

  /// zh-Hans: '帮助'
  String get help => '帮助';

  /// zh-Hans: '添加账号'
  String get addAccount => '添加账号';

  /// zh-Hans: '还没有 WebDAV 账号'
  String get noAccounts => '还没有 WebDAV 账号';

  /// zh-Hans: '添加坚果云、Nextcloud、群晖等支持 WebDAV 的网盘，把备份存到云端。'
  String get noAccountsHint => '添加坚果云、Nextcloud、群晖等支持 WebDAV 的网盘，把备份存到云端。';

  /// zh-Hans: '账号'
  String get account => '账号';

  /// zh-Hans: '切换到 {name}'
  String switchTo({required Object name}) => '切换到 ${name}';

  /// zh-Hans: '远端文件 {path}'
  String remoteFiles({required Object path}) => '远端文件 ${path}';

  /// zh-Hans: '点文件可以恢复或删除；3.x 的 purelive_*.txt 备份也能恢复'
  String get remoteFilesHint => '点文件可以恢复或删除；3.x 的 purelive_*.txt 备份也能恢复';

  /// zh-Hans: '上一级'
  String get up => '上一级';

  /// zh-Hans: '这里还没有备份'
  String get noBackups => '这里还没有备份';

  /// zh-Hans: '操作'
  String get actions => '操作';

  /// zh-Hans: 'WebDAV 帮助'
  String get helpTitle => 'WebDAV 帮助';

  /// zh-Hans: '坚果云：地址填 https://dav.jianguoyun.com/dav/，用户名是登录邮箱，密码要用“账户信息 › 安全选项”里生成的第三方应用密码。 Nextcloud / ownCloud：地址填 https://你的域名/remote.php/dav/files/用户名/。 群晖：在套件中心安装 WebDAV Server，地址填 https://NAS地址:5006/。 Alist 等：地址一般是 https://域名/dav/。 备份目录默认是 pure_live，第一次上传时自动创建。密码加密保存在本机，不会进入普通备份。'
  String get helpBody =>
      '坚果云：地址填 https://dav.jianguoyun.com/dav/，用户名是登录邮箱，密码要用“账户信息 › 安全选项”里生成的第三方应用密码。\n\nNextcloud / ownCloud：地址填 https://你的域名/remote.php/dav/files/用户名/。\n\n群晖：在套件中心安装 WebDAV Server，地址填 https://NAS地址:5006/。\n\nAlist 等：地址一般是 https://域名/dav/。\n\n备份目录默认是 pure_live，第一次上传时自动创建。密码加密保存在本机，不会进入普通备份。';

  /// zh-Hans: '我的网盘'
  String get defaultName => '我的网盘';

  /// zh-Hans: '请填写名称'
  String get nameRequired => '请填写名称';

  /// zh-Hans: '已经有同名的账号'
  String get nameTaken => '已经有同名的账号';

  /// zh-Hans: '地址要以 http:// 或 https:// 开头，不能带用户名、问号参数或 #'
  String get badUrl => '地址要以 http:// 或 https:// 开头，不能带用户名、问号参数或 #';

  /// zh-Hans: '添加 WebDAV 账号'
  String get addTitle => '添加 WebDAV 账号';

  /// zh-Hans: '编辑 WebDAV 账号'
  String get editTitle => '编辑 WebDAV 账号';

  /// zh-Hans: '加密保存在本机'
  String get passwordStored => '加密保存在本机';

  /// zh-Hans: '不修改请留空'
  String get passwordKeep => '不修改请留空';

  /// zh-Hans: '备份目录'
  String get directory => '备份目录';

  /// zh-Hans: '留空表示根目录'
  String get directoryRoot => '留空表示根目录';
}

// Path: sync.webdav.error
class Translations$sync$webdav$error$zh_Hans {
  Translations$sync$webdav$error$zh_Hans.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// zh-Hans: '用户名或密码不对'
  String get unauthorized => '用户名或密码不对';

  /// zh-Hans: '这个账号没有权限访问该位置'
  String get forbidden => '这个账号没有权限访问该位置';

  /// zh-Hans: '远端没有这个文件或目录'
  String get notFound => '远端没有这个文件或目录';

  /// zh-Hans: '网盘空间不足'
  String get storage => '网盘空间不足';

  /// zh-Hans: '连不上服务器，请检查地址和网络'
  String get network => '连不上服务器，请检查地址和网络';

  /// zh-Hans: '服务器的响应不是 WebDAV 格式，请检查地址'
  String get invalid => '服务器的响应不是 WebDAV 格式，请检查地址';

  /// zh-Hans: '服务器出错（HTTP {status}）'
  String http({required Object status}) => '服务器出错（HTTP ${status}）';
}
