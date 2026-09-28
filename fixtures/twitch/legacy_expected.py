"""Writes expected.json for the Twitch samples: what 3.x's parser makes of them.

The other platforms' expected values come from legacy/test/fixtures_expected,
which replays the samples through 3.x's own code. 3.x has no such test for
Twitch, and its TwitchSite cannot run outside the Flutter app (GetX settings,
method channels, WebView). This script is a line-by-line transcription of the
parsing in legacy/lib/core/site/twitch/twitch_site.dart (lines cited below),
3.x's LiveRoom/LiveArea JSON and roomProjection
(legacy/test/fixtures_expected/support.dart), run on each response. It is
kept apart from the Dart adapter on purpose, so the parity tests compare two
independent readings of the same response.

Only responses 3.x could have parsed are covered. S03-streams and S05-user-*
answer raw GraphQL queries that 3.x never sent (it used the persisted
ChannelShell + StreamMetadata pair and the Just Chatting directory), so they
have no expected.json. Where 3.x's result depends on the platform it ran on,
the desktop path is recorded (no Android system TLS, no WebView fallback).

The `?&t=` suffix 3.x added to covers is the Unix time of the parse; the
sample's capturedAt is used.

Run from the repository root: python3 fixtures/twitch/legacy_expected.py
"""

import json
import math
import os
import re
from datetime import datetime
from urllib.parse import urljoin

ROOT = os.path.dirname(os.path.abspath(__file__))


def load(sample):
    directory = os.path.join(ROOT, sample)
    with open(os.path.join(directory, 'meta.json'), encoding='utf-8') as handle:
        meta = json.load(handle)
    with open(os.path.join(directory, meta['body']), encoding='utf-8') as handle:
        body = handle.read()
    return meta, body


def write(sample, generator, value):
    path = os.path.join(ROOT, sample, 'expected.json')
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps({'generator': generator, 'value': value}, ensure_ascii=False, indent=2) + '\n')


def seconds(meta):
    """DateTime.now().millisecondsSinceEpoch ~/ 1000 at capture time."""
    stamp = datetime.fromisoformat(meta['capturedAt'].replace('Z', '+00:00'))
    return int(stamp.timestamp())


def dart_string(value):
    """Dart's toString() for the JSON scalars that occur here."""
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    return str(value)


def proxied(value):
    """(x ?? "").toString().replaceFirst("https://", "https://i2.wp.com/")"""
    text = '' if value is None else dart_string(value)
    return text.replace('https://', 'https://i2.wp.com/', 1)


def append_txt(text, suffix):
    """TextUtilsStringExtension.appendTxt (common/utils/string_to_boolean.dart:55-59)."""
    if text.strip() == '':
        return ''
    return text + suffix


def string_map(value):
    return value if isinstance(value, dict) else None


# 3.x LiveRoom (common/models/live_room.dart:311-354, 559-597) --------------

LIVE, OFFLINE = 0, 1


def room(**fields):
    """LiveRoom(...) with 3.x's defaults, as roomProjection writes it."""
    status_index = fields.pop('liveStatus')
    json_value = {
        'roomId': fields.get('roomId'),
        'userId': fields.get('userId'),
        'title': fields.get('title', ''),
        'nick': fields.get('nick', ''),
        'avatar': fields.get('avatar', ''),
        'cover': fields.get('cover', ''),
        'area': fields.get('area'),
        'watching': fields.get('watching', '0'),
        'audienceMetricType': 'onlineViewers',
        'popularity': fields.get('popularity', ''),
        'onlineViewers': fields.get('onlineViewers', ''),
        'totalViewers': fields.get('totalViewers', ''),
        'followers': fields.get('followers', '0'),
        'platform': 'twitch',
        'tagIds': [],
        'liveStatus': status_index,
        'isRecord': False,
        'status': status_index == LIVE,
        'notice': fields.get('notice'),
        'introduction': fields.get('introduction'),
        'epgId': None,
        'currentProgramme': None,
        'currentProgrammeDescription': None,
        'catchUpUrl': None,
        'isCatchUp': False,
        'catchUpStart': None,
        'catchUpEnd': None,
        'catchUpMode': None,
        'catchUpSource': None,
        'catchUpDays': None,
        'catchUpCorrectionHours': None,
        'httpHeaders': {},
        'lastWatchedAt': None,
        'link': fields.get('link'),
        'danmakuData': None if fields.get('danmakuData') is None else dart_string(fields['danmakuData']),
    }
    return {
        key: value
        for key, value in json_value.items()
        if value is not None and not (isinstance(value, (dict, list)) and len(value) == 0)
    }


