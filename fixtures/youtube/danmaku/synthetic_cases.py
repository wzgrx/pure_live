#!/usr/bin/env python3
"""Writes fixtures/youtube/danmaku/S09-synthetic/cases.json (docs/modules/M5.19-youtube.md).

Synthetic InnerTube answers of a YouTube live chat, for what the recordings
(S06-live, S07-live-paid, S08-ended) do not show: every chat item kind the
parser reads or skips, fields of other types, broken answers, each
continuation kind and `timeoutMs`, and whole sessions (failures, recovery,
reloads, the end of a chat). Shapes follow the recordings; names, ids, tokens
and times are made up.

- `answers`: `live_chat/get_live_chat` answers, each parsed on its own;
- `nexts`: `next` answers;
- `sessions`: what a connection is answered, in order: {"answer": ...} is a
  200 with that JSON, {"raw": ...} a 200 with that text, {"status": n} a
  failed status, {"error": reason} no response.

Run from the repository root: python3 fixtures/youtube/danmaku/synthetic_cases.py
"""

import json
import pathlib

OUT = pathlib.Path(__file__).parent / 'S09-synthetic' / 'cases.json'
VIDEO = 'Synth3tic_0'
BASE_USEC = 1790633000000000


def channel(n):
    return 'UC' + 'syntheticViewer' + str(n).zfill(7)


def text_item(n, runs, **overrides):
    renderer = {
        'message': {'runs': runs},
        'authorName': {'simpleText': f'@viewer{n}'},
        'id': f'ChwKGkN{str(n).zfill(20)}',
        'timestampUsec': str(BASE_USEC + n * 1000000),
        'authorExternalChannelId': channel(n),
    }
    renderer.update(overrides)
    return {'addChatItemAction': {'item': {'liveChatTextMessageRenderer': renderer}}}


def paid_item(n, amount, runs=None, **overrides):
    renderer = {
        'id': f'ChwKGkP{str(n).zfill(20)}',
        'timestampUsec': str(BASE_USEC + n * 1000000),
        'authorName': {'simpleText': f'@supporter{n}'},
        'authorExternalChannelId': channel(1000 + n),
        'headerBackgroundColor': 4291821568,
        'headerTextColor': 4294967295,
        'bodyBackgroundColor': 4293271831,
        'bodyTextColor': 4294967295,
        'authorNameTextColor': 3019898879,
        'timestampColor': 2164260863,
        'isV2Style': True,
    }
    if amount is not None:
        renderer['purchaseAmountText'] = {'simpleText': amount}
    if runs is not None:
        renderer['message'] = {'runs': runs}
    renderer.update(overrides)
    return {'addChatItemAction': {'item': {'liveChatPaidMessageRenderer': renderer}}}


def other_item(kind, n, **fields):
    renderer = {'id': f'ChwKGkO{str(n).zfill(20)}', 'timestampUsec': str(BASE_USEC + n * 1000000), **fields}
    return {'addChatItemAction': {'item': {kind: renderer}}}


def standard_emoji(char, *shortcuts):
    emoji = {
        'emojiId': char,
        'image': {'thumbnails': [{'url': 'https://fonts.gstatic.com/s/e/notoemoji/15.1/1f602/72.png'}],
                  'accessibility': {'accessibilityData': {'label': char}}},
    }
    if shortcuts:
        emoji['shortcuts'] = list(shortcuts)
        emoji['searchTerms'] = [shortcuts[0].strip(':')]
    return {'emoji': emoji}


def custom_emoji(name, shortcut=True):
    emoji = {
        'emojiId': 'UCsyntheticChannel00000001/' + name,
        'image': {'thumbnails': [{'url': 'https://yt3.ggpht.com/synthetic=w24-h24-c-k-nd', 'width': 24, 'height': 24}],
                  'accessibility': {'accessibilityData': {'label': name}}},
        'isCustomEmoji': True,
    }
    if shortcut:
        emoji['shortcuts'] = [f':{name}:']
        emoji['searchTerms'] = [name]
    return {'emoji': emoji}


def continuation(token, kind='invalidationContinuationData', timeout=10000):
    data = {'continuation': token}
    if kind == 'invalidationContinuationData':
        data = {'invalidationId': {'objectSource': 1056, 'topic': f'chat~{VIDEO}', 'subscribeToGcmTopics': True},
                **data}
    if timeout is not None:
        data['timeoutMs'] = timeout
    return {kind: data}


