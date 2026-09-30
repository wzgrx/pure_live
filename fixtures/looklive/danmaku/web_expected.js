// Frozen output of LOOK's website chat code for the recording S05-live
// (docs/modules/M5.28-looklive.md). Neither the archived v4 nor
// pure_live_TV has LOOK chat, so the reference is the website itself.
//
// Run from the repository root: node fixtures/looklive/danmaku/web_expected.js
//
// The functions below are copied from the scripts that
// https://look.163.com/live?id=<room> loaded on 2026-09-30 (static_public
// 672de53804e2cd654a6450c0_672de53804e2cd654a6450c1), de-minified with
// @babel/generator and otherwise unchanged except where noted:
//   chat = Chatroom.e3d6b7d6edc11115bba6.js (NetEase Yunxin web SDK 5.0.1,
//          bundled in webpack module "Inr+"),
//   app  = app.437aa9a876c6e88708b1.js,
//   live = Live.f58eedd602695ad4f195.js.
// Only the reading side is copied: socket.io 0.9's packet parser, the SDK's
// command assembly and answer parsing with its chatroom tables, its message
// models, LOOK's message filter (ignoreMsgs, parseIM, the risk level check
// of onmsgs) and the branch of the Live chunk's getMsgElement that decides
// which messages become chat lines. Each incoming socket frame yields what
// that code makes of it; the login frame is assembled by the SDK's
// createCmd from the recorded guest identity.
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, 'S05-live');

// --- chat: socket.io 0.9.11 parser (module "Inr+", the io.parser IIFE) -----

const parser = (function () {
  var n = {},
    r = n.packets = ["disconnect", "connect", "heartbeat", "message", "json", "event", "ack", "error", "noop"],
    o = n.reasons = ["transport not supported", "client not handshaken", "unauthorized"],
    i = n.advice = ["reconnect"],
    a = JSON,
    s = function (arr, item) { return arr.indexOf(item); }; // t.util.indexOf
  n.encodePacket = function (e) {
    var t = s(r, e.type),
      n = e.id || "",
      c = e.endpoint || "",
      u = e.ack,
      l = null;
    switch (e.type) {
      case "error":
        var p = e.reason ? s(o, e.reason) : "",
          m = e.advice ? s(i, e.advice) : "";
        "" === p && "" === m || (l = p + ("" !== m ? "+" + m : ""));
        break;
      case "message":
        "" !== e.data && (l = e.data);
        break;
      case "event":
        var f = {
          name: e.name
        };
        e.args && e.args.length && (f.args = e.args), l = a.stringify(f);
        break;
      case "json":
        l = a.stringify(e.data);
        break;
      case "connect":
        e.qs && (l = e.qs);
        break;
      case "ack":
        l = e.ackId + (e.args && e.args.length ? "+" + a.stringify(e.args) : "");
    }
    var d = [t, n + ("data" == u ? "+" : ""), c];
    return null != l && d.push(l), d.join(":");
  };
  var c = /([^:]+):([0-9]+)?(\+)?:([^:]+)?:?([\s\S]*)?/;
  n.decodePacket = function (e) {
    if (!(s = e.match(c))) return {};
    var t = s[2] || "",
      n = (e = s[5] || "", {
        type: r[s[1]],
        endpoint: s[4] || ""
      });
    switch (t && (n.id = t, s[3] ? n.ack = "data" : n.ack = !0), n.type) {
      case "error":
        var s = e.split("+");
        n.reason = o[s[0]] || "", n.advice = i[s[1]] || "";
        break;
      case "message":
        n.data = e || "";
        break;
      case "event":
        try {
          var u = a.parse(e);
          n.name = u.name, n.args = u.args;
        } catch (e) {}
        n.args = n.args || [];
        break;
      case "json":
        try {
          n.data = a.parse(e);
        } catch (e) {}
        break;
      case "connect":
        n.qs = e || "";
        break;
      case "ack":
        if ((s = e.match(/^([0-9]+)(\+)?(.*)/)) && (n.ackId = s[1], n.args = [], s[3])) try {
          n.args = s[3] ? a.parse(s[3]) : [];
        } catch (e) {}
    }
    return n;
  };
  n.decodePayload = function (e) {
    var t = function (e, t) {
      for (var n = 0, r = e; r < t.length; r++) {
        if ("\ufffd" == t.charAt(r)) return n;
        n++;
      }
      return n;
    };
    if ("\ufffd" == e.charAt(0)) {
      for (var r = [], o = 1, i = ""; o < e.length; o++) if ("\ufffd" == e.charAt(o)) {
        var a = e.substr(o + 1).substr(0, i);
        if ("\ufffd" != e.charAt(o + 1 + Number(i)) && o + 1 + Number(i) != e.length) {
          var s = Number(i);
          l = t(o + s + 1, e), a = e.substr(o + 1).substr(0, s + l), o += l;
        }
        r.push(n.decodePacket(a)), o += Number(i) + 1, i = "";
      } else i += e.charAt(o);
      return r;
    }
    return [n.decodePacket(e)];
  };
  var l; // implicit global in the original
  return n;
})();

