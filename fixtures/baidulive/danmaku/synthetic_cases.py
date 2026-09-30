"""Writes S07-synthetic/cases.json: synthetic Baidu Live segments and playlists
(M5.26) for what the recordings do not cover: the other message types, broken
frames, unknown messages and boundary values. Names, ids and times are made
up. Each segment is kept as the exact bytes served (base64), so the Dart
tests and web_expected.py read the same thing.

Run from the repository root: python3 fixtures/baidulive/danmaku/synthetic_cases.py
"""
import base64
import gzip
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOM = '11500000001'
LIST = 'http://liveshowstatic.baidu.com/v1/liveshowstatic/live_11500000001.m3u8?authorization=bce-auth-v1/0123456789abcdef0123456789abcdef/2026-09-30T12:00:00Z/15768000/host/' + 'ab' * 32


def compact(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def message(inner, *, outer_type=0, msgid=1790770000000001, create_time=1790770000, wrap='text', extra=None):
    """One list message holding [inner] as the page expects it: content is
    JSON text whose `text` is JSON text (wrap 'text'), or objects."""
    if wrap == 'text':
        content = compact({'text': compact(inner)})
    elif wrap == 'object':
        content = {'text': inner}
    else:
        content = wrap
    entry = {'category': 4, 'contacter': int(ROOM), 'content': content, 'create_time': create_time,
             'from_user': 100000001, 'is_read': 0, 'mcast_id': int(ROOM), 'msg_key': '', 'msgid': msgid,
             'priority': 100, 'type': outer_type}
    if msgid is None:
        del entry['msgid']
    if create_time is None:
        del entry['create_time']
    entry.update(extra or {})
    return entry


def batch(*messages, items=None):
    return {'version': 1, 'time': 1790770000000000000, 'duration': 0,
            'list': items if items is not None else [{'appid': 405384, 'mcast_id': int(ROOM), 'messages': list(messages)}]}


def chat(**fields):
    base = {'bd_uk': 'SyntheticUk00000000000', 'character': '1005', 'character_name': '普通用户', 'content': '你好',
            'message_body': {'txt': {'word': '你好'}}, 'message_type': '0', 'name': '合成观众', 'portrait': '',
            'room_id': ROOM, 'type': '0', 'uid': '2000000001', 'vip': '0'}
    base.update(fields)
    return {k: v for k, v in base.items() if v is not DROP}


def online(count, **fields):
    base = {'type': 101, 'room_id': ROOM, 'data': {'onlineusercnt': count, 'totaluser': count, 'onlineusercnt_str': str(count)}}
    base.update(fields)
    return base


def gift(content, **service):
    info = {'anchor_id': 3000000001, 'anonymity': 0, 'content': content, 'msg_type': '24', 'portrait': '',
            'room_id': int(ROOM), 'user_id': 2000000002, 'user_name': '送礼观众'}
    info.update(service)
    return {'type': 107, 'data': {'service_type': info.pop('service_type', '10024'), 'service_info': info}}


def gift_content(**fields):
    base = {'charm_count': '', 'charm_value': 0, 'gift_count': 1, 'gift_id': '11138', 'gift_name': '拍拍',
            'gift_url': 'https://example.bcebos.com/gift.png', 'is_free': 1, 'total_value': 0}
    base.update(fields)
    return compact({k: v for k, v in base.items() if v is not DROP})


DROP = object()


def gz(data):
    return gzip.compress(data, mtime=0)


def segment(name, value, *, room=ROOM, encode='gzip', note=''):
    raw = value if isinstance(value, bytes) else compact(value).encode()
    data = {'gzip': gz, 'gzip2': lambda b: gz(gz(b)), 'plain': lambda b: b}[encode](raw)
    return {'name': name, 'roomId': room, 'b64': base64.b64encode(data).decode(), 'note': note}


SEGMENTS = [
    segment('chat', batch(message(chat()))),
    segment('chat plain (no gzip)', batch(message(chat())), encode='plain'),
    segment('chat gzipped twice', batch(message(chat())), encode='gzip2'),
    segment('chat content empty: the words', batch(message(chat(content='', message_body={'txt': {'word': '只有正文'}})))),
    segment('chat content missing: the words', batch(message(chat(content=DROP, message_body={'txt': {'word': '只有正文'}})))),
    segment('chat type 0 as a number', batch(message(chat(message_type=0, content='', message_body={'txt': {'word': '数字类型'}})))),
    segment('chat type 3: the link title', batch(message(chat(message_type='3', content='', message_body={'link': {'title': '链接标题'}})))),
    segment('chat types 1, 2, 4, 5 have no text', batch(*[message(chat(message_type=t, content='图片'), msgid=1790770000000010 + i) for i, t in enumerate(['1', '2', '4', '5'])])),
    segment('chat unknown type: the content', batch(message(chat(message_type='9', content='未知类型的文字')))),
    segment('chat without a type: the content', batch(message(chat(message_type=DROP, content='没有类型')))),
    segment('chat reply: its own words', batch(message(chat(content='@别人 回复的话', at_name='别人', at_message_type='0', at_message_body={'txt': {'word': '被回复的话'}}, message_body={'txt': {'word': '回复的话'}})))),
    segment('chat reply without the quoted words: the content', batch(message(chat(content='@别人 回复的话', at_name='别人', at_message_type='0', message_body={'txt': {'word': '回复的话'}})))),
    segment('chat reply to a non-text: the content', batch(message(chat(content='@别人 回复', at_name='别人', at_message_type='1', at_message_body={'txt': {'word': '图'}}, message_body={'txt': {'word': '回复'}})))),
    segment('chat blank text is dropped', batch(message(chat(content='  \n ', message_body={'txt': {'word': '   '}})))),
    segment('chat text and name trimmed', batch(message(chat(content='  两边有空格  ', name='  合成观众  ')))),
    segment('chat of another room is dropped; no room id is kept', batch(message(chat(room_id='11500000002')), message(chat(room_id=DROP, content='没有房间号'), msgid=1790770000000002))),
    segment('chat room id as a number', batch(message(chat(room_id=int(ROOM), content='数字房间号')))),
    segment('chat ids: numbers, text, missing', batch(
        message(chat(uid=2000000003), msgid=1790770000000003),
        message(chat(uid=DROP, content='没有用户'), msgid='1790770000000004'),
        message(chat(content='没有消息号'), msgid=None),
        message(chat(content='小数消息号'), msgid=1.5))),
    segment('chat name missing', batch(message(chat(name=DROP)))),
    segment('chat times: text, zero, negative, missing, too far, fraction', batch(
        message(chat(content='文字时间'), create_time='1790770001', msgid=1),
        message(chat(content='零'), create_time=0, msgid=2),
        message(chat(content='负数'), create_time=-5, msgid=3),
        message(chat(content='没有时间'), create_time=None, msgid=4),
        message(chat(content='太远'), create_time=8640000000001, msgid=5),
        message(chat(content='小数'), create_time=1790770001.5, msgid=6))),
    segment('content and text as objects', batch(message(chat(content='对象'), wrap='object'))),
    segment('content not JSON, text not JSON, text missing', batch(
        message({}, wrap='不是 JSON'),
        message({}, wrap=compact({'text': '不是 JSON'})),
        message({}, wrap=compact({'other': 1})),
        message(chat(content='这条可以'), msgid=7))),
    segment('outer type not 0 is skipped', batch(message(chat(content='类型 1'), outer_type=1), message(chat(content='类型 "0"'), outer_type='0', msgid=8))),
    segment('inner type as text', batch(message(online('12345', type='101')))),
    segment('online count', batch(message(online(147144)))),
    segment('online counts: text, zero, negative, fraction, missing, other room', batch(
        message(online('98765')), message(online(0)), message(online(-1)), message(online(12.5)), message(online(12.0)),
        message({'type': 101, 'room_id': ROOM, 'data': {}}), message(online(5, room_id='11500000002')),
        message(online(99999999999999999999)))),
    segment('gift', batch(message(gift(gift_content())))),
    segment('gift content as an object; numbers as text', batch(message(gift(json.loads(gift_content(gift_count='3', is_free='0', gift_id=11139)), service_type=10024)))),
    segment('gift count missing or zero is 1; http icon dropped', batch(
        message(gift(gift_content(gift_count=DROP, gift_url='http://example.com/a.png')), msgid=11),
        message(gift(gift_content(gift_count=0, gift_url='')), msgid=12))),
    segment('gift without a name, of another room, another service', batch(
        message(gift(gift_content(gift_name='  '))),
        message(gift(gift_content(), room_id=11500000002)),
        message(gift(gift_content(), service_type='10013')),
        message(gift('不是 JSON')))),
    segment('notices are not reported', batch(
        message({'type': 107, 'data': {'service_type': '10013', 'service_info': {'content': {'content_type': 'mix_room_close', 'room_ids': [11500000009]}, 'room_id': int(ROOM), 'user_id': 852517826, 'user_name': '百度网友'}}}),
        message({'type': 107, 'data': {'service_type': '10013', 'service_info': {'content': {'content_type': 'mix_room_close', 'room_ids': [int(ROOM)]}, 'room_id': int(ROOM)}}}),
        message({'type': 103, 'data': {}}), message({'type': 104, 'data': {'live_hls_url': 'x'}}), message({'type': 108}),
        message({'type': 'abc'}), message({'no': 'type'}))),
    segment('broadcast stopped (102)', batch(message(chat(content='最后一句')), message({'type': 102, 'room_id': ROOM}, msgid=21))),
    segment('102 without a room id', batch(message({'type': 102, 'data': {}}))),
    segment('102 of another room is not the end', batch(message({'type': 102, 'data': {'room_id': 11500000002}}))),
    segment('several items and messages keep their order', batch(items=[
        {'messages': [message(chat(content='第一'), msgid=31), message(online(10), msgid=32)]},
        {'messages': 'not a list'}, 'not an object',
        {'messages': [message(chat(content='第二'), msgid=33), message(gift(gift_content()), msgid=34)]}])),
    segment('list missing', {'version': 1}),
    segment('list not a list', {'version': 1, 'list': {'messages': []}}),
    segment('root is an array', [1, 2]),
    segment('root is a string', 'text'),
    segment('not JSON', b'{"list": [', encode='gzip'),
    segment('not UTF-8', b'{"list": "\xff\xfe"}', encode='plain'),
    segment('broken gzip', b'\x1f\x8b\x08\x00broken', encode='plain'),
    segment('empty body', b'', encode='plain'),
]

PLAYLISTS = [
    {'name': 'recorded shape', 'url': LIST, 'text': '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:15\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PROGRAM-DATE-TIME:2026-09-30T20:17:30.304489115+08:00\n#EXTINF:0.955,\n/v1/liveshowstatic/11500000001_1790770669156884044.ts?authorization=bce-auth-v1/x/2026-09-30T12:17:49Z/604800/host/y\n#EXT-X-PROGRAM-DATE-TIME:2026-09-30T20:17:39.895909882+08:00\n#EXTINF:9.189,\n/v1/liveshowstatic/11500000001_1790770677944333002.ts?authorization=bce-auth-v1/x/2026-09-30T12:17:57Z/604800/host/z\n'},
    {'name': 'empty list', 'url': LIST, 'text': '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:15\n#EXT-X-MEDIA-SEQUENCE:0\n'},
    {'name': 'CRLF, blank lines, spaces, a media sequence', 'url': LIST, 'text': '  #EXTM3U  \r\n\r\n#EXT-X-MEDIA-SEQUENCE: 42 \r\n#EXTINF:1,\r\n  /v1/liveshowstatic/a.ts  \r\n'},
    {'name': 'relative and absolute segments; other hosts and schemes skipped', 'url': LIST, 'text': '#EXTM3U\nb.ts\n../c.ts?x=1\nhttp://liveshowstatic.baidu.com/v1/d.ts\nhttps://liveshowstatic.baidu.com/v1/e.ts\nhttp://evil.example.com/v1/f.ts\nhttp://user@liveshowstatic.baidu.com/v1/g.ts\n'},
    {'name': 'not a playlist (an error page)', 'url': LIST, 'text': '<html>busy</html>'},
    {'name': 'a JSON error', 'url': LIST, 'text': '{"code":"NoSuchKey","message":"The specified key does not exist."}'},
    {'name': 'empty text', 'url': LIST, 'text': ''},
    {'name': 'EXTM3U not first', 'url': LIST, 'text': '#EXT-X-VERSION:3\n#EXTM3U\n/v1/a.ts\n'},
]

if __name__ == '__main__':
    (HERE / 'S07-synthetic').mkdir(exist_ok=True)
    document = {'roomId': ROOM, 'segments': SEGMENTS, 'playlists': PLAYLISTS}
    (HERE / 'S07-synthetic' / 'cases.json').write_text(json.dumps(document, ensure_ascii=False, indent=1) + '\n')
