"""Expected readings of the recorded Kick Pusher frames (M5.34).

An independent reading of every received frame of each case after
pure_live_TV's KickDanmaku.parseFrame (e1cca224): chat lines of the chat
channel (`type` message or reply, inline emotes shown by name), the sender's
name, id and colour, the line id and time, plus what v4 adds (the `level`
badge, the end of the broadcast). Writes `<case>/expected.json`.

usage: python3 fixtures/kick/danmaku/expected.py
"""
import json
import re
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
EMOTE = re.compile(r'\[emote:\d+:([^\]\s]+)\]')


def read(case):
    meta = json.loads((HERE / case / 'meta.json').read_text())
    keys = meta['danmakuKeys']
    chat = f"chatrooms.{keys['chatroomId']}.v2"
    broadcast = f"channel.{keys['channelId']}"
    events = []
    for line in (HERE / case / 'frames.jsonl').read_text().splitlines():
        frame = json.loads(line)
        if frame['dir'] != 'in':
            continue
        envelope = json.loads(frame['text'])
        event = envelope.get('event')
        channel = envelope.get('channel')
        if event == 'pusher:connection_established':
            events.append({'kind': 'established'})
        elif event == 'pusher:ping':
            events.append({'kind': 'ping'})
        elif event == 'pusher_internal:subscription_succeeded':
            if channel == chat:
                events.append({'kind': 'joined'})
        elif channel == broadcast and event.endswith('StopStreamBroadcast'):
            events.append({'kind': 'notice', 'text': '直播已结束'})
        elif channel == chat and event == 'App\\Events\\ChatMessageEvent':
            data = json.loads(envelope['data'])
            if data.get('chatroom_id') not in (None, keys['chatroomId']):
                continue
            if data.get('type') not in (None, '', 'message', 'reply'):
                continue
            sender = data['sender']
            text = EMOTE.sub(lambda m: m.group(1), data.get('content') or '').strip()
            if not text or not sender.get('username'):
                continue
            color = sender.get('identity', {}).get('color', '')
            level = ''
            for badge in sender.get('identity', {}).get('badges_v2', []):
                if badge.get('name') == 'level' and (badge.get('metadata') or {}).get('level', 0) > 0:
                    level = str(badge['metadata']['level'])
                    break
            events.append({
                'kind': 'chat',
                'userName': sender['username'],
                'userId': str(sender['id']),
                'text': text,
                'messageId': data['id'],
                'sentAt': int(datetime.fromisoformat(data['created_at']).timestamp() * 1000),
                'color': color.lower() if re.fullmatch(r'#[0-9A-Fa-f]{6}', color) else '#ffffff',
                'userLevel': level,
            })
    return events


for case in ('S07-chat', 'S08-stream-end'):
    value = read(case)
    (HERE / case / 'expected.json').write_text(json.dumps({
        'generator': 'fixtures/kick/danmaku/expected.py: an independent reading after pure_live_TV KickDanmaku.parseFrame (e1cca224) plus the v4 level badge and broadcast end',
        'value': value,
    }, ensure_ascii=False, indent=1) + '\n')
    print(case, len(value), {k: sum(1 for e in value if e['kind'] == k) for k in {e['kind'] for e in value}})
