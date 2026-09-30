#!/usr/bin/env python3
"""Writes fixtures/17live/danmaku/S07-synthetic/cases.json (docs/modules/M5.29-17live.md).

Synthetic frames of a 17LIVE chat socket (Ably's JSON protocol), for what the
recordings (S05-live, S06-live) do not show: hidden and paid comments, fields
missing or of the wrong type, payloads that are not gzip + base64, gifts and
the other message types, and the protocol messages of a refused token, a
failed channel, a detach and a re-authorisation. Field names and shapes follow
S06-live, the website's scripts (2026-09-30) and the read-only probes of
2026-09-28 and 09-30 (the error texts of a made-up token); names, ids and
times are made up.

Run from the repository root:

    python3 fixtures/17live/danmaku/synthetic_cases.py

The output depends only on this file.
"""

import base64
import gzip
import json
import pathlib

ROOM = '27484154'
OUT = pathlib.Path(__file__).parent / 'S07-synthetic' / 'cases.json'
T = 1790636400123


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def packed(payload):
    return base64.b64encode(gzip.compress(dumps(payload).encode(), mtime=0)).decode('ascii')


def text(value, note=None):
    frame = {'text': value if isinstance(value, str) else dumps(value)}
    if note:
        frame['note'] = note
    return frame


def binary(value, note):
    return {'b64': base64.b64encode(value.encode()).decode('ascii'), 'note': note}


def user(n, name=None, **more):
    return {
        'userID': f'{n:08x}-0000-4000-8000-{n:012x}',
        'displayName': f'观众{n}' if name is None else name,
        'picture': f'{n:08X}-0000-4000-8000-{n:012X}.jpg',
        'level': 10 + n,
        'isVIP': False,
        'isGuardian': False,
        'isStreamer': False,
        'isDirty': False,
        'isDirtyUser': False,
        'isFraud': False,
        **more,
    }


def comment(n, words, *, time=None, color='#FFFFFFFF', display_user=None, **more):
    body = {
        'marquee': {'type': 0, 'point': 0},
        'barrage': {'type': 0, 'count': 0, 'isInfinite': False, 'point': 0, 'name': '', 'animationID': '', 'expireTime': 0},
        'isDirty': False,
        'isDirtyUser': False,
        'isFraud': False,
        'region': 'JP',
        'type': 0,
        'sendTime': T + n if time is None else time,
        'level': 10 + n,
        'name': {'text': f'观众{n}', 'textColor': '#FF9E7BFF'},
        'comment': {'text': words, 'textColor': color, 'textSize': 14},
        'content': words,
        'colorCode': '',
        'barrageStyle': False,
        'displayUser': user(n) if display_user is None else display_user,
        'streamerUserID': '20015b43-ab03-43d8-a37e-32250131d6bc',
    }
    body.update(more)
    return {'type': 3, 'commentMsg': body}


def message(payloads, *, frame_id='synthetic001', channel=ROOM, ids=True):
    items = []
    for index, payload in enumerate(payloads):
        item = {'action': 0, 'data': payload if not isinstance(payload, dict) or 'data' in payload else packed(payload)}
        if isinstance(payload, dict) and 'data' in payload:
            item = {'action': 0, **payload}
        if ids and 'id' not in item:
            item['id'] = f'{frame_id}:{index}'
        items.append(item)
    return {
        'action': 15,
        'id': frame_id,
        'channel': channel,
        'channelSerial': f'0{T}-000@4abSYNTHETIC000000000',
        'timestamp': T,
        'messages': items,
    }


def gift(n):
    return {
        'type': 13,
        'giftMsg': {
            'displayUser': user(n),
            'giftID': '2609_jp_cp_akanya',
            'giftIDs': ['2609_jp_cp_akanya'],
            'giftMetas': [{'targetGiftID': '2609_jp_cp_akanya', 'combo': {'count': 1}}],
            'point': 0,
        },
    }


def live(viewers):
    return {
        'type': 38,
        'liveinfo': {'type': 1, 'mute': False, 'giftRankOne': None, 'liveViewerCount': viewers, 'achievementValue': 1},
    }


