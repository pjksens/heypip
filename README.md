<p align="center">
  <img src="docs/media/hero.png" alt="Pip, a tiny friend in your Mac's notch that whispers what to say during calls">
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/pjksens/heypip?label=download&color=2B59FF" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/transcription-on%20your%20Mac-0A84FF" alt="On device">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/pjksens/heypip?style=flat&color=FFD60A&label=%E2%98%85%20stars" alt="Stars"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.fr.md">Français</a>
</p>

<p align="center">
  Made by <b>pjk</b> (Sacha Praljak) ·
  <a href="https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=heypip">sachapraljak.com</a> ·
  <a href="https://www.instagram.com/sachaprljk/">Instagram</a> ·
  <a href="https://www.tiktok.com/@sachaprljk">TikTok</a>
</p>

<p align="center">
  <b>If Pip helps you, a ⭐ helps other people find it.</b>
</p>

**Pip lives in your MacBook's notch and brings your AI agent into your meetings.** During a video call, a client
appointment or a team meeting on Google Meet, Zoom or Teams, Pip transcribes what you say and what the others say, live and
on your Mac. Your agent (Claude Code, Codex, any agent that can read a file) follows the conversation and helps you run it:
the next question to ask, the option to pick, a fact it just looked up, the point nobody settled.
Pip leans out of the notch to whisper it.

<p align="center">
  <img src="docs/media/demo.gif" width="640" alt="Pip during a call: the transcript fills in live, then Pip leans out of the notch to whisper the agent's notes">
  <br><sub>Scripted demo (<code>Pip --demo en</code>): no real call, no real people.</sub>
</p>

## Your agent, in the meeting with you

- **Helps you decide.** They offer two options: your agent weighs them against what you told it before the call and
  tells you which one to take, and why.
- **Steers the meeting.** The question to ask next, the point of your agenda you have not covered yet, the right moment
  to talk price.
- **Looks things up while you talk.** A company, a competitor's price, a rule you are not sure about: your agent searches
  and whispers the answer. Needs an agent with web access, like Claude Code.
- **Checks what is said.** A number that does not add up, a promise that contradicts what was said earlier.
- **Writes the follow-up.** When the call ends: the summary, the decisions, the next steps, the email.

Pip carries the conversation to your agent and its notes back to you; what the agent can do depends on the agent you
connect. A sentence reaches your agent 1–3 s after it is said. In our tests with Claude Code, a note came 3 to 8 s
after the sentence that called for it (about 5 s typically), and 17 to 20 s when the agent searched the web first.

## See it negotiate

A test call: a fictional client, every line scripted, a real Claude Code session. Claude's notes, unedited:

| They said | Pip whispered |
|---|---|
| « Our budget is 800 euros, max. » | €800 < €990 (gap €190). Don't cut Complete: offer Essential + 2 formats ~€800, or 2 pay steps |
| « Could you invoice us at 90 days? » | Fact: FR law caps B2B payment at 60 d from invoice (L441-10). 90 d not allowed *(after a web search, 17 s)* |
| « …plus the video at 490, that's 700 euros. » | WRONG: 490+3x100 = 790, not 700. Also never quoted 100/format: Complete = €990. Correct now |

The whole call, the timings and the summary Claude wrote at the end: [docs/examples/negotiation.md](docs/examples/negotiation.md).

## What Pip does

- **Live, on your Mac.** Apple's speech recognition, sentence by sentence, 1–3 s after it is said. On macOS 26 no audio leaves your Mac (macOS 15: see Privacy).
- **You and Them, separately.** Your microphone is « You », the call's audio is « Them », each on its own track.
- **Your agent, or not.** One switch turns the agent off: Pip keeps transcribing, and nothing is written for the agent.
- **Pause** when the call goes off the record: nothing is heard or saved until you resume.
- **One folder per meeting:** the transcript, both audio tracks and your agent's notes.
- **Updates itself** from this repo's releases, between meetings, after checking the new version is signed by the same developer.
- **Pip shows how things are going.**

<p align="center">
  <img src="docs/media/moods.png" width="640" alt="Pip's states: ready, getting ready, listening, nobody talking, paused, has a note, saved, problem">
</p>

## Install

1. Download **Pip.zip** from the [latest release](../../releases/latest), unzip it and move **Pip** to Applications.
2. Open Pip. A little dotted Pip appears on the left of your notch: move your pointer onto it.
3. Press **Start**. macOS asks for **Screen & System Audio Recording** (to hear the call) and **Microphone**.
   If it asks you to quit and reopen Pip, do it, then press Start again.

Requirements: macOS 15 or later, Apple silicon or Intel. On macOS 26 Pip uses Apple's new SpeechAnalyzer (faster, better);
on macOS 15 the previous speech recognizer. The speech model for your language downloads once. On macOS 15,
on-device transcription is not guaranteed (see Privacy).

**Best with headphones.** Without them your microphone also hears the call. Pip removes that echo from « You », but your
voice mixed with the speakers is recognised a little less well.

> Recording or transcribing a call usually requires the consent of everyone in it. Tell people at the start: Pip reminds you.

## Use

| | |
|---|---|
| Open Pip | move your pointer onto Pip, left of the notch; click to keep it open, click outside to close |
| Start, pause, stop | the buttons under Pip, or the menu |
| Turn the agent on or off | **✦ Claude** at the top of Pip |
| Look back at a recent meeting, start a new one | click the meeting's name, top left of the island |
| Language, vocabulary, folder, quit | the gear, or right-click Pip |
| Hide the little Pip next to the notch | right-click Pip → **Pip next to the notch** |
| Put Pip in the menu bar | gear → **Pip in the menu bar**: Pip leaves the notch, click its icon to open it |

