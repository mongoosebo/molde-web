#!/usr/bin/env python3
"""Makes every sound in the game: sounds/*.ogg, and sounds/CREDITS.md.

Nothing is recorded or downloaded: each sound is worked out here from noise and tones (so there is no licence
to keep track of, the files are small, and a sound can be changed by changing its few numbers). Loops are made
so that their end runs into their beginning without a click: their noise is built from whole waves of the
loop's length.

Needs numpy, scipy and ffmpeg (for Ogg Vorbis).   .venv/bin/python tools/make_sounds.py
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sounds")
SR = 32000
rng = np.random.default_rng(7)
made = []                                       # (file, what it is, how it is made)


def noise(seconds, shape):
    """Noise that loops: `shape` gives the strength at each frequency (Hz -> 0..1)."""
    n = int(seconds * SR)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec = (rng.normal(size=len(f)) + 1j * rng.normal(size=len(f))) * shape(f)
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    return x / (np.abs(x).max() + 1e-9)


def band(lo, hi, soft=0.5):
    """A pass band from lo to hi Hz with soft edges (in octaves)."""
    def shape(f):
        f = np.maximum(f, 1e-3)
        up = 1.0 / (1.0 + (lo / f) ** (2.0 / soft))
        down = 1.0 / (1.0 + (f / hi) ** (2.0 / soft))
        return up * down
    return shape


def pink(f):
    return 1.0 / np.sqrt(np.maximum(f, 20.0))


def t_of(seconds):
    return np.arange(int(seconds * SR)) / SR


def swell(seconds, cycles, depth, phase=0.0):
    """A slow rise and fall that fits the loop a whole number of times."""
    t = t_of(seconds)
    return 1.0 - depth * 0.5 * (1.0 + np.cos(2 * np.pi * cycles * t / seconds + phase))


def env(n, attack, decay):
    """A burst: up in `attack` seconds, dying away with `decay`."""
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def save(name, x, what, how, peak=0.8):
    x = np.asarray(x, np.float64)
    x = x / (np.abs(x).max() + 1e-9) * peak
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (x * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(tmp.name)
    made.append((name + ".ogg", what, how))


# ---------------------------------------------------------------- the places
# waves on the shore: a low wash that swells and falls, with hiss as each wave runs out
s = 12.0
x = noise(s, lambda f: pink(f) * band(60, 900)(f)) * swell(s, 2, 0.75) ** 1.5
x += 0.45 * noise(s, band(1500, 7000)) * np.clip(swell(s, 2, 1.0, 1.9) - 0.35, 0, 1) ** 2
x += 0.25 * noise(s, band(200, 2500)) * swell(s, 3, 0.6, 0.7)
save("sea", x, "waves on the shore (loop)", "low and high noise rising and falling as waves do")

# the town: a hum of traffic some streets away
s = 10.0
x = noise(s, lambda f: band(35, 260, 0.8)(f) / np.maximum(f, 30.0) ** 0.3) * swell(s, 3, 0.35)
x += 0.18 * noise(s, band(400, 1800)) * swell(s, 2, 0.6, 1.0)
save("town", x, "a town's hum of traffic (loop)", "low rumble with a little road hiss, slowly rising and falling")

# wind in the open and in trees
s = 10.0
x = noise(s, band(120, 900, 1.0)) * swell(s, 2, 0.7) * swell(s, 5, 0.3, 0.6)
x += 0.5 * noise(s, band(900, 5000, 1.0)) * swell(s, 3, 0.8, 2.0) ** 2
save("wind", x, "wind, in the open and in trees (loop)", "mid and high noise in gusts")

# running water
s = 7.0
x = noise(s, lambda f: band(250, 6000, 0.8)(f) * pink(f)) * swell(s, 7, 0.25)
x += 0.4 * noise(s, band(2000, 9000)) * swell(s, 11, 0.35, 1.0)
save("river", x, "a river's rush (loop)", "broad noise with a quick small flutter")

# rain
s = 7.0
x = noise(s, band(1500, 11000, 0.7))
drops = np.zeros(int(s * SR))
for at in rng.integers(0, len(drops) - 400, 900):
    n = int(rng.integers(60, 300))
    drops[at:at + n] += rng.normal(size=n) * env(n, 0.0005, 0.004) * rng.uniform(0.3, 1.0)
x = 0.7 * x + 0.6 * drops / np.abs(drops).max()
save("rain", x, "rain (loop)", "high noise with many small drops")


# ---------------------------------------------------------------- birds
def chirp(f0, f1, seconds, wobble=0.0, rate=0.0):
    t = t_of(seconds)
    f = f0 + (f1 - f0) * (t / seconds) + wobble * np.sin(2 * np.pi * rate * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.sin(np.pi * t / seconds) ** 0.7


def gull(base, calls):
    out = []
    for k in range(calls):
        length = 0.42 - 0.03 * k
        t = t_of(length)
        f = base * (1.0 + 0.55 * np.sin(np.pi * t / length) ** 2) * (1.0 - 0.04 * k)
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = np.sin(ph) + 0.55 * np.sin(2 * ph) + 0.35 * np.sin(3 * ph) + 0.2 * np.sin(4 * ph)
        tone *= np.sin(np.pi * t / length) ** 0.5 * (1.0 + 0.25 * np.sin(2 * np.pi * 38 * t))
        out += [tone, np.zeros(int(0.09 * SR))]
    return np.concatenate(out)


save("gull1", gull(1250, 4), "a gull crying", "a rising and falling tone with overtones, four times")
save("gull2", gull(1050, 2), "a gull, two cries", "the same, lower, twice")
save("gull3", np.concatenate([gull(1400, 1), np.zeros(int(0.2 * SR)), gull(1320, 3)]), "a gull, one cry and three", "the same, higher")
save("bird1", np.concatenate([chirp(3800, 5200, 0.09), np.zeros(800), chirp(5200, 3600, 0.11), np.zeros(700), chirp(4200, 5600, 0.08)]),
     "a small bird, three notes", "three short gliding tones")
save("bird2", np.concatenate([np.concatenate([chirp(6200, 5400, 0.045), np.zeros(600)]) for _ in range(6)]), "a small bird, a quick run", "six quick falling tones")
save("bird3", chirp(2600, 2900, 0.5, 260, 21), "a bird's trill", "one tone wobbling fast")
save("bird4", np.concatenate([chirp(3200, 2400, 0.16), np.zeros(2600), chirp(3300, 2300, 0.2)]), "a bird, two falling notes", "two gliding tones")


# ---------------------------------------------------------------- footsteps
def step(shape_lo, shape_hi, decay, thud=0.0, crunch=0, seed=0):
    r = np.random.default_rng(100 + seed)
    n = int(0.22 * SR)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec = (r.normal(size=len(f)) + 1j * r.normal(size=len(f))) * band(shape_lo, shape_hi)(f)
    x = np.fft.irfft(spec, n)
    x = x / np.abs(x).max() * env(n, 0.002, decay)
    if thud > 0.0:
        t = np.arange(n) / SR
        x += thud * np.sin(2 * np.pi * (95 - 50 * t / 0.2) * t) * np.exp(-t / 0.035)
    for _ in range(crunch):
        at = int(r.integers(0, n // 2))
        m = int(r.integers(80, 400))
        x[at:at + m] += r.normal(size=m) * env(m, 0.0005, 0.006) * r.uniform(0.2, 0.7)
    return x


for k in range(3):
    save("step_asphalt%d" % (k + 1), step(700, 3500, 0.016, 0.5, 0, k), "a footstep on asphalt", "a short dull tap", 0.6)
    save("step_slab%d" % (k + 1), step(1200, 5200, 0.012, 0.3, 0, 10 + k), "a footstep on paving slabs", "a short hard tap", 0.6)
    save("step_gravel%d" % (k + 1), step(1500, 8000, 0.045, 0.15, 9, 20 + k), "a footstep on gravel", "a crunch of many small clicks", 0.6)
    save("step_grass%d" % (k + 1), step(500, 3800, 0.05, 0.25, 2, 30 + k), "a footstep on grass", "a soft brush", 0.45)
    save("step_wood%d" % (k + 1), step(250, 1400, 0.03, 0.9, 0, 40 + k), "a footstep on wood", "a hollow knock", 0.65)
    save("step_water%d" % (k + 1), step(600, 6000, 0.07, 0.2, 6, 50 + k), "a footstep in shallow water", "a small splash", 0.6)


# ---------------------------------------------------------------- water
def splash(seconds, weight):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    x = noise(seconds, band(300, 9000, 0.9)) * env(n, 0.004, seconds * 0.28)
    x += weight * noise(seconds, band(80, 500)) * env(n, 0.01, seconds * 0.18)
    x += 0.5 * noise(seconds, band(3000, 12000)) * np.clip(t / seconds * 3, 0, 1) * np.exp(-t / (seconds * 0.4))
    return x


save("splash_big", splash(1.3, 1.2), "something heavy going into the water", "a burst of noise with a low thump, dying away in spray")
save("splash_small", splash(0.6, 0.4), "a small splash", "a short burst of noise")
save("stroke1", splash(0.5, 0.1) * 0.6 + 0.4 * np.resize(noise(0.5, band(500, 2500)), int(0.5 * SR)) * np.sin(np.pi * t_of(0.5) / 0.5), "a swimming stroke", "a soft swish of water", 0.5)
save("stroke2", splash(0.42, 0.15), "a swimming stroke, harder", "a swish with a little splash", 0.55)


# ---------------------------------------------------------------- vehicles
def engine(seconds, fire_hz, cylinders, rough, bright, seed):
    """An engine at idle, a loop to be pitched up with speed: pulses at the firing rate, each cylinder a
    little different, through a few resonances, with intake noise."""
    r = np.random.default_rng(seed)
    n = int(round(seconds * fire_hz)) * int(round(SR / fire_hz))           # a whole number of firings
    per = int(round(SR / fire_hz))
    x = np.zeros(n)
    amp = 1.0 + rough * r.normal(size=cylinders)
    for k in range(n // per):
        a = amp[k % cylinders] * (1.0 + 0.05 * r.normal())
        m = min(per, n - k * per)
        t = np.arange(m) / SR
        x[k * per:k * per + m] += a * (np.exp(-t * fire_hz * 2.2) * np.sin(2 * np.pi * fire_hz * 2.0 * t) + 0.6 * np.exp(-t * fire_hz * 5.0))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec = np.fft.rfft(x)
    res = 1.0 / (1.0 + (f / (900.0 * bright)) ** 2)
    for centre, gain in ((140.0, 1.2), (320.0 * bright, 0.9), (900.0 * bright, 0.5)):
        res += gain * np.exp(-((f - centre) / (centre * 0.35)) ** 2)
    x = np.fft.irfft(spec * res, n)
    x = x / np.abs(x).max()
    hiss = np.fft.irfft((r.normal(size=len(f)) + 1j * r.normal(size=len(f))) * band(600, 5000 * bright)(f), n)
    return x + 0.12 * bright * hiss / np.abs(hiss).max()


save("engine_volvo", engine(2.0, 26.0, 4, 0.10, 1.0, 1), "the Volvo's engine (loop, pitched by speed)", "pulses at the firing rate through a few resonances")
save("engine_integra", engine(2.0, 30.0, 4, 0.06, 1.7, 2), "the Integra's engine (loop)", "the same, quicker and brighter")
save("engine_mercedes", engine(2.0, 22.0, 5, 0.22, 0.7, 3), "the Mercedes diesel (loop)", "the same, slower, five uneven cylinders, darker")
save("engine_atv", engine(2.0, 17.0, 1, 0.0, 1.2, 4), "the ATV's single cylinder (loop)", "one cylinder thumping")

# the helicopter: blades beating, and the turbine's whine
s = 2.0
t = t_of(s)
beat = 13.0
x = noise(s, band(60, 700, 0.9)) * (0.25 + np.clip(np.sin(2 * np.pi * beat * t), 0, 1) ** 4)
x += 0.6 * np.sin(2 * np.pi * beat * t) * np.exp(-((np.mod(t * beat, 1.0) - 0.25) / 0.2) ** 2)
x += 0.10 * np.sin(2 * np.pi * 2100 * t) + 0.06 * np.sin(2 * np.pi * 3150 * t) + 0.12 * noise(s, band(2500, 9000))
save("rotor", x, "the helicopter's rotor and turbine (loop)", "noise beaten at the blade rate, with a high whine")

# tyres sliding
s = 2.0
t = t_of(s)
x = noise(s, band(900, 2600, 0.25)) * (0.8 + 0.2 * np.sin(2 * np.pi * 6 * t)) + 0.5 * noise(s, band(1700, 2100, 0.1)) + 0.3 * noise(s, band(300, 5000))
save("skid", x, "tyres sliding (loop)", "narrow bands of noise that waver")

# a bicycle: the freewheel ticking (pitched by speed) and the chain when pedalling
s = 1.0
x = np.zeros(int(s * SR))
for k in range(24):
    at = int(k * SR / 24.0)
    m = 220
    x[at:at + m] += np.random.default_rng(k).normal(size=m) * env(m, 0.0003, 0.0025) * np.sin(2 * np.pi * 4200 * np.arange(m) / SR + k)
save("freewheel", x, "a bicycle's freewheel ticking (loop)", "twenty-four small clicks a second", 0.4)
s = 1.0
x = 0.5 * noise(s, band(1200, 5000, 0.5)) * (0.6 + 0.4 * np.sin(2 * np.pi * 12 * t_of(s)) ** 2)
save("chain", x, "a bicycle chain running (loop)", "a soft rattle", 0.3)

# a wheel on the road: the roll of tyres, for everything that drives
s = 3.0
x = noise(s, lambda f: band(90, 1400, 0.9)(f) * pink(f)) * swell(s, 6, 0.15)
save("roll", x, "tyres rolling on a road (loop)", "low noise")

# landing after a jump, and a car door
n = int(0.5 * SR)
t = np.arange(n) / SR
x = np.sin(2 * np.pi * (70 - 60 * t) * t) * np.exp(-t / 0.07) + 0.5 * noise(0.5, band(150, 1800)) * env(n, 0.002, 0.05)
save("thump", x, "a vehicle landing", "a low falling tone and a knock")
n = int(0.45 * SR)
t = np.arange(n) / SR
x = np.zeros(n)
x += noise(0.45, band(1500, 6000)) * env(n, 0.0005, 0.006) * 0.8                                   # the latch
late = int(0.09 * SR)
x[late:] += (np.sin(2 * np.pi * 110 * t[:n - late]) * np.exp(-t[:n - late] / 0.045) + 0.6 * noise(0.45, band(200, 1500))[:n - late] * env(n - late, 0.002, 0.03))
save("door", x, "a car door", "a click, then a thud")

with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
    f.write("# Sounds\n\nEvery sound here is made by `tools/make_sounds.py` from noise and tones: nothing is recorded or taken from\n"
            "anywhere, so there is no licence to follow. They are part of this project, like its code.\n\n| file | what it is | how it is made |\n|---|---|---|\n")
    for name, what, how in made:
        f.write("| `%s` | %s | %s |\n" % (name, what, how))
size = sum(os.path.getsize(os.path.join(OUT, m[0])) for m in made)
print("sounds: %d files, %.1f MB" % (len(made), size / 1e6))
