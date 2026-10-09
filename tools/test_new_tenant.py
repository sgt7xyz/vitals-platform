import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import new_tenant  # noqa: E402


class NewTenantTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def run_tool(self, *args):
        return new_tenant.main(list(args), tenants_dir=self.dir)

    def test_creates_all_files_and_index(self):
        rc = self.run_tool("--team", "genomics", "--owner", "alice@example.com")
        self.assertEqual(rc, 0)
        files = sorted(p.name for p in (self.dir / "genomics").iterdir())
        self.assertIn("resourcequota.yaml", files)
        self.assertIn("kustomization.yaml", files)
        ns = (self.dir / "genomics" / "namespace.yaml").read_text()
        self.assertIn("name: team-genomics", ns)
        index = (self.dir / "kustomization.yaml").read_text()
        self.assertIn("  - genomics\n", index)

    def test_index_is_sorted_across_runs(self):
        self.run_tool("--team", "imaging", "--owner", "b@example.com")
        self.run_tool("--team", "genomics", "--owner", "a@example.com")
        index = (self.dir / "kustomization.yaml").read_text()
        self.assertLess(index.index("genomics"), index.index("imaging"))

    def test_rejects_duplicate(self):
        self.run_tool("--team", "genomics", "--owner", "a@example.com")
        self.assertEqual(self.run_tool("--team", "genomics", "--owner", "a@example.com"), 1)

    def test_rejects_bad_input(self):
        self.assertEqual(self.run_tool("--team", "Bad_Name", "--owner", "a@example.com"), 2)
        self.assertEqual(self.run_tool("--team", "ok", "--owner", "not-an-email"), 2)
        self.assertEqual(self.run_tool("--team", "ok", "--owner", "a@example.com", "--memory", "4GB"), 2)
        self.assertFalse((self.dir / "ok").exists())

    def test_quota_values_are_rendered(self):
        self.run_tool("--team", "ml", "--owner", "a@example.com", "--cpu", "500m", "--memory", "2Gi")
        quota = (self.dir / "ml" / "resourcequota.yaml").read_text()
        self.assertIn('requests.cpu: "500m"', quota)
        self.assertIn("requests.memory: 2Gi", quota)


if __name__ == "__main__":
    unittest.main()