// --- chat: SDK utilities (module 1 and the type checks it re-exports) ------

var undef = function (e) { return void 0 === e; };
var notundef = function (e) { return void 0 !== e; };
var exist = function (e) { return notundef(e) && null !== e; };
var util = {
  undef: undef,
  notundef: notundef,
  exist: exist,
  isObject: function (e) { return exist(e) && "object" === Object.prototype.toString.call(e).slice(8, -1).toLowerCase(); },
  isString: function (e) { return "string" === Object.prototype.toString.call(e).slice(8, -1).toLowerCase(); },
  merge: function (e) { for (var t = 1; t < arguments.length; t++) for (var n in arguments[t]) e[n] = arguments[t][n]; return e; },
  filterObj: function (e, t) {
    var n = {};
    return util.isString(t) && (t = t.split(/\s+/)), t.forEach(function (t) {
      e.hasOwnProperty(t) && (n[t] = e[t]);
    }), n;
  }
};

// genError: only the codes the chatroom answers of the recording use; 200
// (and 406, 808, 810) are no error, anything else is.
var genError = function (e) {
  return [200, 406, 808, 810].indexOf(e) !== -1 ? null : { code: e };
};

// --- chat: the chatroom tables (the modules after the ChatroomProtocol) -----

var idMap = {
  link: { id: 1, heartbeat: 2 },
  chatroom: { id: 13, login: 2, kicked: 3, logout: 4, sendMsg: 6, msg: 7 }
};
var cmdConfig = {
  heartbeat: {
    sid: idMap.link.id,
    cid: idMap.link.heartbeat
  },
  login: {
    sid: idMap.chatroom.id,
    cid: idMap.chatroom.login,
    params: [{
      type: "byte",
      name: "type"
    }, {
      type: "Property",
      name: "login"
    }, {
      type: "Property",
      name: "imLogin"
    }]
  }
};
var s = "chatroom";
var packetConfig = {
  "1_2": {
    service: "link",
    cmd: "heartbeat"
  },
  "4_10": {
    service: "notify"
  },
  "4_11": {
    service: "notify"
  },
  "13_2": {
    service: s,
    cmd: "login",
    response: [{
      type: "Property",
      name: "chatroom"
    }, {
      type: "Property",
      name: "chatroomMember"
    }]
  },
  "13_3": {
    service: s,
    cmd: "kicked",
    response: [{
      type: "Number",
      name: "reason"
    }, {
      type: "String",
      name: "custom"
    }]
  },
  "13_7": {
    service: s,
    cmd: "msg",
    response: [{
      type: "Property",
      name: "msg"
    }]
  }
};
var serializeMap = {
  imLogin: {
    os: 4,
    sdkVersion: 6,
    appLogin: 8,
    protocolVersion: 9,
    deviceId: 13,
    appKey: 18,
    account: 19,
    browser: 24,
    session: 26,
    token: 1e3
  },
  login: {
    appKey: 1,
    account: 2,
    deviceId: 3,
    chatroomId: 5,
    appLogin: 8,
    chatroomNick: 20,
    chatroomAvatar: 21,
    chatroomCustom: 22,
    chatroomEnterCustom: 23,
    session: 26,
    isAnonymous: 38
  }
};
var unserializeMap = {
  chatroom: {
    1: "id",
    3: "name",
    4: "announcement",
    5: "broadcastUrl",
    12: "custom",
    14: "createTime",
    15: "updateTime",
    16: "queuelevel",
    100: "creator",
    101: "onlineMemberNum",
    102: "mute"
  },
  msg: {
    1: "idClient",
    2: "type",
    3: "attach",
    4: "custom",
    5: "resend",
    6: "userUpdateTime",
    7: "fromNick",
    8: "fromAvatar",
    9: "fromCustom",
    10: "yidunEnable",
    11: "antiSpamContent",
    12: "skipHistory",
    13: "body",
    14: "antiSpamBusinessId",
    15: "clientAntiSpam",
    16: "antiSpamUsingYidun",
    20: "time",
    21: "from",
    22: "chatroomId",
    23: "fromClientType",
    25: "highPriority"
  },
  chatroomMember: {
    1: "chatroomId",
    2: "account",
    3: "type",
    4: "level",
    5: "nick",
    6: "avatar",
    7: "custom",
    8: "online",
    9: "guest",
    10: "enterTime",
    12: "blacked",
    13: "gaged",
    14: "valid",
    15: "updateTime",
    16: "tempMuted",
    17: "tempMuteDuration"
  }
};

