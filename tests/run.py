#!/usr/bin/env python3
"""Run contracts in a disposable Godot host, without any game globals or Logot."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

package = Path(__file__).resolve().parents[1]
godot = os.environ.get("GODOT") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"
with tempfile.TemporaryDirectory(prefix="shared-state-host-") as directory:
    host = Path(directory)
    (host / "addons").mkdir()
    (host / "addons/state_variable_system").symlink_to(package, target_is_directory=True)
    (host / "project.godot").write_text('[application]\nconfig/name="Shared state contracts"\nconfig/features=PackedStringArray("4.4")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[debug]\ngdscript/warnings/inference_on_variant=2\n[editor_plugins]\nenabled=PackedStringArray("res://addons/state_variable_system/plugin.cfg")\n')
    for arguments in (["--editor", "--import"], ["-s", "res://addons/state_variable_system/tests/contracts.gd"]):
        result = subprocess.run([godot, "--headless", "--path", str(host), *arguments], capture_output=True, text=True, timeout=90)
        print(result.stdout, end="")
        print(result.stderr, end="")
        if result.returncode or "SCRIPT ERROR" in result.stderr:
            raise SystemExit(result.returncode or 1)
