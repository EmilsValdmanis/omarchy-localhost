import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from scripts.release import github, publish, release_notes


class ReleaseNotesTests(unittest.TestCase):
    def notes(self, version, changelog):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "manifest.json").write_text(json.dumps({"version": version}))
            (root / "CHANGELOG.md").write_text(changelog)
            return release_notes(root)

    def test_extracts_only_current_version_preserving_markdown(self):
        self.assertEqual(self.notes("0.5.0", "# Changelog\n\n## 0.5.0 — 2026-09-05\n\n### Fixed\n\n- Scroll bounds.\n\n## 0.4.5\n\n- Older changes."),
                         ("v0.5.0", "### Fixed\n\n- Scroll bounds."))

    def test_requires_current_nonempty_notes_and_stable_version(self):
        for version, changelog in [("0.5.0", "## 0.4.5\nold"), ("0.5.0", "## 0.5.0\n"),
                                   ("0.5.0", "no headings"), ("01.5.0", "## 01.5.0\nnotes"),
                                   ("0.5.0-beta", "## 0.5.0-beta\nnotes")]:
            with self.subTest(version=version, changelog=changelog), self.assertRaises(ValueError):
                self.notes(version, changelog)


class PublishingTests(unittest.TestCase):
    sha = "a" * 40
    url = "https://github.com/owner/repo/releases/tag/v0.5.0"

    def api(self, release=None, tag=None, head=None, annotation=None):
        def request(method, path, payload=None):
            if method == "POST":
                return {"html_url": self.url}
            if path.endswith("/heads/main"):
                return {"object": {"sha": head or self.sha}}
            if "/releases/tags/" in path:
                return release
            if "/git/tags/" in path:
                return annotation
            return tag
        return mock.Mock(side_effect=request)

    def publish(self, api):
        return publish("owner/repo", self.sha, "v0.5.0", "- Fixed scroll", api)

    def test_creates_release_at_tested_commit_with_changelog(self):
        api = self.api()
        self.assertEqual(self.publish(api), "Published: " + self.url)
        api.assert_called_with("POST", "repos/owner/repo/releases", {
            "tag_name": "v0.5.0", "target_commitish": self.sha, "name": "Localhost v0.5.0",
            "body": "- Fixed scroll", "draft": False, "prerelease": False, "make_latest": "true",
        })

    def test_reruns_do_not_modify_existing_releases(self):
        api = self.api(release={"draft": False, "html_url": self.url})
        self.assertEqual(self.publish(api), "Already published: " + self.url)
        self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    def test_does_not_publish_stale_commit_or_existing_draft(self):
        api = self.api(head="b" * 40)
        self.assertIn("Skipped", self.publish(api))
        self.assertEqual(api.call_count, 1)
        api = self.api(release={"draft": True})
        with self.assertRaisesRegex(RuntimeError, "draft"):
            self.publish(api)

    def test_recovers_matching_tag_but_never_moves_another_commit_tag(self):
        for sha in (self.sha, "b" * 40):
            api = self.api(tag={"object": {"type": "commit", "sha": sha}})
            if sha == self.sha:
                self.assertIn("Published", self.publish(api))
            else:
                with self.assertRaisesRegex(RuntimeError, "tested commit"):
                    self.publish(api)
                self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    def test_resolves_annotated_tag(self):
        api = self.api(tag={"object": {"type": "tag", "sha": "b" * 40}},
                       annotation={"object": {"type": "commit", "sha": self.sha}})
        self.assertIn("Published", self.publish(api))

    def test_only_404_is_treated_as_missing(self):
        for status in (403, 404, 500):
            with mock.patch("scripts.release.subprocess.run", return_value=mock.Mock(
                    returncode=1, stderr=f"gh: request failed (HTTP {status})")):
                if status == 404:
                    self.assertIsNone(github("GET", "repos/owner/repo/releases/tags/v0.5.0"))
                else:
                    with self.assertRaises(RuntimeError):
                        github("GET", "repos/owner/repo/releases/tags/v0.5.0")


if __name__ == "__main__":
    unittest.main()