// --- chat: the parser object (module 27: createCmd, parseResponse) --------

function Parser() {
  this.configMap = { cmdConfig: cmdConfig, packetConfig: packetConfig };
  this.serializeMap = serializeMap;
  this.unserializeMap = unserializeMap;
}
Parser.prototype.createCmd = function () {
  var e = 1;
  return function (t, n) {
    var r = this,
      o = this.configMap.cmdConfig[t];
    return t = {
      SID: o.sid,
      CID: o.cid,
      SER: "heartbeat" === t ? 0 : e++
    }, o.params && (t.Q = [], o.params.forEach(function (e) {
      var o = e.type,
        a = e.name,
        s = e.entity,
        c = n[a];
      if (!undef(c)) {
        switch (o) {
          case "PropertyArray":
            o = "ArrayMable", c = c.map(function (e) {
              return {
                t: "Property",
                v: r.serialize(e, s)
              };
            });
            break;
          case "Property":
            c = r.serialize(c, a);
            break;
          case "bool":
            c = c ? "true" : "false";
        }
        t.Q.push({
          t: o,
          v: c
        });
      }
    })), t;
  };
}();
Parser.prototype.parseResponse = function (e) {
  var t = this,
    n = JSON.parse(e),
    r = {
      raw: n,
      rawStr: e,
      error: genError(n.code)
    },
    i = t.configMap.packetConfig[n.sid + "_" + n.cid];
  if (!i) return r.notFound = {
    sid: n.sid,
    cid: n.cid
  }, r;
  var s = n.r,
    c = "notify" === i.service && !i.cmd;
  if (r.isNotify = c, c) {
    var u = n.r[1].headerPacket;
    if (i = t.configMap.packetConfig[u.sid + "_" + u.cid], s = n.r[1].body, !i) return r.notFound = {
      sid: u.sid,
      cid: u.cid
    }, r;
  }
  if (r.service = i.service, r.cmd = i.cmd, r.error) {
    var l = n.sid + "_" + n.cid;
    if (c && (l = u.sid + "_" + u.cid), r.error.cmd = r.cmd, r.error.callFunc = "protocol::parseResponse: " + l, 416 === r.error.code) {
      var p = s[0];
      p && (r.frequencyControlDuration = 1e3 * p);
    }
  }
  var m = !1;
  return r.error && i.trivialErrorCodes && (m = -1 !== i.trivialErrorCodes.indexOf(r.error.code)), r.error && !m || !i.response || (r.content = {}, i.response.forEach(function (e, i) {
    var a = s[i];
    if (!undef(a)) {
      var u = e.type,
        l = e.name,
        p = e.entity || l;
      switch (u) {
        case "Property":
          r.content[l] = t.unserialize(a, p);
          break;
        case "PropertyArray":
          r.content[l] = [], a.forEach(function (e) {
            r.content[l].push(t.unserialize(e, p));
          });
          break;
        case "KVArray":
        default:
          r.content[l] = a;
          break;
        case "long":
        case "Long":
        case "byte":
        case "Byte":
        case "Number":
          r.content[l] = +a;
      }
      if (c && "msg" === l || "sysMsg" === l) {
        var m = r.content[l];
        util.isObject(m) && !m.idServer && (m.idServer = "" + n.r[0], m.type && "8" === m.type && m.deletedIdClient && (m.idServer = m.deletedIdClient));
      }
    }
  })), r;
};
Parser.prototype.serialize = function (e, t) {
  var n = this.serializeMap[t],
    r = {};
  for (var o in n) e.hasOwnProperty(o) && (r[n[o]] = e[o]);
  return r;
};
Parser.prototype.unserialize = function (e, t) {
  var n = this.unserializeMap[t],
    r = {};
  if (e) for (var o in n) e.hasOwnProperty(o) && (r[n[o]] = e[o]);
  return r;
};
var parser27 = new Parser();

