# English audio regression fixture

`english-jfk.flac` is the 11-second public speech fixture used by the official
faster-whisper test suite. Source:
https://github.com/SYSTRAN/faster-whisper/blob/master/tests/data/jfk.flac

`english-jfk.wav` is a 16 kHz mono conversion of the same fixture for real
system-audio playback through the desktop WebView during overlay regression.

`jfk-rice-90s.wav` is a 90-second excerpt from President John F. Kennedy's
September 12, 1962 address at Rice University. It is used for long-running
subtitle layout, system loopback, and translation latency tests. The source is
NASA footage in the United States public domain, distributed by Wikimedia
Commons: https://commons.wikimedia.org/wiki/File:President_Kennedy_speech_on_the_space_effort_at_Rice_University,_September_12,_1962.ogv

Run the delivery-level real-time check with:

`.venv/Scripts/python.exe scripts/smoke_asr.py --realtime --device cuda`

The check requires progressive partial events, accurate final text, valid timing,
and one visible utterance group even when translation starts from several chunks.
