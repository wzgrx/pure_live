"""Expected values of the Kugou Live chat samples, read the way the website's
room page reads them (docs/modules/M5.25-kugoulive.md). Standard library only.

Run from the repository root: `python3 fixtures/kugoulive/danmaku/web_expected.py`.
It writes `expected.json` next to each sample's `frames.jsonl`.

What it follows (scripts of https://fanxing.kugou.com/<room>, 2026-09-30):

- `/pub2/vroom/main/index_5e7bbee.js`
  - `dispatchSocket.getDispatchSocketAddress`: the scheduler's query
    `{_p: 0, _v: liveInitData.version, pv: RoomSocket.socketPv, rid, clienttime,
    cid: 100, at: 102}` and its `sign`: MD5 of the sorted `k=v` joined by `&`
    and `$_fan_xing_$`, hex characters 8 to 23 (`liveInitData.version` is
    `window.staticVersion`, "7.0.0", from the room page);
  - `RoomSocket.login`: the anonymous login object; `socketPv` 20240801;
  - webpack module 1374 (`encodePb`, `decodePb`, `encodeSocketBeat`,
    `isSocketBeat`, `toDataView`, `getPayloadBuffer`), 39296 and 40564 (the
    header layout `[1, 2, 1, 2, 4, 4, 1, 2, 1]`, the variable part 12), 80965
    (the command-to-schema table) and the protobuf schemas it names:
    `SocketProtocol` (55585), `Content` (73190), `Login` (59301), `Chat`
    (38678), `Ext` (40788);
  - `RoomSocket.callback`: an envelope with `ack` is replaced by its
    `content` (the ack socket, `socketType` 1).
- `/pub2/room/js/socket_51738e4.js`, `RoomSocket.callback`, case
  `MESSAGE`/`OTHERMESSAGE`: a sender below 0 and `privateType` 1 are not
  shown; `receiverid` 0 of the message is the public chat, where
  `OTHERMESSAGE` (400305) shows only with `source.tags & 1` (and the PK module's
  consent) and is marked as the other room's; the name and text go through
  `String.prototype.replaceUnicode` (index_5e7bbee.js: characters U+2027 to
  U+202E become a space, then every space is removed).
- `/pub2/room/js/roomBase_a2fb4ce.js`, `dealWithNickName`: the fan badge is
  `ext.intimacyVo` (`nameplate`, `level`) when `level > 0`, `type` is 1 to 4
  and `lightUp` is 1.
- `/pub2/room/modules/ViewerHeat/index_fe0bfcb.js`: `HEAT_NUM` (301005) with
  `actionId` `roomAuNumber` gives `data.hot` (热度) and `data.visited`;
  `/pub2/room/modules/viewerList/index_36b2784.js` shows `visited` as
  “看过：本场累计 N 人” and `count` as the viewer count.
- `setSSID` and `sendSocketEnterRoom`: a status frame (901) with `status` 1
  enters the room, `type` 1 carries `socsid`; `errorno` 622 makes the page ask
  the scheduler again (`dispatchError622`).
- `/pub2/room/js/socket_51738e4.js`, `RoomSocket.callback`: a gift
  (`SENDGIFT`, 601) with `ack` 1 is answered with `{cmd: ACKCMD (211), roomId,
  kugouId: Number(KugooID cookie) (0 without a login), offset, msgId, rpt}`,
  encoded by `encodePb` (`Ack.AckRequest`, module 47985).

Not followed: `sendChatMessage.chatSet.judgeShowChatMes` (the page hides public
chat of users the room's chat limit would not let speak; it needs the room's
admin list and limit) is reported as `chatLimitCheck` for the record.
"""
import base64
import gzip
import hashlib
import json
import pathlib
import struct
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent
GENERATOR = ('fixtures/kugoulive/danmaku/web_expected.py: the website room page\'s own reading '
             '(index_5e7bbee.js modules 1374/80965 and RoomSocket, socket_51738e4.js RoomSocket.callback, '
             'roomBase dealWithNickName, ViewerHeat), reimplemented in Python over the recorded frames')

# --- protobuf (protobufjs reads the last value of a singular field) ----------

def _varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if c < 0x80:
            return r, i


def _fields(b):
    i, out = 0, {}
    while i < len(b):
        k, i = _varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = _varint(b, i)
            if v >= 1 << 63:
                v -= 1 << 64
        elif w == 2:
            n, i = _varint(b, i)
            v = bytes(b[i:i + n])
            i += n
        elif w == 1:
            v, i = b[i:i + 8], i + 8
        elif w == 5:
            v, i = b[i:i + 4], i + 4
        else:
            raise ValueError(w)
        out[f] = v
    return out


def _enc_varint(v):
    if v < 0:
        v += 1 << 64
    out = bytearray()
    while True:
        b, v = v & 0x7F, v >> 7
        out.append(b | 0x80 if v else b)
        if not v:
            return bytes(out)


