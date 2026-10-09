#!/usr/bin/env python3
"""Export App Store previews from native simulator recordings (FFmpeg required)."""

import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw_directory", type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--output", type=Path, default=Path("AppStorePreviews"))
    args = parser.parse_args()
    # Keep UI actions at their original speed; cut pauses between demonstrations.
    edits = {
        "iPhone/01-log-workout": [("iphone-log", 0, 13), ("iphone-log", 23, 29)],
        "iPhone/02-training-journey": [("iphone-journey", 1, 10), ("iphone-journey", 13, 28)],
        "iPhone/03-exercise-progress": [("iphone-discover-good", 0, 7),
            ("iphone-discover-good", 16, 23), ("iphone-chart", 2, 12)],
        "iPad/01-log-workout": [("ipad-log", 0, 12), ("ipad-log", 17, 31)],
        "iPad/02-training-journey": [("ipad-journey", 1, 14), ("ipad-journey", 28, 40)],
        "iPad/03-exercise-progress": [("ipad-discover", 0, 25)],
    }
    for name, segments in edits.items():
        destination = args.output / (name + ".mp4")
        destination.parent.mkdir(parents=True, exist_ok=True)
        width, height = (886, 1920) if name.startswith("iPhone/") else (1200, 1600)
        command = [args.ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
        filters = []
        for index, (source, start, end) in enumerate(segments):
            command += ["-i", str(args.raw_directory / (source + ".mp4"))]
            filters.append(f"[{index}:v]trim=start={start}:end={end},setpts=PTS-STARTPTS[v{index}]")
        # An AAC stereo track provides a valid silent preview without licensed music.
        command += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        inputs = "".join(f"[v{i}]" for i in range(len(segments)))
        filters.append(f"{inputs}concat=n={len(segments)}:v=1:a=0,"
            f"scale={width}:{height}:force_original_aspect_ratio=decrease:force_divisible_by=2,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[out]")
        duration = sum(end - start for _, start, end in segments)
        command += ["-filter_complex", ";".join(filters), "-map", "[out]",
            "-map", f"{len(segments)}:a", "-t", str(duration),
            "-c:v", "libx264", "-preset", "medium", "-profile:v", "high", "-level:v", "4.0",
            "-pix_fmt", "yuv420p", "-b:v", "10M", "-maxrate", "12M", "-bufsize", "20M",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart",
            str(destination)]
        subprocess.run(command, check=True)
        print(f"{destination}: {width} × {height}, {duration} seconds", flush=True)


if __name__ == "__main__":
    main()
