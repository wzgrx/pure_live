#!/usr/bin/env python3
"""Writes fixtures/missevan/danmaku/S08-synthetic/cases.json (docs/modules/M5.12-missevan.md).

Synthetic frames of a Missevan chat socket, for what the recordings (S06-live,
S07-brotli) do not show: paid danmaku, arrays, gifts, other rooms, refused
joins, every way a frame can be broken, fields of the wrong type. Binary frames
are built as the server builds them: flag 1, the UTF-8 length (24 bits,
little-endian), then a Brotli stream from the reference encoder (google/brotli,
`python3-brotli` 1.2.0), or a stored (uncompressed) meta-block as in S06-live.
Field names follow the recordings and the site's IM client; names, ids and
times are made up.

Run from the repository root with a Python that has `brotli`:

    python3 fixtures/missevan/danmaku/synthetic_cases.py

The output depends only on this file and the encoder version.
"""

import base64
import json
import pathlib

import brotli

ROOM = 246709466
UUID = 'aaaaaaaa-0000-4000-8000-000000000001'
OUT = pathlib.Path(__file__).parent / 'S08-synthetic' / 'cases.json'


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def header(length, flag=1):
    return bytes([flag, length & 0xFF, (length >> 8) & 0xFF, (length >> 16) & 0xFF])


def compressed(value, quality=11, lgwin=22):
    """A frame as the server sends it now: Brotli from the reference encoder."""
    plain = (value if isinstance(value, str) else dumps(value)).encode('utf-8')
    data = header(len(plain)) + brotli.compress(plain, quality=quality, lgwin=lgwin)
    return {'b64': base64.b64encode(data).decode('ascii'), 'plain': plain.decode('utf-8', 'replace')}


def stored(plain):
    """One uncompressed meta-block (window 16 bits), as S06-live's frames."""
    n = len(plain) - 1
    assert 0 <= n < 1 << 16
    return bytes([(n & 0x0F) << 4, (n >> 4) & 0xFF, ((n >> 12) & 0x0F) | 0x10]) + plain + b'\x03'


def raw(data, note):
    return {'b64': base64.b64encode(data).decode('ascii'), 'note': note}


def user(user_id=7300001, name='观众甲', level=16, medal=('在花间', 8), extra=()):
    titles = []
    if medal is not None:
        titles.append({'type': 'medal', 'name': medal[0], 'level': medal[1]})
    if level is not None:
        titles.append({'type': 'level', 'level': level})
    titles.extend(extra)
    return {'user_id': user_id, 'username': name, 'iconurl': 'https://static.example/avatar.png', 'titles': titles}


def chat(text, msg_id, room=ROOM, event='new', **fields):
    value = {'type': 'message', 'event': event, 'room_id': room, 'msg_id': msg_id, 'message': text, 'user': user()}
    value.update(fields)
    return value


def statistics(stats, room=ROOM):
    return {'type': 'room', 'event': 'statistics', 'room_id': room, 'statistics': stats}


def join_answer(code=0, uuid=UUID, **fields):
    value = {'type': 'room', 'event': 'join', 'uuid': uuid, 'room_id': ROOM, 'code': code}
    if code == 0:
        value['info'] = {'room': {'status': {'open': 1}}}
    value.update(fields)
    return value


def mid(n):
    return f'bbbbbbbb-0000-4000-8000-{n:012d}'


GIFT = {
    'type': 'gift',
    'event': 'send',
    'room_id': ROOM,
    'user': {'user_id': 7300002, 'username': '观众乙'},
    'gift': {'gift_id': 92264, 'name': '花语笺', 'price': 28, 'num': 2, 'icon_url': 'https://static.maoercdn.com/live/gifts/icons/92264.png'},
}


