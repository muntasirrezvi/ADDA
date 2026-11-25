import numpy as np, subprocess, os
SR = 44100
rng = np.random.default_rng(7)
def note(f): return 440.0 * 2 ** ((f - 69) / 12)
def env(n, a=0.01, d=0.3, s=0.6, r=0.2):
    t = np.arange(n) / SR; L = n / SR
    e = np.ones(n) * s
    ai = int(a * SR); di = int(d * SR); ri = int(r * SR)
    e[:ai] = np.linspace(0, 1, ai, endpoint=False) if ai else e[:ai]
    e[ai:ai+di] = np.linspace(1, s, len(e[ai:ai+di]))
    if ri: e[-ri:] *= np.linspace(1, 0, ri)
    return e
def tone(f, dur, kind='saw', vol=0.3, a=0.01, d=0.2, s=0.5, r=0.1, vib=0.0):
    n = int(dur * SR); t = np.arange(n) / SR
    ph = 2 * np.pi * f * t + vib * np.sin(2 * np.pi * 5 * t)
    if kind == 'sine': w = np.sin(ph)
    elif kind == 'tri': w = 2 / np.pi * np.arcsin(np.sin(ph))
    elif kind == 'square': w = np.sign(np.sin(ph)) * 0.6
    elif kind == 'pluck':
        w = sum(np.sin(ph * k) / k * np.exp(-t * (3 + k)) for k in range(1, 7))
    elif kind == 'epiano':
        w = np.sin(ph) + 0.4 * np.sin(2 * ph) * np.exp(-t * 4) + 0.2 * np.sin(3 * ph) * np.exp(-t * 6)
    else:
        w = sum(np.sin(ph * k) / k for k in range(1, 9))
    return w * env(n, a, d, s, r) * vol
def kick(vol=0.9):
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 120 * np.exp(-t * 25) + 45
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * vol
def snare(vol=0.4):
    n = int(0.2 * SR); t = np.arange(n) / SR
    return (rng.standard_normal(n) * 0.7 + np.sin(2 * np.pi * 190 * t) * 0.5) * np.exp(-t * 18) * vol
def hat(vol=0.15, open_=False):
    n = int((0.25 if open_ else 0.05) * SR); t = np.arange(n) / SR
    x = rng.standard_normal(n); x = np.diff(np.concatenate([[0], x]))
    return x * np.exp(-t * (10 if open_ else 60)) * vol
def clap(vol=0.35):
    n = int(0.25 * SR); t = np.arange(n) / SR
    x = rng.standard_normal(n) * (np.exp(-t * 30) + 0.6 * np.exp(-((t - 0.012) * 300) ** 2) + 0.5 * np.exp(-((t - 0.024) * 300) ** 2))
    return x * vol
def tabla(f=300, vol=0.5):
    n = int(0.4 * SR); t = np.arange(n) / SR
    fr = f * (1 + 0.5 * np.exp(-t * 30))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 8) * vol
def place(buf, x, at):
    i = int(at * SR)
    if i >= len(buf): return
    m = min(len(x), len(buf) - i); buf[i:i+m] += x[:m]
def chord(buf, notes, at, dur, kind, vol):
    for n_ in notes: place(buf, tone(note(n_), dur, kind, vol / len(notes) * 1.6, a=0.02, d=0.5, s=0.5, r=0.2), at)
def master(buf):
    # simple stereo-ish echo + soft clip
    d = int(0.28 * SR); out = buf.copy(); out[d:] += buf[:-d] * 0.25
    out = np.tanh(out * 1.2); out /= max(1e-9, np.max(np.abs(out))) / 0.9
    fade = int(0.8 * SR); out[-fade:] *= np.linspace(1, 0, fade); out[:int(0.05*SR)] *= np.linspace(0, 1, int(0.05*SR))
    return out

def song(bpm, bars, prog, drums, lead_scale, lead_kind, pad_kind, bass_kind='sine', swing=0.0, seed=1, extra=None):
    r = np.random.default_rng(seed)
    beat = 60 / bpm; dur = bars * 4 * beat
    buf = np.zeros(int((dur + 1) * SR))
    for b in range(bars):
        t0 = b * 4 * beat
        root, ch = prog[b % len(prog)]
        chord(buf, [root + 12 + c for c in ch], t0, 4 * beat, pad_kind, 0.22)
        for q in range(4):
            place(buf, tone(note(root - 12), beat * 0.9, bass_kind, 0.32, a=0.005, d=0.15, s=0.7, r=0.05), t0 + q * beat)
        drums(buf, t0, beat, b)
        # melody: 8 eighths per bar, random walk on the scale
        idx = r.integers(0, len(lead_scale))
        for e in range(8):
            if r.random() < 0.35: continue
            idx = int(np.clip(idx + r.integers(-2, 3), 0, len(lead_scale) - 1))
            at = t0 + e * beat / 2 + (swing * beat / 2 if e % 2 else 0)
            place(buf, tone(note(lead_scale[idx] + 24), beat * 0.45, lead_kind, 0.16, a=0.005, d=0.12, s=0.4, r=0.08, vib=0.3), at)
        if extra: extra(buf, t0, beat, b)
    return master(buf[:int(dur * SR)])

