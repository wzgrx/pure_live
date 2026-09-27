import 'package:live_cli/src/fixture/rules/baidulive.dart';
import 'package:live_cli/src/fixture/rules/bilibili.dart';
import 'package:live_cli/src/fixture/rules/douyin.dart';
import 'package:live_cli/src/fixture/rules/douyu.dart';
import 'package:live_cli/src/fixture/rules/huya.dart';
import 'package:live_cli/src/fixture/rules/jdlive.dart';
import 'package:live_cli/src/fixture/rules/kuaishou.dart';
import 'package:live_cli/src/fixture/rules/kugoulive.dart';
import 'package:live_cli/src/fixture/rules/liveme.dart';
import 'package:live_cli/src/fixture/rules/looklive.dart';
import 'package:live_cli/src/fixture/rules/niconico.dart';
import 'package:live_cli/src/fixture/rules/sixroom.dart';
import 'package:live_cli/src/fixture/rules/steambroadcast.dart';
import 'package:live_cli/src/fixture/rules/weibo.dart';
import 'package:live_cli/src/fixture/rules/xiaohongshu.dart';
import 'package:live_cli/src/fixture/scrub.dart';

/// Sensitive fields per platform, one file each under rules/, taken from the
/// "需要脱敏的字段" list in `spec/sites/<platform>.md` §11. Cookie headers,
/// Set-Cookie values and Authorization headers are always scrubbed.
const Map<String, ScrubRules> platformRules = {
  'baidulive': baiduliveRules,
  'bilibili': bilibiliRules,
  'douyin': douyinRules,
  'douyu': douyuRules,
  'huya': huyaRules,
  'jdlive': jdliveRules,
  'kuaishou': kuaishouRules,
  'kugoulive': kugouliveRules,
  'liveme': livemeRules,
  'looklive': lookliveRules,
  'niconico': niconicoRules,
  'sixroom': sixroomRules,
  'steambroadcast': steambroadcastRules,
  'weibo': weiboRules,
  'xiaohongshu': xiaohongshuRules,
};
