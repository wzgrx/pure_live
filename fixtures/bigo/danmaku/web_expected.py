"""Expected values of the Bigo chat samples (M5.20), from the website's reading.

Neither 3.x, the archived v4 nor pure_live_TV has a Bigo chat, so the
reference is the website itself: this script restates, step by step, what
the scripts of https://www.bigo.tv/<id> (downloaded 2026-09-30) do with each
frame, and what they send. It does not copy them; the places are:

- ``14.37bf41.js`` module 931, the chat socket class:
  - ``connect``/``onmessage``: ``l = e.data.indexOf("{")``,
    ``c = JSON.parse(e.data.slice(l))``, ``d = +e.data.slice(0, l).trim()``;
    a ``256`` (``Challenge_KEY``) with ``c.challenge`` is answered with
    ``79108`` + ``generateChallengeKey(challenge)``, the login follows after
    ``setTimeout(…, 1e3)`` and ``doPing`` every ``1e4`` ms;
    ``"unsigned" === c.info || c.errUri`` is a failed login;
  - ``generateChallengeKey``: fixed fields, ``timeStamp`` in seconds,
    ``sign = MD5("60#4#5#<ts>#1#1#1#1#" + challenge.slice(-8))``;
  - ``doLogin`` (``toUri("2001|23")``), ``enterRoom`` (``"5|24"``),
    ``pullChatRoomUser`` (``"42|24"``), ``doPing`` (``"791"``);
  - ``handleMessage``: ``LOGIN`` (512535) ``res == "200"`` enters the room,
    ``ENTER_ROOM_RES`` (1560) ``resCode == "200"`` pulls the audience;
  - ``toUri("a|b") = a << 8 | b``.
- ``97.929aaf.js``, the room page's ``subWs``: ``NUMS`` (10264) sets
  ``nums = totalUserCount`` when ``gid`` is the room, ``11032`` sets
  ``nums = total`` when ``room_id`` is the room, ``NORMAL_TEXT`` (2584) of
  the room decodes ``payload.content`` with
  ``JSON.parse(decodeURIComponent(escape(atob(…))))`` and adds
  ``{type: +payload.tag, grade: payload.grade, ...content}`` to the chat list,
  whose ``comments`` are the types ``NORMAL_TEXT`` (1) and ``DAMMARKU_TEXT``
  (2).
- ``app.2a1a24.js``: ``getWebSocketLink`` posts the form ``deviceId=…`` to
  ``https://ta.bigo.tv/official_website/studio/getWebSocketLink``; the
  answer's ``data`` is the ``wsConfig`` of the login.

The ``events`` of each frame are the page's comments and audience in the
app's message model (M5.20): a comment's text is ``m`` and its name ``n``,
both trimmed, empty text dropped; the user id is ``payload.uid`` (else
``from_uid``), the level ``payload.grade``, the id ``<user id>:<seqId>``;
the audience is ``nums`` as a whole number.

Run from the repository root: ``python3 fixtures/bigo/danmaku/web_expected.py``
writes ``expected.json`` next to each sample's ``frames.jsonl``.
"""
import base64
import hashlib
import json
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))
CASES = ['S05-live', 'S06-idle', 'S07-unsigned']
GENERATOR = ('fixtures/bigo/danmaku/web_expected.py: the chat reading and frames of the Bigo website '
             '(scripts 14.37bf41.js, 97.929aaf.js and app.2a1a24.js of 2026-09-30), restated')


def to_uri(pair):
    high, low = pair.split('|')
    return int(high) << 8 | int(low)


def js_number(head):
    """``+head.trim()`` of JavaScript: NaN (None here) unless the trimmed text is a number."""
    text = head.strip(' \t\n\r\x0b\x0c ﻿')
    if text == '':
        return 0
    return int(text) if re.fullmatch(r'[0-9]+', text) else None


def dumps(value):
    """``JSON.stringify``: no spaces, non-ASCII as is."""
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def answer(challenge, time):
    fields = {
        'appId': '60', 'osType': '4', 'clientVersion': '5', 'timeStamp': time, 'nonce': '1',
        'reservedForSecurity': '1', 'appSign': '1', 'redundancy': '1', 'sign': '',
    }
    fields['sign'] = hashlib.md5(f'60#4#5#{time}#1#1#1#1#{challenge[-8:]}'.encode()).hexdigest()
    return '79108' + dumps(fields)


def login(ws_config):
    return str(to_uri('2001|23')) + dumps({
        'uid': ws_config['userId'],
        'cookie': ws_config['uidToken'].replace('###VER2', ''),
        'secret': '0',
        'userName': ws_config.get('userName') or '0',
        'deviceId': ws_config['deviceId'],
        'userFlag': '0', 'status': '0', 'password': '0', 'sdkVersion': '0', 'displayType': '0',
        'pbVersion': '0', 'lang': 'cn', 'loginLevel': '0', 'clientVersionCode': '0', 'clientType': '7',
        'clientOsVer': '0',
        'netConf': {
            'clientIp': ws_config.get('clientIp') or '0', 'proxySwitch': '0', 'proxyTimestamp': '0',
            'mcc': '0', 'mnc': '0', 'countryCode': 'CN',
        },
    })


def enter_room(room_id, device_id, seq_id):
    return str(to_uri('5|24')) + dumps({
        'secretKey': '0', 'seqId': seq_id, 'roomId': room_id, 'reserver': '1', 'clientVersion': '0',
        'clientType': '7', 'version': '15', 'deviceid': device_id, 'other': [],
    })


