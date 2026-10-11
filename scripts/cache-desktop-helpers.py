#!/usr/bin/env python3
"""Build copied Desktop helpers so CI can publish their runtime closures."""

import json
import subprocess
import sys


def helper_drvs(document):
    # Nix 2.34 uses a versioned envelope and store-relative derivation keys;
    # older Nix emits absolute keys and an inputDrvs attribute.
    derivations = document.get("derivations", document)
    helpers = set()
    for derivation in derivations.values():
        inputs = derivation.get("inputDrvs")
        if inputs is None:
            inputs = derivation["inputs"]["drvs"]
        for path in inputs:
            name = path.rsplit("/", 1)[-1]
            if "-codex-desktop-feature-helpers-" in name and name.endswith(".drv"):
                helpers.add(path if path.startswith("/") else "/nix/store/" + path)
    if not helpers:
        raise ValueError("Desktop derivation has no feature helper input")
    return helpers


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: cache-desktop-helpers.py DESKTOP_INSTALLABLE ...")
    helpers = set()
    for desktop in sys.argv[1:]:
        document = json.loads(subprocess.check_output(
            ["nix", "derivation", "show", desktop], text=True
        ))
        helpers.update(helper_drvs(document))
    subprocess.run([
        "nix", "build", "--no-link", "--print-out-paths", "-L",
        *(path + "^out" for path in sorted(helpers)),
    ], check=True)


if __name__ == "__main__":
    main()
