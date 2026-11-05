"""The API brain: how it reads answers, and how the API key is stored."""
import os
import stat
import unittest

from support import HomeCase, load_script

KEY = "sk-test-key-123"
REPLY = '{"reply": "hello", "mood": "happy", "action": null}'


class AnswerParsingTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.ask = load_script("nyx-ask")
        os.environ["NYX_API_KEY"] = KEY
        self.sent = []

    def answer(self, data):
        """What ask_api makes of the API sending back `data` (small-talk style: no tools)."""
        self.ask.api_call = lambda url, key, body, deadline, path="": self.sent.append((key, body)) or data
        return self.ask.ask_api("hi", "some/model", None, "", tools=False)

    def failure(self, data):
        with self.assertRaises(self.ask.BrainError) as caught:
            self.answer(data)
        return str(caught.exception)

    def test_plain_answer(self):
        result, _ = self.answer({"choices": [{"message": {"content": REPLY}}]})
        self.assertEqual(result["reply"], "hello")
        self.assertEqual(self.sent[0][0], KEY)

    def test_content_in_parts_is_joined(self):
        parts = [{"type": "text", "text": REPLY[:20]}, {"type": "image_url", "image_url": {"url": "x"}},
                 {"type": "text", "text": REPLY[20:]}]
        result, _ = self.answer({"choices": [{"message": {"content": parts}}]})
        self.assertEqual(result, {"reply": "hello", "mood": "happy", "action": None})

    def test_odd_content_does_not_crash(self):
        for content in (None, [], [None, 3, {"type": "text"}], 42, {"text": "x"}):
            with self.subTest(content=content):
                result, _ = self.answer({"choices": [{"message": {"content": content}}]})
                self.assertEqual(result["reply"], "…")

    def test_error_body_with_http_200_is_shown(self):
        message = self.failure({"error": {"message": "No credits left for this model", "code": 402}})
        self.assertEqual(message, "The API said: No credits left for this model")

    def test_error_body_may_be_a_plain_string(self):
        self.assertEqual(self.failure({"error": "model not found"}), "The API said: model not found")

    def test_error_text_never_echoes_the_key_or_hides_things(self):
        sneaky = KEY[:5] + "\u200b" + KEY[5:]  # zero-width space inside the key
        message = self.failure({"error": {"message": f"Bad key {KEY} / {sneaky} \u202e evil\nline"}})
        self.assertNotIn(KEY, message)
        self.assertNotIn("\u200b", message)
        self.assertNotIn("\u202e", message)
        self.assertNotIn("\n", message)
        self.assertIn("Bad key ***", message)

    def test_error_text_is_short(self):
        message = self.failure({"error": {"message": "x" * 5000}})
        self.assertLessEqual(len(message), len("The API said: ") + 200)

    def test_error_without_a_message_still_fails_cleanly(self):
        for error in ({"code": 500}, ["a"], 7):
            with self.subTest(error=error):
                self.assertTrue(self.failure({"error": error}).startswith("The API said: "))

    def test_unusable_answers_are_reported(self):
        for data in ({"choices": []}, {"choices": [{}]}, {"choices": ["x"]}, [], "text", {"id": "1"}):
            with self.subTest(data=data):
                self.assertEqual(self.failure(data), "The API sent back an answer I don't understand.")

    def test_a_real_answer_wins_over_an_error_field(self):
        result, _ = self.answer({"error": None, "choices": [{"message": {"content": REPLY}}]})
        self.assertEqual(result["reply"], "hello")


class KeyFileTests(HomeCase):
    def setUp(self):
        super().setUp()
        self.ask = load_script("nyx-ask")
        old = os.umask(0)  # the modes must come from Nyx, not from a strict umask
        self.addCleanup(os.umask, old)

    def mode(self, path):
        return stat.S_IMODE(os.stat(path).st_mode)

    def test_key_is_saved_0600_in_a_0700_folder(self):
        self.ask.write_key(KEY + "\n")
        self.assertEqual(self.mode(self.ask.STATE), 0o700)
        self.assertEqual(self.mode(self.ask.API_KEY_FILE), 0o600)
        self.assertEqual(self.ask.saved_key(), KEY)
        self.assertEqual(os.listdir(self.ask.STATE), ["api-key"])  # no temp file left behind

    def test_saving_again_keeps_0600(self):
        self.ask.write_key("first\n")
        self.ask.write_key(KEY + "\n")
        self.assertEqual(self.mode(self.ask.API_KEY_FILE), 0o600)
        self.assertEqual(self.ask.saved_key(), KEY)

    def test_a_symlinked_key_file_is_replaced_not_written_through(self):
        victim = self.write("victim.txt", "precious\n")
        self.ask.STATE.mkdir(mode=0o700, parents=True)
        self.ask.API_KEY_FILE.symlink_to(victim)
        self.ask.write_key(KEY + "\n")
        self.assertEqual(victim.read_text(), "precious\n")
        self.assertFalse(self.ask.API_KEY_FILE.is_symlink())
        self.assertEqual(self.mode(self.ask.API_KEY_FILE), 0o600)

    def test_a_planted_symlink_for_the_temp_file_is_refused(self):
        victim = self.write("victim.txt", "precious\n")
        self.ask.STATE.mkdir(mode=0o700, parents=True)
        (self.ask.STATE / f".api-key.{os.getpid()}.tmp").symlink_to(victim)
        with self.assertRaises(OSError):  # O_NOFOLLOW
            self.ask.write_key(KEY + "\n")
        self.assertEqual(victim.read_text(), "precious\n")

    def test_a_key_that_isnt_one_line_is_not_a_key(self):
        self.ask.write_key("two words\n")
        self.assertEqual(self.ask.saved_key(), "")


if __name__ == "__main__":
    unittest.main()