def _encode(fields):
    """protobufjs's encoder: every set field, in field-number order."""
    out = bytearray()
    for number, value in sorted(fields.items()):
        if isinstance(value, int):
            out += _enc_varint(number << 3) + _enc_varint(value)
        else:
            data = value.encode() if isinstance(value, str) else value
            out += _enc_varint(number << 3 | 2) + _enc_varint(len(data)) + data
    return bytes(out)

# --- the page's schemas (only the fields read below) -------------------------

LOGIN = {'cmd': 1, 'roomid': 2, 'kugouid': 3, 'token': 4, 'appid': 6, 'platid': 7, 'deviceNo': 10, 'v': 12,
         'referer': 13, 'clientid': 14, 'soctoken': 15, 'sid': 18, 'socsid': 23, 'screen': 29, 'dfid': 38}
ERROR_RESPONSE = {1: 'cmd', 2: 'type', 3: 'seq', 4: 'status', 5: 'errorno', 6: 'msg', 7: 'socsid'}
CONTENT = {1: 'cmd', 3: 'roomid', 4: 'receiverid', 5: 'receiverkugouid', 6: 'senderid', 7: 'senderkugouid',
           11: 'time', 16: 'codec'}
CHAT = {1: 'chatmsg', 2: 'senderid', 3: 'senderkugouid', 4: 'sendername', 5: 'senderrichlevel', 6: 'receiverid',
        7: 'receiverkugouid', 8: 'receivername', 10: 'issecrect', 13: 'seq', 25: 'senderrichlevelV2'}
STRINGS = {'msg', 'socsid', 'chatmsg', 'sendername', 'receivername'}
INTIMACY = {1: 'level', 2: 'nameplate', 3: 'type', 5: 'lightUp'}
SINFO = {5: 'ck', 8: 'ckid'}
SOURCE = {1: 'roomid', 2: 'tags'}


def _read(raw, names):
    fields = _fields(raw)
    out = {}
    for number, name in names.items():
        if number in fields:
            value = fields[number]
            out[name] = value.decode('utf-8', 'replace') if isinstance(value, bytes) else value
        else:
            # protobufjs's prototype defaults, copied by clonePrototypeAttr
            out[name] = '' if name in STRINGS or name in ('nameplate', 'ckid') else 0
    return out, fields

# --- frames ------------------------------------------------------------------

def _payload(raw):
    """getPayloadBuffer: type at 3, the variable length at 4, the command at 6."""
    n = struct.unpack('>h', raw[4:6])[0]
    return struct.unpack('>i', raw[6:10])[0], raw[6 + n:]


def _uncompress(data, compression):
    if compression == 1:
        return gzip.decompress(data)
    if compression == 2:
        raise NotImplementedError('snappy is not in the samples')
    return data


def decode_pb(raw):
    """decodePb, then RoomSocket.callback's unwrap of an ack envelope."""
    cmd, payload = _payload(raw)
    envelope = _fields(payload)
    codec = envelope.get(6, 0)
    content = _uncompress(envelope.get(7, b''), envelope.get(5, 0))
    if codec == 1:
        if cmd == 901:
            message, _ = _read(content, ERROR_RESPONSE)
        else:
            message, fields = _read(content, CONTENT)
            if message['codec'] == 1 and cmd in (501, 400305):
                message['content'], _ = _read(fields.get(2, b''), CHAT)
                ext = _fields(fields.get(14, b''))
                if 39 in ext:
                    message['ext'] = {'intimacyVo': _read(ext[39], INTIMACY)[0]}
                if 15 in fields:
                    message['sinfo'] = _read(fields[15], SINFO)[0]
                if 18 in fields:
                    message['source'] = _read(fields[18], SOURCE)[0]
    else:
        message = json.loads(content.decode('utf-8'))
    # RoomSocket.callback: the envelope's ack fields go on the message.
    message['ack'] = envelope.get(2, 0)
    message['rpt'] = envelope.get(3, 0)
    message['msgId'] = envelope.get(4, b'').decode()
    message['offset'] = envelope.get(1, b'').decode()
    return cmd, message


def replace_unicode(text):
    """String.prototype.replaceUnicode of index_5e7bbee.js."""
    out = ''.join(' ' if 8231 <= ord(ch) <= 8238 else ch for ch in text)
    return out.replace(' ', '')


def chat(cmd, k):
    """RoomSocket.callback, case MESSAGE / OTHERMESSAGE."""
    content = k['content']
    other = cmd == 400305
    if k['senderid'] < 0 or content.get('privateType') == 1:
        return {'shown': False, 'why': 'sender below 0 or privateType 1'}
    if k['receiverid'] != 0:
        return {'shown': False, 'why': 'private message'}
    if other and not (k.get('source', {}).get('tags', 0) & 1):
        return {'shown': False, 'why': 'other room without source.tags & 1'}
    intimacy = k.get('ext', {}).get('intimacyVo')
    badge = None
    if intimacy and intimacy['level'] > 0 and intimacy['type'] in (1, 2, 3, 4) and intimacy['lightUp'] == 1:
        badge = {'clubName': intimacy['nameplate'], 'level': intimacy['level']}
    mystery = k.get('sinfo', {}).get('ck') == 1
    return {
        'shown': True,
        'otherRoom': other,
        'source': k.get('source'),
        'roomid': k['roomid'],
        'senderid': k['senderid'],
        'senderkugouid': k['senderkugouid'],
        'operationUserId': k['sinfo']['ckid'] if mystery else k['senderid'],
        'userName': replace_unicode(content['sendername']),
        'text': replace_unicode(content['chatmsg']),
        'toName': replace_unicode(content['receivername']) if content['receiverid'] != 0 else None,
        'richLevel': content['senderrichlevelV2'] or content['senderrichlevel'],
        'fanBadge': badge,
        'seq': content['seq'],
        'time': k['time'],
        'msgId': k['msgId'],
        'chatLimitCheck': 'judgeShowChatMes not applied (needs the room limit and admin list)',
    }


