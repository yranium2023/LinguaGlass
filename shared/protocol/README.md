# Local pipeline protocol v1

Transport: UTF-8 JSON Lines on anonymous child stdin/stdout pipes. Python stderr is
not a protocol channel. Rust assigns monotonic `seq` and `session_id` on UI events.

Rust → Python:

```json
{"type":"audio","sample_rate":48000,"start":1.28,"pcm":"base64 little-endian float32 mono"}
{"type":"stop"}
```

`start` is the absolute session offset of the first native sample, including gaps.
Each audio message is at most 2 seconds; lines are at most 2 MB. Stop and EOF flush VAD.

Python → Rust: `ready`, `asr_partial`, `asr_final`, `asr_clear`, `warning`, `error`, `stopped`.
ASR events carry `id`, `start`, `end`, `text`. A final supersedes every partial with
the same ID. Rust queues only `asr_final`. UI events additionally include `status`,
`level`, `translation_queued`, `translation_started`, `translation_delta`,
`translation_done`, `translation_error`. Translation deltas contain the complete
Chinese text so far rather than an incremental token. They always carry the original
segment ID. `asr_clear` removes only a provisional row.

Snapshot subscription: listen first, buffer arriving events, read snapshot, replay
snapshot rows in sequence order, then apply only events newer than its sequence.
