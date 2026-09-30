#!/usr/bin/env python3
"""Writes fixtures/sixroom/danmaku/S07-live/expected.json (docs/modules/M5.27-sixroom.md).

There is no earlier decoder to compare with: 3.x had no Six Rooms chat, and
neither the archived v4 nor pure_live_TV has one. So the expected values come
from the room page's own scripts (v.6.cn, downloaded 2026-09-30), ported line
by line to Python below, independently of the Dart code:

- chunkimport-pcwebsocket_b65c7291518068d7x.js (PCWebSocket): `login`,
  `convey`/`implode`, `explode`, `onMessage`, `_heartbeat`;
- chunk6236_09189e40d009daf6x.js (module 54418): `D4` (the site's Base64,
  raw inflate) for `enc=yes`, `atob` otherwise;
- chunk8104_637d0de24aec0ea9x.js (Room.Socket, Room.Msg): `login` (the
  server list `websock`, "wss://" + host + ":" + port), `callback`,
  `pMessage`, `Msg.get` with a guest's `_puser` (no uid, no `new_rich`, no
  `L.user`), the handlers 110 and 1413, `parseErr` and its flags;
- chunkimport-room_2016_59f3e19f42e15dcfx.js: the handler 101 and
  `chatList.parsePub`; `Room.GiftFly` for 108.

What a chat line shows is projected as the page builds it: the sender name
(`t.from`), the user id of its user link (`t.fid`), the text node of
`<span class="con">` (the content with `&amp;` made `&`, then character
references decoded as the browser does, trimmed; a picture message is the
image whose alternative text is AI表情, written `[AI表情]`) and `t.tm`. The
page's room-type (`rtype`) and `screenSocket` filters depend on page data
that the chat does not carry and are not modelled; the recording has neither.

Run from the repository root:

    python3 fixtures/sixroom/danmaku/page_expected.py

The output depends only on the recording and this file.
"""

import base64
import html
import json
import pathlib
import zlib

ROOT = pathlib.Path(__file__).parent
SAMPLE = ROOT / 'S07-live'

# parseErr: the flags whose handler calls room_stop() or disconnects.
STOPPING = {'101', '102', '103', '104', '109', '110', '111', '112', '113', '114', '204', '305', '306'}


def explode(frame):
    """PCWebSocket.explode: `var [s, i] = t.split("=")` for every line with an '='."""
    fields = {}
    for line in frame.split('\r\n'):
        if line and '=' in line:
            parts = line.split('=')
            fields[parts[0]] = parts[1]
    return fields


def atob(text):
    """window.atob: forgiving Base64, padding optional; bytes as Latin-1 characters."""
    return base64.b64decode(text + '=' * (-len(text) % 4), validate=True)


def d4(text):
    """Module 54418's D4: `( ) @` back to `+ / =`, atob, pako.inflate(raw), TextDecoder."""
    raw = atob(text.replace('(', '+').replace(')', '/').replace('@', '='))
    return zlib.decompressobj(-15).decompress(raw).decode('utf-8', errors='replace')


def truthy(value):
    return value not in (None, False, 0, '') and value == value


def js_number(value):
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            return float(value.strip()) if value.strip() else 0
        except ValueError:
            return float('nan')
    return float('nan')


def parse_int(value):
    """parseInt(String(value)), NaN as None."""
    if value is None:
        return None
    text = str(value).strip()
    sign = -1 if text.startswith('-') else 1
    text = text.lstrip('+-')
    digits = ''
    for ch in text:
        if not ch.isdigit():
            break
        digits += ch
    return sign * int(digits) if digits else None


def shown_to_guest(e):
    """Room.Msg.get's filters for a guest."""
    if truthy(e.get('cli')):
        number = js_number(e['cli'])
        if number != number or (int(number) & 1) < 1:
            return False
    # checkLimitLevel(e.newLimitLevel): undefined, or parseInt(...) == -1 (a guest's new_rich is undefined).
    if 'newLimitLevel' in e and parse_int(e['newLimitLevel']) != -1:
        return False
    # checkLimitStar(e.starLimitLevel): NaN or -1 (a guest has no L.user).
    star = parse_int(e.get('starLimitLevel'))
    return star is None or star == -1


