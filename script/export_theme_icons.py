#!/usr/bin/env python3
"""Export theme variants of the existing X2 Icon Composer artwork with Apple's renderer."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Two-stop backgrounds in the app's Apple color families. Blue retains the
# original artwork's gradient. Shapes, materials, lighting, and shadows are shared.
GRADIENTS = {
    "blue": ((0.10, 0.72, 0.98), (0.00, 0.33, 1.00)),
    "purple": ((0.78, 0.45, 0.98), (0.52, 0.20, 0.76)),
    "pink": ((1.00, 0.45, 0.66), (0.94, 0.11, 0.35)),
    "red": ((1.00, 0.42, 0.34), (0.82, 0.10, 0.12)),
    "orange": ((1.00, 0.69, 0.21), (1.00, 0.40, 0.04)),
    "yellow": ((1.00, 0.90, 0.30), (0.96, 0.67, 0.03)),
    "green": ((0.40, 0.87, 0.39), (0.16, 0.65, 0.26)),
    "graphite": ((0.67, 0.69, 0.73), (0.36, 0.38, 0.42)),
}


def main():
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    tool = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    if not tool.is_file():
        raise SystemExit("Icon Composer's export tool is missing from the selected Xcode.")
    source = ROOT / "Tapster/Resources/Textend.icon"
    catalog = ROOT / "Tapster/Resources/Assets.xcassets"
    with tempfile.TemporaryDirectory(prefix="textend-theme-icons-") as temporary:
        document = Path(temporary) / "Theme.icon"
        shutil.copytree(source, document)
        original = json.loads((source / "icon.json").read_text())
        for color, stops in GRADIENTS.items():
            variant = dict(original)
            variant["fill"] = {"linear-gradient": [
                "srgb:" + ",".join(f"{value:.5f}" for value in (*stop, 1.0))
                for stop in stops
            ]}
            (document / "icon.json").write_text(json.dumps(variant, indent=2) + "\n")
            image = Path(temporary) / f"{color}.png"
            subprocess.run([
                str(tool), str(document), "--export-image", "--output-file", str(image),
                "--platform", "macOS", "--rendition", "Default", "--width", "1024",
                "--height", "1024", "--scale", "1", "--design-generation", "27",
            ], check=True)
            asset = catalog / f"ThemeIcon-{color}.imageset"
            asset.mkdir(exist_ok=True)
            shutil.copyfile(image, asset / "icon.png")
            contents = {
                "images": [{"filename": "icon.png", "idiom": "mac", "scale": "1x"}],
                "info": {"author": "xcode", "version": 1},
            }
            (asset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
            print(f"Exported {color}", flush=True)


if __name__ == "__main__":
    main()