def poll(actions, token='SYNTH-next', kind='invalidationContinuationData', timeout=10000):
    chat = {}
    if token is not None:
        chat['continuations'] = [continuation(token, kind, timeout)]
    if actions is not None:
        chat['actions'] = actions
    return {'continuationContents': {'liveChatContinuation': chat}}


def watch(token='SYNTH-reload-0', viewers='1,234', replay=False, bar=True):
    root = {'contents': {'twoColumnWatchNextResults': {}}}
    results = root['contents']['twoColumnWatchNextResults']
    if bar:
        chat = {'continuations': [{'reloadContinuationData': {'continuation': token}}]}
        if replay:
            chat['isReplay'] = True
        results['conversationBar'] = {'liveChatRenderer': chat}
    else:
        results['conversationBar'] = {'conversationBarRenderer': {'availabilityMessage': {'messageRenderer': {
            'text': {'runs': [{'text': 'Live chat replay is not available for this video.'}]}}}}}
    if viewers is not None:
        results['results'] = {'results': {'contents': [{'videoPrimaryInfoRenderer': {'viewCount': {
            'videoViewCountRenderer': {'viewCount': {'runs': [{'text': viewers}, {'text': ' watching now'}]},
                                       'isLive': True, 'originalViewCount': viewers.replace(',', '')}}}}]}}
    return root


ENDED = {'contents': {'messageRenderer': {'text': {'runs': [{'text': 'Chat is disabled for this live stream.'}]}}}}

