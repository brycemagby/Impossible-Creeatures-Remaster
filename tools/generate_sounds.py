#!/usr/bin/env python3
"""Synthesises the game's placeholder sound effects: cartoonish boings, bonks,
slide whistles, kazoos and gibberish creature voices, in the goofy spirit of
the original.

Run from the repository root:  python3 tools/generate_sounds.py
Writes 16-bit mono WAVs to assets/sounds/. Needs numpy. Human-made sounds can
replace any file one for one (scripts/autoload/sfx.gd lists them).
"""
import math
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
RATE = 22050

# Vowel formants (Hz) for the gibberish voices.
VOWELS = {
    "a": (800, 1150, 2900),
    "e": (400, 1700, 2600),
    "i": (300, 2200, 3000),
    "o": (450, 800, 2830),
    "u": (325, 700, 2530),
    "w": (300, 610, 2200),
}


def t_axis(duration):
    return np.arange(int(RATE * duration)) / RATE


def curve(points, n):
    """Piecewise-linear curve through (time fraction, value) points, n samples."""
    xs, ys = zip(*points)
    return np.interp(np.linspace(0, 1, n), xs, ys)


def envelope(n, attack=0.01, release=0.08):
    env = np.ones(n)
    a, r = int(RATE * attack), int(RATE * release)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def phase(freq):
    return 2 * np.pi * np.cumsum(freq) / RATE


def voice(duration, pitch, vowels, buzz=0.0, vibrato=0.0, growl=0.0):
    """A cartoon voice: harmonics of [param pitch] (a (fraction, Hz) curve)
    weighted by moving vowel formants. [param vowels] is a list of
    (fraction, vowel letter) points."""
    n = int(RATE * duration)
    f0 = curve(pitch, n)
    t = t_axis(duration)
    if vibrato:
        f0 = f0 * (1 + vibrato * np.sin(2 * np.pi * 7 * t))
    formants = [curve([(x, VOWELS[v][k]) for x, v in vowels], n) for k in range(3)]
    out = np.zeros(n)
    ph = phase(f0)
    for h in range(1, 40):
        fh = f0 * h
        weight = sum(np.exp(-((fh - f) / (90 + 0.12 * f)) ** 2) * g
                     for f, g in zip(formants, (1.0, 0.6, 0.25)))
        weight = weight + 0.04 / h
        weight[fh > RATE / 2.2] = 0
        out += weight * np.sin(h * ph)
    if buzz:
        out += buzz * np.sign(np.sin(ph)) * 0.15
    if growl:
        out *= 1 - growl * (0.5 + 0.5 * np.sin(2 * np.pi * 32 * t))
    return out * envelope(n, 0.015, 0.06)


def tone(duration, freq, shape="sine", vibrato=0.0, vib_rate=6.0):
    n = int(RATE * duration)
    f = curve(freq, n) if isinstance(freq, list) else np.full(n, float(freq))
    t = t_axis(duration)
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * vib_rate * t))
    ph = phase(f)
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.5
    if shape == "saw":
        return ((ph / (2 * np.pi)) % 1.0) * 2 - 1
    if shape == "triangle":
        return 2 * np.abs(((ph / (2 * np.pi)) % 1.0) * 2 - 1) - 1
    return np.sin(ph)


def noise(duration, seed=1):
    return np.random.default_rng(seed).uniform(-1, 1, int(RATE * duration))


def decay(n, rate):
    return np.exp(-np.arange(n) / RATE * rate)


def concat(*parts, gap=0.0):
    silence = np.zeros(int(RATE * gap))
    out = []
    for p in parts:
        out += [p, silence]
    return np.concatenate(out[:-1]) if out else np.zeros(0)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def kazoo(duration, freq, vowel="u"):
    return voice(duration, [(0, freq), (1, freq)], [(0, vowel), (1, vowel)], buzz=1.2, vibrato=0.012)


