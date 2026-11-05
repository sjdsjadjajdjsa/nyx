"""When the Claude and Codex brains may retry, and what they keep locked down.
The CLIs themselves are replaced by fakes: no network, no logins."""
import json
import subprocess
import unittest
import warnings
from pathlib import Path
from unittest import mock

from support import HomeCase, load_script

CLAUDE_OK = json.dumps({"structured_output": {"reply": "hi", "mood": "happy", "action": None}, "session_id": "new-id"})


def done(stdout="", stderr="", code=0):
    return subprocess.CompletedProcess([], code, stdout, stderr)


class ClaudeTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.ask = load_script("nyx-ask")
        self.ask.find_claude = lambda: "/fake/claude"
        self.calls = []

    def run_claude(self, outcomes, session="old-id"):
        """ask_claude with each `claude` run answered from `outcomes` in order."""
        queue = list(outcomes)

        def fake_run(cmd, **kwargs):
            self.calls.append(cmd)
            return queue.pop(0)
        with mock.patch.object(subprocess, "run", fake_run):
            return self.ask.ask_claude("hello", None, None, session)

    def resumed(self):
        return ["--resume" in c for c in self.calls]

    def test_session_gone_is_recognised(self):
        gone = self.ask.claude_session_gone
        self.assertTrue(gone(done(stderr="No conversation found with session ID: 1111", code=1)))
        self.assertTrue(gone(done(stderr='Error: --resume requires a valid session ID or session title ...', code=1)))
        for stderr in ("API Error: 429 rate_limit_error", "Overloaded", "Credit balance is too low", "", None):
            self.assertFalse(gone(done(stderr=stderr, code=1)), stderr)

    def test_missing_session_starts_a_fresh_chat(self):
        result, session = self.run_claude([done(stderr="No conversation found with session ID: x", code=1),
                                           done(CLAUDE_OK)])
        self.assertEqual((result["reply"], session), ("hi", "new-id"))
        self.assertEqual(self.resumed(), [True, False])

    def test_other_failures_keep_the_conversation(self):
        for stderr in ("API Error: 429 rate limit reached", "Overloaded, try again", "Invalid API key"):
            self.calls.clear()
            with self.subTest(stderr), self.assertRaises(self.ask.BrainError):
                self.run_claude([done(stderr=stderr, code=1)])
            self.assertEqual(self.resumed(), [True])  # asked once, never without the session

    def test_failure_without_a_session_is_not_retried(self):
        with self.assertRaises(self.ask.BrainError):
            self.run_claude([done(stderr="No conversation found", code=1)], session="")
        self.assertEqual(len(self.calls), 1)

    def test_every_secret_gets_a_read_deny_rule(self):
        self.run_claude([done(CLAUDE_OK)])
        cmd = self.calls[0]
        settings = json.loads(cmd[cmd.index("--settings") + 1])
        deny = settings["permissions"]["deny"]
        for rel in (".config/nyx", ".local/state/nyx", ".config/environment.d", ".config/uwsm", ".config/systemd"):
            self.assertIn(f"Read(/{self.home}/{rel})", deny)
            self.assertIn(f"Read(/{self.home}/{rel}/**)", deny)
        self.assertTrue(settings["permissions"]["blockReadsOutsideWorkingDirectories"])
        self.assertNotIn(str(self.home / ".config/nyx"), cmd[cmd.index("--add-dir") + 1:])


class CodexTests(HomeCase):
    def setUp(self):
        super().setUp()
        # ask_codex keeps its lock file open until the process ends (it is short-lived).
        self.enterContext(warnings.catch_warnings())
        warnings.simplefilter("ignore", ResourceWarning)
        self.ask = load_script("nyx-ask")
        self.ask.STATE.mkdir(mode=0o700, parents=True)
        self.ask.find_codex = lambda: "/fake/codex"
        self.ask.codex_home = lambda codex, quiet: (self.home / "codex-home", self.home / "auth.json")
        self.ask.sync_codex_login = lambda *a: None
        self.ask.system_prompt = lambda brain: "rules"
        self.calls = []  # (model or None, resuming?)

    def run_codex(self, behave, model=None, session="", tools=True):
        """ask_codex with a fake codex: behave(model, resuming) -> (answer or None, stdout, stderr)."""
        def fake_run(cmd, **kwargs):
            model_used = cmd[cmd.index("-m") + 1] if "-m" in cmd else None
            resuming = "resume" in cmd
            self.calls.append((model_used, resuming))
            answer, stdout, stderr = behave(model_used, resuming)
            if answer is not None:
                Path(cmd[cmd.index("-o") + 1]).write_text(answer)
            return done(stdout, stderr, 0 if answer is not None else 1)
        with mock.patch.object(subprocess, "run", fake_run):
            return self.ask.ask_codex("hello", model, None, session, tools=tools)

    ANSWER = '{"reply": "hi", "mood": "happy", "action": null}'
    UNAUTHORIZED = '{"type": "error", "message": "unexpected status 401 Unauthorized: Missing bearer"}\n'
    NO_MODEL = '{"type": "error", "message": "The model `gpt-6-luna` does not exist or you do not have access"}\n'
    DEFAULT = "gpt-6.1-terra"

    def test_small_talk_falls_back_when_its_model_is_missing(self):
        luna = self.ask.QUIP_MODEL["codex"]
        result, _ = self.run_codex(lambda m, r: (self.ANSWER, "", "") if m != luna else (None, self.NO_MODEL, ""),
                                   model=luna, tools=False)
        self.assertEqual(result["reply"], "hi")
        self.assertEqual(self.calls, [(luna, False), (self.DEFAULT, False)])

    def test_a_failed_login_is_not_retried(self):
        for model, tools in ((None, True), (self.ask.QUIP_MODEL["codex"], False)):
            self.calls.clear()
            with self.subTest(model=model), self.assertRaises(self.ask.BrainError) as caught:
                self.run_codex(lambda m, r: (None, self.UNAUTHORIZED, ""), model=model, tools=tools)
            self.assertIn("isn't logged in", str(caught.exception))
            self.assertEqual(len(self.calls), 1)

    def test_a_failed_login_is_not_retried_with_a_session_either(self):
        with self.assertRaises(self.ask.BrainError):
            self.run_codex(lambda m, r: (None, self.UNAUTHORIZED, ""), session="thread-1")
        self.assertEqual(self.calls, [(self.DEFAULT, True)])

    def test_default_model_missing_falls_back_to_codexs_own(self):
        result, _ = self.run_codex(lambda m, r: (self.ANSWER, "", "") if m is None else (None, self.NO_MODEL, ""))
        self.assertEqual(result["reply"], "hi")
        self.assertEqual([m for m, _ in self.calls], [self.DEFAULT, None])

    def test_a_model_the_user_chose_is_not_swapped(self):
        with self.assertRaises(self.ask.BrainError):
            self.run_codex(lambda m, r: (None, self.NO_MODEL, ""), model="my-model")
        self.assertEqual(self.calls, [("my-model", False)])

    def test_a_missing_session_starts_over_once(self):
        gone = "Error: thread/resume failed: no rollout found for thread id thread-1 (code -32600)"
        result, _ = self.run_codex(lambda m, resuming: (None, "", gone) if resuming else (self.ANSWER, "", ""),
                                   session="thread-1")
        self.assertEqual(result["reply"], "hi")
        self.assertEqual(self.calls, [(self.DEFAULT, True), (self.DEFAULT, False)])


if __name__ == "__main__":
    unittest.main()
