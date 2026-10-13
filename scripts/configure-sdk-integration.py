"""Create an ignored local-only SDK override and a reproducible provenance file."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sdk", type=Path)
    parser.add_argument("--sha", required=True)
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    actual = subprocess.check_output(
        ["git", "-C", str(sdk), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual != args.sha:
        raise SystemExit(f"SDK revision mismatch: expected {args.sha}, got {actual}")
    packages = ("dakit_core", "dakit_api", "dakit_web", "dakit_flutter")
    lines = ["dependency_overrides:", "  html: 0.15.6"]
    for package in packages:
        path = sdk / "packages" / package
        if not (path / "pubspec.yaml").is_file():
            raise SystemExit(f"Missing SDK package: {package}")
        lines.extend([f"  {package}:", f"    path: {json.dumps(path.as_posix())}"])
    Path("pubspec_overrides.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    app_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    Path("sdk-integration-provenance.json").write_text(
        json.dumps({"daviewer_sha": app_sha, "dakit_sha": actual,
                    "candidate_only": True, "packages": packages}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Joint candidate: DAViewer {app_sha}; DAKit {actual}")


if __name__ == "__main__":
    main()