def cases():
    line = chat('你好', mid(1), time=1790612400123, bubble={'type': 'message', 'text_color': '#FFE7E8'})
    plain = dumps(line).encode('utf-8')
    good = header(len(plain)) + brotli.compress(plain, quality=11)
    yield 'a chat line with every field', [compressed(line)]
    yield 'the same line compressed at quality 0, 5 and 11, windows 10 and 24, and stored', [
        compressed(line, quality=0),
        compressed(line, quality=5, lgwin=10),
        compressed(line, quality=11, lgwin=24),
        raw(header(len(plain)) + stored(plain), 'one uncompressed meta-block, as S06-live'),
    ]
    yield 'a paid danmaku (message/danmaku) is chat', [
        compressed(chat('付费弹幕来啦', mid(2), event='danmaku', price=30, danmaku_bubble={'image_url': 'https://static.example/b.png'}))
    ]
    yield 'an array: two chat lines, a gift, a cross-room gift and the statistics', [
        compressed([
            chat('第一条', mid(3)),
            chat('第二条', mid(4)),
            GIFT,
            {'type': 'gift', 'event': 'cross_send', 'room_id': ROOM, 'room': {'room_id': 100000001}, 'gift': {'name': '别处', 'num': 1}},
            statistics({'score': 105019, 'online': 22, 'vip': 6}),
        ])
    ]
    yield 'statistics: numbers, numbers as text, negative, missing, zero, not an object', [
        compressed(statistics({'score': 5164, 'online': 3})),
        compressed(statistics({'score': '12', 'online': '7'})),
        compressed(statistics({'score': -1, 'online': 4})),
        compressed(statistics({'vip': 2})),
        compressed(statistics({'score': 0, 'online': 0})),
        compressed(statistics([1, 2])),
        compressed(statistics({'score': 1.5, 'online': True})),
    ]
    yield "another room's chat and statistics are skipped; no room_id and room_id as text are this room", [
        compressed(chat('别的房间', mid(5), room=100000001)),
        compressed(statistics({'score': 1, 'online': 1}, room=100000001)),
        compressed({k: v for k, v in chat('没有房间号', mid(6)).items() if k != 'room_id'}),
        compressed(chat('房间号是文字', mid(7), room=str(ROOM))),
        compressed(chat('房间号是零', mid(8), room=0)),
    ]
    yield 'the answer to the join: accepted, refused, another uuid, no uuid, no code', [
        compressed(join_answer()),
        compressed(join_answer(500030004, info='无法找到该聊天室')),
        compressed(join_answer(uuid='cccccccc-0000-4000-8000-000000000009')),
        compressed({k: v for k, v in join_answer().items() if k != 'uuid'}),
        compressed({k: v for k, v in join_answer().items() if k != 'code'}),
        compressed([join_answer(), chat('加入后', mid(9))]),
    ]
    yield 'connects, entries, ranks, global notices and gifts show nothing', [
        compressed({'type': 'user', 'event': 'connect', 'user': {'user_id': 0}}),
        compressed({'event': 'join_queue', 'queue': [{'user_id': 0, 'count': 1}], 'room_id': ROOM, 'type': 'member'}),
        compressed({'type': 'creator', 'event': 'new_rank', 'room_id': ROOM, 'rank_type': 4, 'rank': 11, 'rank_up': 1984}),
        compressed({'type': 'notify', 'notify_type': 'gift', 'event': 'send', 'room_id': 100000001, 'message': '<font>观众丙</font> 送出'}),
        compressed(GIFT),
        compressed({'type': 'question', 'event': 'ask', 'room_id': ROOM, 'content': {'price': 30, 'question': '问题'}}),
    ]
    yield 'text frames: the heartbeat, JSON as text, not JSON', [
        {'text': '❤️'},
        {'text': dumps(chat('文字帧', mid(10)))},
        {'text': 'not json'},
        {'text': ''},
    ]
    yield 'binary frames that are dropped', [
        raw(bytes([0]) + good[1:], 'flag 0'),
        raw(bytes([2]) + good[1:], 'flag 2'),
        raw(good[:4], 'the header only'),
        raw(good[:3], 'three bytes'),
        raw(b'', 'empty'),
        raw(header(len(plain) + 1) + good[4:], 'declares one byte more'),
        raw(header(len(plain) - 1) + good[4:], 'declares one byte less'),
        raw(header(len(plain)) + good[4:-3], 'the stream truncated'),
        raw(good + b'\x00', 'a byte after the stream'),
        raw(good[:4] + bytes([good[4] ^ 0xFF]) + good[5:], 'the first byte of the stream flipped'),
        raw(header(10) + brotli.compress(b'{"a":"' + b'x' * 100000 + b'"}'), 'declares 10 bytes; the stream holds 100 kB'),
    ]
    yield 'good frames whose JSON shows nothing', [
        compressed('not json'),
        compressed('"a string"'),
        compressed('42'),
        compressed('[]'),
        compressed('null'),
        compressed(''),
        compressed(['a', 1, None, chat('混在里面', mid(11))]),
    ]
    yield 'chat fields of other types', [
        compressed(chat('   ', mid(12))),
        compressed(chat(123, mid(13))),
        compressed(chat(['x'], mid(14))),
        compressed({k: v for k, v in chat('没有用户', mid(15)).items() if k != 'user'}),
        compressed(chat('数字名字', mid(16), user={'user_id': '7300003', 'username': 8866, 'titles': 'none'})),
        compressed(chat('文字等级', mid(17), user=user(level='16', medal=('粉丝牌', '9')))),
        compressed(chat('没有粉丝牌名', mid(18), user=user(medal=(None, 3)))),
        compressed(chat('粉丝牌名是数字', mid(19), user=user(medal=(42, 3)))),
        compressed(chat('没有消息号', None)),
        compressed(chat('  前后空白  ', 12345)),
    ]
    yield 'times: milliseconds, zero, negative, beyond DateTime, text, create_time', [
        compressed(chat('毫秒', mid(20), time=1790612400123)),
        compressed(chat('零', mid(21), time=0)),
        compressed(chat('负数', mid(22), time=-5)),
        compressed(chat('太大', mid(23), time=8640000000000001)),
        compressed(chat('文字', mid(24), time='1790612400123')),
        compressed(chat('create_time', mid(25), create_time=1790612400123)),
    ]
    bad_utf8 = b'{"type":"message","event":"new","room_id":246709466,"msg_id":"' + mid(26).encode() + \
        b'","message":"bad \xff\xfe utf-8","user":{"user_id":7300001,"username":"x"}}'
    yield 'malformed UTF-8 is replaced, not fatal', [
        raw(header(len(bad_utf8)) + brotli.compress(bad_utf8), 'two bytes that are not UTF-8 in the text')
    ]
    yield 'a sticker and a line of many lines', [
        compressed(chat('[打call]', mid(27), sticker={'package_id': 1, 'sticker_id': 2, 'name': '打call'})),
        compressed(chat('第一行\n第二行\n　', mid(28))),
    ]


def main():
    result = {
        'note': 'Synthetic frames of a Missevan chat socket (docs/modules/M5.12-missevan.md), read for room roomId '
        'with the join uuid. Each case is one or more frames in order: {"text": ...} is a text frame, {"b64": ...} a '
        'binary frame; "plain" shows what a Brotli frame holds, "note" what a broken one is. Written by '
        'fixtures/missevan/danmaku/synthetic_cases.py (google/brotli ' + brotli.version + '); names, ids and times are '
        'made up.',
        'roomId': str(ROOM),
        'uuid': UUID,
        'cases': [{'name': name, 'frames': frames} for name, frames in cases()],
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'wrote {OUT}')


if __name__ == '__main__':
    main()
