#!/usr/bin/env python3
"""Writes fixtures/chzzk/danmaku/S12-synthetic/cases.json (docs/modules/M5.16-chzzk.md).

Synthetic frames of a CHZZK chat socket, for what the recordings (S09-live,
S10-live, S11-recent) do not show: donations and subscriptions pushed live
(cmd 93102), hidden lines, refused joins, the server's ping and its end of the
session, every way a frame can be broken and fields of the wrong type. Field
names and shapes follow the recordings and the site's chat client (NAVER's
chat SDK 4.11.0 and chzzk.naver.com's index-*.js, 2026-09-29); names, ids,
tokens and times are made up.

Run from the repository root:

    python3 fixtures/chzzk/danmaku/synthetic_cases.py

The output depends only on this file.
"""

import base64
import json
import pathlib

CHAT = 'N2lpu9'
STREAMER = 'af3323d30e11ae42c39d7203c7e07fa2'
OUT = pathlib.Path(__file__).parent / 'S12-synthetic' / 'cases.json'
T = 1790612400123


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def text(value, note=None):
    frame = {'text': value if isinstance(value, str) else dumps(value)}
    if note:
        frame['note'] = note
    return frame


def binary(data, note):
    return {'b64': base64.b64encode(data).decode('ascii'), 'note': note}


def user_id(n):
    return f'{n:032x}'


def profile(n, name):
    return dumps({
        'userIdHash': user_id(n),
        'nickname': name,
        'profileImageUrl': '',
        'userRoleCode': 'common_user',
        'badge': None,
        'title': None,
        'verifiedMark': False,
        'verifiedMarkType': None,
        'activityBadges': [],
        'streamingProperty': {'nicknameColor': {'colorCode': 'CC000'}, 'activatedAchievementBadgeIds': []},
        'viewerBadges': [],
    })


def chat_extras(**more):
    return dumps({
        'chatType': 'STREAMING',
        'osType': 'PC',
        'extraToken': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==',
        'streamingChannelId': STREAMER,
        'emojis': {},
        **more,
    })


def donation_extras(amount=1000, anonymous=False, kind='CHAT', nickname=None):
    extras = {
        'emojis': {},
        'streamingChannelId': STREAMER,
        'donationId': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'donationType': kind,
        'weeklyRankList': [],
        'isAnonymous': anonymous,
        'payType': 'CURRENCY',
        'payAmount': amount,
    }
    if nickname is not None:
        extras['nickname'] = nickname
    extras.update({'osType': 'PC', 'continuousDonationDays': 0, 'chatType': 'STREAMING'})
    return dumps(extras)


DEFAULT = object()


def line(n=1, name='시청자1', msg='안녕', kind=1, status='NORMAL', extras=None, time=None, members=8826, uid=None,
         the_profile=DEFAULT, drop=()):
    """One line pushed live (cmd 93101/93102), as the recordings have it."""
    item = {
        'svcid': 'game',
        'cid': CHAT,
        'mbrCnt': members,
        'uid': user_id(n) if uid is None else uid,
        'profile': profile(n, name) if the_profile is DEFAULT else the_profile,
        'msg': msg,
        'msgTypeCode': kind,
        'msgStatusType': status,
        'extras': chat_extras() if extras is None else extras,
        'ctime': T + n if time is None else time,
        'utime': T + n if time is None else time,
        'msgTid': None,
        'cuid': None,
        'msgTime': T + n if time is None else time,
    }
    for key in drop:
        item.pop(key, None)
    return item


def recent_line(n=1, name='시청자1', content='안녕', kind=1, status='NORMAL', extras=None, uid=None,
                the_profile=DEFAULT):
    """One line of the recent chat (cmd 15101)."""
    return {
        'serviceId': 'game',
        'channelId': CHAT,
        'messageTime': T + n,
        'userId': user_id(n) if uid is None else uid,
        'profile': profile(n, name) if the_profile is DEFAULT else the_profile,
        'content': content,
        'extras': chat_extras() if extras is None else extras,
        'memberCount': 8826,
        'messageTypeCode': kind,
        'messageStatusType': status,
        'createTime': T + n,
        'updateTime': T + n,
        'msgTid': None,
    }


def push(items, cmd=93101, cid=CHAT):
    return {'svcid': 'game', 'ver': '1', 'bdy': items, 'cmd': cmd, 'tid': None, 'cid': cid}


def answer(code=0, message='SUCCESS', sid='10_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', body=True):
    frame = {'svcid': 'game', 'cmd': 10100, 'retCode': code, 'retMsg': message, 'tid': '1', 'cid': CHAT}
    if body:
        frame['bdy'] = {'accTkn': None, 'auth': 'READ', 'uuid': '00000000-0000-4000-8000-000000000001', 'sid': sid}
    return frame


