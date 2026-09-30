"""Writes expected.json for the Baidu Live danmaku samples (M5.26).

Neither 3.x, the archived v4 nor pure_live_TV decoded Baidu Live chat, so the
expected values come from this independent port of the website's reading,
written from the page script and not from the Dart code:

- the PC room page's fallback poller (pchome.live.fcb2dc0e.js, class `Se`:
  `parseM3u8Text` takes every line after `#EXTINF` as a segment, a segment
  already taken is skipped; `parseTsFileText` walks `list[*].messages[*]`);
- its chat client (class `Te`): `handleMessage` reads a message whose
  `type` is 0, `content` is JSON (or an object) whose `text` is JSON (or an
  object); payload type 0 is chat, 102 stops the live broadcast (`stopLive`),
  101 (online count) and 107 (notices) do not show in the page's chat;
  `addChatItem` picks the text by `message_type` (see `chat_text`);
- the archived spec/sites/baidulive.md section 7 for what the page does not
  show: the online count is 101's `data.onlineusercnt`, a gift is 107 with
  `service_type` 10024.

Stricter than the page where JavaScript coercion would accept odd values
(`+"" == 0`), as documented in docs/modules/M5.26-baidulive.md.

Run from the repository root: python3 fixtures/baidulive/danmaku/web_expected.py
"""
import base64
import gzip
import json
import math
import re
from pathlib import Path
from urllib.parse import urljoin, urlsplit

HERE = Path(__file__).resolve().parent
GENERATOR = ('fixtures/baidulive/danmaku/web_expected.py: an independent Python port of the Baidu Live PC room '
             "page's message-list reading (pchome.live.fcb2dc0e.js, classes Se and Te) and the archived spec's "
             'section 7 (online count 101, gift 107/10024)')
MAX_SECONDS = 8640000000000


def whole(value):
    """A whole number: int, finite whole float, or decimal text; else None."""
    if isinstance(value, bool):
        return None
    number = None
    if isinstance(value, int):
        number = value
    elif isinstance(value, float):
        number = int(value) if math.isfinite(value) and value == int(value) and abs(value) < 9.2e18 else None
    elif isinstance(value, str):
        text = value.strip()
        number = int(text) if re.fullmatch(r'[+-]?\d+', text) else None
    return number if number is not None and -2 ** 63 <= number < 2 ** 63 else None


def ident(value):
    if isinstance(value, bool):
        return ''
    if isinstance(value, str):
        return value.strip()
    number = whole(value) if isinstance(value, (int, float)) else None
    return '' if number is None else str(number)


def text_of(value):
    return value if isinstance(value, str) else ''


def obj(value):
    return value if isinstance(value, dict) else {}


def decoded(value):
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except ValueError:
        return None


def seconds(value):
    number = whole(value)
    return number if number is not None and 0 < number <= MAX_SECONDS else None


def for_room(value, room):
    found = ident(value)
    return found == '' or found == room


def chat_text(inner):
    """The page's addChatItem."""
    body = obj(inner.get('message_body'))
    words = text_of(obj(body.get('txt')).get('word'))
    content = text_of(inner.get('content'))
    kind = ident(inner.get('message_type'))
    if kind == '0':
        text = content if content else words
    elif kind in ('1', '2', '4', '5'):
        text = ''  # images, cards, voice: nothing to fly ("5" shows a placeholder on the page)
    elif kind == '3':
        text = text_of(obj(body.get('link')).get('title'))
    else:
        text = content
    quoted = text_of(obj(obj(inner.get('at_message_body')).get('txt')).get('word'))
    if text_of(inner.get('at_name')) and whole(inner.get('at_message_type')) == 0 and quoted and words:
        text = words
    return text.strip()


