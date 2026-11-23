#!/usr/bin/env python3
"""Spitball's sounds: quiet, soft and calm (think meditation app, not notification).
Pure tones, slow fade-ins, long gentle tails, low volume. Each set has a start + stop,
plus a soft practice chime and the ID-card sparkle."""
import math, struct, wave, os, random
SR = 44100
D = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'Sounds')
random.seed(3)

def save(name, x, vol):
    peak = max(1e-9, max(abs(v) for v in x))
    with wave.open(os.path.join(D, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(v / peak * vol * 32767)) for v in x))

def soft(f, dur=0.55, attack=0.025, decay=6.5):
    """A pure sine that swells in and fades out slowly."""
    n = int(SR * dur)
    return [math.sin(2 * math.pi * f * i / SR) * min(1, i / (SR * attack)) * math.exp(-decay * i / SR) for i in range(n)]

def bowl(f, dur=1.4):
    """Singing bowl: a fundamental and a slightly detuned twin that gently beat, long tail."""
    n = int(SR * dur); out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * f * t) + 0.6 * math.sin(2 * math.pi * (f * 1.004) * t) + 0.12 * math.sin(2 * math.pi * f * 2.71 * t) * math.exp(-6 * t)
        out.append(s * min(1, i / (SR * 0.03)) * math.exp(-2.6 * t))
    return out

def felt(f, dur=0.6):
    """Felt piano: a muted, warm note with a quick soft decay."""
    n = int(SR * dur)
    return [(math.sin(2 * math.pi * f * i / SR) + 0.25 * math.sin(4 * math.pi * f * i / SR) * math.exp(-14 * i / SR))
            * min(1, i / (SR * 0.006)) * math.exp(-7 * i / SR) for i in range(n)]

def rain(f0, f1, dur=0.45):
    """A single soft raindrop: a gentle glide with a long round tail."""
    n = int(SR * dur); out = []; ph = 0.0
    for i in range(n):
        t = i / SR; f = f1 + (f0 - f1) * math.exp(-t * 30); ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * min(1, i / (SR * 0.01)) * math.exp(-t * 9))
    return out

def breath(dur=0.5, bright=0.08):
    """A soft breath: filtered noise that swells and fades."""
    n = int(SR * dur); out = []; lp = 0.0; lp2 = 0.0
    for i in range(n):
        lp += (random.uniform(-1, 1) - lp) * bright; lp2 += (lp - lp2) * bright
        t = i / n; out.append(lp2 * math.sin(math.pi * t) ** 2)
    return out

def chord(fs, dur=1.2, gap=0.09, vol_each=1.0):
    n = int(SR * (dur + gap * (len(fs) - 1))); out = [0.0] * n
    for k, f in enumerate(fs):
        s = soft(f, dur, attack=0.03, decay=3.2)
        off = int(SR * gap * k)
        for i, v in enumerate(s): out[off + i] += v * vol_each
    return out

# start = a step up, stop = a step down; all quiet.
save('soft-start', soft(523.25), .11);  save('soft-stop', soft(392.0), .10)          # C5 / G4
save('bowl-start', bowl(392.0), .13);   save('bowl-stop', bowl(329.63), .12)         # G4 / E4
save('felt-start', felt(659.25), .12);  save('felt-stop', felt(523.25), .11)         # E5 / C5
save('rain-start', rain(520, 880), .10); save('rain-stop', rain(700, 440), .10)
save('breath-start', breath(0.45, 0.10), .14); save('breath-stop', breath(0.5, 0.06), .12)
save('chime', chord([523.25, 783.99], dur=1.0, gap=0.11), .11)                          # C5 + G5
save('sparkle', chord([523.25, 659.25, 783.99, 1046.5], dur=1.3, gap=0.09), .11)      # C major, rolled
print('ok')
