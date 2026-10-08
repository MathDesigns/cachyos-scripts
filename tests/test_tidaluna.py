"""Run with: python3 -m unittest discover -s tests -v

Execute the actual TidaLuna section in isolation. Mock network and sudo;
delegate filesystem operations and ZIP checks to real shell commands.
No root privileges, package installs, network, or Tidal runtime required.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


MOCK = r"""#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ["FAILURE"]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(command + " " + " ".join(args) + "\n")
if command == "curl":
    assert "--fail" in args and "--location" in args and "--show-error" in args
    if mode == "download":
        Path(args[args.index("-o") + 1]).write_bytes(b"partial download")
        sys.exit(22)
    import shutil
    shutil.copyfile(os.environ["ARCHIVE"], args[args.index("-o") + 1])
    sys.exit(0)
if command == "mktemp":
    if mode == "temp":
        sys.exit(1)
    sys.exit(subprocess.call(["/usr/bin/mktemp", *args]))
if command == "unzip":
    if mode == "extract" and "-tq" not in args:
        Path(args[args.index("-d") + 1], "partial").write_text("partial")
        sys.exit(1)
    sys.exit(subprocess.call(["/usr/bin/unzip", *args]))
assert command == "sudo"
operation, *rest = args
src = rest[-2] if len(rest) >= 2 else ""
dst = rest[-1] if rest else ""
fail = (
    (mode == "stage-temp" and operation == "mktemp")
    or (mode == "stage-copy" and operation == "cp" and dst.endswith("/new-app"))
    or (mode == "ownership" and operation == "chown")
    or (mode == "backup-copy" and operation == "cp" and dst.endswith("/original.asar"))
    or (mode == "backup-move" and operation == "mv" and src.endswith("/original.asar"))
    or (mode == "save-app" and operation == "mv" and dst.endswith("/previous-app"))
    or (mode == "save-asar" and operation == "mv" and dst.endswith("/previous.asar"))
    or (mode in ("publish", "rollback", "signal") and operation == "mv" and src.endswith("/new-app"))
    or (mode == "rollback" and operation == "mv" and src.endswith("/previous-app"))
)
if fail:
    if mode == "signal":
        import signal
        os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(1)
if operation == "chown":
    sys.exit(0)
status = subprocess.call(["/usr/bin/" + operation, *rest])
if mode == "signal-after-publish" and operation == "mv" and src.endswith("/new-app") and status == 0:
    import signal
    os.kill(os.getppid(), signal.SIGTERM)
