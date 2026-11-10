#!/usr/bin/env python3
"""Check the shipped app, including bridges reached only by runtime lookup."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
args = parser.parse_args()
app = args.app
assert not (app / "WolkaraMobile").exists(), "Retired mobile interface must not ship"
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info.get("UIFileSharingEnabled"), "Documents must be visible in Files"
assert info.get("LSSupportsOpeningDocumentsInPlace"), "Files must support moving the installation in place"
assert info.get("NSMicrophoneUsageDescription"), "Missing microphone permission message"
assert info.get("NSSpeechRecognitionUsageDescription"), "Missing speech permission message"
assert not info.get("CADisableMinimumFrameDurationOnPhone", False), "Unexpected 120 Hz override"
assert "audio" in info.get("UIBackgroundModes", []), "Missing background audio declaration"
for name in ("LICENSE", "NOTICE.md", "WolkaraForever-LICENSE", "ZIPFoundation-LICENSE", "Importing WoW.txt"):
    assert (app / name).is_file(), f"Missing bundled notice: {name}"
executable = app / info["CFBundleExecutable"]
symbols = subprocess.check_output(["nm", "-g", str(executable)], text=True)
assert "_TKWolkaraForeverRequestGamePlayback" in symbols, "Audio adapter hook was stripped"
# Release can strip local symbols while keeping ObjC runtime metadata. Looking
# only at nm -g would incorrectly reject perfectly usable Swift/ObjC classes.
metadata = subprocess.check_output(["otool", "-ov", str(executable)], text=True)
for name in ("TKAddonArchive", "TKForeverUIArchive", "WKSavedTextController"):
    assert re.search(r"\bname\s+0x[0-9a-f]+ " + name + r"\s", metadata), f"Missing ObjC bridge: {name}"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("APP_BUNDLE_PASS: permissions, Files access, runtime bridges, licenses, signature and standard frame-rate behavior")
