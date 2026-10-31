# check.py <source.txt> <target.txt>: does the target page contain the source's first 8 words?
# HIT: all 8 inside. STRADDLE: the first k (>=3) words end the target page (the rest are on its next page).
import sys, re, unicodedata
def norm(s):
    s = unicodedata.normalize('NFKC', s)
    for a, b in (('’', "'"), ('‘', "'"), ('“', '"'), ('”', '"'), ('—', '-'), ('­', '')):
        s = s.replace(a, b)
    return re.sub(r'\s+', ' ', s).strip()
src = norm(open(sys.argv[1]).read()); tgt = norm(open(sys.argv[2]).read())
words = src.split(' ')[:8]
probe = ' '.join(words)
i = tgt.find(probe)
if i >= 0:
    print(f"HIT at char {i}/{len(tgt)}: {probe!r}")
else:
    for k in range(7, 2, -1):
        p = ' '.join(words[:k])
        if tgt.endswith(p) or tgt.endswith(p + ' ' + words[k][:1]):
            print(f"STRADDLE: first {k}/8 words end the page: {p!r}"); break
    else:
        print(f"NOT FOUND: {probe!r}")
print("target starts:", tgt[:80], "| ends:", tgt[-60:])