def area(**fields):
    """3.x LiveArea.toJson (common/models/live_area.dart:42-50)."""
    return {
        'platform': fields['platform'],
        'areaType': fields['areaType'],
        'typeName': fields['typeName'],
        'areaId': fields['areaId'],
        'areaName': fields['areaName'],
        'areaPic': fields['areaPic'],
        'shortName': fields['shortName'],
    }


# twitch_site.dart --------------------------------------------------------


def parse_connection(raw):
    """TwitchSite.parseConnection (site:386-396)."""
    connection = string_map(raw)
    if connection is None:
        return [], False
    raw_edges = connection.get('edges')
    edges = [edge for edge in raw_edges if isinstance(edge, dict)] if isinstance(raw_edges, list) else []
    page_info = string_map(connection.get('pageInfo'))
    return edges, (page_info or {}).get('hasNextPage') is True


def graphql_error_summary(envelope):
    """TwitchSite._graphQlErrorSummary (site:404-413)."""
    errors = envelope.get('errors')
    if not isinstance(errors, list) or not errors:
        return ''
    messages = []
    for error in errors:
        if isinstance(error, dict):
            message = dart_string(error.get('message')).strip() if error.get('message') is not None else ''
            if message:
                messages.append(message)
    return '; '.join(messages)


def categories(response):
    """getCategores (site:427-431): one LiveCategory per tag, name = tagName."""
    return [{'id': item['id'], 'name': item['tagName']} for item in response['data']['searchCategoryTags']]


def sub_categories(response, category):
    """getSubCategores (site:498-519) for one BrowsePage_AllDirectories answer."""
    data = string_map((string_map(response) or {}).get('data'))
    edges, has_next = parse_connection((data or {}).get('directoriesWithTags'))
    cursor = '' if not edges else ('' if edges[-1].get('cursor') is None else dart_string(edges[-1]['cursor']))
    if not has_next:
        cursor = ''
    areas = []
    for item in edges:
        node = item['node']
        areas.append(area(
            areaId=node['id'],
            areaName=node['displayName'],
            shortName=node['slug'],
            areaType=category['id'],
            platform='twitch',
            areaPic=proxied(node.get('avatarURL')),
            typeName=category['name'],
        ))
    return {'areas': areas, 'nextCursor': cursor}


def category_rooms(response, now):
    """getCategoryRooms (site:817-871)."""
    envelopes = response if isinstance(response, list) else []
    envelope = string_map(envelopes[0]) if envelopes else None
    if envelope is None:
        return {'throws': {'type': 'StateError', 'message': 'Bad state: Twitch stream directory returned an invalid response envelope'}}
    data = string_map(envelope.get('data'))
    game = string_map((data or {}).get('game'))
    streams = None if game is None else string_map(game.get('streams'))
    if streams is None:
        summary = graphql_error_summary(envelope)
        if summary:
            return {'throws': {'type': 'StateError', 'message': 'Bad state: Twitch GraphQL error: ' + summary}}
        return {'rooms': [], 'nextCursor': None}
    edges, has_next = parse_connection(streams)
    if not edges:
        return {'rooms': [], 'nextCursor': None}
    cursor = '' if edges[-1].get('cursor') is None else dart_string(edges[-1]['cursor'])
    if not has_next:
        cursor = ''
    rooms = []
    for item in edges:
        node = string_map(item.get('node'))
        broadcaster = string_map((node or {}).get('broadcaster'))
        if node is None or broadcaster is None:
            continue
        login = '' if broadcaster.get('login') is None else dart_string(broadcaster['login']).strip()
        if login == '':
            continue
        stream_game = string_map(node.get('game'))
        viewers = dart_string(node['viewersCount'] if node.get('viewersCount') is not None else 0)
        area_name = None
        if stream_game is not None:
            if stream_game.get('displayName') is not None:
                area_name = dart_string(stream_game['displayName'])
            elif stream_game.get('name') is not None:
                area_name = dart_string(stream_game['name'])
        rooms.append(room(
            roomId=login,
            title='' if node.get('title') is None else dart_string(node['title']),
            cover=append_txt(proxied(node.get('previewImageURL')), '?&t=%d' % now),
            nick=login if broadcaster.get('displayName') is None else dart_string(broadcaster['displayName']),
            avatar=proxied(broadcaster.get('profileImageURL')),
            watching=viewers,
            onlineViewers=viewers,
            introduction='',
            notice='',
            danmakuData=login if broadcaster.get('id') is None else dart_string(broadcaster['id']),
            liveStatus=LIVE,
            area='' if area_name is None else area_name,
        ))
    return {'rooms': rooms, 'nextCursor': cursor}


