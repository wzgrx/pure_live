import 'package:live_cli/src/fixture/rules/bilibili.dart';
import 'package:live_cli/src/fixture/rules/chzzk.dart';
import 'package:live_cli/src/fixture/rules/douyin.dart';
import 'package:live_cli/src/fixture/rules/douyu.dart';
import 'package:live_cli/src/fixture/rules/huya.dart';
import 'package:live_cli/src/fixture/rules/inke.dart';
import 'package:live_cli/src/fixture/rules/kilakila.dart';
import 'package:live_cli/src/fixture/rules/kuaishou.dart';
import 'package:live_cli/src/fixture/rules/missevan.dart';
import 'package:live_cli/src/fixture/rules/pandalive.dart';
import 'package:live_cli/src/fixture/rules/picarto.dart';
import 'package:live_cli/src/fixture/rules/seventeenlive.dart';
import 'package:live_cli/src/fixture/rules/showroom.dart';
import 'package:live_cli/src/fixture/rules/twitcasting.dart';
import 'package:live_cli/src/fixture/scrub.dart';

/// Sensitive fields per platform, one file each under rules/, taken from the
/// "需要脱敏的字段" list in `spec/sites/<platform>.md` §11. Cookie headers,
/// Set-Cookie values and Authorization headers are always scrubbed.
const Map<String, ScrubRules> platformRules = {
  '17live': seventeenliveRules,
  'bilibili': bilibiliRules,
  'chzzk': chzzkRules,
  'douyin': douyinRules,
  'douyu': douyuRules,
  'huya': huyaRules,
  'inke': inkeRules,
  'kilakila': kilakilaRules,
  'kuaishou': kuaishouRules,
  'missevan': missevanRules,
  'pandalive': pandaliveRules,
  'picarto': picartoRules,
  'showroom': showroomRules,
  'twitcasting': twitcastingRules,
};