ANSWERS = [
    ('a text line with every field', poll([text_item(1, [{'text': 'hello chat'}])])),
    ('runs: text, a link, standard emoji with and without shortcuts, custom emoji with and without shortcuts', poll([
        text_item(2, [
            {'text': 'gg '},
            {'text': 'example.com', 'navigationEndpoint': {'urlEndpoint': {'url': 'https://example.com/'}}},
            {'text': ' '},
            standard_emoji('😂', ':face_with_tears_of_joy:', ':joy:'),
            standard_emoji('🇹🇷'),
            custom_emoji('face-purple-crying'),
            custom_emoji('channel-badge', shortcut=False),
            {'text': ' !'},
        ]),
    ])),
    ('a Super Chat with a message', poll([paid_item(1, 'TRY 55.00', [{'text': 'great show '},
                                                                    standard_emoji('👏', ':clapping_hands:')])])),
    ('a Super Chat without a message', poll([paid_item(2, '$5.00')])),
    ('a Super Chat with neither amount nor message', poll([paid_item(3, None)])),
    ('a Super Chat with only spaces for its message', poll([paid_item(4, '₫1,000,000', [{'text': '   '}])])),
    ('Super Stickers, memberships, gifted memberships, engagement messages and placeholders are not read', poll([
        other_item('liveChatPaidStickerRenderer', 10, purchaseAmountText={'simpleText': '€2.00'},
                   authorName={'simpleText': '@sticker10'}, authorExternalChannelId=channel(10)),
        other_item('liveChatMembershipItemRenderer', 11, headerSubtext={'runs': [{'text': 'Welcome to Members!'}]},
                   authorName={'simpleText': '@member11'}, authorExternalChannelId=channel(11)),
        other_item('liveChatSponsorshipsGiftPurchaseAnnouncementRenderer', 12, authorExternalChannelId=channel(12)),
        other_item('liveChatViewerEngagementMessageRenderer', 13,
                   message={'runs': [{'text': 'Welcome to live chat! Remember to guard your privacy.'}]}),
        other_item('liveChatPlaceholderItemRenderer', 14),
        text_item(15, [{'text': 'after the others'}]),
    ])),
    ('removals, a replacement and other actions are not read', poll([
        {'removeChatItemAction': {'targetItemId': 'ChwKGkN00000000000000000001'}},
        {'removeChatItemByAuthorAction': {'externalChannelId': channel(16)}},
        {'replaceChatItemAction': {'targetItemId': 'ChwKGkO00000000000000000014',
                                   'replacementItem': text_item(14, [{'text': 'held, then shown'}])[
                                       'addChatItemAction']['item']}},
        {'markChatItemAsDeletedAction': {'targetItemId': 'ChwKGkN00000000000000000002'}},
        {'addLiveChatTickerItemAction': {}},
        {'updateLiveChatPollAction': {}},
        {'addBannerToLiveChatCommand': {}},
        {'liveChatReportModerationStateCommand': {}},
        text_item(17, [{'text': 'still read'}]),
    ])),
    ('text that is only spaces, empty runs, runs that are not a list', poll([
        text_item(20, [{'text': '  '}, {'text': '\t'}]),
        text_item(21, []),
        text_item(22, None),
        {'addChatItemAction': {'item': {'liveChatTextMessageRenderer': {
            'message': {'simpleText': 'simple text, not runs'}, 'id': 'ChwKGkN00000000000000000023'}}}},
        text_item(24, [{'text': '  padded  '}]),
    ])),
    ('author, id and time missing', poll([
        {'addChatItemAction': {'item': {'liveChatTextMessageRenderer': {'message': {'runs': [{'text': 'anonymous'}]}}}}},
    ])),
    ('fields of other types', poll([
        text_item(30, [{'text': 'numeric id'}], id=12345, authorExternalChannelId=67890,
                  timestampUsec=BASE_USEC + 30000000),
        text_item(31, [{'text': 'author in runs'}], authorName={'runs': [{'text': '@viewer'}, {'text': '31'}]}),
        text_item(32, [{'text': 'author is text'}], authorName='@viewer32'),
        text_item(33, [{'text': 7}, {'text': 'run text is a number'}, 'not a run', {'emoji': 'not a map'}]),
        {'addChatItemAction': {'item': {'liveChatTextMessageRenderer': {'message': 'not a map', 'id': 'x34'}}}},
        paid_item(35, '$1.00', purchaseAmountText={'runs': [{'text': '$1.00'}]}),
    ])),
    ('times: zero, negative, not a number, spaces, past int64', poll([
        text_item(40, [{'text': 'zero'}], timestampUsec='0'),
        text_item(41, [{'text': 'negative'}], timestampUsec='-1000000'),
        text_item(42, [{'text': 'not a number'}], timestampUsec='soon'),
        text_item(43, [{'text': 'spaces'}], timestampUsec=' 1790633043000000 '),
        text_item(44, [{'text': 'past int64'}], timestampUsec='99999999999999999999'),
        text_item(45, [{'text': 'a fraction'}], timestampUsec=1790633045000000.5),
    ])),
    ('a time past what DateTime holds', poll([
        text_item(46, [{'text': 'before'}]),
        text_item(47, [{'text': 'far future'}], timestampUsec='8640000000000000001'),
        text_item(48, [{'text': 'after'}]),
    ])),
    ('emoji: shortcuts that are not text, no emojiId, custom without shortcuts or id', poll([
        text_item(50, [
            {'emoji': {'emojiId': '🔥', 'shortcuts': [7]}},
            {'emoji': {'shortcuts': [':fire:']}},
            {'emoji': {'isCustomEmoji': True, 'searchTerms': ['nothing']}},
            {'emoji': {'emojiId': '', 'shortcuts': []}},
            {'emoji': {'isCustomEmoji': 'true', 'emojiId': '⭐', 'shortcuts': [':star:']}},
            {'text': 'end'},
        ]),
    ])),
    ('a timed continuation, 3 s', poll([], kind='timedContinuationData', timeout=3000)),
    ('an invalidation continuation, 10 s', poll([], timeout=10000)),
    ('timeoutMs 200', poll([], kind='timedContinuationData', timeout=200)),
    ('timeoutMs 0', poll([], kind='timedContinuationData', timeout=0)),
    ('timeoutMs missing', poll([], timeout=None)),
    ('timeoutMs as text', poll([], kind='timedContinuationData', timeout='3000')),
    ('timeoutMs negative', poll([], kind='timedContinuationData', timeout=-5)),
    ('timeoutMs a fraction', poll([], kind='timedContinuationData', timeout=2500.0)),
    ('a reload continuation', poll([], token='SYNTH-reload', kind='reloadContinuationData', timeout=None)),
    ('a continuation kind not seen yet', poll([text_item(60, [{'text': 'kept'}])], kind='liveChatReplayContinuationData',
                                             timeout=4000)),
    ('two continuation kinds in one entry', {'continuationContents': {'liveChatContinuation': {
        'continuations': [{'timedContinuationData': {'timeoutMs': 2000, 'continuation': 'SYNTH-first'},
                           'reloadContinuationData': {'continuation': 'SYNTH-second'}}], 'actions': []}}}),
    ('a continuation that is not text', {'continuationContents': {'liveChatContinuation': {
        'continuations': [{'timedContinuationData': {'timeoutMs': 2000, 'continuation': 7}}], 'actions': []}}}),
    ('no continuations: the chat is over, its actions are still read', poll([text_item(61, [{'text': 'last words'}])],
                                                                           token=None)),
    ('no continuationContents, a message: the chat is over', ENDED),
    ('an empty object', {}),
    ('liveChatContinuation that is not an object', {'continuationContents': {'liveChatContinuation': []}}),
    ('actions that are not a list', {'continuationContents': {'liveChatContinuation': {
        'continuations': [continuation('SYNTH-next')],
        'actions': {'0': text_item(70, [{'text': 'in a map'}])}}}}),
    ('actions and items that are not objects', poll(['text', 7, None, {'addChatItemAction': 'x'},
                                                     {'addChatItemAction': {'item': []}},
                                                     text_item(71, [{'text': 'the only line'}])])),
    ('an action with its tracking before the item', poll([
        {'clickTrackingParams': 'CAEQ', 'addChatItemAction': {'item': text_item(72, [{'text': 'tracked'}])[
            'addChatItemAction']['item'], 'clientId': 'client-72'}},
    ])),
]

