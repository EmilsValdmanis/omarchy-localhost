import unittest

from lint_qml import upstream_metadata


class QmlLintAllowlistTests(unittest.TestCase):
    def test_only_known_dynamic_theme_members_are_allowed(self):
        warning = {"id": "missing-property", "message": 'Member "caption" not found on type "QObject"'}
        self.assertTrue(upstream_metadata(warning, "font.pixelSize: Style.font.caption"))
        self.assertFalse(upstream_metadata(warning, "font.pixelSize: server.caption"))
        warning["message"] = 'Member "captino" not found on type "QObject"'
        self.assertFalse(upstream_metadata(warning, "font.pixelSize: Style.font.captino"))

    def test_layout_and_unresolved_import_warnings_are_never_allowed(self):
        for code in ("Quick.layout-positioning", "import", "unresolved-type", "unqualified"):
            self.assertFalse(upstream_metadata({"id": code, "message": "problem"}, "Style.font.caption"))

    def test_backend_exception_is_specific_to_panel_window(self):
        self.assertTrue(upstream_metadata({"id": "uncreatable-type", "message": "Type PanelWindow is not creatable."}, ""))
        self.assertFalse(upstream_metadata({"id": "uncreatable-type", "message": "Type Widget is not creatable."}, ""))


if __name__ == "__main__":
    unittest.main()
