#!/usr/bin/env python3
"""Generate CodexNotif's original bundled notification tones."""

from __future__ import annotations

import argparse
import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
PEAK_AMPLITUDE = 0.42
EDGE_SECONDS = 0.012

TONES: dict[str, list[tuple[float, float]]] = {
    "tone_soft.wav": [(523.25, 0.18), (659.25, 0.22)],
    "tone_chime.wav": [(659.25, 0.16), (783.99, 0.16), (1046.50, 0.28)],
    "tone_alert.wav": [(880.00, 0.14), (0.0, 0.08), (880.00, 0.14)],
    "tone_phone.wav": [(440.00, 0.35), (554.37, 0.35), (659.25, 0.35)],
    "tone_hajimi.wav": [(392.00, 0.16), (493.88, 0.16), (587.33, 0.16), (783.99, 0.30)],
}


def _envelope(sample_index: int, sample_count: int) -> float:
    edge_samples = max(1, round(SAMPLE_RATE * EDGE_SECONDS))
    attack = min(1.0, sample_index / edge_samples)
    release = min(1.0, (sample_count - 1 - sample_index) / edge_samples)
    value = max(0.0, min(attack, release))
    return value * value * (3.0 - 2.0 * value)


def _render_sequence(sequence: list[tuple[float, float]]) -> bytes:
    frames = bytearray()
    phase = 0.0

    for frequency, duration in sequence:
        sample_count = round(SAMPLE_RATE * duration)
        for sample_index in range(sample_count):
            if frequency == 0.0:
                value = 0.0
            else:
                value = (
                    math.sin(phase)
                    * _envelope(sample_index, sample_count)
                    * PEAK_AMPLITUDE
                )
                phase = (phase + 2.0 * math.pi * frequency / SAMPLE_RATE) % (
                    2.0 * math.pi
                )
            frames.extend(struct.pack("<h", round(value * 32_767)))

    return bytes(frames)


def generate_tones(output: Path) -> list[Path]:
    output.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []

    for filename, sequence in TONES.items():
        path = output / filename
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(SAMPLE_RATE)
            wav_file.writeframes(_render_sequence(sequence))
        generated.append(path)

    return generated


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate deterministic original WAV tones for CodexNotif."
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Destination Android res/raw directory.",
    )
    args = parser.parse_args()

    for generated in generate_tones(args.output):
        print(generated.as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