// --- chat: message models (modules 20, 67, 155, 161, 162) -----------------

var clientTypeMap = { 1: "Android", 2: "iOS", 4: "PC", 8: "WindowsPhone", 16: "Web", 32: "Server", 64: "Mac" };
var typeReverseMap = { 0: "text", 1: "image", 2: "audio", 3: "video", 4: "geo", 5: "notification", 6: "file", 10: "tip", 11: "robot", 100: "custom" };
var Message = {
  getType: function (e) {
    var t = e.type;
    return typeReverseMap[t] || t;
  },
  // genPrivateUrl only rewrites NOS download hosts; the recording has no
  // fromAvatar, so it is the identity here.
  reverse: function (e) {
    var t = util.filterObj(e, "chatroomId idClient from fromNick fromAvatar fromCustom userUpdateTime custom status");
    return t = util.merge(t, {
      fromClientType: clientTypeMap[e.fromClientType] || e.fromClientType,
      time: +e.time,
      type: Message.getType(e),
      text: exist(e.body) ? e.body : "",
      resend: 1 == +e.resend
    }), notundef(t.userUpdateTime) && (t.userUpdateTime = +t.userUpdateTime), t.status = t.status || "success", t;
  }
};
var TextMessage = { reverse: function (e) { var t = Message.reverse(e); return t.text = e.attach, t; } };
var CustomMessage = { reverse: function (e) { var t = Message.reverse(e); return t.content = e.attach, t; } };
var TipMessage = { reverse: function (e) { var t = Message.reverse(e); return t.tip = e.attach, t; } };
function reverseMessage(e) {
  switch (Message.getType(e)) {
    case "text":
      return TextMessage.reverse(e);
    case "custom":
      return CustomMessage.reverse(e);
    case "tip":
      return TipMessage.reverse(e);
    default:
      return Message.reverse(e); // the recording has no other types
  }
}

// --- app: parseIM (module NomM) --------------------------------------------