def pull_users(owner_uid, room_id, seq_id):
    return str(to_uri('42|24')) + dumps({
        'uid': str(owner_uid), 'seqId': seq_id, 'roomid': room_id, 'contribution': '0', 'enterTimestamp': '0',
        'number': '0', 'ident': '0', 'userGrade': '0', 'version': '0', 'lastUserBeanGrade': '0',
        'lastUserId': '0', 'others': [],
    })


def ping(seq_id):
    return '791' + dumps({'status': '0', 'seqid': seq_id, 'flag': '0', 'roomId': '0', 'ownerStatus': '0',
                          'micUid': '0'})


def atob_utf8_json(content):
    try:
        return json.loads(base64.b64decode(content, validate=True).decode('utf-8'))
    except (ValueError, UnicodeDecodeError):
        return None


def digits(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9]{1,20}', value) is not None


def read_frame(text, room_id):
    """What the page does with one received frame, and its events."""
    brace = text.find('{')
    body = json.loads(text[brace:])
    eid = js_number(text[:brace])
    page = None
    events = []
    if body.get('info') == 'unsigned' or body.get('errUri'):
        page = {'loginFail': True}
    elif eid == 256 and body.get('challenge'):
        page = {'answer': True}
    elif eid == to_uri('2002|23'):
        page = {'login': body.get('res')}
    elif eid == to_uri('6|24'):
        page = {'enterRoom': body.get('resCode'), 'sid': body.get('sid')}
    elif eid == to_uri('40|24') and str(body.get('gid')) == room_id:
        page = {'nums': body.get('totalUserCount')}
        events.append({'type': 'online', 'value': int(body['totalUserCount'])})
    elif eid == 11032 and body.get('room_id') == room_id:
        page = {'nums': body.get('total')}
        events.append({'type': 'online', 'value': int(body['total'])})
    elif eid == to_uri('10|24') and body.get('room_id') == room_id:
        payload = body['payload']
        content = atob_utf8_json(payload['content']) if payload.get('content') else None
        if content is not None:
            tag = int(payload['tag'])
            entry = {'type': tag, 'grade': payload.get('grade'), **content}
            page = {'chat': entry, 'comment': tag in (1, 2)}
            text_value = content.get('m')
            text_value = text_value.strip() if isinstance(text_value, str) else ''
            if tag in (1, 2) and text_value:
                user = payload.get('uid') if digits(payload.get('uid')) else body.get('from_uid')
                user = user if digits(user) else ''
                name = content.get('n')
                events.append({
                    'type': 'chat',
                    'userId': user,
                    'userName': name.strip() if isinstance(name, str) else '',
                    'text': text_value,
                    'level': payload.get('grade') if digits(payload.get('grade')) else '',
                    'id': f'{user}:{body["seqId"]}' if user and digits(body.get('seqId')) else '',
                })
    return {'eid': eid, 'page': page, 'events': events}


def generate(case):
    folder = os.path.join(ROOT, case)
    meta = json.load(open(os.path.join(folder, 'meta.json')))
    keys = meta['danmakuKeys']
    room_id, owner = keys['roomId'], keys['ownerId']
    lines = [json.loads(line) for line in open(os.path.join(folder, 'frames.jsonl'))]
    ws_config = None
    challenge = None
    client = []
    frames = []
    link = None
    for number, line in enumerate(lines, start=1):
        if line.get('url'):
            if line['dir'] == 'in':
                ws_config = json.loads(line['text'])['data']
                link = {
                    'url': line['url'],
                    'visitor': {
                        'userId': ws_config['userId'],
                        'userName': ws_config['userName'],
                        'deviceId': ws_config['deviceId'],
                    },
                }
            else:
                link_form = line['form']
            continue
        text = line['text']
        if line['dir'] == 'in':
            frame = read_frame(text, room_id)
            if frame['page'] == {'answer': True}:
                challenge = json.loads(text[text.find('{'):])['challenge']
            frames.append({'line': number, **frame})
            continue
        recorded = json.loads(text[text.find('{'):])
        head = text[:text.find('{')]
        if head == '79108':
            expected = answer(challenge, recorded['timeStamp'])
        elif head == str(to_uri('2001|23')):
            expected = login(ws_config)
        elif head == str(to_uri('5|24')):
            expected = enter_room(room_id, ws_config['deviceId'], recorded['seqId'])
        elif head == str(to_uri('42|24')):
            expected = pull_users(owner, room_id, recorded['seqId'])
        elif head == '791':
            expected = ping(recorded['seqid'])
        else:
            raise ValueError(f'{case}:{number}: unexpected client frame {head}')
        client.append({'line': number, 'text': expected})
    link['form'] = link_form
    value = {'roomId': room_id, 'ownerId': owner, 'link': link, 'client': client, 'frames': frames}
    with open(os.path.join(folder, 'expected.json'), 'w') as out:
        json.dump({'generator': GENERATOR, 'value': value}, out, ensure_ascii=False, indent=2)
        out.write('\n')
    chats = sum(1 for f in frames for e in f['events'] if e['type'] == 'chat')
    online = sum(1 for f in frames for e in f['events'] if e['type'] == 'online')
    print(f'{case}: {len(client)} client frames, {len(frames)} received, {chats} chats, {online} audience')


for name in CASES:
    generate(name)