cases = [
    ('a chat line with every field', [text(push([line()]))]),
    ('three lines in one frame, the member count changing', [
        text(push([line(1, '시청자1', 'ㅋㅋㅋ', members=8826), line(2, 'viewer2', 'gg', members=8825),
                   line(3, '观众3', '你好', members=8830)])),
    ]),
    ('donations pushed live (93102): named, anonymous by user and by flag, without text, a video', [
        text(push([line(4, '후원자', '응원해요', kind=10, extras=donation_extras(1000, nickname='후원자'))], 93102)),
        text(push([line(5, msg='익명 후원', kind=10, uid='anonymous', the_profile=None,
                        extras=donation_extras(2000, anonymous=True))], 93102),
             note='uid "anonymous" and profile null, as S11-recent records them'),
        text(push([line(6, '숨은후원자', '이름은 숨겨주세요', kind=10,
                        extras=donation_extras(3000, anonymous=True))], 93102),
             note='flagged anonymous but carrying a user id and profile'),
        text(push([line(7, '후원자2', '', kind=10, extras=donation_extras(5000))], 93102)),
        text(push([line(8, '후원자3', '노래 제목 - 가수', kind=10, extras=donation_extras(1820, kind='VIDEO'))], 93102)),
    ]),
    ('subscriptions with and without a message, a subscription gift', [
        text(push([line(9, '구독자', '32개월 축하해 주세요', kind=11,
                        extras=dumps({'month': 32, 'tierName': '팬', 'nickname': '구독자', 'tierNo': 1}))], 93102)),
        text(push([line(10, '구독자2', '', kind=11,
                        extras=dumps({'month': 1, 'tierName': '팬', 'nickname': '구독자2', 'tierNo': 1}))], 93102)),
        text(push([line(11, '선물자', '구독권 선물', kind=12,
                        extras=dumps({'giftType': 'SUBSCRIPTION_GIFT', 'quantity': 5}))], 93102)),
    ]),
    ('system lines, images, stickers, parties and shop purchases show nothing', [
        text(push([line(uid='SYSTEM_MESSAGE', the_profile='{}', msg='이모티콘 모드 ON', kind=30,
                        extras=dumps({'description': '텍스트 대신 이모티콘만 전송할 수 있어요.', 'styleType': 1,
                                      'params': {}}))], 93102)),
        text(push([line(12, msg='이미지', kind=2), line(13, msg='스티커', kind=3), line(14, msg='파티', kind=13),
                   line(15, msg='구매', kind=15), line(16, msg='알 수 없음', kind=121)])),
        text(push([line(58, msg='스티커 후원', kind=3, extras=donation_extras(500))], 93102),
             note='a sticker whose extras carry payAmount'),
    ]),
    ('hidden lines: BLIND, CBOTBLIND, HIDDEN; a line without a status', [
        text(push([line(17, msg='가려짐', status='BLIND'), line(18, msg='클린봇', status='CBOTBLIND'),
                   line(19, msg='숨김', status='HIDDEN'), line(20, msg='상태 없음', drop=('msgStatusType',))])),
    ]),
    ('the recent chat (15101): its field names; an answer that is not retCode 0', [
        text({'svcid': 'game', 'bdy': {'messageList': [
            recent_line(21, '예전', '입장 전 채팅'),
            recent_line(22, content='익명 후원', kind=10, uid='anonymous', the_profile=None,
                        extras=donation_extras(1000, anonymous=True)),
            recent_line(23, '구독', '구독 메시지', kind=11,
                        extras=dumps({'month': 3, 'tierName': '팬', 'nickname': '구독', 'tierNo': 1})),
            recent_line(24, '클린봇', '가려진 말', status='CBOTBLIND'),
        ], 'userCount': 8826, 'notice': None}, 'cmd': 15101, 'retCode': 0, 'retMsg': 'SUCCESS', 'tid': '2',
              'cid': CHAT}),
        text({'svcid': 'game', 'bdy': {'messageList': [recent_line(25, '실패', '보이면 안 됨')]}, 'cmd': 15101,
              'retCode': 500, 'retMsg': 'INTERNAL_ERROR', 'tid': '2', 'cid': CHAT}),
    ]),
    ('the answer to the join: accepted, without a session id, refused, to be retried, without a code', [
        text(answer()),
        text(answer(body=False)),
        text({'cmd': 10100, 'retCode': 105, 'retMsg': 'Incorrect parameter', 'tid': '1'},
             note='as the server answers a chat channel that does not exist, then closes (1000 Bye)'),
        text({'cmd': 10100, 'retCode': 302, 'retMsg': 'Moved', 'tid': '1'}),
        text({'cmd': 10100, 'retCode': 303, 'tid': '1'}),
        text({'cmd': 10100, 'retCode': 304, 'retMsg': 'Moved', 'tid': '1'}),
        text({'cmd': 10100, 'tid': '1'}),
    ]),
    ("the server's ping, the pong, the end of the session", [
        text({'ver': '2', 'cmd': 0}),
        text({'ver': '2', 'cmd': 10000}),
        text({'ver': '2', 'cmd': 90102, 'bdy': {}}),
    ]),
    ('events, blind notices, notices, kicks and penalties show nothing', [
        text({'svcid': 'game', 'ver': '1', 'bdy': {'type': 'CHANGE_CHAT_MODE', 'chatAvailableGroup': 'ALL'},
              'cmd': 93006, 'tid': None, 'cid': CHAT}),
        text({'svcid': 'game', 'ver': '1', 'bdy': {'messageTime': T, 'blindType': 'BLIND', 'blindUserId': None,
                                                   'serviceId': 'game', 'message': None, 'userId': user_id(1),
                                                   'channelId': CHAT}, 'cmd': 94008, 'tid': None, 'cid': CHAT}),
        text({'svcid': 'game', 'ver': '1', 'bdy': recent_line(26, '스트리머', '공지입니다'), 'cmd': 94010, 'tid': None,
              'cid': CHAT}),
        text({'svcid': 'game', 'ver': '1', 'bdy': {'userId': user_id(27), 'penaltyType': 'BAN'}, 'cmd': 94015,
              'tid': None, 'cid': CHAT}),
        text({'svcid': 'game', 'ver': '1', 'bdy': {'quitUserIdList': [user_id(28)]}, 'cmd': 94005, 'tid': None,
              'cid': CHAT}),
    ]),
    ('broken frames', [
        text('not json'),
        text('[1,2]'),
        text('"93101"'),
        text('42'),
        text('{}'),
        text(dumps(push([line(29)])).replace('"cmd":93101', '"cmd":"93101"'), note='cmd as text'),
        text(push({'msg': '객체'}), note='bdy an object'),
        text(push(None), note='bdy null'),
        text(push([1, 'x', None, [line(30)], line(31, msg='남은 줄')]), note='items that are not objects'),
        binary(dumps(push([line(32, msg='바이너리')])).encode('utf-8'), 'a chat frame sent as binary'),
        binary(dumps(push([line(33, msg='깨진XX')])).encode('utf-8').replace(b'XX', b'\xff\xfe'),
               'a binary frame with bytes that are not UTF-8 in the text'),
        text('{"cmd":93101,"bdy":[{"msg":"잘림"', note='cut short'),
    ]),
    ('fields of other types', [
        text(push([line(34, msg=42)]), note='text a number'),
        text(push([line(35, msg=['x'])]), note='text a list'),
        text(push([line(36, msg={'a': 1})]), note='text an object'),
        text(push([line(uid=12345, msg='숫자 아이디')]), note='user id a number'),
        text(push([line(37, msg='프로필 깨짐', the_profile='{not json')])),
        text(push([line(38, msg='프로필 객체', the_profile={'nickname': '객체이름'})])),
        text(push([line(39, msg='프로필 목록', the_profile='["x"]')])),
        text(push([line(40, msg='닉네임 숫자', the_profile=dumps({'nickname': 7}))])),
        text(push([line(41, msg='익명 표시 깨짐', kind=10, extras='{not json')])),
        text(push([line(42, msg='종류 문자', kind='1'), line(43, msg='후원 문자', kind='10',
                                                           extras=donation_extras(1000))])),
        text(push([line(44, msg='종류 없음', drop=('msgTypeCode',))])),
        text(push([line(45, msg='이상한 종류', kind='x')])),
    ]),
    ('times: milliseconds, zero, negative, beyond DateTime, text, a fraction', [
        text(push([line(46, msg='밀리초', time=1790612400123)])),
        text(push([line(47, msg='영', time=0)])),
        text(push([line(48, msg='음수', time=-5)])),
        text(push([line(49, msg='너무 큼', time=8640000000000001)])),
        text(push([line(50, msg='문자 시간', time='1790612400123')])),
        text(push([line(51, msg='소수', time=1790612400123.5)])),
        text(push([line(52, msg='시간 없음', drop=('msgTime',))])),
    ]),
    ('emoji placeholders and white space', [
        text(push([line(53, msg='{:d_45:}{:d_46:}', extras=chat_extras(emojis={
            'd_45': 'https://ssl.pstatic.net/static/nng/glive/icon/d_45.gif',
            'd_46': 'https://ssl.pstatic.net/static/nng/glive/icon/d_46.gif'}))])),
        text(push([line(54, msg='  앞뒤 공백  '), line(55, msg='   '), line(56, msg='')])),
    ]),
    ("a frame of another chat channel is read as it is (the site's client does not check)", [
        text(push([line(57, msg='다른 채널')], cid='N2zzzz')),
    ]),
]

document = {
    'note': 'Synthetic frames of a CHZZK chat socket (docs/modules/M5.16-chzzk.md), read for chat channel '
            'chatChannelId. Each case is one or more frames in order: {"text": ...} is a text frame, {"b64": ...} a '
            'binary frame; "note" says what a frame is for. Written by fixtures/chzzk/danmaku/synthetic_cases.py; '
            'names, ids, tokens and times are made up.',
    'chatChannelId': CHAT,
    'cases': [{'name': name, 'frames': frames} for name, frames in cases],
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'wrote {OUT} ({len(cases)} cases, {sum(len(frames) for _, frames in cases)} frames)')