RAW_ANSWERS = [
    ('not JSON', '<!DOCTYPE html><html><body>Sorry</body></html>'),
    ('a JSON array', '[{"continuationContents": {}}]'),
    ('a JSON string', '"continuationContents"'),
]

NEXTS = [
    ('live, with the viewers in runs', watch()),
    ('live, with the viewers in simpleText', {'contents': {'twoColumnWatchNextResults': {
        'results': {'results': {'contents': [{'videoPrimaryInfoRenderer': {'viewCount': {'videoViewCountRenderer': {
            'viewCount': {'simpleText': '1,331 watching now'}, 'isLive': True}}}}]}},
        'conversationBar': {'liveChatRenderer': {'continuations': [
            {'reloadContinuationData': {'continuation': 'SYNTH-reload-1'}}]}}}}}),
    ('live, without a view count', watch(viewers=None)),
    ('no live chat: a conversation bar message', watch(bar=False, viewers=None)),
    ('a chat replay', watch(replay=True, viewers=None)),
    ('isReplay false', {'contents': {'twoColumnWatchNextResults': {'conversationBar': {'liveChatRenderer': {
        'isReplay': False, 'continuations': [{'reloadContinuationData': {'continuation': 'SYNTH-reload-2'}}]}}}}}),
    ('continuations empty', {'contents': {'twoColumnWatchNextResults': {'conversationBar': {'liveChatRenderer': {
        'continuations': []}}}}}),
    ('a continuation that is not text', {'contents': {'twoColumnWatchNextResults': {'conversationBar': {
        'liveChatRenderer': {'continuations': [{'reloadContinuationData': {'continuation': 12}}]}}}}}),
    ('liveChatRenderer elsewhere in the answer', {'engagementPanels': [{'panel': {'liveChatRenderer': {
        'continuations': [{'reloadContinuationData': {'continuation': 'SYNTH-elsewhere'}}]}}}]}),
    ('a liveChatRenderer that is not an object, then one that is', {'a': {'liveChatRenderer': 'x'}, 'b': {
        'liveChatRenderer': {'continuations': [{'reloadContinuationData': {'continuation': 'SYNTH-second'}}]}}}),
    ('a view count that is not live', {'contents': {'twoColumnWatchNextResults': {
        'results': {'results': {'contents': [{'videoPrimaryInfoRenderer': {'viewCount': {'videoViewCountRenderer': {
            'viewCount': {'simpleText': '402,519 views'}}}}}]}},
        'conversationBar': {'liveChatRenderer': {'continuations': [
            {'reloadContinuationData': {'continuation': 'SYNTH-reload-3'}}]}}}}}),
    ('an empty object', {}),
]

RAW_NEXTS = [
    ('not JSON', '<html>'),
    ('a JSON array holding the chat', json.dumps([{'liveChatRenderer': {'continuations': [
        {'reloadContinuationData': {'continuation': 'SYNTH-in-array'}}]}}])),
]


def ok(value):
    return {'answer': value}


