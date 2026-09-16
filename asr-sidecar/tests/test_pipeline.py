import base64
import io
import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from jobs import Jobs
from protocol import Emitter, decode_audio


class QueueTests(unittest.TestCase):
    def test_final_priority_and_partial_coalescing(self):
        jobs = Jobs(2)
        jobs.put(("old", 0, None), False)
        jobs.put(("latest", 0, None), False)
        jobs.put(("final", 0, None), True)
        self.assertEqual(jobs.get()[0][0], "final")
        self.assertEqual(jobs.get()[0][0], "latest")

    def test_overload_is_explicit_and_bounded(self):
        jobs = Jobs(1)
        self.assertTrue(jobs.put(("a", 0, None), True))
        self.assertFalse(jobs.put(("b", 0, None), True))
        jobs.close()
        self.assertEqual(jobs.get()[0][0], "a")
        self.assertIsNone(jobs.get())
        self.assertFalse(jobs.put(("c", 0, None), True))

    def test_final_supersedes_pending_partial(self):
        jobs = Jobs()
        jobs.put(("a", 0, None), False)
        jobs.put(("a", 0, None), True)
        self.assertIsNone(jobs.partial)


class ProtocolTests(unittest.TestCase):
    def test_unicode_event_is_one_json_line(self):
        stream = io.StringIO()
        Emitter(stream)("warning", message="中文\nsecond line")
        self.assertEqual(len(stream.getvalue().splitlines()), 1)
        self.assertEqual(json.loads(stream.getvalue())["message"], "中文\nsecond line")

    def test_pcm_validation(self):
        import struct
        msg = {"sample_rate": 48000, "start": 2.5,
               "pcm": base64.b64encode(struct.pack("<ff", .5, -.5)).decode()}
        rate, start, samples = decode_audio(msg)
        self.assertEqual((rate, start), (48000, 2.5))
        self.assertEqual(samples.tolist(), [.5, -.5])
        for patch in [{"sample_rate": 0}, {"start": -1}, {"start": float("nan")},
                      {"pcm": "!!!"}, {"pcm": base64.b64encode(b"a").decode()},
                      {"pcm": base64.b64encode(struct.pack("<f", float("nan"))).decode()}]:
            with self.assertRaises(ValueError):
                decode_audio({**msg, **patch})


if __name__ == "__main__":
    unittest.main()
