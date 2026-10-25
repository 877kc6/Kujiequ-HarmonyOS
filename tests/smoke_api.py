"""Read-only guest probes. Never sends SMS, signs in, likes, or submits credentials."""
import json
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

HOST = 'https://api.kurobbs.com'
HEADERS = {'source': 'android', 'version': '2.2.0', 'versionCode': '2200',
           'devCode': str(uuid.uuid4()), 'User-Agent': 'KujiequHarmony/1.0',
           'Origin': 'https://web-static.kurobbs.com',
           'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}

def post(route, values):
    req = urllib.request.Request(HOST + route, data=urllib.parse.urlencode(values).encode(), headers=HEADERS)
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.load(resp)

def main():
    results = []
    for game, forum in [(3, 9), (2, 2)]:
        data = post('/forum/list', {'gameId': game, 'forumId': forum, 'pageIndex': 1, 'pageSize': 2,
                                  'searchType': 1, 'timeType': 0, 'topicId': 0})
        assert data['code'] == 200, data.get('msg')
        posts = data['data']['postList']
        assert isinstance(posts, list) and posts
        assert all(isinstance(p['postId'], str) for p in posts), 'IDs must stay strings'
        results.append({'endpoint': '/forum/list', 'gameId': game, 'code': data['code'], 'count': len(posts)})
        if game == 3:
            detail = post('/forum/getPostDetail', {'postId': posts[0]['postId'], 'isOnlyPublisher': 0, 'showOrderType': 2})
            assert detail['code'] == 200
            assert isinstance(detail['data']['postDetail']['postContent'], list)
            results.append({'endpoint': '/forum/getPostDetail', 'code': 200, 'contentBlocks': len(detail['data']['postDetail']['postContent'])})
    protected = post('/gamer/role/list', {'gameId': 3})
    assert protected['code'] != 200, 'Role endpoint unexpectedly accepted guest'
    results.append({'endpoint': '/gamer/role/list', 'guestCode': protected['code'], 'authenticatedTest': False})
    report = {'testedAt': datetime.now(timezone.utc).isoformat(), 'transport': 'Python HTTPS, not HarmonyOS Network Kit', 'results': results}
    target = Path(__file__).resolve().parents[1] / 'docs' / 'api-smoke-result.json'
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