**Vocabulary:** add the names of people, companies and products you talk about so they are transcribed right
(`~/Library/Application Support/Pip/vocabulary.txt`).

Each meeting is a folder in `~/Documents/Pip/<date>_<name>/`:

| File | What |
|---|---|
| `transcript.md` | one line per sentence, `[12:03:15] You: …` Always written, stays on your Mac. |
| `agent-feed.md` | the same lines, only while the agent is on. **This is the file your agent follows.** |
| `notes.md` | written by your agent; the newest line pops out of the notch |
| `summary.md` | written by your agent when the meeting ends (if you ask it to) |
| `you.m4a`, `them.m4a` | the audio of each side |
| `screens/` | with Claude Code: screenshots of what was on your screen, kept only where it changed or when it mattered (see below) |

`~/Documents/Pip/current` always points to the meeting in progress.

## Connect your agent

Your agent follows `agent-feed.md` and adds one short line per note to `notes.md`.

**Claude Code** (a recent version: it uses the Monitor tool).

1. Install the `/pip` command, once:

   ```bash
   mkdir -p ~/.claude/skills/pip && curl -fsSL https://raw.githubusercontent.com/pjksens/heypip/main/integrations/claude-code/pip/SKILL.md -o ~/.claude/skills/pip/SKILL.md && curl -fsSL https://raw.githubusercontent.com/pjksens/heypip/main/integrations/claude-code/pip/screens.sh -o ~/.claude/skills/pip/screens.sh
   ```

2. Before the call, run `claude` in a terminal and type `/pip` with who you are meeting and what you want out of it:

   ```
   /pip Call with Atelier Lune, they want a launch video. Goal: close the €990 package, paid within 30 days.
   ```

3. Press **Start** in Pip, with **✦ Claude** on. Notes pop out of the notch; when you stop, the summary is in
   `summary.md`. If no agent is reading the feed, Pip says so in the notch after 20 seconds.

During the call you can ask Claude out loud: « Claude, what did they pay last time? ». The answer comes as the next
note (the other side hears the question too).

**Screenshots.** Claude also keeps what was shown on screen: a capture every 15 seconds while the meeting runs, plus
one at once when a screen is shared, a document or a number is shown, or you say « Claude, capture ». When the meeting
ends, only the key captures and those where the screen changed are kept, in `screens/` with an `index.md`; the rest is
deleted, and the summary cites each kept image. Everything stays in the meeting folder. The app that runs Claude Code
(your terminal, or the Claude app) needs **Screen Recording** in System Settings. Type `/pip --no-screens …` to skip
screenshots for a call.

A meeting recorded without an agent can be summarised afterwards: `/pip summary` (the latest meeting) or
`/pip summary ~/Documents/Pip/<folder>` writes `summary.md` in that folder.

Without the command, tell Claude who you are meeting and what you want out of it, then paste:

   > Follow my call with Pip and help me get to my goal. Watch `~/Documents/Pip/current/agent-feed.md` with the Monitor
   > tool (`tail -n 0 -F`). When something deserves it, add ONE line of 90 characters max to
   > `~/Documents/Pip/current/notes.md`: the next question to ask, the option I should pick and why, an unclear point,
   > a number that does not add up, a fact you looked up. Search the web when a fact is worth checking.
   > Stay quiet otherwise. When the meeting ends, write the summary, the decisions and the next steps
   > in `~/Documents/Pip/current/summary.md`.

**Any other agent:** anything that can watch a file and write one is enough. The
[`/pip` command](integrations/claude-code/pip/SKILL.md) is plain instructions you can give it.

## Privacy

- On macOS 26, transcription runs on your Mac (Apple's SpeechAnalyzer).
- On macOS 15, Pip asks for on-device transcription first. If your language's model isn't available on the Mac,
  Apple's speech recognition uses Apple's servers, so on-device transcription is not guaranteed there.
- Pip itself has no account, no server, no analytics, and sends nothing anywhere.
- Your agent only sees `agent-feed.md`, and only while it is on. If your agent runs in the cloud, what it reads goes to its provider.
- Audio and transcripts stay in your meetings folder until you delete them.

Found a leak? See [SECURITY.md](SECURITY.md).

## FAQ

**Does it join the call like a bot?** No. Nobody sees Pip: it listens to your Mac, like your ears do.

**Does it work without an agent?** Yes. Turn the agent off and Pip is a private, live transcriber.

**Does it work for meetings in person?** Yes, with your Mac's microphone, but then everyone is « You »: Pip tells
the sides apart only on a call.

**My Mac has no notch.** Pip sits at the top center of your screen instead, or in the menu bar if you prefer
(gear → **Pip in the menu bar**).

**Which languages?** Every language your Mac's speech recognition supports. The interface is in English and French.

## Build from source

```bash
git clone https://github.com/pjksens/heypip.git && cd heypip
bash build.sh && open Pip.app
```

Needs Xcode 26 command line tools. See [AGENTS.md](AGENTS.md) for the map of the code and how to check a change,
and [CONTRIBUTING.md](CONTRIBUTING.md) to help.

## Roadmap

- Tell apart several people on the « Them » side, after the call.
- A first-launch guide (permissions, headphones, consent).

## Made by

**pjk** (Sacha Praljak). I build AI tools and show them in short videos. Pip is built with Claude Code.

- Site: [sachapraljak.com](https://sachapraljak.com/?utm_source=github&utm_medium=readme&utm_campaign=heypip)
- Instagram: [@sachaprljk](https://www.instagram.com/sachaprljk/)
- TikTok: [@sachaprljk](https://www.tiktok.com/@sachaprljk)

If Pip helps you, a ⭐ on the repo and a follow help a lot.

## License

[MIT](LICENSE)