var shortKeys = {
  content: ["c", {
    isRoomManager: "ir",
    msgDisplayInfo: ["md", {
      fontInfoId: "f",
      bubbleInfoId: "b"
    }],
    user: ["u", {
      avatarUrl: ["a", "url"],
      fanClubAnchorId: "fa",
      fanClubLevel: "fcl",
      fanClubName: "fcn",
      fanClubPrivilege: "fcp",
      fanClubType: "fct",
      fanClubNameplate: ["fcnp", {
        fanClubAnchorId: "fa",
        fanClubLevel: "fcl",
        fanClubPrivilege: "fcp",
        fanClubType: "fct"
      }],
      gender: "g",
      liveLevel: "l",
      nickname: "n",
      userId: "i",
      nobleInfo: ["ni", {
        nobleLevel: "l"
      }],
      numen: ["nu", {
        numenId: "i",
        status: "s"
      }],
      headFrameInfo: ["h", {
        bigImgUrl: ["b", "url"],
        configId: "c",
        endTime: "e",
        smallImgUrl: ["s", "url"]
      }],
      userTitle: ["ut", {
        isOn: "o",
        configId: "c",
        endTime: "e",
        resourceUrl: ["r", "url"],
        visibleType: "v"
      }],
      unionUserTitle: ["uut", {
        titleType: "t",
        expireTime: "e",
        styleText: "s",
        unionId: "u"
      }]
    }],
    userHonorsConfig: ["uhc", {
      id: "i",
      appearanceType: "a",
      backgroundUrl: ["b", "url"],
      bigMedalUrl: ["bm", "url"],
      medalUrl: ["m", "url"],
      name: "n"
    }],
    attachments: "a"
  }]
};
var f = function () {
  var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : {};
  return Object.keys(e).reduce(function (t, n) {
    var r = e[n];
    if (!Array.isArray(r)) return Object.assign({}, t, { [r]: n });
    var u = r[0],
      c = r[1];
    return "url" === c ? Object.assign({}, t, { [u]: [n, "url"] }) : Object.assign({}, t, { [u]: [n, f(c)] });
  }, {});
};
var d = f(shortKeys);
var p = ["http://p1.music.126.net/", "http://p2.music.126.net/", "http://p3.music.126.net/", "http://p4.music.126.net/"];
var h = function () {
  var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : {},
    t = arguments.length > 1 && void 0 !== arguments[1] ? arguments[1] : {},
    n = arguments.length > 2 ? arguments[2] : void 0;
  return "object" !== typeof e || null === e ? e : Array.isArray(e) ? e.map(function (e) {
    return h(e, t, n);
  }) : Object.keys(e).reduce(function (r, o) {
    var c = t[o],
      l = e[o],
      s = Array.isArray(c) ? c : [c],
      d = s[0],
      m = s[1];
    return "url" === m ? Object.assign({}, r, { [d || o]: function (e, t) {
      var n = e || "";
      // (0, u.createUrl)(n).currentHost only matters when encoding
      var o = 0; // Math.round(3 * Math.random()): fixed so the output is stable
      return -1 === n.indexOf("http") ? p[o] + n : n;
    }(l, n) }) : Object.assign({}, r, { [d || o]: h(l, m, n) });
  }, {});
};
var parseIM = function (e) {
  return 1 === e.sp ? h(e, d) : e;
};

// --- app: ignoreMsgs (module Ph1m) and the risk level check of onmsgs ------

var ignoreMsgs = function () {
  var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : [],
    t = arguments.length > 1 ? arguments[1] : void 0,
    n = (Array.isArray(e) ? e : [e]).map(function (e) {
      return function () {
        var e = arguments.length > 0 && void 0 !== arguments[0] ? arguments[0] : {},
          t = !(arguments.length > 1 && void 0 !== arguments[1]) || arguments[1],
          n = e.type,
          r = e.custom,
          o = e.text,
          a = e.from;
        if ("text" === n && !o && !o) return null;
        if ("custom" === n && "musiclive_server" !== a) return null;
        try {
          if (r) {
            if (e.custom = parseIM(JSON.parse(r)), "text" === n && "iplay" !== e.custom.bizName && t) return null;
          } else if ("text" === n && t) return null;
        } catch (e) {
          if ("text" === n && t) return null;
        }
        return e;
      }(e, t);
    }).filter(function (e) {
      return null !== e;
    });
  return n;
};
// onmsgs: `this.appSettings` is the SDK's options there, so shouldIntercept
// is undefined and ignoreMsgs keeps its default (true); a guest's
// `login.riskLevel` is {}.
function onmsgs(e) {
  var o = ignoreMsgs(e, undefined),
    i = {};
  if (o.length > 0) {
    var c = o.filter(function (e) {
      var t, n, r, o = null == e || null === (t = e.custom) || void 0 === t || null === (n = t.content) || void 0 === n || null === (r = n.commonCtrl) || void 0 === r ? void 0 : r.riskLevelKey;
      return !(o && !i[o]);
    });
    return c;
  }
  return [];
}

// --- live: getMsgElement (module of the chat list; only which messages ----
// --- become chat lines and with what name and text) ------------------------