def four_floor(buf, t0, beat, b):
    for q in range(4):
        place(buf, kick(), t0 + q * beat); place(buf, hat(open_=True), t0 + q * beat + beat / 2)
    place(buf, clap(), t0 + beat); place(buf, clap(), t0 + 3 * beat)
def boom_bap(buf, t0, beat, b):
    place(buf, kick(), t0); place(buf, kick(0.7), t0 + 1.75 * beat); place(buf, kick(0.8), t0 + 2.5 * beat)
    place(buf, snare(), t0 + beat); place(buf, snare(), t0 + 3 * beat)
    for e in range(8): place(buf, hat(), t0 + e * beat / 2)
def lofi(buf, t0, beat, b):
    place(buf, kick(0.6), t0); place(buf, kick(0.5), t0 + 2.6 * beat)
    place(buf, snare(0.25), t0 + beat); place(buf, snare(0.25), t0 + 3 * beat)
    for e in range(8): place(buf, hat(0.08), t0 + e * beat / 2 + (0.1 * beat if e % 2 else 0))
def afro(buf, t0, beat, b):
    for q in range(4): place(buf, kick(0.8), t0 + q * beat)
    for s in (0.75, 1.5, 2.75, 3.5): place(buf, snare(0.2), t0 + s * beat)
    for e in range(16): place(buf, hat(0.07), t0 + e * beat / 4)
    place(buf, clap(0.3), t0 + beat); place(buf, clap(0.3), t0 + 3 * beat)
def dhol(buf, t0, beat, b):
    for s, f in ((0, 120), (0.5, 300), (1, 300), (1.5, 120), (2, 120), (2.25, 300), (2.5, 300), (3, 120), (3.5, 300), (3.75, 300)):
        place(buf, tabla(f, 0.55 if f == 120 else 0.35), t0 + s * beat)
    place(buf, clap(0.25), t0 + beat); place(buf, clap(0.25), t0 + 3 * beat)
def arabic(buf, t0, beat, b):  # maqsum-style doum/tek
    for s, f in ((0, 110), (0.5, 380), (1.5, 380), (2, 110), (3, 380)):
        place(buf, tabla(f, 0.6 if f == 110 else 0.3), t0 + s * beat)
    for e in range(8): place(buf, hat(0.05), t0 + e * beat / 2)
def soft(buf, t0, beat, b):
    if b % 2 == 0: place(buf, kick(0.4), t0)
    place(buf, hat(0.05), t0 + beat * 2)

maj = [0, 4, 7]; mn = [0, 3, 7]; mj7 = [0, 4, 7, 11]; m7 = [0, 3, 7, 10]
C_maj = [60, 62, 64, 67, 69, 72, 74]
A_min = [57, 60, 62, 64, 67, 69, 72]
hijaz = [62, 63, 66, 67, 69, 70, 72, 74]
bhairav = [60, 61, 64, 65, 67, 68, 71, 72]

tracks = [
  ("golden-hour", "Golden Hour", "Adda Originals", 88, lambda: song(88, 12, [(48, mj7), (45, m7), (41, mj7), (43, maj)], lofi, C_maj, 'epiano', 'epiano', swing=0.3, seed=3)),
  ("desert-nights", "Desert Nights", "Adda Originals", 100, lambda: song(100, 13, [(50, maj), (51, maj), (50, maj), (48, mn)], arabic, hijaz, 'pluck', 'saw', seed=5)),
  ("dhaka-beats", "Dhaka Beats", "Adda Originals", 110, lambda: song(110, 14, [(48, maj), (49, maj), (48, maj), (53, mn)], dhol, bhairav, 'pluck', 'saw', seed=8)),
  ("party-mode", "Party Mode", "Adda Originals", 124, lambda: song(124, 16, [(45, mn), (41, maj), (48, maj), (43, maj)], four_floor, A_min, 'square', 'saw', bass_kind='saw', seed=11)),
  ("lagos-sunset", "Lagos Sunset", "Adda Originals", 104, lambda: song(104, 13, [(48, maj), (45, mn), (41, maj), (43, maj)], afro, C_maj, 'pluck', 'epiano', seed=13)),
  ("midnight-cypher", "Midnight Cypher", "Adda Originals", 90, lambda: song(90, 11, [(45, m7), (45, m7), (41, mj7), (40, mn)], boom_bap, A_min, 'tri', 'epiano', swing=0.25, seed=17)),
  ("first-love", "First Love", "Adda Originals", 76, lambda: song(76, 10, [(48, maj), (43, maj), (45, mn), (41, maj)], soft, C_maj, 'epiano', 'epiano', seed=19)),
  ("celebrate", "Celebrate", "Adda Originals", 128, lambda: song(128, 16, [(48, maj), (43, maj), (45, mn), (41, maj)], four_floor, C_maj, 'saw', 'saw', bass_kind='square', seed=23)),
]
os.makedirs('out', exist_ok=True)
for slug, title, artist, bpm, fn in tracks:
    x = fn(); pcm = (x * 32767).astype(np.int16).tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '1', '-i', '-', '-b:a', '128k', f'out/{slug}.mp3'], input=pcm, check=True)
    print(slug, round(len(x) / SR, 1), 's', os.path.getsize(f'out/{slug}.mp3') // 1024, 'KB')
