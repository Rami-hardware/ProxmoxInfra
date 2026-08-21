#!/usr/bin/env python3
"""Saudi National Address lookup.

Nominatim can only find what OpenStreetMap contains, and Saudi residential
streets are largely unnamed there. This service indexes the OpenAddresses
Saudi countrywide dataset (~1.5M addresses that do carry street names) and
answers in a Nominatim-compatible shape, so the maps UI can fall back to it
without special-casing the response.
"""
import json, os, re, sqlite3, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB = os.environ.get("ADDR_DB", "/data/sa_addr.sqlite")
PORT = int(os.environ.get("PORT", "8080"))

# Arabic normalisation: users type أ/ا, ة/ه, ى/ي interchangeably.
_MAP = str.maketrans({"أ":"ا","إ":"ا","آ":"ا","ة":"ه","ى":"ي","ؤ":"و","ئ":"ي"})
_DIA = re.compile(r"[ً-ْـ]")

def norm(s):
    return _DIA.sub("", (s or "").translate(_MAP)).strip()

def tokens(q):
    # Drop punctuation and SANA short codes (JDSC7362) — they are not in the
    # dataset, but the digits inside them often match a building number.
    q = re.sub(r"[،,]+", " ", q)
    out = []
    for t in q.split():
        t = t.strip("().-")
        if not t:
            continue
        m = re.fullmatch(r"[A-Za-z]{3,5}(\d{3,6})", t)
        if m:
            out.append(m.group(1))
            continue
        out.append(t)
    return out

class DBPool:
    def __init__(self, path):
        self.path = path
    def conn(self):
        c = sqlite3.connect(self.path, check_same_thread=False)
        c.row_factory = sqlite3.Row
        return c

pool = DBPool(DB)

def search(q, limit=10):
    toks = [norm(t) for t in tokens(q)]
    toks = [t for t in toks if len(t) > 1]
    if not toks:
        return []
    sql = ("SELECT a.num,a.ar,a.en,a.dist,a.city,a.region,a.zip,a.lat,a.lon "
           "FROM fts JOIN a ON a.rowid = fts.rowid WHERE fts MATCH ? LIMIT ?")

    def run(c, terms):
        expr = " AND ".join('"%s"' % t.replace('"', '') for t in terms)
        try:
            return c.execute(sql, (expr, limit)).fetchall()
        except sqlite3.OperationalError:
            return []

    # A pasted address carries words this dataset does not hold ("District",
    # "As", the SANA additional number). Requiring every token would return
    # nothing, so drop the weakest terms progressively until something matches.
    c = pool.conn()
    try:
        rows = run(c, toks)
        if not rows:
            # Prefer the distinctive parts: longest words plus any building
            # number, dropping one term at a time from the least useful end.
            ranked = sorted(set(toks), key=lambda t: (t.isdigit(), len(t)),
                            reverse=True)
            for keep in range(min(4, len(ranked)), 0, -1):
                rows = run(c, ranked[:keep])
                if rows:
                    break
        return [dict(r) for r in rows]
    finally:
        c.close()

def as_nominatim(r):
    parts = [p for p in [r["num"], r["ar"], r["dist"], r["city"], r["zip"],
                         "السعودية"] if p]
    return {
        "place_id": 0,
        "osm_type": "node",
        "lat": str(r["lat"]),
        "lon": str(r["lon"]),
        "display_name": ", ".join(parts),
        "name": ("%s %s" % (r["num"], r["ar"])).strip(),
        "class": "place",
        "type": "house",
        "importance": 0.4,
        "source": "openaddresses-sa",
        "address": {
            "house_number": r["num"], "road": r["ar"], "road_en": r["en"],
            "suburb": r["dist"], "city": r["city"], "state": r["region"],
            "postcode": r["zip"], "country": "Saudi Arabia",
            "country_code": "sa",
        },
    }

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p = urllib.parse.parse_qs(u.query)
        if u.path.rstrip("/") in ("/health", "/status"):
            return self._send(200, {"status": "ok"})
        if u.path.rstrip("/") in ("", "/search"):
            q = (p.get("q") or [""])[0]
            try:
                limit = max(1, min(50, int((p.get("limit") or ["10"])[0])))
            except ValueError:
                limit = 10
            return self._send(200, [as_nominatim(r) for r in search(q, limit)])
        self._send(404, {"error": "not found"})

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("", PORT), H).serve_forever()
