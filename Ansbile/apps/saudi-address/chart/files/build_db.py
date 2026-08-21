#!/usr/bin/env python3
"""Download the OpenAddresses Saudi dataset and build the lookup database.

Runs once in an init container; the result lives on a PVC so restarts and
re-syncs reuse it instead of rebuilding.
"""
import csv, io, os, sqlite3, sys, urllib.request, zipfile

SRC = os.environ.get("ADDR_SRC",
    "https://data.openaddresses.io/cache/uploads/ingalls/10e26c/"
    "ksa_FeatureToPoint_RESTACKED.zip")
DB = os.environ.get("ADDR_DB", "/data/sa_addr.sqlite")
MARKER = DB + ".done"

if os.path.exists(MARKER):
    print("Address database already built — skipping.")
    sys.exit(0)

print("Downloading %s ..." % SRC)
tmp = DB + ".zip"
urllib.request.urlretrieve(SRC, tmp)
print("Downloaded %.0f MB" % (os.path.getsize(tmp) / 1e6))

for p in (DB, DB + "-journal"):
    if os.path.exists(p):
        os.remove(p)

c = sqlite3.connect(DB)
c.execute("PRAGMA journal_mode=OFF")
c.execute("PRAGMA synchronous=OFF")
c.execute("CREATE TABLE a(num TEXT,ar TEXT,en TEXT,city TEXT,dist TEXT,"
          "region TEXT,zip TEXT,lat REAL,lon REAL)")

n = 0
batch = []
with zipfile.ZipFile(tmp) as z:
    name = [x for x in z.namelist() if x.lower().endswith(".csv")][0]
    with z.open(name) as fh:
        for row in csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8-sig")):
            st = (row.get("ARABIC_STREET") or "").strip()
            # Rows whose "street" is just a number carry no searchable name.
            if not st or st.isdigit():
                continue
            try:
                lat, lon = float(row["Y"]), float(row["X"])
            except (TypeError, ValueError):
                continue
            batch.append((row.get("NUMBER"), st,
                          (row.get("ENGLISH_STREET") or "").strip(),
                          row.get("CITY"), row.get("DISTRICT"),
                          row.get("EMIRATE"), row.get("ZIPCODE"), lat, lon))
            n += 1
            if len(batch) >= 200000:
                c.executemany("INSERT INTO a VALUES(?,?,?,?,?,?,?,?,?)", batch)
                batch = []
if batch:
    c.executemany("INSERT INTO a VALUES(?,?,?,?,?,?,?,?,?)", batch)
c.commit()
print("Indexed %d addresses" % n)

c.execute("CREATE VIRTUAL TABLE fts USING fts5(num,ar,en,city,dist,zip,"
          "content='')")
c.execute("INSERT INTO fts(rowid,num,ar,en,city,dist,zip) "
          "SELECT rowid,num,ar,en,city,dist,zip FROM a")
c.commit()
c.close()

os.remove(tmp)
open(MARKER, "w").write(SRC)
print("Done: %.0f MB" % (os.path.getsize(DB) / 1e6))
