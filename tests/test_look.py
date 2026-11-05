"""bin/nyx-look: the `space` topic's folder checks and the argument pattern."""
import contextlib
import io
import os
import sys
import unittest
from unittest import mock

from support import HomeCase, load_script


class SpaceTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.look = load_script("nyx-look")
        (self.home / "Documents").mkdir()
        self.write("Documents/big.bin", "x" * 5000)

    def refused(self, path):
        """The message `space <path>` exits with."""
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as caught:
            self.look.space(str(path))
        return str(caught.exception.code)

    def test_ordinary_folder_is_listed(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.look.space(str(self.home / "Documents"))
        self.assertIn(str(self.home / "Documents"), out.getvalue())

    def test_private_folders_are_refused(self):
        for rel in (".ssh", ".gnupg", ".config/nyx", ".local/state/nyx", ".config/environment.d", ".config/uwsm",
                    ".config/systemd", ".config/gh", ".codex", ".claude", ".local/state/omarchy/clipboard-images",
                    ".local/state/omarchy/notifications"):
            (self.home / rel / "inside").mkdir(parents=True)
            for path in (self.home / rel, self.home / rel / "inside"):
                with self.subTest(str(path)):
                    self.assertIn("private data", self.refused(path))

    def test_ways_around_the_check_are_refused(self):
        (self.home / ".config/nyx").mkdir(parents=True)
        (self.home / "shortcut").symlink_to(self.home / ".config/nyx")
        self.assertIn("private data", self.refused(self.home / "shortcut"))
        self.assertIn("private data", self.refused(self.home / "Documents/../.config/nyx"))

    def test_a_symlinked_config_folder_still_counts(self):
        real = self.home / "dotfiles/environment.d"
        real.mkdir(parents=True)
        (self.home / ".config").mkdir()
        (self.home / ".config/environment.d").symlink_to(real)
        look = load_script("nyx-look")  # PRIVATE is built when the script starts
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as caught:
            look.space(str(real))
        self.assertIn("private data", str(caught.exception.code))

    def test_xdg_folders_are_honoured(self):
        config, state = self.home / "xc", self.home / "xs"
        for path in (config / "nyx", config / "environment.d", state / "nyx"):
            path.mkdir(parents=True)
        os.environ["XDG_CONFIG_HOME"], os.environ["XDG_STATE_HOME"] = str(config), str(state)
        look = load_script("nyx-look")
        for path in (config / "nyx", config / "environment.d", state / "nyx"):
            with self.subTest(str(path)), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as c:
                look.space(str(path))
            self.assertIn("private data", str(c.exception.code))

    def test_only_home_and_a_few_system_folders(self):
        self.assertIn("only looks inside", self.refused("/etc"))
        self.assertIn("only looks inside", self.refused("/"))
        self.assertIn("only looks inside", self.refused(self.home / "Documents/../.."))

    def test_not_a_folder(self):
        self.assertIn("not a directory", self.refused(self.home / "Documents/big.bin"))
        self.assertIn("not a directory", self.refused(self.home / "missing"))


class ArgumentTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.look = load_script("nyx-look")

    def main(self, *argv):
        with mock.patch.object(sys, "argv", ["nyx-look", *argv]), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                self.look.main()
        return str(caught.exception.code)

    def test_names_must_match_the_pattern(self):
        for bad in ("-rf", "a b", "x;reboot", "$(id)", "../etc", "a\nb", "", "x" * 101, "`id`", "a/b"):
            with self.subTest(bad):
                self.assertIsNone(self.look.NAME.match(bad))
        for good in ("firefox", "org.gnome.Foo", "general:gaps_in", "sshd@host.service", "lib32-glibc"):
            with self.subTest(good):
                self.assertTrue(self.look.NAME.match(good))

    def test_topics_other_than_space_reject_odd_arguments(self):
        for topic in ("package", "service", "option", "search", "omarchy"):
            with self.subTest(topic):
                self.assertIn("not a valid name", self.main(topic, "--help; id"))

    def test_one_argument_at_most(self):
        self.assertIn("usage", self.main("package", "a", "b"))
        self.assertIn("usage", self.main("battery", "a"))

    def test_space_does_not_take_a_name_but_still_checks_the_folder(self):
        (self.home / ".ssh").mkdir()
        self.assertIn("only looks inside", self.main("space", "/etc"))
        self.assertIn("private data", self.main("space", "~/.ssh"))


if __name__ == "__main__":
    unittest.main()