def save(name, samples, volume=0.8):
    samples = np.asarray(samples, dtype=float)
    peak = np.max(np.abs(samples)) or 1.0
    data = (samples / peak * volume * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


# --- The sounds ---------------------------------------------------------------

def creature_voices():
    # Selection: questioning gibberish ("hwee?", "bwah?", "oo-ee?").
    save("select_1", voice(0.28, [(0, 260), (0.6, 300), (1, 420)], [(0, "w"), (0.35, "e"), (1, "i")]))
    save("select_2", voice(0.32, [(0, 220), (0.5, 210), (1, 330)], [(0, "w"), (0.3, "a"), (1, "a")]))
    save("select_3", concat(voice(0.14, [(0, 300), (1, 280)], [(0, "o"), (1, "u")]),
                            voice(0.18, [(0, 320), (1, 460)], [(0, "e"), (1, "i")]), gap=0.03))
    # Move orders: cheerful "hup!" and "okey!".
    save("move_1", voice(0.18, [(0, 340), (0.3, 380), (1, 260)], [(0, "u"), (0.4, "u"), (1, "o")]))
    save("move_2", concat(voice(0.12, [(0, 300), (1, 310)], [(0, "o"), (1, "o")]),
                          voice(0.16, [(0, 380), (1, 300)], [(0, "e"), (1, "i")]), gap=0.02))
    # Attack orders: growly "rarr!" and "hyah!".
    save("attack_1", voice(0.34, [(0, 170), (0.3, 210), (1, 120)], [(0, "w"), (0.25, "a"), (1, "o")], growl=0.7))
    save("attack_2", voice(0.26, [(0, 240), (0.4, 300), (1, 180)], [(0, "i"), (0.3, "a"), (1, "a")], growl=0.4))


def combat():
    # Melee hit: a cartoon bonk.
    n = int(RATE * 0.22)
    bonk = tone(0.22, [(0, 420), (0.15, 160), (1, 110)]) * decay(n, 18)
    click = noise(0.22, 2) * decay(n, 120) * 0.6
    save("hit", mix(bonk, click), 0.7)
    # Ranged shot: "pew".
    n = int(RATE * 0.16)
    save("shoot", tone(0.16, [(0, 1400), (1, 380)], "square") * decay(n, 14), 0.45)
    # Death: a descending slide whistle and a plop.
    whistle = tone(0.55, [(0, 1100), (1, 260)], vibrato=0.02) * envelope(int(RATE * 0.55), 0.02, 0.1)
    n = int(RATE * 0.12)
    plop = tone(0.12, [(0, 200), (1, 600)]) * decay(n, 30)
    save("death", concat(whistle, plop, gap=0.02), 0.65)


def base():
    # Building finished: a ratchet then a ding.
    ratchet = np.concatenate([np.concatenate([noise(0.012, i) * decay(int(RATE * 0.012), 300),
                                              np.zeros(int(RATE * 0.035))]) for i in range(1, 6)])
    n = int(RATE * 0.8)
    ding = (tone(0.8, 1320) + 0.5 * tone(0.8, 2640) + 0.25 * tone(0.8, 3960 * 1.01)) * decay(n, 5)
    save("building_done", concat(ratchet * 0.6, ding), 0.6)
    # Placing a building: a wooden thunk.
    n = int(RATE * 0.18)
    save("place", mix(tone(0.18, [(0, 180), (1, 90)]) * decay(n, 25), noise(0.18, 9) * decay(n, 80) * 0.4), 0.7)
    # Unit ready: pop and a rising chirp.
    n = int(RATE * 0.08)
    pop = tone(0.08, [(0, 300), (1, 900)]) * decay(n, 40)
    chirp = voice(0.22, [(0, 380), (1, 620)], [(0, "o"), (1, "i")])
    save("unit_ready", concat(pop, chirp, gap=0.01), 0.7)
    # Research done: a kazoo arpeggio.
    notes = [262, 330, 392, 523]
    save("research_done", concat(*[kazoo(0.13 if i < 3 else 0.35, f) for i, f in enumerate(notes)], gap=0.01), 0.7)
    # Move-order boing (also used for rally points).
    n = int(RATE * 0.4)
    save("boing", tone(0.4, [(0, 140), (0.1, 320), (1, 260)], vibrato=0.08, vib_rate=14) * decay(n, 7), 0.5)


def interface():
    # Button click: a wood-block tick.
    n = int(RATE * 0.05)
    save("click", (tone(0.05, 1800) * 0.6 + noise(0.05, 4) * 0.4) * decay(n, 90), 0.4)
    # Error: a deflated two-note "bwomp".
    save("error", concat(kazoo(0.12, 233, "o"), kazoo(0.22, 175, "o"), gap=0.01), 0.6)
    # Under attack: an "awooga" klaxon.
    awooga = tone(0.45, [(0, 180), (0.6, 330), (1, 300)], "square") + 0.5 * tone(0.45, [(0, 182), (0.6, 334), (1, 304)], "saw")
    awooga *= envelope(len(awooga), 0.02, 0.08)
    save("alert", concat(awooga, awooga, gap=0.08), 0.55)
    # Victory: kazoo fanfare. Defeat: sad trombone.
    fanfare = [(392, 0.12), (392, 0.12), (392, 0.12), (523, 0.5), (466, 0.14), (523, 0.6)]
    save("victory", concat(*[kazoo(d, f, "a") for f, d in fanfare], gap=0.03), 0.7)
    trombone = [(294, 0.35), (277, 0.35), (262, 0.35)]
    parts = [voice(d, [(0, f), (1, f)], [(0, "w"), (0.4, "a"), (1, "o")], buzz=1.0) for f, d in trombone]
    parts.append(voice(1.1, [(0, 247), (1, 240)], [(0, "w"), (0.2, "a"), (1, "o")], buzz=1.0, vibrato=0.03))
    save("defeat", concat(*parts, gap=0.06), 0.7)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    creature_voices()
    combat()
    base()
    interface()
    print("wrote sounds to", os.path.normpath(OUT))
