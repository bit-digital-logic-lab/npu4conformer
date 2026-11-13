"""Offline recovery tests; hardware operations are mocked and never invoked."""
from contextlib import nullcontext
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import restore_assets as assets


class AssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "asr_v1"
        self.root.mkdir()
        self.archive = self.base / "assets.zip"
        with zipfile.ZipFile(self.archive, "w") as bundle:
            bundle.writestr("asr_v1/work/a.bin", b"fixed model")
        import hashlib
        self.manifest = dict(bytes=self.archive.stat().st_size, sha256=assets.sha(self.archive),
                             files={"work/a.bin": dict(bytes=11, sha256=hashlib.sha256(b"fixed model").hexdigest())})
        self.save_manifest()

    def save_manifest(self):
        (self.root / "release_assets.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def test_restore_and_idempotent(self):
        self.assertEqual(assets.restore(self.archive, self.root)["restored"], 1)
        self.assertTrue(assets.audit(self.root)["passed"])
        self.assertEqual(assets.restore(self.archive, self.root)["restored"], 0)

    def test_missing_report(self):
        self.assertEqual(assets.audit(self.root)["missing"], ["work/a.bin"])

    def test_conflicting_file_is_preserved(self):
        target = self.root / "work/a.bin"
        target.parent.mkdir()
        target.write_bytes(b"user data")
        with self.assertRaises(ValueError):
            assets.restore(self.archive, self.root)
        self.assertEqual(target.read_bytes(), b"user data")

    def test_corrupt_archive_does_not_extract(self):
        with self.archive.open("ab") as stream:
            stream.write(b"corrupted")
        with self.assertRaises(ValueError):
            assets.restore(self.archive, self.root)
        self.assertFalse((self.root / "work").exists())

    def test_wrong_member_hash_does_not_publish(self):
        self.manifest["files"]["work/a.bin"]["sha256"] = "0" * 64
        self.save_manifest()
        with self.assertRaises(ValueError):
            assets.restore(self.archive, self.root)
        self.assertFalse((self.root / "work/a.bin").exists())

    def test_escape_is_rejected(self):
        for name in ("../escape", "/absolute", "C:/escape", "work\\escape"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                assets.destination(self.root, name)

    def test_duplicate_archive_is_rejected(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            with zipfile.ZipFile(self.archive, "a") as bundle:
                bundle.writestr("asr_v1/work/a.bin", b"fixed model")
        self.manifest.update(bytes=self.archive.stat().st_size, sha256=assets.sha(self.archive))
        self.save_manifest()
        with self.assertRaises(ValueError):
            assets.restore(self.archive, self.root)


class CommissionFailureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(assets.ROOT / "work/v024_ddr_resident"))
        import cold_start
        cls.cold = cold_start

    def test_preflight_failure_preserves_old_state(self):
        with patch.object(self.cold, "preflight", side_effect=ValueError("missing attachment")), \
                patch.object(self.cold.deploy, "command") as command:
            with self.assertRaises(ValueError):
                self.cold.run()
            command.assert_not_called()

    def test_hardware_failure_invalidates_but_archives_old_pointers(self):
        with tempfile.TemporaryDirectory() as folder:
            here = Path(folder)
            pointers = [here / "board_test/active_qualification.json",
                        here / "native_model/ACTIVE_BOARD_WEIGHTS.json"]
            for p in pointers:
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text("old evidence", encoding="utf-8")
            with patch.object(self.cold, "HERE", here), patch.object(self.cold, "preflight"), \
                    patch.object(self.cold.deploy, "_board_lock", return_value=nullcontext()), \
                    patch.object(self.cold.deploy, "ensure_server"), \
                    patch.object(self.cold.deploy, "command", side_effect=RuntimeError("fixture DDR failure")), \
                    patch.object(self.cold, "activate") as activate:
                with self.assertRaises(RuntimeError):
                    self.cold.run()
                activate.assert_not_called()
            for p in pointers:
                self.assertFalse(p.exists())
                self.assertEqual(next(p.parent.glob(p.name + ".stale.*")).read_text(), "old evidence")
            report = next(here.glob("cold_start_runs/*/result.json"))
            self.assertFalse(json.loads(report.read_text())["passed"])

    def test_archived_build_records_are_accepted_but_not_copied_to_live_state(self):
        result = self.cold.deploy.validate_image()
        self.assertEqual(result.name, "candidate_A51A2493.bit")
        for name in ("board_test/active_qualification.json", "native_model/ACTIVE_BOARD_WEIGHTS.json"):
            self.assertFalse((self.cold.HERE / name).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
