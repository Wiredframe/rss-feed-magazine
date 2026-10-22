#!/usr/bin/env python3
# Exports the newest articles per folder from NetNewsFeed’s local account (read-only) into data.js for the magazine prototype.
import html, json, os, re, sqlite3, sys, xml.etree.ElementTree as ET
from datetime import datetime, timezone

ACCOUNT = os.path.expanduser('~/Library/Application Support/NetNewsFeed/Accounts/OnMyMac')
PER_SECTION = 80

def feeds_by_folder():
    root = ET.parse(os.path.join(ACCOUNT, 'Subscriptions.opml')).getroot()
    sections = {}
    for o in root.find('body'):
        if o.get('xmlUrl'):
            continue
        sections[o.get('text')] = {k.get('xmlUrl'): k.get('title') or k.get('text') for k in o if k.get('xmlUrl')}
    return sections

ATTR = re.compile(r'(?<![\w.:-])([\w:-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))')

def first_image(content):
    for tag in re.findall(r'<img\b[^>]*>', content or '', re.I)[:5]:
        a = {m.group(1).lower(): html.unescape(m.group(2) or m.group(3) or m.group(4) or '') for m in ATTR.finditer(tag[4:])}
        if any(a.get(k, '').isdigit() and int(a[k]) < 64 for k in ('width', 'height')):
            continue
        if 'emoji' in a.get('class', '') or 'smiley' in a.get('class', ''):
            continue
        src = a.get('src') or a.get('data-src') or ''
        if src.startswith('http') and '/emoji/' not in src and not src.endswith('.svg'):
            return src
    return None

def plain_text(content, title):
    t = re.sub(r'<(script|style|figure|figcaption)\b.*?</\1>', ' ', content or '', flags=re.S | re.I)
    t = re.sub(r'<br\s*/?>|</p>', '\n', t, flags=re.I)
    t = html.unescape(re.sub(r'<[^>]+>', ' ', t))
    t = re.sub(r'[ \t ]+', ' ', t)
    t = re.sub(r'\s*\n\s*', '\n', t).strip()
    if title and t.startswith(title):
        t = t[len(title):].strip()
    # Feed boilerplate after the teaser: links to the article, social accounts, "appeared first on".
    t = re.split(r'\s(?:Zum Beitrag:|Weiterlesen|Read more|Continue reading|The post .{0,200} appeared first on|Wo du uns folgen kannst)', t)[0]
    return t.strip()[:2400]

def main():
    db = sqlite3.connect('file:' + os.path.join(ACCOUNT, 'DB.sqlite3') + '?mode=ro', uri=True)
    out = []
    for section, feeds in feeds_by_folder().items():
        if not feeds:
            continue
        q = ','.join('?' * len(feeds))
        rows = db.execute(f'''select a.articleID, a.feedID, a.title, a.contentHTML, a.summary, a.url, a.externalURL,
                coalesce(a.datePublished, s.dateArrived), s.read
                from articles a join statuses s using (articleID)
                where a.feedID in ({q}) order by coalesce(a.datePublished, s.dateArrived) desc limit {PER_SECTION}''', list(feeds))
        articles = []
        for aid, fid, title, content, summary, url, ext, date, read in rows:
            body = content or summary or ''
            articles.append({
                'id': aid, 'feed': feeds.get(fid, ''), 'title': html.unescape(title or '').strip(),
                'text': plain_text(body, title), 'image': first_image(body), 'url': url or ext,
                'date': datetime.fromtimestamp(date, timezone.utc).isoformat() if date else None, 'read': bool(read)})
        out.append({'name': section, 'articles': articles})
    path = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'data.js')
    with open(path, 'w') as f:
        f.write('window.SECTIONS = ' + json.dumps(out, ensure_ascii=False) + ';\n')
    print(path, sum(len(s['articles']) for s in out), 'articles')

main()
