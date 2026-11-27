# Run with: python3 -I tests/cliamp_library_test.py
# cliamp-library has no .py suffix, so it is loaded by path. No cliamp is needed: only
# the cache and paging logic is exercised, against temporary files and fake replies.

import importlib.machinery
import importlib.util
import json
import os
import stat
import sys
import tempfile

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("cliamp_library", os.path.join(HERE, "..", "cliamp-library"))
spec = importlib.util.spec_from_loader("cliamp_library", loader)
lib = importlib.util.module_from_spec(spec)
loader.exec_module(lib)

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        failures += 1
        print("FAIL", name, "got", repr(got), "want", repr(want))


def search(tag, size):
    return {"%s%d" % (tag, i): {"path": "x://%s/%d" % (tag, i)} for i in range(size)}


workdir = tempfile.mkdtemp()
lib.TRACK_CACHE = os.path.join(workdir, "state", "tracks.json")

# Unequal sizes: a small search right after a large one must not shed the large one.
lib.save_tracks(search("A", 1200))
lib.save_tracks(search("B", 1))
check("a track from a large search survives a small one", lib.load_track("A0") is not None, True)
check("the last track of that search too", lib.load_track("A1199") is not None, True)
lib.save_tracks(search("C", 5000))
check("and a huge one after that", lib.load_track("A0") is not None, True)

# Retention counts searches, so the oldest set goes on the next one.
lib.save_tracks(search("D", 1))
check("the oldest search is shed after three newer ones", lib.load_track("A0"), None)
check("the newer ones remain", [lib.load_track(k) is not None for k in ("B0", "C4999", "D0")], [True, True, True])

# A key seen again resolves to its newest object.
lib.save_tracks({"B0": {"path": "x://newer"}})
check("the newest object wins", lib.load_track("B0"), {"path": "x://newer"})

check("an unknown key is None", lib.load_track("nope"), None)
check("the cache is owner only", oct(stat.S_IMODE(os.stat(lib.TRACK_CACHE).st_mode)), "0o600")

# The flat shape an earlier build wrote still reads, as one set.
with open(lib.TRACK_CACHE, "w", encoding="utf-8") as handle:
    json.dump({"old1": {"path": "x://old"}}, handle)
check("a flat cache file still resolves", lib.load_track("old1"), {"path": "x://old"})
lib.save_tracks(search("E", 1))
check("and is kept as a set on the next save", lib.load_track("old1"), {"path": "x://old"})

# The row index is bounded by entries, newest kept.
index = os.path.join(workdir, "rows.json")
lib.merge_bounded(index, {str(i): i for i in range(8)}, 5)
lib.merge_bounded(index, {"3": "again", "new": 1}, 5)
with open(index, encoding="utf-8") as handle:
    check("the row index keeps the newest, refreshed keys included", list(json.load(handle)), ["5", "6", "7", "3", "new"])

# Paging: a provider may clamp the page size, so only an empty page ends the walk.
rows = [{"id": str(i)} for i in range(250)]


def walk(reply, field):
    offsets = []

    def fake(operation, **params):
        offsets.append(params["offset"])
        return reply(params["offset"], params["limit"])

    lib.remote = fake
    got = lib.paged("op", field, "p")
    return len(got), len({r["id"] for r in got}), offsets


def clamped(offset, limit):
    page = rows[offset:offset + min(limit, 100)]
    return {"albums": page, "total": len(page)}


def ignores_offset(offset, limit):
    return {"albums": rows[:100], "total": 100}


def real_total(offset, limit):
    return {"playlists": rows[offset:offset + limit], "total": len(rows)}


check("a page clamped to 100 is not the end", walk(clamped, "albums"), (250, 250, [0, 100, 200, 250]))
check("a provider ignoring offset does not loop", walk(ignores_offset, "albums"), (100, 100, [0, 100]))
check("a real total ends the walk without an empty page", walk(real_total, "playlists"), (250, 250, [0, 200]))

print("all library tests passed" if failures == 0 else "%d failing" % failures)
sys.exit(1 if failures else 0)