SESSIONS = [
    ('a chat: history, two answers, the end', VIDEO, [
        ok(watch()),
        ok(poll([text_item(100, [{'text': 'history, not shown'}])], token='SYNTH-1')),
        ok(poll([text_item(101, [{'text': 'first'}]), paid_item(102, '$2.00', [{'text': 'thanks'}])],
                token='SYNTH-2', kind='timedContinuationData', timeout=3000)),
        ok(poll([text_item(103, [{'text': 'second'}])], token='SYNTH-3')),
        ok(ENDED),
    ]),
    ('next fails once', VIDEO, [
        {'status': 503},
        ok(watch()),
        ok(poll([], token='SYNTH-1')),
        ok(poll([text_item(110, [{'text': 'after a retry'}])], token=None)),
    ]),
    ('next fails three times', VIDEO, [{'error': 'timeout'}, {'status': 500}, {'error': 'connect'}]),
    ('the first poll fails twice, then answers', VIDEO, [
        ok(watch()),
        {'status': 500},
        {'error': 'timeout'},
        ok(poll([text_item(120, [{'text': 'history'}])], token='SYNTH-1')),
        ok(poll([text_item(121, [{'text': 'shown'}])], token=None)),
    ]),
    ('the first poll fails three times', VIDEO, [ok(watch()), {'status': 500}, {'status': 500}, {'status': 403}]),
    ('failures after joining, then recovery', VIDEO, [
        ok(watch(viewers=None)),
        ok(poll([], token='SYNTH-1', kind='timedContinuationData', timeout=1500)),
        {'error': 'timeout'},
        {'status': 503},
        {'raw': '<html>not json</html>'},
        ok(poll([text_item(130, [{'text': 'back'}])], token='SYNTH-2')),
        {'status': 503},
        ok(poll([text_item(131, [{'text': 'back again'}])], token=None)),
    ]),
    ('eight failures in a row', VIDEO, [
        ok(watch(viewers=None)),
        ok(poll([], token='SYNTH-1')),
        *[{'status': 500}] * 8,
        ok(poll([text_item(140, [{'text': 'too late'}])], token='SYNTH-2')),
    ]),
    ('no live chat', VIDEO, [ok(watch(bar=False))]),
    ('a chat replay', VIDEO, [
        ok(watch(replay=True, viewers=None)),
        {'status': 400},
        {'status': 400},
        {'status': 400},
    ]),
    ('the history answer has no continuation', VIDEO, [ok(watch()), ok(ENDED)]),
    ('a reload in the middle', VIDEO, [
        ok(watch(viewers=None)),
        ok(poll([], token='SYNTH-1')),
        ok(poll([text_item(150, [{'text': 'before the reload'}])], token='SYNTH-reload', kind='reloadContinuationData',
                timeout=None)),
        ok(poll([text_item(151, [{'text': 'recent, again'}]), text_item(150, [{'text': 'before the reload'}])],
                token='SYNTH-2')),
        ok(poll([text_item(152, [{'text': 'after the reload'}])], token=None)),
    ]),
    ('server delays: 3 s, 10 s, 200 ms, none, 0', VIDEO, [
        ok(watch(viewers=None)),
        ok(poll([], token='SYNTH-1', kind='timedContinuationData', timeout=3000)),
        ok(poll([], token='SYNTH-2', timeout=10000)),
        ok(poll([], token='SYNTH-3', kind='timedContinuationData', timeout=200)),
        ok(poll([], token='SYNTH-4', timeout=None)),
        ok(poll([], token='SYNTH-5', kind='timedContinuationData', timeout=0)),
        ok(poll([], token=None)),
    ]),
    ('the next answer has no chat renderer at all', VIDEO, [ok({'responseContext': {}})]),
    ('no video id', '', []),
    ('not a video id', 'not-a-video-id', [ok(watch()), ok(poll([], token=None))]),
]


def main():
    cases = {
        'note': ('Synthetic YouTube live chat answers (docs/modules/M5.19-youtube.md). answers: get_live_chat '
                 'answers parsed on their own; nexts: next answers; sessions: what a connection to videoId is '
                 'answered, in order ({"answer"}: 200 with that JSON, {"raw"}: 200 with that text, {"status"}: that '
                 'status, {"error"}: no response). Written by fixtures/youtube/danmaku/synthetic_cases.py; names, '
                 'ids, tokens and times are made up.'),
        'videoId': VIDEO,
        'answers': [{'name': name, 'body': body} for name, body in ANSWERS]
        + [{'name': name, 'raw': raw} for name, raw in RAW_ANSWERS],
        'nexts': [{'name': name, 'body': body} for name, body in NEXTS]
        + [{'name': name, 'raw': raw} for name, raw in RAW_NEXTS],
        'sessions': [{'name': name, 'videoId': video, 'steps': steps} for name, video, steps in SESSIONS],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(cases, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'wrote {OUT} ({len(cases["answers"])} answers, {len(cases["nexts"])} nexts, '
          f'{len(cases["sessions"])} sessions)')


if __name__ == '__main__':
    main()
