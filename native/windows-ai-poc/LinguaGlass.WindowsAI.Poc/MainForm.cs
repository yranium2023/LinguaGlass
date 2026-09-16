using Microsoft.Windows.AI;
using Microsoft.Windows.AI.Speech;
using Windows.Media.Devices;

namespace LinguaGlass.WindowsAI.Poc;

internal sealed class MainForm : Form
{
    private readonly Label _readyState = new()
    {
        AutoSize = true,
        Font = new Font((SystemFonts.MessageBoxFont ?? SystemFonts.DefaultFont).FontFamily, 11, FontStyle.Bold),
        Text = "尚未检查 Windows AI Speech"
    };

    private readonly Button _checkButton = new() { AutoSize = true, Text = "检查系统模型" };
    private readonly Button _prepareButton = new() { AutoSize = true, Text = "准备系统模型" };
    private readonly Button _startButton = new() { AutoSize = true, Text = "开始麦克风识别" };
    private readonly Button _stopButton = new() { AutoSize = true, Enabled = false, Text = "停止识别" };
    private readonly RichTextBox _transcript = new()
    {
        Dock = DockStyle.Fill,
        ReadOnly = true,
        Font = new Font("Microsoft YaHei UI", 11),
        BackColor = SystemColors.Window
    };

    private SpeechRecognitionModel? _model;
    private StreamingRecognition? _recognition;
    private AIFeatureReadyState? _lastReadyState;
    private SpeechRecognitionModelProgressStatus? _lastModelProgressStatus;
    private int _lastModelProgressBucket = -1;
    private readonly string _statusLogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LinguaGlass",
        "WindowsAIPoc",
        "status.log");

    public MainForm()
    {
        Text = "LinguaGlass · Windows AI Speech PoC";
        Width = 860;
        Height = 620;
        MinimumSize = new Size(680, 480);
        StartPosition = FormStartPosition.CenterScreen;

        var actions = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            FlowDirection = FlowDirection.LeftToRight,
            Padding = new Padding(0, 12, 0, 8),
            WrapContents = true
        };
        actions.Controls.AddRange([_checkButton, _prepareButton, _startButton, _stopButton]);

        var description = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(790, 0),
            Text = "此窗口只用于验证 systemAIModels、模型准备和麦克风 partial/final。" +
                   "模型不会在未经确认的情况下下载。"
        };

        var layout = new TableLayoutPanel
        {
            ColumnCount = 1,
            Dock = DockStyle.Fill,
            Padding = new Padding(20),
            RowCount = 4
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(_readyState, 0, 0);
        layout.Controls.Add(description, 0, 1);
        layout.Controls.Add(actions, 0, 2);
        layout.Controls.Add(_transcript, 0, 3);
        Controls.Add(layout);

        Append("backend-status", "session-start");

        _checkButton.Click += async (_, _) => await CheckReadyStateAsync();
        _prepareButton.Click += async (_, _) => await PrepareModelAsync();
        _startButton.Click += async (_, _) => await StartRecognitionAsync();
        _stopButton.Click += (_, _) => StopRecognition();
        FormClosing += (_, _) => StopRecognition();
        Shown += async (_, _) => await CheckReadyStateAsync();
    }

    private async Task CheckReadyStateAsync()
    {
        SetBusy(true, "正在检查 Windows AI Speech…");
        try
        {
            var stateTask = Task.Run(SpeechRecognitionModel.GetReadyState);
            var completed = await Task.WhenAny(stateTask, Task.Delay(TimeSpan.FromSeconds(15)));
            if (completed != stateTask)
            {
                throw new TimeoutException("Windows AI Speech 状态检查超过 15 秒仍未返回。");
            }

            var state = await stateTask;
            _lastReadyState = state;
            _readyState.Text = $"Windows AI Speech：{Describe(state)}";
            _prepareButton.Enabled = state != AIFeatureReadyState.Ready;
            _startButton.Enabled = state == AIFeatureReadyState.Ready && _recognition is null;
            Append("backend-status", $"ready-state={state}");
        }
        catch (Exception error)
        {
            _lastReadyState = null;
            SetFailure("读取系统模型状态失败", error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task PrepareModelAsync()
    {
        if (MessageBox.Show(
                this,
                "Windows 可能需要通过 Windows Update 下载语音识别模型。是否继续？",
                "准备 Windows AI Speech",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information) != DialogResult.Yes)
        {
            Append("backend-status", "model-download-declined");
            return;
        }

        SetBusy(true, "正在准备 Windows AI Speech 模型…");
        try
        {
            _lastModelProgressStatus = null;
            _lastModelProgressBucket = -1;
            var operation = SpeechRecognitionModel.EnsureReadyAsync();
            operation.Progress = (_, progress) => PostModelProgress(progress);
            var result = await operation;
            Append("backend-status", $"ensure-ready={result.Status}");
            await CheckReadyStateAsync();
        }
        catch (Exception error)
        {
            SetFailure("系统模型准备失败", error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task StartRecognitionAsync()
    {
        SetBusy(true, "正在创建 Windows AI Speech 识别器…");
        try
        {
            var modelResult = await SpeechRecognitionModel.TryCreateAsync();
            _model = modelResult.SpeechModel ?? throw new InvalidOperationException(
                $"系统模型创建失败：{modelResult.ExtendedError}");

            var deviceId = MediaDevice.GetDefaultAudioCaptureId(AudioDeviceRole.Default);
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                throw new InvalidOperationException("没有可用的默认麦克风设备。");
            }

            var audio = AudioConfiguration.FromAudioDevice(deviceId);
            _recognition = new StreamingRecognition(audio, _model);
            _recognition.Recognizing += OnRecognizing;
            _recognition.Recognized += OnRecognized;
            await _recognition.StartContinuousRecognitionAsync();

            _readyState.Text = "Windows AI Speech：正在监听麦克风";
            _startButton.Enabled = false;
            _stopButton.Enabled = true;
            Append("backend-status", "listening");
        }
        catch (Exception error)
        {
            StopRecognition();
            SetFailure("无法开始麦克风识别", error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void StopRecognition()
    {
        if (_recognition is not null)
        {
            try
            {
                _recognition.StopContinuousRecognition();
            }
            catch (Exception error)
            {
                Append("error", $"stop-failed: {error.HResult:X8}");
            }

            _recognition.Recognizing -= OnRecognizing;
            _recognition.Recognized -= OnRecognized;
            _recognition.Dispose();
            _recognition = null;
        }

        _model?.Dispose();
        _model = null;
        _stopButton.Enabled = false;
        Append("backend-status", "idle");
        _readyState.Text = "Windows AI Speech：已停止；可重新检查或开始识别";
    }

    private void OnRecognizing(StreamingRecognition sender, StreamingRecognizingEventArgs args) =>
        PostTranscript("partial", args.Text);

    private void OnRecognized(StreamingRecognition sender, StreamingRecognizedEventArgs args) =>
        PostTranscript("final", args.Text);

    private void PostTranscript(string kind, string text)
    {
        if (IsDisposed)
        {
            return;
        }

        BeginInvoke(() => Append(kind, text));
    }

    private void PostModelProgress(SpeechRecognitionModelProgress progress)
    {
        if (IsDisposed)
        {
            return;
        }

        BeginInvoke(() =>
        {
            var normalized = Math.Clamp(progress.Progress, 0, 1);
            var percentage = (int)Math.Round(normalized * 100);
            _readyState.Text = $"Windows AI Speech：{Describe(progress.Status)} · {percentage}%";

            var bucket = percentage / 5;
            if (progress.Status != _lastModelProgressStatus || bucket != _lastModelProgressBucket)
            {
                _lastModelProgressStatus = progress.Status;
                _lastModelProgressBucket = bucket;
                Append("backend-status", $"model-progress; status={progress.Status}; progress={normalized:F3}");
            }
        });
    }

    private void Append(string kind, string text)
    {
        var line = $"{DateTimeOffset.Now:O}  {kind,-14} {text}{Environment.NewLine}";
        _transcript.AppendText(line);
        _transcript.SelectionStart = _transcript.TextLength;
        _transcript.ScrollToCaret();

        if (kind is "backend-status" or "error")
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_statusLogPath)!);
                File.AppendAllText(_statusLogPath, line);
            }
            catch
            {
                // Diagnostics must never interrupt model or microphone validation.
            }
        }
    }

    private void SetBusy(bool busy, string? message = null)
    {
        UseWaitCursor = busy;
        _checkButton.Enabled = !busy;
        _prepareButton.Enabled = !busy && _lastReadyState != AIFeatureReadyState.Ready;
        _startButton.Enabled = !busy && _lastReadyState == AIFeatureReadyState.Ready && _recognition is null;
        if (message is not null)
        {
            _readyState.Text = message;
            Append("backend-status", message);
        }
    }

    private void SetFailure(string message, Exception error)
    {
        _readyState.Text = message;
        Append("error", $"{message}; hresult=0x{error.HResult:X8}; {error.Message}");
        MessageBox.Show(this, error.Message, message, MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private static string Describe(AIFeatureReadyState state) => state switch
    {
        AIFeatureReadyState.Ready => "已就绪",
        AIFeatureReadyState.NotReady => "尚未安装",
        AIFeatureReadyState.NotSupportedOnCurrentSystem => "当前系统不支持",
        AIFeatureReadyState.DisabledByUser => "已被用户禁用",
        _ => state.ToString()
    };

    private static string Describe(SpeechRecognitionModelProgressStatus status) => status switch
    {
        SpeechRecognitionModelProgressStatus.Installing => "正在下载并安装",
        SpeechRecognitionModelProgressStatus.Caching => "正在缓存",
        SpeechRecognitionModelProgressStatus.Loading => "正在加载",
        SpeechRecognitionModelProgressStatus.CompletedSuccess => "准备完成",
        SpeechRecognitionModelProgressStatus.CompletedFailure => "准备失败",
        _ => status.ToString()
    };
}
