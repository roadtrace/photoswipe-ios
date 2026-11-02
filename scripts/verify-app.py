"""Fail packaging if Xcode produced a simulator app or an incomplete device app."""
import plistlib
import subprocess
import sys
from pathlib import Path


def verify(app):
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundlePackageType") != "APPL":
        raise ValueError("Expected an iOS application")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Expected an iPhoneOS device build, not a simulator build")
    for key in ("CFBundleIdentifier", "CFBundleExecutable", "MinimumOSVersion",
                "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"):
        if not info.get(key):
            raise ValueError(f"Missing required Info.plist key: {key}")
    executable = app / info["CFBundleExecutable"]
    if executable.parent != app or not executable.is_file():
        raise ValueError("App executable is missing or outside the app bundle")
    subprocess.run(["xcrun", "lipo", "-verify_arch", "arm64", str(executable)], check=True)
    load_commands = subprocess.check_output(
        ["xcrun", "otool", "-l", str(executable)], text=True)
    for line in load_commands.splitlines():
        fields = line.split()
        if fields[:1] == ["cryptid"] and fields[1:] != ["0"]:
            raise ValueError("Encrypted binaries cannot be re-signed by SideStore")
    print(f"Verified device app: {info['CFBundleIdentifier']}, iOS {info['MinimumOSVersion']}+")


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve())
