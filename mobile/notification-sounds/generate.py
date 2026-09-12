"""Original Unitymob sound design: soft attacks, distinct timbres, short room tails."""
import math
from pathlib import Path
import random
import shutil
import struct
import wave

ROOT = Path(__file__).resolve().parent
RATE = 44100
# start, frequency, duration, gain; each category has its own instrument.
TONES = {
    'distribution': [(0, 1046.5, .90, .76), (.115, 1567.98, 1.02, .56)],
    'pool': [(0, 392, .60, .95), (.135, 587.33, .66, .70)],
    'reminder': [(0, 659.25, .84, .68), (.29, 523.25, .90, .72)],
    'general': [(0, 783.99, .72, .80)],
}
TAU = math.tau


def voice(kind, t, frequency, noise):
    phase = TAU * frequency * t
    if kind == 'distribution':
        # Glass: FM shimmer retreats quickly, leaving a smooth, airy fundamental.
        return (math.sin(phase + .85 * math.exp(-t * 24) * math.sin(phase * 2.01)) * math.exp(-t * 6)
                + .20 * math.sin(phase * 3.98) * math.exp(-t * 15))
    if kind == 'pool':
        # Wooden pluck: inharmonic body and a tiny, soft mallet transient.
        return (math.sin(phase) * math.exp(-t * 9)
                + .32 * math.sin(phase * 2.76) * math.exp(-t * 23)
                + .10 * math.sin(phase * 5.4) * math.exp(-t * 38)
                + .09 * noise * math.exp(-t * 160))
    if kind == 'reminder':
        # Felt keys: warm overtones and a slow attack, unlike a repeated beep.
        return (math.sin(phase) * math.exp(-t * 6)
                + .24 * math.sin(phase * 2) * math.exp(-t * 10)
                + .09 * math.sin(phase * 3) * math.exp(-t * 17))
    # Soft bell: stable pitch, a warm fifth and a gentle, fading shimmer.
    return (math.sin(phase) * math.exp(-t * 8)
            + .22 * math.sin(phase * 1.5) * math.exp(-t * 11)
            + .08 * math.sin(phase * 4.01) * math.exp(-t * 24))


for category, notes in TONES.items():
    rng = random.Random(42)
    samples = [0.0] * int((max(start + duration for start, _, duration, _ in notes) + .20) * RATE)
    for start, frequency, duration, gain in notes:
        attack = .016 if category in ('reminder', 'general') else .004
        for i in range(int(duration * RATE)):
            t = i / RATE
            envelope = (1 - math.exp(-t / attack)) * min((duration - t) / .10, 1)
            samples[int(start * RATE) + i] += gain * envelope * voice(category, t, frequency, rng.uniform(-1, 1))
    # Short early reflections, not an echo sequence or a long ringtone reverb.
    dry = samples[:]
    for delay, gain in [(.029, .11), (.047, .075), (.073, .045), (.109, .025)]:
        offset = int(delay * RATE)
        for i in range(offset, len(samples)):
            samples[i] += dry[i - offset] * gain
    peak = max(abs(sample) for sample in samples)
    level = .48 if category == 'general' else .62
    samples = [sample * level / peak for sample in samples]
    assert max(abs(sample) for sample in samples) < 1
    assert 0 < len(samples) / RATE < 2
    assert abs(samples[0]) < .001 and abs(samples[-1]) < .001
    target = ROOT / f'unitymob_{category}_v1.wav'
    with wave.open(str(target), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(struct.pack('<h', round(sample * 32767)) for sample in samples))
    android = ROOT.parent / 'android/app/src/main/res/raw'
    android.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(target, android / target.name)
    print(f'{category}: {len(samples) / RATE:.2f}s')