def decode_segment(data, room):
    body = data
    for _ in range(2):
        if len(body) >= 2 and body[:2] == b'\x1f\x8b':
            body = gzip.decompress(body)
    root = json.loads(body.decode('utf-8'))
    if not isinstance(root, dict):
        raise ValueError('not an object')
    messages, ended = [], False
    for item in root.get('list') if isinstance(root.get('list'), list) else []:
        entries = obj(item).get('messages')
        for message in entries if isinstance(entries, list) else []:
            outer = obj(message)
            if whole(outer.get('type')) != 0:
                continue
            inner = decoded(obj(decoded(outer.get('content'))).get('text'))
            if not isinstance(inner, dict):
                continue
            kind = whole(inner.get('type'))
            if kind == 0:
                if not for_room(inner.get('room_id'), room):
                    continue
                text = chat_text(inner)
                if text:
                    messages.append({'type': 'chat', 'userName': text_of(inner.get('name')).strip(),
                                     'userId': ident(inner.get('uid')), 'message': text,
                                     'messageId': ident(outer.get('msgid')), 'sentAt': seconds(outer.get('create_time'))})
            elif kind == 101:
                if not for_room(inner.get('room_id'), room):
                    continue
                count = whole(obj(inner.get('data')).get('onlineusercnt'))
                if count is not None and count >= 0:
                    messages.append({'type': 'online', 'online': count})
            elif kind == 102:
                own = inner.get('room_id')
                if for_room(own if own is not None else obj(inner.get('data')).get('room_id'), room):
                    ended = True
            elif kind == 107:
                data = obj(inner.get('data'))
                if ident(data.get('service_type')) != '10024':
                    continue
                service = obj(data.get('service_info'))
                if not for_room(service.get('room_id'), room):
                    continue
                gift = obj(decoded(service.get('content')))
                name = text_of(gift.get('gift_name')).strip()
                if not name:
                    continue
                count = whole(gift.get('gift_count'))
                count = count if count is not None and count > 0 else 1
                icon = text_of(gift.get('gift_url')).strip()
                parts = urlsplit(icon) if icon else None
                messages.append({'type': 'gift', 'userName': text_of(service.get('user_name')).strip(),
                                 'userId': ident(service.get('user_id')), 'message': f'{name} ×{count}',
                                 'messageId': ident(outer.get('msgid')), 'sentAt': seconds(outer.get('create_time')),
                                 'gift': {'id': ident(gift.get('gift_id')), 'name': name, 'count': count,
                                          'free': whole(gift.get('is_free')) == 1,
                                          'icon': icon if parts and parts.scheme == 'https' and parts.hostname else None}})
    return {'messages': messages, 'ended': ended}


def decode_playlist(text, url):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines or lines[0] != '#EXTM3U':
        raise ValueError('not a playlist')
    base = urlsplit(url)
    sequence, segments = None, []
    for line in lines:
        if line.startswith('#EXT-X-MEDIA-SEQUENCE:'):
            found = line[len('#EXT-X-MEDIA-SEQUENCE:'):].strip()
            sequence = whole(found)
        if line.startswith('#'):
            continue
        resolved = urlsplit(urljoin(url, line))
        if resolved.scheme == base.scheme and resolved.hostname == base.hostname and not resolved.username:
            segments.append(resolved.path)
    return {'segments': segments, 'mediaSequence': sequence}


def recorded(case):
    meta = json.loads((HERE / case / 'meta.json').read_text())
    room = meta['room'].split(':', 1)[1]
    playlists, segments = [], []
    for index, line in enumerate((HERE / case / 'frames.jsonl').read_text().splitlines()):
        frame = json.loads(line)
        if frame['kind'] == 'playlist' and frame.get('status') == 200 and 'text' in frame:
            playlists.append({'frame': index, **decode_playlist(frame['text'], frame['url'])})
        if frame['kind'] == 'segment' and frame.get('status') == 200:
            segment = decode_segment(base64.b64decode(frame['b64']), room)
            segments.append({'frame': index, 'path': urlsplit(frame['url']).path, **segment})
    return {'playlists': playlists, 'segments': segments}


def synthetic():
    cases = json.loads((HERE / 'S07-synthetic' / 'cases.json').read_text())
    out = {'segments': {}, 'playlists': {}}
    for case in cases['segments']:
        try:
            out['segments'][case['name']] = decode_segment(base64.b64decode(case['b64']), case['roomId'])
        except (ValueError, OSError, EOFError, UnicodeDecodeError):
            out['segments'][case['name']] = {'throws': 'FormatException'}
    for case in cases['playlists']:
        try:
            out['playlists'][case['name']] = decode_playlist(case['text'], case['url'])
        except ValueError:
            out['playlists'][case['name']] = {'throws': 'FormatException'}
    return out


def write(case, value):
    document = {'generator': GENERATOR, 'value': value}
    (HERE / case / 'expected.json').write_text(json.dumps(document, ensure_ascii=False, indent=1) + '\n')


if __name__ == '__main__':
    for case in ('S03-live-chat', 'S04-live-online', 'S05-live-gift', 'S06-ended'):
        write(case, recorded(case))
    write('S07-synthetic', synthetic())