CASES = [
    {
        'name': 'comments: a coloured one, a barrage, a name only in openID, no display user',
        'frames': [
            text(message([comment(1, 'こんばんは', color='#FF33CDBB')], frame_id='case01a')),
            text(
                message(
                    [
                        comment(
                            2,
                            '弾幕です',
                            barrageStyle=True,
                            barrage={'type': 2, 'count': 1, 'isInfinite': False, 'point': 30, 'name': 'Rocket'},
                        )
                    ],
                    frame_id='case01b',
                ),
                'a barrage: a paid comment that also flies over the video',
            ),
            text(
                message(
                    [comment(3, 'openIDだけ', display_user={'userID': user(3)['userID'], 'openID': 'viewer_three', 'level': 13})],
                    frame_id='case01c',
                )
            ),
            text(message([comment(4, '匿名', display_user='not an object')], frame_id='case01d')),
        ],
    },
    {
        'name': 'hidden comments: isDirty, isDirtyWord, isDirtyUser',
        'frames': [
            text(message([comment(5, '見えない1', isDirty=True)], frame_id='case02a')),
            text(message([comment(6, '見えない2', isDirtyWord=True)], frame_id='case02b')),
            text(message([comment(7, '見えない3', isDirtyUser=True)], frame_id='case02c')),
            text(message([comment(8, '見える', isFraud=True, isDirty=False)], frame_id='case02d'), 'isFraud does not hide'),
        ],
    },
    {
        'name': 'comment text: content first, comment.text without it, blank, not text',
        'frames': [
            text(message([comment(9, '表示される本文', comment={'text': '別の本文', 'textColor': '#FFFFFFFF'})], frame_id='case03a')),
            text(message([comment(10, '本文だけ', content=None)], frame_id='case03b'), 'content is null'),
            text(message([comment(11, '  ', comment={'text': ' ', 'textColor': '#FFFFFFFF'})], frame_id='case03c')),
            text(message([comment(12, '  前後の空白  ')], frame_id='case03d')),
            text(message([comment(13, 12345, comment={'text': None})], frame_id='case03e'), 'content is a number'),
        ],
    },
    {
        'name': 'comment times and colours',
        'frames': [
            text(message([comment(14, '時間ゼロ', time=0)], frame_id='case04a')),
            text(message([comment(15, '時間が文字', time='1790636400123')], frame_id='case04b')),
            text(message([comment(16, '色なし', color='')], frame_id='case04c')),
            text(message([comment(17, '六桁の色', color='#3366CC')], frame_id='case04d')),
            text(message([comment(18, '壊れた色', color='#FFF')], frame_id='case04e')),
        ],
    },
    {
        'name': 'a time beyond DateTime',
        'frames': [text(message([comment(19, '遠い未来', time=8640000000000001)], frame_id='case05a'))],
    },
    {
        'name': 'message ids: the message id, else the frame id and index, else none',
        'frames': [
            text(message([{'id': 'own:7', 'data': packed(comment(20, '自分のid'))}], frame_id='case06a')),
            text(message([comment(21, 'idなし'), comment(22, 'idなし2')], frame_id='case06b', ids=False)),
            text(
                {
                    'action': 15,
                    'channel': ROOM,
                    'messages': [{'action': 0, 'data': packed(comment(23, 'どちらもなし'))}],
                },
                'neither the message nor the frame has an id',
            ),
        ],
    },
    {
        'name': 'live figures (38)',
        'frames': [
            text(message([live(95)], frame_id='case07a')),
            text(message([live(0)], frame_id='case07b')),
            text(message([live(-1)], frame_id='case07c')),
            text(message([live('95')], frame_id='case07d')),
            text(message([{'type': 38}], frame_id='case07e')),
        ],
    },
    {
        'name': 'gifts and the other types show nothing',
        'frames': [
            text(message([gift(24)], frame_id='case08a')),
            text(message([{'type': 32, 'giftMsg': {'displayUser': user(25), 'giftID': 'bag_1', 'extID': 'bag'}}], frame_id='case08b')),
            text(
                message(
                    [{'type': 18, 'commentMsg': {'content': 'が参加しました！', 'comment': {'text': 'が参加しました！'}, 'displayUser': user(26)}}],
                    frame_id='case08c',
                ),
                'JOIN_ROOM: shown to the streamer only',
            ),
            text(message([{'type': 28, 'reactMsg': {'type': 2, 'openID': '观众27', 'displayUser': user(27)}}], frame_id='case08d')),
            text(message([{'type': 5, 'endStreamMsg': {'closeBy': 0}}], frame_id='case08e'), 'LIVE_STREAM_END'),
            text(message([{'type': 6, 'liveinfoChange': {'streamID': '1', 'duration': 1}}, {'type': 74}, {'type': 79}, {'type': 80}], frame_id='case08f')),
            text(message([{'type': '3', 'commentMsg': comment(28, '型が文字')['commentMsg']}], frame_id='case08g'), 'type as text'),
        ],
    },
    {
        'name': 'payloads that are not gzip + base64',
        'frames': [
            text(message([dumps(comment(29, 'そのままのJSON'))], frame_id='case09a'), 'plain JSON text'),
            text(message([{'data': comment(30, 'オブジェクト')}], frame_id='case09b'), 'a JSON object'),
            text(message(['H4sInotgzip'], frame_id='case09c')),
            text(message([base64.b64encode(b'not gzip at all').decode()], frame_id='case09d')),
            text(message([base64.b64encode(gzip.compress(b'[1,2]', mtime=0)).decode()], frame_id='case09e'), 'an array'),
            text(message([base64.b64encode(gzip.compress(b'{"type":3,"x":"\xff"}', mtime=0)).decode()], frame_id='case09f'), 'malformed UTF-8'),
            text(message([''], frame_id='case09g')),
        ],
    },
    {
        'name': 'several messages in one frame; broken items are skipped',
        'frames': [
            text(message([comment(31, '一つ目'), live(120), gift(32), comment(33, '四つ目')], frame_id='case10a')),
            text(
                {
                    'action': 15,
                    'id': 'case10b',
                    'channel': ROOM,
                    'messages': ['not an object', {'id': 'case10b:1'}, {'id': 'case10b:2', 'data': packed(comment(34, '残る'))}],
                }
            ),
            text({'action': 15, 'id': 'case10c', 'channel': ROOM, 'messages': 'not a list'}),
        ],
    },
    {
        'name': 'protocol messages: connection, attach, heartbeats and other channels',
        'frames': [
            text(
                {
                    'action': 4,
                    'connectionId': 'AAAAAAAAAA',
                    'connectionDetails': {'connectionKey': 'aaaaaaaaaaaaaa!AAAAAAAAAA-aaaaaa', 'maxIdleInterval': 15000},
                }
            ),
            text({'action': 11, 'channel': ROOM, 'channelSerial': f'0{T}-000@4abSYNTHETIC000000000', 'flags': 786432}),
            text({'action': 11, 'channel': '999999999999', 'flags': 786433}, 'another channel'),
            text({'action': 16, 'channel': ROOM, 'channelSerial': 'aaaaaaaa:', 'presence': []}, 'SYNC'),
            text({'action': 0}),
            text(message([comment(35, '別の部屋')], frame_id='case11a', channel='999999999999'), 'another channel'),
            binary(dumps(message([comment(36, 'バイナリ')], frame_id='case11b')), 'a binary frame of UTF-8 JSON'),
            text('not json'),
            text([1, 2, 3]),
        ],
    },
    {
        'name': 'protocol messages: refusals, detaches and re-authorisation',
        'frames': [
            text(
                {
                    'action': 9,
                    'error': {'message': 'Key/token status changed (expire)', 'code': 40142, 'statusCode': 401},
                },
                'a token error of the connection',
            ),
            text(
                {
                    'action': 9,
                    'error': {
                        'message': 'token invalid - could not decode legacy token: invalid token size',
                        'href': 'https://help.ably.io/error/40101',
                        'code': 40101,
                        'statusCode': 401,
                    },
                    'timestamp': T,
                },
                'a made-up token (probe of 2026-09-28)',
            ),
            text(
                {'action': 9, 'error': {'message': 'No application found with id AAAAAA', 'code': 40400, 'statusCode': 404}},
                'a made-up app id (probe of 2026-09-28)',
            ),
            text({'action': 9, 'channel': ROOM, 'error': {'message': 'Channel denied', 'code': 40160, 'statusCode': 401}}),
            text({'action': 9, 'channel': '999999999999', 'error': {'code': 40160}}, "another channel's error"),
            text({'action': 6, 'error': {'message': 'Token expired', 'code': 40142, 'statusCode': 401}}),
            text({'action': 6}, 'DISCONNECTED without an error'),
            text({'action': 6, 'error': {'message': 'Connection disconnected', 'code': 80003, 'statusCode': 400}}),
            text({'action': 13, 'channel': ROOM}, 'DETACHED without an error'),
            text({'action': 13, 'channel': ROOM, 'error': {'code': 90198, 'message': 'Channel detached'}}),
            text({'action': 17}, 'AUTH'),
            text({'action': 9}, 'ERROR without an error object'),
            text({'action': 7}, 'CLOSED'),
        ],
    },
]


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = {'roomId': ROOM, 'cases': CASES}
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'wrote {OUT} ({sum(len(case["frames"]) for case in CASES)} frames in {len(CASES)} cases)')


if __name__ == '__main__':
    main()
