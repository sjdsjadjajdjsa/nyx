"""Shared test setup: load the extension-less scripts in bin/ against a throwaway
home folder, so nothing here ever touches the real ~/.config, ~/.local/state,
~/.claude or ~/.codex."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent

# Variables that move Nyx's folders; tests set them on purpose or not at all.
PATH_VARS = ("XDG_CONFIG_HOME", "XDG_STATE_HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "NYX_API_KEY")


def load_script(name):
    """bin/<name> as a fresh module, built from the current environment (HOME and
    the XDG variables are read when the script is imported)."""
    loader = importlib.machinery.SourceFileLoader("nyx_test_" + name.replace("-", "_"), str(ROOT / "bin" / name))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


class HomeCase(unittest.TestCase):
    """A temporary HOME with the usual folders; the environment is restored afterwards."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="nyx-test-")
        self.addCleanup(tmp.cleanup)
        self.home = Path(os.path.realpath(tmp.name)) / "home"
        self.home.mkdir()
        patcher = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        patcher.start()
        self.addCleanup(patcher.stop)
        for var in PATH_VARS:
            os.environ.pop(var, None)

    def write(self, rel, text="data\n"):
        """Create a file under the temporary home and return its path."""
        path = self.home / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path