def loosely_empty(value):
    """`"" == value` in JavaScript."""
    return value == '' or value is False or (isinstance(value, (int, float)) and not isinstance(value, bool) and value == 0) \
        or value == []


def js_string(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return str(value)


def parse_pub(t, lines):
    """chatList.parsePub, the parts that decide whether and what is shown."""
    if loosely_empty(t.get('from')) and js_number(t.get('supremeMystery')) != 1:
        return
    picture = t.get('picEmoji')
    if isinstance(picture, dict) and truthy(picture.get('pic')):
        text = '[AI表情]'
    else:
        text = html.unescape(t['content'].replace('&amp;', '&')).strip()
    lines.append({
        'userName': js_string(t.get('from')),
        'userId': js_string(t.get('fid')),
        'text': text,
        'tm': t.get('tm'),
    })


def gift_fly(t, lines):
    """Room.GiftFly.add(t): "<from>说：<content>" flies over the video."""
    lines.append({
        'userName': js_string(t.get('from')),
        'userId': js_string(t.get('fid')) if 'fid' in t else '',
        'text': html.unescape(str(t.get('content')).replace('&amp;', '&')).strip(),
        'tm': t.get('tm'),
    })


def msg_get(e, lines):
    if not isinstance(e, dict) or not shown_to_guest(e):
        return
    type_id = js_string(e.get('typeID'))
    if type_id == '101':
        parse_pub(e, lines)
    elif type_id == '110':
        for entry in e['content']:
            parse_pub(entry, lines)
    elif type_id == '1413':
        for entry in e['content']:
            msg_get(entry, lines)
    elif type_id == '108':
        gift_fly(e, lines)


def on_message(text):
    """PCWebSocket.onMessage, then Room.Socket.callback and pMessage."""
    fields = explode(text)
    command, content = fields.get('command'), fields.get('content')
    frame = {}
    if command == 'result':
        if content == 'login.success':
            frame['joined'] = True
        elif content == 'login.failed':
            frame['loginFailed'] = True
        return frame
    if command != 'receivemessage':
        return frame
    try:
        payload = d4(content) if fields.get('enc') == 'yes' else atob(content).decode('latin-1')
        root = json.loads(payload)
    except (ValueError, zlib.error):
        return frame
    lines = []
    if root.get('flag') == '001':
        msg_get(root.get('content'), lines)
    elif root.get('flag') in STOPPING:
        frame['refusal'] = root['flag']
    if lines:
        frame['chats'] = lines
    return frame


def main():
    meta = json.loads((SAMPLE / 'meta.json').read_text(encoding='utf-8'))
    records = [json.loads(line) for line in (SAMPLE / 'frames.jsonl').read_text(encoding='utf-8').splitlines()]
    answer = json.loads(records[0]['text'])
    servers = ['wss://' + entry.split(':')[0] + ':' + entry.split(':')[1] for entry in answer['websock']]
    login = next(r['text'] for r in records if r['dir'] == 'out' and r['text'].startswith('command=login'))
    guest = explode(login)['uid']
    frames = []
    for number, record in enumerate(records, start=1):
        if record['dir'] != 'in' or 'url' in record:
            continue
        frames.append({'line': number, **on_message(record['text'])})
    value = {
        'servers': servers,
        # PCWebSocket.login: convey(["command=login", "uid=" + t, "encpass=" + s, "roomid=" + i]).
        'login': '\r\n'.join(['command=login', 'uid=' + guest, 'encpass=', 'roomid=' + meta['danmakuKeys']['userId'], '']),
        # _heartbeat: convey(["command=sendmessage", "content=y8vPLwAA"]).
        'heartbeat': '\r\n'.join(['command=sendmessage', 'content=y8vPLwAA', '']),
        'heartbeatSeconds': 16,
        'loginTimeoutSeconds': 6,
        'frames': frames,
    }
    expected = {
        'generator': 'fixtures/sixroom/danmaku/page_expected.py: the v.6.cn room page scripts of 2026-09-30 '
                     '(PCWebSocket, module 54418, Room.Socket, Room.Msg.get for a guest, handlers 101/110/1413/108, '
                     'parsePub, parseErr) ported to Python, over every received socket frame',
        'value': value,
    }
    (SAMPLE / 'expected.json').write_text(json.dumps(expected, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
