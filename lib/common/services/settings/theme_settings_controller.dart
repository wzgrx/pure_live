import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';

class ThemeSettingsController extends GetxController {
  Worker? _spacingWorker;
  final RxString themeModeName = hiveString('themeMode', "System");
  final RxBool enableDynamicTheme = hiveBool('enableDynamicTheme', false);
  final RxString themeColorSwitch = hiveString('themeColorSwitch', Colors.blue.hex);
  final RxString languageName = hiveString('language', "简体中文");
  final RxDouble crossAxisSpacing = hiveDouble('crossAxisSpacing', 6.0);
  final RxDouble mainAxisSpacing = hiveDouble('mainAxisSpacing', 6.0);
  final RxString loadingStyle = hiveString('loadingStyle', AppConsts.defaultLoadingStyleKey);
  final RxString loadingStyleColorSwitch = hiveString('loadingStyleColorSwitch', '');

  ThemeMode get themeMode => AppConsts.themeModes[themeModeName.v]!;
  Locale get language => AppConsts.languages[languageName.v]!;

  final Map<ColorSwatch<Object>, String> colorsNameMap = AppConsts.themeColors.map(
    (k, v) => MapEntry(ColorTools.createPrimarySwatch(v), k),
  );

  @override
  void onInit() {
    super.onInit();
    _spacingWorker = everAll([crossAxisSpacing, mainAxisSpacing], (_) {
      Get.find<FontSettingsController>().refreshSystemTheme();
    });
  }

  @override
  void onClose() {
    _spacingWorker?.dispose();
    super.onClose();
  }

  void changeThemeMode(String mode) {
    themeModeName.v = mode;
    Get.changeThemeMode(themeMode);
  }

  void changeThemeColorSwitch(String hex) {
    final color = HexColor(hex);
    final t = MyTheme(primaryColor: color);
    Get.changeTheme(t.lightThemeData);
    Get.changeTheme(t.darkThemeData);
  }

  Future<void> changeLanguage(String v, BuildContext context) async {
    languageName.value = v;
    final locale = AppConsts.languages[v]!;
    await context.setLocale(locale);
    Get.updateLocale(locale);
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeModeName.v,
      'enableDynamicTheme': enableDynamicTheme.v,
      'themeColorSwitch': themeColorSwitch.v,
      'language': languageName.v,
      'crossAxisSpacing': crossAxisSpacing.v,
      'mainAxisSpacing': mainAxisSpacing.v,
      'loadingStyle': loadingStyle.v,
      'loadingStyleColorSwitch': loadingStyleColorSwitch.v,
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    return {
      'themeModeName': (json['themeMode'] ?? "System") as String,
      'enableDynamicTheme': (json['enableDynamicTheme'] ?? false) as bool,
      'themeColorSwitch': (json['themeColorSwitch'] ?? const Color.fromARGB(255, 218, 70, 12).hex) as String,
      'languageName': (json['language'] ?? "简体中文") as String,
      'crossAxisSpacing': ((json['crossAxisSpacing'] ?? 6.0) as num).toDouble(),
      'mainAxisSpacing': ((json['mainAxisSpacing'] ?? 6.0) as num).toDouble(),
      'loadingStyle': (json['loadingStyle'] ?? AppConsts.defaultLoadingStyleKey) as String,
      'loadingStyleColorSwitch': (json['loadingStyleColorSwitch'] ?? '') as String,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    themeModeName.v = parsed['themeModeName'];
    enableDynamicTheme.v = parsed['enableDynamicTheme'];
    themeColorSwitch.v = parsed['themeColorSwitch'];
    languageName.v = parsed['languageName'];
    crossAxisSpacing.v = parsed['crossAxisSpacing'];
    mainAxisSpacing.v = parsed['mainAxisSpacing'];
    loadingStyle.v = parsed['loadingStyle'];
    loadingStyleColorSwitch.v = parsed['loadingStyleColorSwitch'];
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final theme = rootConfig?['theme'] as Map<String, dynamic>? ?? {};
    return {
      'themeMode': theme['themeMode'] ?? "System",
      'enableDynamicTheme': theme['enableDynamicTheme'] ?? false,
      'themeColorSwitch': theme['themeColorSwitch'] ?? Colors.blue.hex,
      'language': theme['language'] ?? "简体中文",
      'crossAxisSpacing': (theme['crossAxisSpacing'] ?? 6.0).toDouble(),
      'mainAxisSpacing': (theme['mainAxisSpacing'] ?? 6.0).toDouble(),
      'loadingStyle': theme['loadingStyle'] ?? AppConsts.defaultLoadingStyleKey,
      'loadingStyleColorSwitch': theme['loadingStyleColorSwitch'] ?? '',
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final theme = Map<String, dynamic>.from(rootConfig['theme'] ?? {});
    updateFields.forEach((k, v) => theme[k] = v);
    rootConfig['theme'] = theme;
    return rootConfig;
  }
}
