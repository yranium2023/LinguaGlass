import pathlib
import sys
import types
import unittest
import time
from unittest.mock import patch

import numpy as np
import soxr

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from engine import Engine, RATE, STREAMING_COMMIT_SECONDS


class EngineTests(unittest.TestCase):
    def make_engine(self):
        events = []
        with patch('faster_whisper.WhisperModel') as whisper:
            whisper.return_value.transcribe.side_effect = lambda *a, **kw: (
                iter([types.SimpleNamespace(text='A local test sentence.', words=None)]), None)
            engine = Engine(lambda kind, **fields: events.append({'type':kind, **fields}),
                            'distil-large-v3', 'cpu')
        return engine, events

    def test_real_silero_silence_never_reaches_asr(self):
        engine, events = self.make_engine()
        for i in range(100):
            engine.feed(48000, i*.1, np.zeros(4800, dtype=np.float32))
        self.assertLessEqual(len(engine.buffer), RATE * 2 + 4800)
        engine.close()
        self.assertFalse(any(e['type'] in ['asr_final','asr_partial'] for e in events))

    def test_soxr_state_is_continuous_at_44100(self):
        resampler = soxr.ResampleStream(44100, RATE, 1, dtype='float32', quality='HQ')
        blocks = [resampler.resample_chunk(np.zeros(441,dtype=np.float32)) for _ in range(100)]
        blocks.append(resampler.resample_chunk(np.empty(0,dtype=np.float32),last=True))
        self.assertEqual(sum(map(len,blocks)), RATE)

    def test_gap_flushes_old_utterance_and_preserves_session_time(self):
        engine, events = self.make_engine()
        engine.detect = lambda x: [{'start':0,'end':len(x)}] if len(x) else []
        engine.feed(16000,0,np.ones(16000,dtype=np.float32)*.1)
        engine.feed(16000,8,np.ones(16000,dtype=np.float32)*.1)
        engine.close()
        finals = [e for e in events if e['type']=='asr_final']
        self.assertEqual(len(finals),2)
        self.assertAlmostEqual(finals[0]['start'],0)
        self.assertAlmostEqual(finals[1]['start'],8)
        self.assertNotEqual(finals[0]['id'],finals[1]['id'])
        self.assertTrue(any(e['type']=='warning' for e in events))

    def test_long_speech_is_segmented_and_shutdown_drains(self):
        engine, events = self.make_engine()
        engine.detect = lambda x: [{'start':0,'end':len(x)}] if len(x) else []
        for i in range(30):
            engine.feed(16000,float(i),np.ones(RATE,dtype=np.float32)*.1)
            self.assertLess(len(engine.buffer), RATE * (STREAMING_COMMIT_SECONDS + 2))
        engine.close()
        finals = [e for e in events if e['type']=='asr_final']
        self.assertGreaterEqual(len(finals),2)
        self.assertEqual(len({e['group_id'] for e in finals}), 1)
        self.assertFalse(engine.worker.is_alive())

    def test_continuous_speech_keeps_enough_context_before_commit(self):
        engine, events = self.make_engine()
        engine.detect = lambda x: [{'start': 0, 'end': len(x)}] if len(x) else []
        block = RATE // 4
        for index in range(84):
            engine.feed(RATE, index * .25, np.ones(block, dtype=np.float32) * .1)
        engine.close()
        finals = [event for event in events if event['type'] == 'asr_final']
        self.assertGreaterEqual(len(finals), 2)
        self.assertGreaterEqual(finals[0]['end'] - finals[0]['start'], 19.5)
        self.assertLessEqual(finals[0]['end'] - finals[0]['start'],
                             STREAMING_COMMIT_SECONDS + .3)
        self.assertEqual(len({event['group_id'] for event in finals}), 1)

    def test_whisper_internal_segments_stay_one_visible_utterance(self):
        events = []
        pieces = [types.SimpleNamespace(text='One clause.'),
                  types.SimpleNamespace(text='Another clause.')]
        with patch('faster_whisper.WhisperModel') as whisper:
            whisper.return_value.transcribe.side_effect = lambda *args, **kwargs: (iter(pieces), None)
            engine = Engine(lambda kind, **fields: events.append({'type':kind, **fields}),
                            'distil-large-v3', 'cpu')
        engine.detect = lambda x: [{'start':0,'end':len(x)}] if len(x) else []
        engine.feed(RATE, 0, np.ones(RATE, dtype=np.float32) * .1)
        engine.close()
        finals = [e for e in events if e['type'] == 'asr_final']
        self.assertEqual(len(finals), 1)
        self.assertEqual(finals[0]['text'], 'One clause. Another clause.')

    def test_partial_inference_emits_one_translation_hint(self):
        engine, events = self.make_engine()
        engine.detect = lambda x: [{'start': 0, 'end': len(x)}] if len(x) else []
        engine.feed(RATE, 0, np.ones(RATE, dtype=np.float32) * .1)
        for _ in range(100):
            if any(event['type'] == 'translation_hint' for event in events):
                break
            time.sleep(.01)
        engine.close()
        hints = [event for event in events if event['type'] == 'translation_hint']
        self.assertEqual(len(hints), 1)
        self.assertEqual(hints[0]['text'], 'A local test sentence.')