def search_rooms(response, now):
    """searchRooms (site:900-932)."""
    channels = response['data']['searchFor']['channels']
    if channels is None:
        channels = {}
    cursor = channels.get('cursor') if channels.get('cursor') is not None else ''
    edges = channels.get('edges') if channels.get('edges') is not None else []
    rooms = []
    for item in edges:
        node = item['item']
        stream = node.get('stream')
        live = stream is not None
        viewers = dart_string((stream or {}).get('viewersCount') if (stream or {}).get('viewersCount') is not None else 0)
        game = (stream or {}).get('game')
        rooms.append(room(
            roomId=node['login'],
            title=node['broadcastSettings']['title'],
            cover=append_txt(proxied((stream or {}).get('previewImageURL')), '?&t=%d' % now),
            nick=node['displayName'],
            avatar=node['profileImageURL'].replace('https://', 'https://i2.wp.com/', 1),
            watching=viewers,
            onlineViewers=viewers,
            introduction='',
            notice='',
            danmakuData=node['login'],
            liveStatus=LIVE if live else OFFLINE,
            area=(game or {}).get('displayName') if (game or {}).get('displayName') is not None else '',
        ))
    return {'rooms': rooms, 'cursor': cursor}


def dart_round(value):
    """double.round(): half away from zero."""
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def quality_label(raw_label):
    """LiveQualityLabel.normalize(platform: 'twitch', ...) for the labels 3.x built
    (core/utils/live_quality_label.dart:85-93): '<height>p<fps>[ (Source)]'."""
    raw = re.sub(r'\s+', ' ', raw_label.strip())
    token = re.sub('[^a-z0-9]+', '', raw.lower())
    source = 'source' in token
    match = re.search(r'(\d{3,4})p(?:\s*(\d{2,3}))?', raw, re.IGNORECASE)
    if match is None:
        raise AssertionError('3.x only built <height>p labels here: %r' % raw_label)
    return '%sP%s%s' % (match.group(1), match.group(2) or '', '（原画）' if source else '')


def quality_name(bandwidth, height, frame_rate, source):
    """TwitchSite._qualityName (site:658-674)."""
    if height > 0:
        fps = str(dart_round(frame_rate)) if frame_rate >= 45 else ''
        return quality_label('%dp%s%s' % (height, fps, ' (Source)' if source else ''))
    if source:
        return '原画'
    if bandwidth > 5000000:
        return '1080P'
    if bandwidth > 2500000:
        return '720P'
    if bandwidth > 1000000:
        return '480P'
    if bandwidth > 500000:
        return '360P'
    return '自动'


def playlist_attributes(value):
    """TwitchSite._parsePlaylistAttributes (site:647-656)."""
    attributes = {}
    for match in re.finditer(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)', value):
        raw = match.group(2) or ''
        attributes[match.group(1)] = raw[1:-1] if len(raw) >= 2 and raw.startswith('"') and raw.endswith('"') else raw
    return attributes


def parse_int(text):
    return int(text) if re.fullmatch(r'[+-]?\d+', text or '') else None