def frame(line, entry, room):
    raw = base64.b64decode(entry['b64'])
    if raw[3] == 0:
        return {'line': line, 'dir': entry['dir'], 'heartbeat': raw.hex()}
    if entry['dir'] == 'out':
        return {'line': line, 'dir': 'out', 'cmd': _payload(raw)[0]}
    cmd, k = decode_pb(raw)
    out = {'line': line, 'dir': entry['dir'], 'cmd': cmd}
    if cmd == 901:
        out['status'] = {name: k[name] for name in ('type', 'status', 'errorno', 'socsid')}
        out['entered'] = k['status'] == 1
        out['sessionSet'] = k['status'] == 1 and k['type'] == 1
        out['askSchedulerAgain'] = k['errorno'] == 622
    elif cmd in (501, 400305):
        out['chat'] = chat(cmd, k)
    elif cmd == 601:
        if k['ack'] == 1:
            ack = {'cmd': 211, 'roomId': room, 'kugouId': 0, 'offset': k['offset'], 'msgId': k['msgId'],
                   'rpt': k['rpt']}
            numbers = {'cmd': 1, 'roomId': 2, 'kugouId': 3, 'offset': 4, 'msgId': 5, 'rpt': 6}
            message = _encode({7: _encode({numbers[key]: value for key, value in ack.items()})})
            header = struct.pack('>bhbhii', 100, 3, 1, 12, 211, len(message)) + bytes(4)
            out['ack'] = {'object': ack, 'b64': base64.b64encode(header + message).decode()}
    elif cmd == 301005:
        content = k['content']
        if content.get('actionId') == 'roomAuNumber':
            data = content['data']
            out['audience'] = {'count': data['count'], 'visited': data['visited'], 'hot': data['hot'],
                               'roomid': k['roomid']}
    return out


def login(entry):
    """The login the page would write with the recorded ids (encodePb of
    RoomSocket.login's object, JSON.stringify dropping nothing)."""
    raw = base64.b64decode(entry['b64'])
    cmd, payload = _payload(raw)
    sent = _fields(_fields(payload)[7])
    obj = {'cmd': cmd, 'roomid': sent[2], 'kugouid': 0, 'token': '', 'appid': 1010, 'referer': 0, 'clientid': 100,
           'v': 20240801, 'soctoken': sent[15].decode(), 'sid': sent[18].decode(), 'socsid': sent[23].decode(),
           'deviceNo': sent[10].decode(), 'screen': 0, 'platid': 7, 'dfid': '-'}
    message = _encode({7: _encode({LOGIN[key]: value for key, value in obj.items()})})
    header = struct.pack('>bhbhii', 100, 3, 1, 12, cmd, len(message)) + bytes(4)
    return {'object': obj, 'b64': base64.b64encode(header + message).decode()}


def sign(url):
    query = urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query, keep_blank_values=True)
    params = {key: value for key, value in query if key not in ('sign', '_')}
    text = '&'.join(f'{key}={params[key]}' for key in sorted(params)) + '$_fan_xing_$'
    return {'params': params, 'sign': hashlib.md5(text.encode()).hexdigest()[8:24], 'recorded': dict(query)['sign']}


def sample(case):
    root = ROOT / case
    entries = [json.loads(line) for line in (root / 'frames.jsonl').read_text().splitlines()]
    room = int(json.loads((root / 'meta.json').read_text())['danmakuKeys']['roomId'])
    value = {'frames': []}
    for line, entry in enumerate(entries, 1):
        if 'url' in entry:
            answer = json.loads(entry['text'])
            value['dispatch'] = {
                'sign': sign(entry['url']),
                'hosts': [f"{answer['data']['protocol']}{address['host']}" for address in answer['data']['addrs']],
                'soctoken': answer['data']['soctoken'],
                'age': answer['data']['age'],
            }
            continue
        if entry['dir'] == 'out' and base64.b64decode(entry['b64'])[3] == 1:
            value['login'] = login(entry)
        value['frames'].append(frame(line, entry, room))
    value['heartbeat'] = base64.b64encode(struct.pack('>bhb', 100, 1, 0)).decode()
    (root / 'expected.json').write_text(
        json.dumps({'generator': GENERATOR, 'value': value}, ensure_ascii=False, indent=1) + '\n')


if __name__ == '__main__':
    for case in ('S07-live', 'S08-refused', 'S09-pk-chat'):
        sample(case)
