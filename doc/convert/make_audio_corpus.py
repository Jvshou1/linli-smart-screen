#!/usr/bin/env python3
"""Convert an uncompressed WAV file to 48 kHz, mono, signed 16-bit PCM."""

import argparse
import struct
import wave
from pathlib import Path


def decode_sample(data: bytes, width: int, offset: int) -> int:
    if width == 1:
        return (data[offset] - 128) << 8
    if width == 2:
        return struct.unpack_from("<h", data, offset)[0]
    if width == 3:
        value = int.from_bytes(data[offset : offset + 3], "little", signed=False)
        if value & 0x800000:
            value -= 1 << 24
        return value >> 8
    if width == 4:
        return struct.unpack_from("<i", data, offset)[0] >> 16
    raise ValueError(f"unsupported PCM sample width: {width} bytes")


def load_mono(path: Path) -> tuple[list[int], int]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        width = wav_file.getsampwidth()
        rate = wav_file.getframerate()
        frames = wav_file.getnframes()
        if wav_file.getcomptype() != "NONE":
            raise ValueError("only uncompressed PCM WAV files are supported")
        if channels < 1:
            raise ValueError("WAV file has no channels")
        raw = wav_file.readframes(frames)

    frame_bytes = channels * width
    mono = []
    for frame_offset in range(0, len(raw) - frame_bytes + 1, frame_bytes):
        total = 0
        for channel in range(channels):
            total += decode_sample(raw, width, frame_offset + channel * width)
        mono.append(max(-32768, min(32767, total // channels)))
    return mono, rate


def resample_linear(samples: list[int], source_rate: int, target_rate: int) -> list[int]:
    if source_rate == target_rate or len(samples) < 2:
        return samples
    output_count = (len(samples) * target_rate) // source_rate
    output = []
    for index in range(output_count):
        position_num = index * source_rate
        left = position_num // target_rate
        fraction = position_num % target_rate
        if left >= len(samples) - 1:
            value = samples[-1]
        else:
            value = (samples[left] * (target_rate - fraction) +
                     samples[left + 1] * fraction) // target_rate
        output.append(max(-32768, min(32767, value)))
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_wav", type=Path)
    parser.add_argument("output_pcm", type=Path)
    args = parser.parse_args()

    samples, source_rate = load_mono(args.input_wav)
    samples = resample_linear(samples, source_rate, 48_000)
    with args.output_pcm.open("wb") as output_file:
        for sample in samples:
            output_file.write(struct.pack("<h", sample))
    print(f"{len(samples)} samples, 48000 Hz mono, {len(samples) * 2} bytes")


if __name__ == "__main__":
    main()
