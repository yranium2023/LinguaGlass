import { useEffect, useRef, useState, type CSSProperties } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  AudioLines,
  Monitor,
  Mic,
  Play,
  Square,
  Settings2,
  Subtitles,
  Download,
  RefreshCw,
  X,
  Check,
  ShieldCheck,
  Moon,
  Sun,
  Volume2,
} from "lucide-react";
import { desktop, usePipeline } from "./usePipeline";
import { timecode } from "./protocol";
import { groupTranscript, subtitlePages } from "./transcript";
import { loadPreferences, savePreferences, type Config } from "./preferences";
import { WindowControls } from "./WindowControls";
import { GlassSelect } from "./GlassSelect";
import { ThemePicker } from "./ThemePicker";

type Device = { id: string; name: string };
type Environment = {
  python_ready: boolean;
  system_audio_supported: boolean;
  models?: string[];
  cuda_available?: boolean;
  message?: string;
};
const domains: Record<string, string> = {
  General: "通用",
  "Computer Science": "计算机科学",
  "Artificial Intelligence": "人工智能",
  Networking: "网络通信",
  "Electrical Engineering": "电子工程",
  Mathematics: "数学",
  Custom: "自定义",
};
const asrModels = [
  { value: "distil-large-v3", description: "高精度" },
  { value: "distil-medium.en", description: "均衡" },
  { value: "distil-small.en", description: "轻量" },
] as const;
const stateLabels = {
  IDLE: "准备就绪",
  INITIALIZING: "正在加载语音模型",
  LISTENING: "正在聆听",
  STOPPING: "正在保存并结束",
};

