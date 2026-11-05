"""The deny list in bin/nyx-ask: what no brain may read, however it asks."""
import os
import unittest

from support import HomeCase, load_script


class SecretPathTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.ask = load_script("nyx-ask")
        (self.home / ".config/hypr").mkdir(parents=True)
        self.normal = self.write(".config/hypr/hyprland.conf", "bind = SUPER, N, exec, nyx\n")

    def test_private_files_are_denied(self):
        for rel in (".config/nyx/config.json", ".local/state/nyx/api-key", ".local/state/nyx/session-claude",
                    ".config/environment.d/10-keys.conf", ".config/uwsm/env", ".config/uwsm/env-hyprland",
                    ".config/systemd/user/tokens.service", ".ssh/id_ed25519", ".gnupg/pubring.kbx",
                    ".codex/auth.json", ".claude/.credentials.json", ".claude.json", ".aws/credentials",
                    ".netrc", ".config/gh/hosts.yml", ".local/share/keyrings/login.keyring"):
            path = self.write(rel)
            with self.subTest(rel):
                self.assertTrue(self.ask.is_secret(os.path.realpath(path)))
                self.assertIsNone(self.ask.allowed_path(path))

    def test_folder_itself_and_lookalikes(self):
        self.assertTrue(self.ask.is_secret(str(self.home / ".config/nyx")))
        # A name that merely starts the same way is not the folder.
        self.assertFalse(self.ask.is_secret(str(self.home / ".config/nyx-notes/todo")))
        self.assertFalse(self.ask.is_secret(str(self.normal)))

    def test_normal_config_file_is_allowed(self):
        self.assertEqual(self.ask.tool_read_file(self.normal), "bind = SUPER, N, exec, nyx\n")

    def test_dot_dot_and_symlinks_do_not_get_around_it(self):
        secret = self.write(".config/nyx/config.json", '{"brain": "api"}')
        env_dir = self.home / ".config/environment.d"
        self.write(".config/environment.d/keys.conf", "TOKEN=hunter2\n")
        state = self.write(".local/state/nyx/api-key", "sk-secret\n").parent
        hypr = self.home / ".config/hypr"
        (hypr / "to-file").symlink_to(secret)
        (hypr / "to-env").symlink_to(env_dir)
        (hypr / "to-state").symlink_to(state)
        for path in (hypr / "to-file", hypr / "to-env/keys.conf", hypr / "to-state/api-key", hypr / "to-state",
                     str(hypr) + "/../nyx/config.json", str(hypr) + "/to-env/../environment.d/keys.conf"):
            with self.subTest(str(path)):
                self.assertIsNone(self.ask.allowed_path(path))
        self.assertTrue(self.ask.tool_read_file(hypr / "to-env/keys.conf").startswith("Refused"))
        self.assertTrue(self.ask.tool_list_dir(hypr / "to-state").startswith("Refused"))

    def test_a_readable_folder_that_leads_to_a_secret_is_dropped(self):
        self.write(".config/nyx/config.json")
        (self.home / ".config/hypr").rename(self.home / ".config/hypr-real")
        (self.home / ".config/hypr").symlink_to(self.home / ".config/nyx")
        self.ask.secret_paths.cache_clear()
        self.ask.readable_dirs.cache_clear()
        self.assertNotIn(str(self.home / ".config/hypr"), self.ask.readable_dirs())

    def test_xdg_folders_are_honoured(self):
        config, state = self.home / "xdg-config", self.home / "xdg-state"
        os.environ["XDG_CONFIG_HOME"], os.environ["XDG_STATE_HOME"] = str(config), str(state)
        ask = load_script("nyx-ask")
        for path in (config / "nyx/config.json", config / "environment.d/a.conf", config / "uwsm/env",
                     state / "nyx/api-key"):
            with self.subTest(str(path)):
                self.assertTrue(ask.is_secret(str(path)))

    def test_etc_is_an_allow_list(self):
        for path in ("/etc/passwd", "/etc/environment", "/etc/environment.d/a.conf", "/etc/fstab"):
            with self.subTest(path):
                self.assertIsNone(self.ask.allowed_path(path))
        if os.path.exists("/etc/os-release"):
            self.assertEqual(self.ask.allowed_path("/etc/os-release"), os.path.realpath("/etc/os-release"))

    def test_results_are_computed_once_and_can_be_reset(self):
        calls = []
        real = self.ask.etc_denied
        self.ask.etc_denied = lambda: calls.append(1) or real()
        self.ask.secret_paths.cache_clear()
        self.ask.readable_dirs.cache_clear()
        for _ in range(5):
            self.ask.is_secret("/nowhere")
            self.ask.allowed_path(self.normal)
        self.assertEqual(len(calls), 1)
        self.ask.secret_paths.cache_clear()
        self.ask.is_secret("/nowhere")
        self.assertEqual(len(calls), 2)

    def test_a_reset_picks_up_a_different_home(self):
        other = self.home / "other"
        self.assertFalse(self.ask.is_secret(str(other / ".ssh/id_rsa")))
        self.ask.HOME = other
        self.ask.secret_paths.cache_clear()
        self.assertTrue(self.ask.is_secret(str(other / ".ssh/id_rsa")))
        self.assertFalse(self.ask.is_secret(str(self.home / ".ssh/id_rsa")))


class HardLinkTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.ask = load_script("nyx-ask")
        (self.home / ".config/hypr").mkdir(parents=True)

    def test_hard_link_to_a_secret_is_refused(self):
        secret = self.write(".config/nyx/config.json", "sk-do-not-leak\n")
        link = self.home / ".config/hypr/innocent.conf"
        os.link(secret, link)  # looks like an ordinary readable file by name and path
        self.assertEqual(self.ask.allowed_path(link), str(link))
        out = self.ask.tool_read_file(link)
        self.assertTrue(out.startswith("Refused"), out)
        self.assertNotIn("sk-do-not-leak", out)

    def test_single_link_files_are_read(self):
        path = self.write(".config/hypr/hyprland.conf", "gaps = 5\n")
        self.assertEqual(self.ask.tool_read_file(path), "gaps = 5\n")

    def test_folders_and_special_files_are_not_read(self):
        self.assertEqual(self.ask.tool_read_file(self.home / ".config/hypr"), "Not a regular file.")


class CodexProfileTests(HomeCase):
    def test_symlinks_inside_readable_folders_do_not_open_secrets(self):
        ask = load_script("nyx-ask")
        (self.home / ".config/hypr").mkdir(parents=True)
        self.write(".config/hypr/hyprland.conf")
        self.write(".config/nyx/config.json")
        (self.home / ".config/hypr/sneaky").symlink_to(self.home / ".config/nyx")
        codex = self.home / "bin/codex"
        codex.parent.mkdir()
        codex.write_text("#!/bin/sh\n")
        ask.codex_features = lambda _: {"shell_tool", "other"}
        profile = ask.codex_config(str(codex), quiet=False)
        secret = f'"{self.home}/.config/nyx"'
        self.assertIn(f"{secret} = \"deny\"", profile)
        self.assertNotIn(f"{secret} = \"read\"", profile)
        self.assertNotIn(f'"{self.home}/.local/state/nyx" = "read"', profile)
        self.assertIn(f'"{self.home}/.config/hypr" = "read"', profile)


if __name__ == "__main__":
    unittest.main()
