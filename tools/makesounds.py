#!/usr/bin/env python3
"""Synthesises the game's generated sound effects into sounds/.

Run from the project root:  python3 tools/makesounds.py

Makes key.wav, back.wav, enter.wav, tick.wav, flush.wav, win1-3.wav and
lose1-3.wav. The fart*.wav and poop*.wav files are the originals and are left
alone. The noise uses a fixed seed, so rerunning reproduces the same files.
Standard library only.
"""
import math
import random
import struct
import wave

SR = 22050
random.seed(42)


def save(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(f"sounds/{name}", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))


def env(i, n, a=0.005, r=None):
    t = i / SR
    dur = n / SR
    att = min(1.0, t / a) if a > 0 else 1.0
    rel = math.exp(-t / r) if r else max(0.0, 1 - t / dur)
    return att * rel


def tone(freq, dur, amp=0.4, shape="sine", r=None, vib=0.0, vibhz=6.0, slide=None):
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = freq if slide is None else freq + (slide - freq) * (i / n)
        f *= 1 + vib * math.sin(2 * math.pi * vibhz * t)
        ph += 2 * math.pi * f / SR
        if shape == "sine":
            v = math.sin(ph)
        elif shape == "tri":
            v = 2 / math.pi * math.asin(math.sin(ph))
        elif shape == "square":
            v = 0.6 * (1 if math.sin(ph) >= 0 else -1) + 0.4 * math.sin(ph)
        elif shape == "saw":
            v = 0.5 * (((ph / math.pi) % 2) - 1) + 0.5 * math.sin(ph)
        out.append(amp * v * env(i, n, r=r))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(SR * gap)
    return out


def silence(d):
    return [0.0] * int(SR * d)


def delay(p, d):
    return silence(d) + p


# --- key feedback ---------------------------------------------------------
save("key.wav", mix(tone(1900, 0.03, 0.30, "sine", r=0.006),
                    [random.uniform(-.12, .12) * math.exp(-i / 60) for i in range(int(SR * .03))]))
save("back.wav", tone(900, 0.07, 0.30, "tri", r=0.03, slide=450))
save("enter.wav", mix(tone(220, 0.14, 0.45, "sine", r=0.05), tone(440, 0.10, 0.20, "tri", r=0.03)))
save("tick.wav", tone(1250, 0.035, 0.35, "square", r=0.008))

# --- flush: swirling filtered noise with gurgles ----------------------------
n = int(SR * 1.7)
lp = 0.0
fl = []
for i in range(n):
    t = i / SR
    cutoff = 0.02 + 0.10 * math.sin(math.pi * t / 1.7)          # opens then closes
    lp += cutoff * (random.uniform(-1, 1) - lp)
    swirl = 0.6 + 0.4 * math.sin(2 * math.pi * (3 + 4 * t) * t)
    e = min(1, t / 0.15) * max(0, 1 - max(0, t - 1.1) / 0.6)
    gurgle = 0.25 * math.sin(2 * math.pi * (90 + 60 * math.sin(2 * math.pi * 7 * t)) * t) * (1 if (int(t * 9) % 3 == 0) else 0)
    fl.append((lp * 2.8 * swirl + gurgle) * e)
save("flush.wav", fl)

# --- victories ---------------------------------------------------------------
C5, E5, G5, C6 = 523.25, 659.25, 783.99, 1046.5
save("win1.wav", seq(tone(C5, .11, .4, "tri", r=.08), tone(E5, .11, .4, "tri", r=.08),
                     tone(G5, .11, .4, "tri", r=.08),
                     mix(tone(C6, .45, .4, "tri", r=.25), tone(G5, .45, .2, "sine", r=.25))))
save("win2.wav", seq(tone(G5, .09, .35, "square", r=.05), tone(G5, .09, .35, "square", r=.05),
                     tone(G5, .09, .35, "square", r=.05),
                     mix(tone(C6, .55, .35, "square", r=.3), tone(E5, .55, .2, "tri", r=.3)), gap=.02))
sparkle = mix(*[delay(tone(f, .18, .18, "sine", r=.07), d)
                for f, d in [(1568, 0), (2093, .07), (2637, .14), (3136, .21)]])
save("win3.wav", seq(tone(400, .35, .35, "sine", r=None, slide=1200), sparkle))


# --- failures ------------------------------------------------------------------
def trombone(f, d, vib=0.0):
    return tone(f, d, .4, "saw", r=d * .9, vib=vib, vibhz=7)


save("lose1.wav", seq(trombone(311.1, .32), trombone(293.7, .32), trombone(277.2, .32),
                      trombone(261.6, 1.0, vib=.03), gap=.04))
save("lose2.wav", tone(700, .9, .4, "tri", r=None, slide=110))
save("lose3.wav", seq(tone(140, .35, .35, "square", r=.2), silence(.05), tone(95, .5, .4, "square", r=.3)))
print("sounds written")