function chatLine(e) {
  var t = e.type,
    n = e.text,
    r = e.custom,
    f = ((r || {}).content || {}).user;
  if ("custom" === t && (r || {}).type === 2601) { // h.default.EMOJI
    var A = JSON.parse(((r || {}).content || {}).emoji || "{}");
    if (!f) return null;
    return { kind: "emoji", nick: f.nickname || f.nickName, text: A.name };
  }
  if ("custom" === t) return null; // other custom types are gifts, entries, notices
  if (!f) return null;
  if ("text" === t) return { kind: "text", nick: f.nickname || f.nickName, text: n };
  return null;
}

// --- the recording -----------------------------------------------------------

const lines = fs.readFileSync(path.join(root, 'frames.jsonl'), 'utf8').split('\n').filter(Boolean).map(JSON.parse);
const frames = [];
let login = null;
lines.forEach((entry, index) => {
  if (entry.url || entry.dir !== 'in') {
    if (entry.dir === 'out' && entry.text.startsWith('3:::') && login === null) {
      const command = JSON.parse(entry.text.slice(4));
      if (command.SID === 13 && command.CID === 2) {
        // The SDK's assembly of the same login (assembleLogin with the
        // recorded guest, chatroom and system strings).
        const v = command.Q[1].v, im = command.Q[2].v;
        const assembled = parser27.createCmd('login', {
          type: 1,
          login: { appKey: v['1'], account: v['2'], deviceId: v['3'], chatroomId: v['5'], session: v['26'], appLogin: 0, chatroomNick: v['20'], chatroomAvatar: v['21'], isAnonymous: 1 },
          imLogin: { appLogin: 1, appKey: im['18'], account: im['19'], token: '', sdkVersion: '47', protocolVersion: 1, os: im['4'], browser: im['24'], session: im['26'], deviceId: im['13'] },
        });
        login = { line: index + 1, assembled: '3:::' + JSON.stringify(assembled) };
      }
    }
    return;
  }
  const out = { line: index + 1, packets: [], replies: [], joined: false, chat: [] };
  for (const packet of parser.decodePayload(entry.text)) {
    out.packets.push(packet.type || 'unknown');
    if (packet.type === 'heartbeat') out.replies.push(parser.encodePacket({ type: 'heartbeat' }));
    if (packet.type !== 'message') continue;
    const answer = parser27.parseResponse(packet.data);
    if (answer.cmd === 'login') {
      out.joined = !answer.error;
      out.online = answer.content ? answer.content.chatroom.onlineMemberNum : undefined;
    }
    if (answer.cmd === 'heartbeat') out.heartbeatAck = !answer.error;
    if (answer.cmd !== 'msg' || answer.error) continue;
    const message = reverseMessage(answer.content.msg);
    for (const kept of onmsgs([message])) {
      const line = chatLine(kept);
      if (!line) continue;
      const user = kept.custom.content.user;
      out.chat.push({
        idClient: kept.idClient,
        time: kept.time,
        from: kept.from,
        kind: line.kind,
        nick: line.nick,
        text: line.text,
        userId: user.userId,
        liveLevel: user.liveLevel,
        fanClubLevel: user.fanClubLevel || (user.fanClubInfo || {}).fanClubLevel,
        fanClubName: user.fanClubName || (user.fanClubInfo || {}).fanClubName,
      });
    }
  }
  frames.push(out);
});

const expected = {
  generator: 'fixtures/looklive/danmaku/web_expected.js: LOOK website code of 2026-09-30 (socket.io 0.9.11 parser and ' +
    'Yunxin web SDK 5.0.1 from Chatroom.e3d6b7d6edc11115bba6.js; ignoreMsgs, parseIM and onmsgs from ' +
    'app.437aa9a876c6e88708b1.js; getMsgElement from Live.f58eedd602695ad4f195.js) over every incoming frame of ' +
    'S05-live/frames.jsonl, and the SDK\'s createCmd for the recorded login',
  value: { login, frames },
};
fs.writeFileSync(path.join(root, 'expected.json'), JSON.stringify(expected, null, 2) + '\n');
console.log(`frames ${frames.length}, chat ${frames.reduce((n, f) => n + f.chat.length, 0)}`);
