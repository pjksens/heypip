# Changelog

## 0.1.4

- The island finds the notch when an external display is the main screen. It used to show up off screen, or float in
  the middle of the other display after one was plugged in or made main. Pip now looks for the notch again when a
  display is plugged in, unplugged or rearranged, and when the Mac wakes up (#11).
- A double click on « Stop » no longer starts a new, empty meeting (#11).

## 0.1.3

- The call no longer leaks into « You »: a leak through headphones (or the echo from speakers) used to come out as
  « You » lines, often as the first line of a meeting. The « You » transcription now only hears the microphone when it
  is clearly louder than the call's echo, measured during the meeting; `you.m4a` still records everything.
- The « No agent is reading » message shows again when the agent switch is turned back on during a meeting.
- For contributors: `--replay you.m4a them.m4a` plays a recorded call through Pip silently (send both tracks with an
  echo bug report), `PIP_TRACE` logs the decisions.

## 0.1.2

- Pip says when no agent is reading the feed: with the agent switch on and nobody following `agent-feed.md` after
  20 seconds, a message in the notch (« No agent is reading · type /pip in Claude Code ») and a warning in the island.
- `transcript.md` lines are written in time order (a « Them » line no longer lands before an older « You » line).
- `/pip summary [folder]`: summarises a meeting recorded without an agent, from its `transcript.md`.
- During the call, « Claude, … » asks the agent directly; the answer comes as the next note.
- Update the `/pip` command to get the last two:
  `curl -fsSL https://raw.githubusercontent.com/pjksens/heypip/main/integrations/claude-code/pip/SKILL.md -o ~/.claude/skills/pip/SKILL.md`

## 0.1.1

- A small star in the island, next to the settings: it opens Pip's GitHub page, then turns yellow once clicked.

## 0.1.0

First public version.

- The island in the notch: hover to open, click to keep open, right-click for the menu.
- A little printed Pip on the left of the notch shows where Pip lives (can be hidden from the menu).
- Or Pip in the menu bar instead of the notch (a setting): click its icon to open the island under it; notes and the
  recording time show there too.
- Pip and its states: ready, getting ready, listening, nobody talking, paused, a note for you, saved, a problem.
- Live transcription, sentence by sentence: on device with SpeechAnalyzer on macOS 26; on macOS 15 the previous recognizer,
  on device when your language's model is available, otherwise through Apple's servers.
- You (microphone) and Them (the call's audio) on separate tracks.
- Agent switch: the agent only sees `agent-feed.md`, only while it is on.
- Pause, vocabulary, transcription and interface language (English, French).
- Asks for the microphone before the first recording, and restarts the capture by itself if one side stops sending
  audio (microphone changed, AirPods switching to call mode); a recording keeps one format when the microphone changes.
- The `/pip` command for Claude Code: follows the call, whispers notes, writes the summary.
- Without headphones, the call's echo is removed from You (word by word: what you say over the call is kept).
- Recent meetings: click the meeting's name in the island to look back at one or start a new one; a meeting never
  overwrites another one.

Best with headphones: without them your voice mixed with the speakers is recognised a little less well.