def parse_double(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def master_playlist(content, master):
    """TwitchSite.parseMasterPlaylist (site:591-645)."""
    grouped = {}
    pending = None
    for raw_line in re.split(r'\r?\n', content):
        line = raw_line.strip()
        if line.startswith('#EXT-X-STREAM-INF:'):
            pending = playlist_attributes(line[len('#EXT-X-STREAM-INF:'):])
            continue
        if line == '' or line.startswith('#') or pending is None:
            continue
        uri = urljoin(master, line)
        if not (uri.startswith('http://') or uri.startswith('https://')):
            pending = None
            continue
        attributes = pending
        pending = None
        bandwidth = parse_int(attributes.get('BANDWIDTH')) or 0
        resolution = re.fullmatch(r'(\d+)x(\d+)', attributes.get('RESOLUTION', ''))
        height = int(resolution.group(2)) if resolution else 0
        frame_rate = parse_double(attributes.get('FRAME-RATE')) or 0.0
        video = attributes.get('VIDEO', '')
        source = video.lower() == 'chunked'
        label = quality_name(bandwidth, height, frame_rate, source)
        identifier = '%d:%d:%d:%s' % (height, dart_round(frame_rate), bandwidth, video.lower())
        if identifier not in grouped:
            grouped[identifier] = {'label': label, 'sort': (1 << 30) if source else bandwidth, 'urls': [uri]}
        elif uri not in grouped[identifier]['urls']:
            grouped[identifier]['urls'].append(uri)
    qualities = [
        {'quality': value['label'], 'id': key, 'data': value['urls'], 'sort': value['sort']}
        for key, value in grouped.items()
    ]
    return sorted(qualities, key=lambda quality: -quality['sort'])


def access_token(response):
    """getPlayQualites (site:556-557): data.streamPlaybackAccessToken value and signature."""
    token = response['data']['streamPlaybackAccessToken']
    if token is None:
        return {'throws': {'type': 'NoSuchMethodError', 'at': 'twitch_site.dart:556'}}
    return {'token': token['value'], 'sig': token['signature']}


def main():
    meta, body = load('S01-tags')
    tags = categories(json.loads(body))
    write('S01-tags', 'TwitchSite.getCategores (twitch_site.dart:427-431)', tags)
    by_id = {tag['id']: tag for tag in tags}

    for sample in ['S01-dirs-1', 'S01-dirs-2']:
        meta, body = load(sample)
        operations = json.loads(meta['request']['body'])
        answers = json.loads(body)
        value = {}
        for operation, answer in zip(operations, answers):
            wanted = operation['variables']['options']['tags']
            if not wanted:
                continue  # the "top" operation of the archived v4; 3.x never sent it
            value[wanted[0]] = sub_categories(answer, by_id[wanted[0]])
        write(sample, 'TwitchSite.getSubCategores per tag (twitch_site.dart:498-519)', value)

    for sample in ['S02-game', 'S02-game-missing', 'S02-game-cursor']:
        meta, body = load(sample)
        write(sample, 'TwitchSite.getCategoryRooms (twitch_site.dart:817-871)', category_rooms(json.loads(body), seconds(meta)))

    for sample in ['S04-search-p1', 'S04-search-p2', 'S04-search-empty']:
        meta, body = load(sample)
        write(sample, 'TwitchSite.searchRooms (twitch_site.dart:900-932)', search_rooms(json.loads(body), seconds(meta)))

    for sample in ['S06-pat-live', 'S06-pat-offline', 'S06-pat-missing']:
        meta, body = load(sample)
        write(sample, 'TwitchSite.getPlayQualites token (twitch_site.dart:556-557)', access_token(json.loads(body)))

    meta, body = load('S06-usher-live')
    master = meta['request']['url'].split('?')[0]
    write('S06-usher-live', 'TwitchSite.parseMasterPlaylist (twitch_site.dart:591-645)', master_playlist(body, master))

    meta, body = load('S06-usher-offline')
    write(
        'S06-usher-offline',
        'HttpClient.getText (core/common/http_client.dart:55-71, 198-214)',
        {'throws': {'type': 'HttpError', 'statusCode': meta['response']['status']}},
    )


if __name__ == '__main__':
    main()