sys.exit(status)
"""


class TidaLunaTests(unittest.TestCase):
    def run_install(self, mode="", layout="both", backup=True, archive="valid"):
        with tempfile.TemporaryDirectory(prefix="tidaluna-test-") as directory:
            root = Path(directory)
            resources = root / "resources with spaces"
            resources.mkdir()
            if layout in ("both", "app"):
                (resources / "app").mkdir()
                (resources / "app" / "old.txt").write_text("old app")
            if layout in ("both", "asar"):
                (resources / "app.asar").write_text("current asar")
            if backup:
                (resources / "original.asar").write_text("pristine backup")
            before = self.snapshot(resources)
            download = root / "luna.zip"
            if archive == "invalid":
                download.write_text("not a ZIP")
            else:
                with zipfile.ZipFile(download, "w") as output:
                    if archive == "valid":
                        output.writestr("package.json", '{"main":"injector.mjs"}')
                        output.writestr("injector.mjs", "new app")
                    elif archive == "wrong-layout":
                        output.writestr("nested/package.json", "{}")
            binaries = root / "bin"
            binaries.mkdir()
            for command in ("curl", "unzip", "sudo", "mktemp"):
                executable = binaries / command
                executable.write_text(MOCK)
                executable.chmod(0o755)
            scratch = root / "tmp"
            scratch.mkdir()
            log = root / "commands.log"
            script = (Path(__file__).resolve().parents[1] / "cachy-freshinstall.sh").read_text()
            section = script.split("# --- D. TidaLuna (Direct Method) ---", 1)[1]
            section = section.split("# 4. FINAL HEALTH CHECKS", 1)[0]
            section = section.replace('TIDAL_RES="/opt/tidal-hifi/resources"',
                                      'TIDAL_RES="$TEST_RESOURCES"')
            if mode == "missing":
                shutil.rmtree(resources)
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                       FAILURE=mode, ARCHIVE=str(download), COMMAND_LOG=str(log),
                       TMPDIR=str(scratch), TEST_RESOURCES=str(resources))
            result = subprocess.run(["bash"], input=section, text=True, env=env,
                                    capture_output=True, timeout=10)
            after = self.snapshot(resources) if resources.exists() else {}
            output = result.stdout + result.stderr
            commands = log.read_text() if log.exists() else ""
            self.assertEqual(list(scratch.iterdir()), [], output)
            recovery = list(resources.glob(".tidaluna.*")) if resources.exists() else []
            if mode == "missing":
                self.assertEqual(result.returncode, 0, output)
                self.assertIn("Tidal directory not found", output)
                self.assertEqual(commands, "")
            elif mode or archive != "valid":
                self.assertNotEqual(result.returncode, 0, output)
                self.assertNotIn("TidaLuna Patched.", output)
                self.assertIn("TidaLuna installation failed", output)
                if mode == "rollback":
                    self.assertEqual(len(recovery), 1, output)
                    self.assertEqual((recovery[0] / "previous-app" / "old.txt").read_text(), "old app")
                    self.assertIn(str(recovery[0]), output)
                    self.assertIn("Rollback failed", output)
                    self.assertEqual((resources / "app.asar").read_text(), "current asar")
                else:
                    # A completed pristine backup may remain after later failure.
                    if not backup and "original.asar" in after:
                        self.assertEqual(after.pop("original.asar"), b"current asar")
                    self.assertEqual(after, before, output)
                    self.assertEqual(recovery, [], output)
                if mode in ("download", "temp", "extract") or archive != "valid":
                    self.assertNotIn("sudo ", commands)
            else:
                self.assertEqual(result.returncode, 0, output)
                self.assertIn("TidaLuna Patched.", output)
                self.assertEqual(after["app/injector.mjs"], b"new app")
                self.assertNotIn("app/old.txt", after)
                self.assertNotIn("app.asar", after)
                self.assertEqual(after["original.asar"],
                                 b"pristine backup" if backup else b"current asar")
                self.assertEqual(recovery, [], output)
                self.assertLess(commands.index("unzip -tq"), commands.index("sudo "))
                self.assertLess(commands.index("unzip -q"), commands.index("sudo "))

    @staticmethod
    def snapshot(directory):
        return {str(path.relative_to(directory)): path.read_bytes()
                for path in directory.rglob("*") if path.is_file()}

    def test_success(self):
        for layout, backup in (("asar", False), ("app", True), ("both", True), ("both", False)):
            with self.subTest(layout=layout, backup=backup):
                self.run_install(layout=layout, backup=backup)

    def test_invalid_archives(self):
        for archive in ("invalid", "empty", "wrong-layout"):
            with self.subTest(archive=archive):
                self.run_install(archive=archive)

    def test_failures(self):
        for mode in ("temp", "download", "extract", "stage-temp", "stage-copy",
                     "ownership", "backup-copy", "backup-move", "save-app",
                     "save-asar", "publish", "signal", "signal-after-publish"):
            with self.subTest(mode=mode):
                self.run_install(mode=mode, backup=False)

    def test_first_install_publish_failure(self):
        self.run_install(mode="publish", layout="asar", backup=False)

    def test_existing_mod_publish_failure(self):
        self.run_install(mode="publish", layout="app")

    def test_failed_rollback_retains_recovery_files(self):
        self.run_install(mode="rollback")

    def test_missing_tidal(self):
        self.run_install(mode="missing")


if __name__ == "__main__":
    unittest.main()
