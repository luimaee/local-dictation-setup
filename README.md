# local-dictation-setup

Hold a key, talk, and the text lands at your cursor. Fully local — no cloud, no
subscription, no audio leaving the machine.

This repo is the writeup of an actual install done on two machines, including
the parts that went wrong. It uses [Handy](https://github.com/cjpais/Handy)
(MIT), which runs on Windows, macOS and Linux.

## Start here: will Sotto work for you?

A lot of people arrive at local dictation through
[Sotto](https://github.com/kingbootoshi/sotto) and the "talk to your computer"
writeup. Sotto is genuinely good, but check this before you spend an hour on it:

> **Sotto is Apple Silicon only.** It runs FluidAudio's Parakeet TDT model on
> CoreML against the Apple Neural Engine. Intel Macs do not have one. There is
> no CPU fallback and no build flag that changes this.

| Your machine | Sotto | Handy |
| --- | --- | --- |
| Apple Silicon Mac (M1–M4) | Yes | Yes |
| Intel Mac | **No** | Yes |
| Windows | **No** | Yes |
| Linux | **No** | Yes |

If you're on Apple Silicon and only want dictation on that Mac, try Sotto first
— it's purpose-built for that hardware. Everyone else, keep reading.

## What you get with Handy

- Push-to-talk or toggle, your choice of hotkey
- Transcription runs on your own GPU or CPU, offline
- Text pastes into whatever app has focus
- ~70 models to pick from, downloaded on demand
- MIT licensed

## Install

### Windows

```powershell
winget install --id cjpais.Handy -e --source winget
```

That's the whole thing. winget pulls the Vulkan runtime and VC++ redistributable
as dependencies, which is what gets you GPU acceleration.

Or run [`scripts/install-handy.ps1`](scripts/install-handy.ps1), which does the
same and then reports your GPU, RAM and which compute backends Handy registered.

### macOS

```bash
brew install --cask handy
```

Manual download if you don't use Homebrew — **check your chip first**, the
Apple Silicon build will not launch on an Intel Mac:

```bash
# Apple Silicon
curl -L -o Handy.dmg https://github.com/cjpais/Handy/releases/download/v0.9.6/Handy_0.9.6_aarch64.dmg
# Intel
curl -L -o Handy.dmg https://github.com/cjpais/Handy/releases/download/v0.9.6/Handy_0.9.6_x64.dmg

open Handy.dmg   # then drag Handy to Applications
```

If macOS refuses to open it ("damaged"):

```bash
xattr -cr /Applications/Handy.app
```

### Linux

`.deb`, `.rpm` and `.AppImage` for x86_64 and aarch64 are on the
[releases page](https://github.com/cjpais/Handy/releases).

## Permissions

**macOS** asks for two, and both are load-bearing:

- **Microphone** — obvious one, prompted on first launch.
- **Accessibility** — System Settings → Privacy & Security → Accessibility.
  This is the one people skip. Without it dictation records and transcribes
  fine and then silently pastes nothing.

**Windows** needs neither in practice. Microphone access for desktop apps is on
by default; confirm at Settings → Privacy & security → Microphone if dictation
records silence.

## Picking a model

This is the decision that actually determines whether you like the tool, and it
depends entirely on whether you have a usable GPU.

| Model | Size | Notes |
| --- | --- | --- |
| Canary 180M Flash | 208 MB | Tiny, instant, runs on anything. Accuracy is the tradeoff. |
| Parakeet Unified EN 0.6B | 697 MB | English only. Fast *and* accurate. Best pick for CPU-only. |
| Nemotron Streaming 3.5 | 716 MB | 28 languages, streaming. |
| Cohere Transcribe | 1.6 GB | Highest accuracy. Labeled "slower" — that assumes CPU. |
| Whisper Medium / Large | varies | Broadest language coverage, heaviest. |

### Size the model against FREE VRAM, not against your GPU

This is the mistake worth learning from someone else's time. "I have a decent
GPU, so I'll take the big model" is wrong reasoning. What matters is how much
VRAM is **free while you actually work**, and a modern desktop eats a lot of it.

Measure first:

```powershell
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free --format=csv
```

A real reading from an RTX 2060 box mid-workday — browsers, Electron apps, a
couple of WebView2 processes, vendor tray utilities:

```
NVIDIA GeForce RTX 2060, 6144 MiB total, 4728 MiB used, 1218 MiB free
```

6 GB card, **1.2 GB actually available**. Cohere Transcribe is a 1.6 GB model.
It loaded, and it "worked" — but see the symptom below.

**Pick a model that fits in the free figure, with room to spare.** Weights are
the floor, not the ceiling: activation buffers grow with how long you speak.

| Free VRAM | Take |
| --- | --- |
| < 1.5 GB (or no usable GPU) | Parakeet Unified EN 0.6B, or Canary 180M |
| 1.5–3 GB | Parakeet Unified EN 0.6B comfortably |
| 3 GB+ | Cohere Transcribe |

### The symptom of a model that doesn't fit

It does not fail loudly. It gets **super-linearly slower as clips get longer**,
because short utterances fit in the VRAM that's left and long ones spill across
PCIe into system RAM. Measured on the 1.2 GB-free machine above with Cohere:

| Audio | Time | Speed |
| --- | --- | --- |
| 2.13s | 0.31s | 6.8x real-time |
| 2.25s | 0.37s | 6.1x real-time |
| 7.05s | 16.56s | **0.43x real-time** |

Three times the audio, **fifty times** the work. If short test phrases feel
instant but real sentences hang, you are over your VRAM budget — drop a model
size. Don't be fooled by a quick "testing, one two three."

Handy logs the ratio, so you can check rather than guess:

```
Transcription completed in 16.56s for 7.05s of audio (0.43x real-time)
```

Anything below 1.0x means transcribing takes longer than talking did.

### Other rules of thumb

- **No discrete GPU (incl. every Intel Mac):** Parakeet Unified EN. If you pick
  Whisper, pick Small, not Medium — Medium on an Intel CPU crawls.
- **You dictate in more than one language:** Nemotron or Whisper. Parakeet
  Unified EN is English-only and will not degrade gracefully.
- **First run after a model load is always slow** (8–11s is normal) — that's the
  load, not the transcription. Judge speed from the second run onward.

### Confirming you're actually on the GPU

Don't assume. Handy says so in its log:

- Windows: `%LOCALAPPDATA%\com.pais.handy\logs\handy.log`
- macOS: `~/Library/Logs/com.pais.handy/`

Look for a line like:

```
Loaded whisper model '...' (requested Auto, bound backend 'Vulkan0',
bound device 'NVIDIA GeForce RTX 2060', ...)
```

`bound backend 'CPU'` means you're on the CPU and should expect a real pause
after you stop speaking.

## Hotkeys

Handy's defaults are `Ctrl+Space` on Windows and `Option+Space` on macOS.

**The Windows default is a bad default if you write code.** `Ctrl+Space` is
"trigger suggestion" in VS Code, Cursor, most JetBrains IDEs and Visual Studio.
It will fight with autocomplete every time you dictate in an editor. Change it.

Handy accepts **modifier-only bindings**, which is the nicest setup for
push-to-talk — nothing to mistype, no conflict with an app's own shortcuts.
`ctrl+win` works and registers as:

```
Registered handy-keys shortcut: transcribe ->
  Hotkey { modifiers: Modifiers(CMD_LEFT | CTRL_LEFT | CMD_RIGHT | CTRL_RIGHT), key: None }
```

Set it in the UI, or script it — see below.

## Scripting the config

Handy keeps everything in one JSON file, so the whole setup is automatable:

- Windows: `%APPDATA%\com.pais.handy\settings_store.json`
- macOS: `~/Library/Application Support/com.pais.handy/settings_store.json`

[`scripts/configure-handy.ps1`](scripts/configure-handy.ps1) patches the hotkey
and autostart safely.

### Two traps if you edit it yourself

**1. Do not write a BOM.** This cost me the whole config once. PowerShell 5's
`Set-Content -Encoding UTF8` prepends a UTF-8 byte-order mark. Handy's parser
rejects the file, falls back to defaults, and silently wipes your selected model
and every other setting. Write UTF-8 *without* BOM:

```powershell
[IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
```

Verify — the first byte must be `123` (`{`), not `239`:

```powershell
$b = [IO.File]::ReadAllBytes($path); $b[0]
```

**2. Quit Handy first.** It holds settings in memory and writes on exit, so any
edit you make while it's running gets overwritten. Stop it, edit, relaunch.

Back the file up before touching it. `configure-handy.ps1` does.

## Things that bite

- **Another dictation app running.** Wispr Flow, superwhisper, MacWhisper and
  Windows' own Voice Access all register global hotkeys. If Handy's hotkey does
  nothing, something else grabbed it first.
- **Virtual audio devices.** Voicemeeter, VB-Cable, OBS virtual mics and the
  like mean "Default" may not be your actual microphone. Set the input device
  explicitly in Handy's settings.
- **First dictation after a break is slow.** Handy unloads the model after 5
  minutes idle. Settings → Advanced → Unload Model → Never keeps it resident, at
  the cost of holding the model in RAM/VRAM permanently.
- **Accessibility permission on macOS** — again, because it's the single most
  common reason "it records but nothing appears."

## Credits

- [Handy](https://github.com/cjpais/Handy) by cjpais — MIT
- [Sotto](https://github.com/kingbootoshi/sotto) by kingbootoshi — MIT
- Model catalog served from [Hugging Face](https://huggingface.co)

This repo is documentation and helper scripts only. It vendors no code from
either project.

## License

MIT — see [LICENSE](LICENSE).