export function App() {
  const [initial] = useState(loadPreferences);
  const [config, setConfig] = useState(initial.config);
  const [appearance, setAppearance] = useState(initial.appearance);
  const view = usePipeline();
  const [devices, setDevices] = useState<Device[]>([]);
  const [loadingDevices, setLoadingDevices] = useState(false);
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [keyReady, setKeyReady] = useState(false),
    [key, setKey] = useState("");
  const [settings, setSettings] = useState(false),
    [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(""),
    [dismissed, setDismissed] = useState("");
  const [overlay, setOverlay] = useState(false),
    [clickThrough, setClickThrough] = useState(false);
  const [format, setFormat] = useState("md"),
    [follow, setFollow] = useState(true),
    [elapsed, setElapsed] = useState(0);
  const [refresh, setRefresh] = useState(0);
  const [downloadingModel, setDownloadingModel] = useState<string | null>(null);
  const transcript = useRef<HTMLDivElement>(null),
    dialog = useRef<HTMLDialogElement>(null);
  const settingsButton = useRef<HTMLButtonElement>(null);
  const overlayOperation = useRef({ busy: false, revision: 0 });
  const active = view.state !== "IDLE";
  const rows = view.rows;
  const transcriptGroups = groupTranscript(rows);
  const preview = subtitlePages(rows, config.subtitle_pause_seconds).at(-1);
  const previewPartial = preview?.rows.some((row) => row.status === "partial");
  const pending = rows.filter((r) =>
    ["queued", "translating", "final"].includes(r.status),
  ).length;
  const warning = notice || (view.message !== dismissed ? view.message : "");
  const modelMissing =
    environment?.models && !environment.models.includes(config.asr_model);
  const startReason = !desktop
    ? "请在桌面应用中使用"
    : !environment
      ? "正在检查本地环境"
      : !environment.python_ready
        ? "本地识别环境尚未就绪"
        : modelMissing
          ? "所选语音模型尚未下载"
          : loadingDevices
            ? "正在读取设备"
            : devices.length === 0
              ? "未找到可用音频设备"
              : "";

  useEffect(() => {
    if (!desktop) return;
    void getCurrentWindow()
      .setDecorations(false)
      .catch(() => {});
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = appearance.theme;
    document.documentElement.dataset.size = appearance.size;
    document.documentElement.dataset.accent = appearance.accent;
    if (!savePreferences(config, appearance))
      setNotice("设置暂时无法保存到本机。");
  }, [config, appearance]);
  useEffect(() => {
    if (!desktop) return;
    void invoke<Environment>("environment")
      .then((e) => {
        setEnvironment(e);
        if (!e.system_audio_supported)
          setConfig((c) => ({
            ...c,
            input_mode: "microphone",
            device_id: null,
          }));
      })
      .catch((e) => setNotice(String(e)));
    void invoke<boolean>("key_status")
      .then(setKeyReady)
      .catch((e) => setNotice(String(e)));
  }, []);
  useEffect(() => {
    if (!desktop) return;
    let cancelled = false;
    setLoadingDevices(true);
    setDevices([]);
    invoke<Device[]>("devices", { inputMode: config.input_mode })
      .then((d) => {
        if (cancelled) return;
        setDevices(d);
        setConfig((c) =>
          c.device_id && !d.some((item) => item.id === c.device_id)
            ? { ...c, device_id: null }
            : c,
        );
      })
      .catch((e) => {
        if (!cancelled) setNotice(String(e));
      })
      .finally(() => {
        if (!cancelled) setLoadingDevices(false);
      });
    return () => {
      cancelled = true;
    };
  }, [config.input_mode, refresh]);
  useEffect(() => {
    if (follow && transcript.current)
      transcript.current.scrollTo({
        top: transcript.current.scrollHeight,
        behavior: "smooth",
      });
  }, [rows, follow]);
  useEffect(() => {
    if (view.state !== "LISTENING") return;
    const started = Date.now();
    setElapsed(0);
    const t = setInterval(
      () => setElapsed((Date.now() - started) / 1000),
      1000,
    );
    return () => clearInterval(t);
  }, [view.state]);
  useEffect(() => {
    if (settings) {
      dialog.current?.showModal();
    } else {
      dialog.current?.close();
      setKey("");
    }
  }, [settings]);
  useEffect(() => {
    if (!desktop) return;
    // Native close/hide and window state are the source of truth, including Alt+F4.
    const sync = () => {
      if (overlayOperation.current.busy) return;
      const revision = overlayOperation.current.revision;
      void invoke<{ visible: boolean; click_through: boolean }>(
        "overlay_status",
      )
        .then((s) => {
          if (
            overlayOperation.current.busy ||
            revision !== overlayOperation.current.revision
          )
            return;
          setOverlay(s.visible);
          setClickThrough(s.click_through);
        })
        .catch(() => {});
    };
    sync();
    const timer = setInterval(sync, 1500);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    if (!desktop) return;
    let dispose: (() => void) | undefined;
    void listen<{ visible: boolean }>("overlay-visibility", (event) => {
      setOverlay(event.payload.visible);
    }).then((unlisten) => {
      dispose = unlisten;
    });
    return () => dispose?.();
  }, []);
  async function action(work: () => Promise<unknown>) {
    setBusy(true);
    setNotice("");
    try {
      await work();
    } catch (e) {
      setNotice(String(e));
    } finally {
      setBusy(false);
    }
  }
  async function toggleOverlay(visible: boolean, pass = clickThrough) {
    const previous = { visible: overlay, pass: clickThrough };
    overlayOperation.current.busy = true;
    overlayOperation.current.revision++;
    setOverlay(visible);
    setClickThrough(pass);
    try {
      await invoke("set_overlay", { visible, clickThrough: pass });
    } catch (error) {
      setOverlay(previous.visible);
      setClickThrough(previous.pass);
      throw error;
    } finally {
      overlayOperation.current.busy = false;
    }
  }
  function update<K extends keyof Config>(key: K, value: Config[K]) {
    setConfig((c) => ({ ...c, [key]: value }));
  }
  async function downloadAsrModel(model: string) {
    setDownloadingModel(model);
    setNotice(`正在下载 ${model}，首次下载可能需要几分钟…`);
    try {
      await invoke("download_model", { model });
      setEnvironment(await invoke<Environment>("environment"));
      setConfig((current) => ({ ...current, asr_model: model }));
      setNotice(`${model} 已下载并设为当前识别模型。`);
    } catch (error) {
      setNotice(String(error));
    } finally {
      setDownloadingModel(null);
    }
  }
  function closeSettings() {
    setSettings(false);
    setKey("");
    settingsButton.current?.focus();
  }
  return (
    <div className="app-shell">
      <header className="app-header" data-tauri-drag-region>
        <div className="brand">
          <span className="brand-mark">
            <AudioLines size={25} />
          </span>
          LinguaGlass
        </div>
        <div className="header-actions">
          <div className="size-control">
            <GlassSelect
              compact
              ariaLabel="文字大小"
              value={appearance.size}
              options={[
                { value: "standard", label: "标准" },
                { value: "large", label: "大" },
                { value: "extra", label: "特大" },
              ]}
              onChange={(size) =>
                setAppearance((appearance) => ({ ...appearance, size }))
              }
            />
          </div>
          <ThemePicker
            value={appearance.accent}
            onChange={(accent) =>
              setAppearance((current) => ({ ...current, accent }))
            }
          />
          <button
            className="icon-button"
            aria-label={
              appearance.theme === "light" ? "切换深色外观" : "切换浅色外观"
            }
            onClick={() =>
              setAppearance((a) => ({
                ...a,
                theme: a.theme === "light" ? "dark" : "light",
              }))
            }
          >
            {appearance.theme === "light" ? (
              <Moon size={21} />
            ) : (
              <Sun size={21} />
            )}
          </button>
          <button
            className="button"
            ref={settingsButton}
            onClick={() => setSettings(true)}
          >
            <Settings2 size={19} />
            设置
          </button>
          <WindowControls />
        </div>
      </header>
      <main className="main-content">
        <section className="page-heading">
          <div>
            <h1>实时翻译</h1>
            <p>选好声音来源，专注接下来的内容。</p>
          </div>
          <div className={`state-pill ${active ? "on" : ""}`}>
            <span className="status-dot" />
            {stateLabels[view.state]}
            {view.state === "LISTENING" && <time>{timecode(elapsed)}</time>}
          </div>
        </section>
        {!desktop && (
          <div className="notice">
            界面预览模式。请打开桌面应用使用音频采集、翻译和悬浮字幕。
          </div>
        )}
        {warning && (
          <div className="notice" role="status">
            <span>{warning}</span>
            <button
              className="icon-button"
              aria-label="关闭提示"
              onClick={() => {
                setNotice("");
                setDismissed(view.message);
              }}
            >
              <X size={18} />
            </button>
          </div>
        )}
        <div className="work-grid">
          <section className="panel controls">
            <h2>声音来源</h2>
            <div
              className="source-picker"
              role="group"
              aria-label="声音来源"
              data-mode={config.input_mode}
            >
              <button
                aria-pressed={config.input_mode === "system"}
                disabled={
                  active ||
                  (environment !== null && !environment.system_audio_supported)
                }
                onClick={() =>
                  setConfig((c) => ({
                    ...c,
                    input_mode: "system",
                    device_id: null,
                  }))
                }
              >
                <Monitor size={24} />
                系统音频
              </button>
              <button
                aria-pressed={config.input_mode === "microphone"}
                disabled={active}
                onClick={() =>
                  setConfig((c) => ({
                    ...c,
                    input_mode: "microphone",
                    device_id: null,
                  }))
                }
              >
                <Mic size={24} />
                麦克风
              </button>
            </div>
            <p className="help source-help">
              {config.input_mode === "system"
                ? "识别电脑正在播放的网课、视频或会议声音。请选择实际播放声音的耳机或扬声器。"
                : "识别你和周围人的讲话。"}
            </p>
            <label className="field-label" htmlFor="device">
              {config.input_mode === "system" ? "播放设备" : "输入设备"}
            </label>
            <div className="device-row">
              <GlassSelect
                id="device"
                ariaLabel={
                  config.input_mode === "system" ? "播放设备" : "输入设备"
                }
                disabled={active || loadingDevices || !desktop}
                value={config.device_id ?? ""}
                onChange={(value) => update("device_id", value || null)}
                options={[
                  {
                    value: "",
                    label: loadingDevices
                      ? "正在读取设备…"
                      : config.input_mode === "system"
                        ? "系统默认播放设备"
                        : "系统默认麦克风",
                  },
                  ...devices.map((device) => ({
                    value: device.id,
                    label: device.name,
                  })),
                ]}
              />
              <button
                className="icon-button"
                title={active ? "结束聆听后可刷新设备" : "刷新设备列表"}
                aria-label="刷新设备列表"
                disabled={active || loadingDevices || !desktop}
                onClick={() => setRefresh((n) => n + 1)}
              >
                <RefreshCw size={20} />
              </button>
            </div>
            <div className="level-heading">
              <Volume2 size={17} />
              <span>
                {view.state === "LISTENING"
                  ? view.level > 0.002
                    ? "正在接收声音"
                    : "等待声音…"
                  : "音量监测"}
              </span>
            </div>
            <div
              className="level-track"
              role="meter"
              aria-label="音频输入音量"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(Math.min(1, view.level * 5) * 100)}
            >
              <div style={{ width: `${Math.min(100, view.level * 500)}%` }} />
            </div>
            <button
              className={`primary-button ${
                active
                  ? view.state === "INITIALIZING"
                    ? "cancel-loading"
                    : "stop"
                  : ""
              }`}
              disabled={
                busy || view.state === "STOPPING" || (!active && !!startReason)
              }
              onClick={() =>
                void action(() =>
                  active
                    ? invoke("stop_session")
                    : invoke("start_session", { config }),
                )
              }
            >
              {active ? (
                <Square size={18} />
              ) : (
                <Play size={19} fill="currentColor" />
              )}
              {active
                ? view.state === "STOPPING"
                  ? "正在结束…"
                  : view.state === "INITIALIZING"
                    ? "取消加载"
                    : "结束聆听"
                : "开始聆听"}
            </button>
            {!active && startReason && <p className="help">{startReason}</p>}
            {active && (
              <p className="help">结束聆听后可切换设备和修改识别设置。</p>
            )}
            <div className="engine-summary">
              <div>
                <span>英文识别</span>
                <strong>
                  {config.asr_model.replace("distil-", "Distil ")}
                </strong>
              </div>
              <div>
                <span>中文翻译</span>
                <strong>
                  DeepSeek{" "}
                  {config.translation_model.endsWith("pro") ? "Pro" : "Flash"}
                </strong>
              </div>
            </div>
            {!keyReady && (
              <button className="text-button" onClick={() => setSettings(true)}>
                设置翻译密钥 <span>→</span>
              </button>
            )}
            <p className="privacy">
              <ShieldCheck size={17} />
              音频留在本机，仅文本用于云端翻译。
            </p>
          </section>
          <div className="right-column">
            <section className="panel subtitle-preview">
              <header className="section-header">
                <h2>
                  <Subtitles size={22} />
                  实时字幕
                </h2>
                <button
                  className="button"
                  disabled={!desktop || busy}
                  onClick={() => void action(() => toggleOverlay(!overlay))}
                >
                  {overlay ? "关闭悬浮字幕" : "打开悬浮字幕"}
                </button>
              </header>
              <div
                className="preview-copy"
                aria-live="polite"
                data-card-id={preview?.id}
              >
                <p className={`english ${previewPartial ? "partial" : ""}`}>
                  {preview?.en || "Your English transcript will appear here."}
                </p>
                <p className="chinese">
                  {preview?.zh ||
                    (preview?.error
                      ? "翻译暂不可用，英文已保留。"
                      : preview?.en
                        ? previewPartial
                          ? "正在识别英文…"
                          : "正在翻译…"
                        : "开始聆听后，中文翻译会显示在这里。")}
                </p>
                {!preview?.en && (
                  <span className="help">尚未开始 · 此处为字幕占位说明</span>
                )}
              </div>
            </section>
            <section className="panel transcript-panel">
              <header className="section-header">
                <h2>
                  会话记录{" "}
                  <span className="count">
                    {
                      transcriptGroups.filter((g) =>
                        g.rows.some((r) => r.status !== "partial"),
                      ).length
                    }
                    {rows.length >= 300 ? "（最近）" : ""}
                  </span>
                </h2>
                <div className="export-controls">
                  <GlassSelect
                    compact
                    ariaLabel="导出格式"
                    value={format}
                    onChange={setFormat}
                    options={["md", "txt", "json", "srt"].map((value) => ({
                      value,
                      label: value.toUpperCase(),
                    }))}
                  />
                  <button
                    className="button"
                    disabled={!desktop || !view.sessionId || busy}
                    title={
                      !view.sessionId ? "开始会话后可导出完整记录" : undefined
                    }
                    onClick={() =>
                      void action(async () => {
                        const path = await invoke<string>("export_session", {
                          format,
                        });
                        setNotice(`完整记录已导出到：${path}`);
                      })
                    }
                  >
                    <Download size={18} />
                    导出
                  </button>
                </div>
              </header>
              <div className="transcript-body" ref={transcript}>
                {rows.length === 0 ? (
                  <div className="empty-state">
                    <AudioLines size={36} />
                    <h3>准备好，就开始吧。</h3>
                    <p>
                      英文原文和中文翻译会按时间保留在这里。
                      <br />
                      没有配置翻译密钥时，也可以记录英文。
                    </p>
                  </div>
                ) : (
                  transcriptGroups.map((group) => (
                    <article className="transcript-row" key={group.id}>
                      <time>{timecode(group.start)}</time>
                      <div>
                        <p className="row-en">{group.en}</p>
                        {group.zh && <p className="row-zh">{group.zh}</p>}
                        {group.error && (
                          <p className="row-error">{group.error}</p>
                        )}
                        {group.pending && <p className="pending">正在翻译…</p>}
                      </div>
                    </article>
                  ))
                )}
              </div>
              <footer className="transcript-footer">
                <span>
                  {pending ? `${pending} 个片段等待翻译` : "完整记录保存在本机"}
                </span>
                <label>
                  <input
                    type="checkbox"
                    checked={follow}
                    onChange={(e) => setFollow(e.target.checked)}
                  />
                  跟随最新
                </label>
              </footer>
            </section>
          </div>
        </div>
      </main>
      <dialog
        className="settings-dialog"
        ref={dialog}
        onCancel={(e) => {
          e.preventDefault();
          closeSettings();
        }}
        onClick={(e) => {
          if (e.target === e.currentTarget) closeSettings();
        }}
      >
        <section className="settings-content">
          <header className="section-header">
            <h2>设置</h2>
            <button
              className="icon-button"
              aria-label="关闭设置"
              onClick={closeSettings}
            >
              <X size={23} />
            </button>
          </header>
          <label className="field-label" htmlFor="api-key">
            DeepSeek API Key{" "}
            <span className="saved-state">
              {keyReady ? "已安全保存" : "未设置"}
            </span>
          </label>
          <input
            id="api-key"
            type="password"
            autoComplete="off"
            placeholder="输入翻译密钥"
            value={key}
            onChange={(e) => setKey(e.target.value)}
          />
          <div className="key-actions">
            <button
              className="button accent"
              disabled={!desktop || !key.trim() || busy}
              onClick={() =>
                void action(async () => {
                  await invoke("save_key", { key: key.trim() });
                  setKey("");
                  setKeyReady(true);
                  setNotice("密钥已保存到系统凭据管理器。");
                })
              }
            >
              <Check size={18} />
              保存密钥
            </button>
            <button
              className="button"
              disabled={!desktop || !keyReady || busy}
              onClick={() =>
                void action(async () => {
                  await invoke("delete_key");
                  setKeyReady(false);
                  setKey("");
                })
              }
            >
              移除密钥
            </button>
          </div>
          <p className="help">
            密钥保存在系统凭据管理器。没有密钥时，英文识别仍可使用。
          </p>
          <div className="settings-grid">
            <label>
              字幕短停顿合并 · {config.subtitle_pause_seconds.toFixed(1)} 秒
              <input
                aria-label="字幕短停顿合并时长"
                type="range"
                min="0.5"
                max="4"
                step="0.1"
                value={config.subtitle_pause_seconds}
                style={
                  {
                    "--range-progress": `${((config.subtitle_pause_seconds - 0.5) / 3.5) * 100}%`,
                  } as CSSProperties
                }
                onChange={(e) =>
                  update("subtitle_pause_seconds", Number(e.target.value))
                }
              />
              <span className="help">
                在这段时间内继续说话会合并到当前页。调小可更快换页，调大可合并更多演讲停顿。
              </span>
            </label>
            <label>
              识别模型
              <GlassSelect
                ariaLabel="识别模型"
                disabled={active}
                value={config.asr_model}
                onChange={(value) => update("asr_model", value)}
                options={asrModels.map((model) => ({
                  value: model.value,
                  label: `${model.value}${
                    environment?.models &&
                    !environment.models.includes(model.value)
                      ? " · 未下载"
                      : ""
                  }`,
                }))}
              />
            </label>
            <label>
              自然停顿断句 · {config.asr_silence_seconds.toFixed(1)} 秒
              <input
                aria-label="自然停顿断句时长"
                type="range"
                min="0.4"
                max="2"
                step="0.1"
                disabled={active}
                value={config.asr_silence_seconds}
                style={
                  {
                    "--range-progress": `${((config.asr_silence_seconds - 0.4) / 1.6) * 100}%`,
                  } as CSSProperties
                }
                onChange={(e) =>
                  update("asr_silence_seconds", Number(e.target.value))
                }
              />
              <span className="help">
                调小会更快断句，调大可保留较长的演讲停顿。
              </span>
            </label>
            <label>
              连续语音最长片段 · {config.asr_max_segment_seconds} 秒
              <input
                aria-label="连续语音最长片段"
                type="range"
                min="8"
                max="30"
                step="1"
                disabled={active}
                value={config.asr_max_segment_seconds}
                style={
                  {
                    "--range-progress": `${((config.asr_max_segment_seconds - 8) / 22) * 100}%`,
                  } as CSSProperties
                }
                onChange={(e) =>
                  update("asr_max_segment_seconds", Number(e.target.value))
                }
              />
              <span className="help">
                仅在一直没有自然停顿时强制切段；越长越连贯，但最终定稿更慢。
              </span>
            </label>
            <label>
              最终识别搜索耐心 · {config.asr_patience.toFixed(1)}
              <input
                aria-label="最终识别搜索耐心"
                type="range"
                min="1"
                max="2"
                step="0.1"
                disabled={active}
                value={config.asr_patience}
                style={
                  {
                    "--range-progress": `${(config.asr_patience - 1) * 100}%`,
                  } as CSSProperties
                }
                onChange={(e) => update("asr_patience", Number(e.target.value))}
              />
              <span className="help">
                调大可能提高最终文本准确率，但会增加计算量和定稿延迟。
              </span>
            </label>
            <label>
              计算设备
              <GlassSelect
                ariaLabel="计算设备"
                disabled={active}
                value={config.compute}
                onChange={(value) => update("compute", value)}
                options={[
                  { value: "cpu", label: "CPU" },
                  {
                    value: "cuda",
                    label: `NVIDIA CUDA${
                      environment?.cuda_available === false ? " · 不可用" : ""
                    }`,
                    disabled: environment?.cuda_available === false,
                  },
                ]}
              />
            </label>
            <label>
              翻译模型
              <GlassSelect
                ariaLabel="翻译模型"
                disabled={active}
                value={config.translation_model}
                onChange={(value) => update("translation_model", value)}
                options={[
                  {
                    value: "deepseek-v4-flash",
                    label: "DeepSeek Flash · 快速",
                  },
                  { value: "deepseek-v4-pro", label: "DeepSeek Pro · 高精度" },
                ]}
              />
            </label>
            <label>
              课程领域
              <GlassSelect
                ariaLabel="课程领域"
                disabled={active}
                value={config.domain}
                onChange={(value) => update("domain", value)}
                options={Object.entries(domains).map(([value, label]) => ({
                  value,
                  label,
                }))}
              />
            </label>
            <label>
              上下文
              <GlassSelect
                ariaLabel="上下文"
                disabled={active}
                value={config.context_length}
                onChange={(value) => update("context_length", value)}
                options={[0, 2, 3, 4].map((value) => ({
                  value,
                  label: value ? `前 ${value} 个片段` : "不使用上下文",
                }))}
              />
            </label>
            <label>
              输入增益 · {Math.round(config.gain * 100)}%
              <input
                aria-label="输入增益"
                type="range"
                min="0"
                max="2"
                step="0.05"
                disabled={active}
                value={config.gain}
                style={
                  {
                    "--range-progress": `${(config.gain / 2) * 100}%`,
                  } as CSSProperties
                }
                onChange={(e) => update("gain", Number(e.target.value))}
              />
            </label>
          </div>
          <p className="field-label">本地模型与计算环境</p>
          <div className="model-manager">
            {asrModels.map((model) => {
              const installed =
                environment?.models?.includes(model.value) ?? false;
              const downloading = downloadingModel === model.value;
              return (
                <div className="model-manager-row" key={model.value}>
                  <span>
                    <strong>{model.value}</strong>
                    <small>
                      {model.description} · {installed ? "已安装" : "未安装"}
                    </small>
                  </span>
                  <button
                    className={`button ${
                      !installed && config.asr_model === model.value
                        ? "accent"
                        : ""
                    }`}
                    disabled={
                      !desktop ||
                      active ||
                      !environment?.python_ready ||
                      installed ||
                      downloadingModel !== null
                    }
                    onClick={() => void downloadAsrModel(model.value)}
                  >
                    {installed ? (
                      <>
                        <Check size={16} /> 已安装
                      </>
                    ) : downloading ? (
                      "正在下载…"
                    ) : (
                      "下载"
                    )}
                  </button>
                </div>
              );
            })}
          </div>
          <div className="key-actions">
            <button
              className="button"
              disabled={!desktop || busy || downloadingModel !== null}
              onClick={() =>
                void action(async () => {
                  setEnvironment(await invoke<Environment>("environment"));
                  setNotice("本地模型与 GPU 状态已刷新。");
                })
              }
            >
              重新检测环境
            </button>
          </div>
          <p className="help">
            {environment?.cuda_available
              ? "GPU 运行库已就绪，可选择 NVIDIA CUDA。"
              : "GPU 不可用时请检查 NVIDIA 驱动及项目 CUDA 运行库。"}{" "}
            模型和计算设备在结束聆听后切换，下次开始时生效。
          </p>
          <label className="field-label" htmlFor="glossary">
            课程术语表
          </label>
          <textarea
            id="glossary"
            rows={3}
            maxLength={4000}
            disabled={active}
            placeholder={
              "gradient descent = 梯度下降\nbackpropagation = 反向传播"
            }
            value={config.glossary}
            onChange={(e) => update("glossary", e.target.value)}
          />
          <p className="help">
            等号左侧的英文术语会同时用于本地语音识别热词，提高专有名词命中率。
          </p>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={clickThrough}
              disabled={!desktop || busy}
              onChange={(e) =>
                void action(() => toggleOverlay(overlay, e.target.checked))
              }
            />
            悬浮字幕鼠标穿透
          </label>
          <p className="help">
            开启后鼠标可操作字幕下方的窗口。回到这里即可关闭。
          </p>
          {active && (
            <p className="notice">正在聆听。结束后可修改识别与翻译设置。</p>
          )}
          {notice && (
            <p className="notice" role="status">
              {notice}
            </p>
          )}
          <footer className="settings-footer">
            <span>偏好设置自动保存在本机</span>
            <button className="button accent" onClick={closeSettings}>
              完成
            </button>
          </footer>
        </section>
      </dialog>
    </div>
  );
}
