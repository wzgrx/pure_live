import 'package:live_cli/src/fixture/rules/acfun.dart';
import 'package:live_cli/src/fixture/rules/bilibili.dart';
import 'package:live_cli/src/fixture/rules/cc.dart';
import 'package:live_cli/src/fixture/rules/douyin.dart';
import 'package:live_cli/src/fixture/rules/douyu.dart';
import 'package:live_cli/src/fixture/rules/huya.dart';
import 'package:live_cli/src/fixture/rules/kuaishou.dart';
import 'package:live_cli/src/fixture/rules/soop.dart';
import 'package:live_cli/src/fixture/rules/yy.dart';
import 'package:live_cli/src/fixture/scrub.dart';

/// Sensitive fields per platform, one file each under rules/, taken from the
/// "需要脱敏的字段" list in `spec/sites/<platform>.md` §11. Cookie headers,
/// Set-Cookie values and Authorization headers are always scrubbed.
const Map<String, ScrubRules> platformRules = {
  'acfun': acfunRules,
  'bilibili': bilibiliRules,
  'cc': ccRules,
  'douyin': douyinRules,
  'douyu': douyuRules,
  'huya': huyaRules,
  'kuaishou': kuaishouRules,
  'soop': soopRules,
  'yy': yyRules,
};
