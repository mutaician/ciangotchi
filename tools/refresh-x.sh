#!/bin/sh
# Save links to your X bookmarks, for the pet to open.
# Reads ONLY the x.com session cookies from Brave (in memory, never printed or
# written), hands them to tweethoarder as env vars, syncs bookmarks into its
# local database, then writes each bookmarked post's URL to links.d.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
DIR="$STATE/ciangotchi-links.d"
TH="$HOME/.local/share/tweethoarder-src/repo/.venv/bin/tweethoarder"
DB="$HOME/.local/share/tweethoarder/tweethoarder.db"
mkdir -p "$DIR"
[ -x "$TH" ] || { echo "tweethoarder not installed" >&2; exit 1; }

/usr/bin/python3 - "$TH" <<'PY' || exit 1
import os, sys
from yt_dlp.cookies import extract_cookies_from_browser
jar = extract_cookies_from_browser('brave', keyring='GNOMEKEYRING')
want = {'auth_token': 'TWITTER_AUTH_TOKEN', 'ct0': 'TWITTER_CT0', 'twid': 'TWITTER_TWID'}
env = dict(os.environ)
for c in jar:
    if c.domain.lstrip('.') in ('x.com', 'twitter.com') and c.name in want:
        env[want[c.name]] = c.value
if 'TWITTER_AUTH_TOKEN' not in env or 'TWITTER_CT0' not in env:
    sys.exit('not logged in to x.com in Brave')
os.execve(sys.argv[1], [sys.argv[1], 'sync', 'bookmarks', '--all'], env)
PY

[ -f "$DB" ] || exit 1
/usr/bin/python3 - "$DB" "$DIR/x-bookmarks.txt" <<'PY'
import os, sqlite3, sys
db = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
rows = db.execute("""select t.author_username, t.id from collections c
    join tweets t on t.id = c.tweet_id
    where c.collection_type = 'bookmark'""").fetchall()
urls = sorted({'https://x.com/%s/status/%s' % r for r in rows})
# Never replace a good list with an empty one.
if urls:
    tmp = sys.argv[2] + '.tmp'
    open(tmp, 'w').write('\n'.join(urls) + '\n')
    os.replace(tmp, sys.argv[2])
PY
