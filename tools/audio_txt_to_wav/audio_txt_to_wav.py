#!/usr/bin/env python3
"""Convert md_sound_module text audio samples to a 16-bit stereo WAV file."""

import argparse
import struct
import wave


def clamp_i16(value):
    return max(-32768, min(32767, value))


def convert(input_path, output_path, sample_rate, gain):
    sample_count = 0

    with open(input_path, "r", encoding="utf-8") as src, wave.open(output_path, "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)

        for line_number, line in enumerate(src, start=1):
            line = line.strip()
            if not line:
                continue

            parts = line.split()
            if len(parts) != 2:
                raise ValueError(f"{input_path}:{line_number}: expected two integers")

            left = clamp_i16(round(int(parts[0], 10) * gain))
            right = clamp_i16(round(int(parts[1], 10) * gain))
            wav.writeframesraw(struct.pack("<hh", left, right))
            sample_count += 1

    print(
        f"wrote {sample_count} stereo samples to {output_path} "
        f"at {sample_rate} Hz, gain {gain:g}"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Convert /tmp/md_sound_audio.txt to a 16-bit stereo WAV."
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="/tmp/md_sound_audio.txt",
        help="input text file, default: /tmp/md_sound_audio.txt",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default="/tmp/md_sound_audio.wav",
        help="output WAV file, default: /tmp/md_sound_audio.wav",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=44100,
        help="WAV sample rate in Hz, default: 44100",
    )
    parser.add_argument(
        "--gain",
        type=float,
        default=1.0,
        help="linear gain multiplier before 16-bit clipping, default: 1.0",
    )
    args = parser.parse_args()

    convert(args.input, args.output, args.sample_rate, args.gain)


if __name__ == "__main__":
    main()
