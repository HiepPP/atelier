import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock
from types import SimpleNamespace
from contextlib import redirect_stderr, redirect_stdout


SCRIPT = Path(__file__).resolve().parents[1] / "atelier-doctor"
LOADER = importlib.machinery.SourceFileLoader("atelier_doctor", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
doctor = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(doctor)


class AtelierDoctorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="atelier-doctor-tests-")
        self.cache_root = Path(self.temporary.name)
        self.runtime = doctor.runtime_directory(self.cache_root)
        self.runtime.mkdir(parents=True)
        self.now = datetime(2026, 7, 21, 12, tzinfo=timezone.utc)

    def tearDown(self):
        self.temporary.cleanup()

    def write_snapshot(self, generated_at=None):
        snapshot = {
            "schemaVersion": 1,
            "generatedAt": (generated_at or self.now).isoformat(),
            "process": {"cpuPercent": 1, "physicalFootprintBytes": 100},
            "mainThread": {"heartbeatAgeMs": 10},
            "workspace": {"selectedTabKind": "file"},
            "editor": {"scrollInputsWindow": 0, "boundsChangesWindow": 0},
            "verdicts": [],
        }
        (self.runtime / "snapshot.json").write_text(json.dumps(snapshot), encoding="utf-8")

    def test_stopped_status_has_distinct_exit_code(self):
        value, code = doctor.load_status(self.cache_root, pid_finder=lambda: None)
        self.assertEqual(code, doctor.EXIT_APP_STOPPED)
        self.assertEqual(value["status"], "stopped")

    def test_running_without_snapshot_is_degraded(self):
        value, code = doctor.load_status(self.cache_root, pid_finder=lambda: 42)
        self.assertEqual(code, doctor.EXIT_SNAPSHOT_MISSING)
        self.assertEqual(value["status"], "degraded")

    def test_fresh_snapshot_is_healthy(self):
        self.write_snapshot()
        value, code = doctor.load_status(
            self.cache_root,
            pid_finder=lambda: 42,
            now=lambda: self.now,
        )
        self.assertEqual(code, 0)
        self.assertEqual(value["status"], "healthy")

    def test_stale_snapshot_adds_verdict(self):
        self.write_snapshot(self.now - timedelta(seconds=10))
        value, code = doctor.load_status(
            self.cache_root,
            pid_finder=lambda: 42,
            now=lambda: self.now,
        )
        self.assertEqual(code, 0)
        self.assertEqual(value["status"], "stale")
        self.assertEqual(value["snapshot"]["verdicts"][-1]["code"], "diagnosticsStale")

    def test_malformed_snapshot_is_degraded(self):
        (self.runtime / "snapshot.json").write_text("{broken", encoding="utf-8")
        value, code = doctor.load_status(self.cache_root, pid_finder=lambda: 42)
        self.assertEqual(code, doctor.EXIT_SNAPSHOT_INVALID)
        self.assertEqual(value["status"], "degraded")

    def test_capture_keeps_partial_collector_results(self):
        self.write_snapshot()
        artifact = self.cache_root / "artifact"
        artifact.mkdir()
        degraded = {
            "command": ["collector"],
            "status": "degraded",
            "exitCode": 1,
            "output": "missing",
            "stderr": "fixture failure",
        }
        with mock.patch.object(doctor, "run_collector", return_value=degraded), mock.patch.object(
            doctor, "recent_reports", return_value=[]
        ):
            collectors = doctor.collect_capture(42, 1, self.runtime, artifact)
        self.assertEqual(collectors["snapshot.json"]["status"], "ok")
        self.assertEqual(collectors["flight-recorder.json"]["status"], "degraded")
        self.assertEqual(collectors["sample"]["status"], "degraded")
        self.assertTrue((artifact / "diagnostic-reports.json").exists())

    def test_probe_matches_swift_uppercase_uuid(self):
        request_id = uuid.UUID("846ba56d-c603-46fa-b0a3-717d6f7d02dc")
        response = {
            "schemaVersion": 1,
            "id": str(request_id).upper(),
            "command": "main",
            "status": "ok",
        }
        (self.runtime / "response.json").write_text(json.dumps(response), encoding="utf-8")
        args = SimpleNamespace(probe_command="main", delta=400, restore=False)
        with mock.patch.object(doctor, "load_status", return_value=({"pid": 42}, 0)), mock.patch.object(
            doctor, "runtime_directory", return_value=self.runtime
        ), mock.patch.object(doctor.uuid, "uuid4", return_value=request_id):
            with redirect_stdout(io.StringIO()):
                code = doctor.command_probe(args)
        self.assertEqual(code, 0)

    def test_chrome_probe_writes_a_request_and_reports_panels(self):
        request_id = uuid.UUID("2f1c9d0e-7b64-4d21-9a5f-0c8e2b3a4d55")
        response = {
            "schemaVersion": 1,
            "id": str(request_id),
            "command": "chrome",
            "status": "ok",
            "result": {
                "selectedSidebarTab": "Git",
                "showsSidebar": True,
                "showsInspector": False,
                "sessionCount": 2,
                "sessionsInSync": True,
            },
        }
        (self.runtime / "response.json").write_text(json.dumps(response), encoding="utf-8")
        args = SimpleNamespace(probe_command="chrome", delta=400, restore=False)
        with mock.patch.object(doctor, "load_status", return_value=({"pid": 42}, 0)), mock.patch.object(
            doctor, "runtime_directory", return_value=self.runtime
        ), mock.patch.object(doctor.uuid, "uuid4", return_value=request_id):
            stream = io.StringIO()
            with redirect_stdout(stream):
                code = doctor.command_probe(args)
        request = json.loads((self.runtime / "request.json").read_text(encoding="utf-8"))
        self.assertEqual(code, 0)
        self.assertEqual(request["command"], "chrome")
        self.assertEqual(request["arguments"], {})
        self.assertEqual(json.loads(stream.getvalue())["result"]["selectedSidebarTab"], "Git")

    def test_probe_rejects_an_unknown_command(self):
        parser = doctor.build_parser()
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            parser.parse_args(["probe", "sidebar"])


if __name__ == "__main__":
    unittest.main()
