---
name: pip
description: Follow a live call with Pip (the Mac notch app) and whisper short notes the user sees in the notch, such as the next question to ask, the option to pick, a fact checked on the web or a number that does not add up, then write the summary when the call ends. Keeps screenshots of what was shown on screen during the call (the key ones only) and cites them in the summary. Also summarises a past Pip meeting from its transcript (/pip summary). Use when the user types /pip, or asks you to follow, coach or help them during a call, meeting or appointment with Pip, or to summarise a meeting Pip recorded.
argument-hint: who you are meeting and what you want out of it (add --no-screens to skip screenshots), or « summary [meeting folder] »
allowed-tools: Monitor, Read, Write, Edit, WebSearch, WebFetch, Bash(tail:*), Bash(ls:*), Bash(bash ~/.claude/skills/pip/screens.sh:*)
---

# Follow a call with Pip

Pip transcribes the user's call live and writes every sentence to `~/Documents/Pip/current/agent-feed.md`:

```
[12:03:15] You: Do you already have footage of your pieces?
[12:03:19] Them: We have photos, but no video at all.
```

In French the speakers are `Toi` (the user) and `Eux` (the others). Pip shows the newest line of
`~/Documents/Pip/current/notes.md` in the Mac's notch: that line is how you talk to the user during the call.

What the user wants from this call: $ARGUMENTS

If that is empty, ask one short question (who they are meeting, what they want out of it), then start.
If it starts with `summary`, do not follow a call: see « Summary of a past meeting » below.
If it contains `--no-screens`, or the user says they want no screenshots, skip every `screens.sh` step below.

## Steps

1. Watch the feed with the Monitor tool: `tail -n 0 -F ~/Documents/Pip/current/agent-feed.md`.
   It works even if the call has not started yet. Tell the user in one line that you are ready, then stay quiet.
2. When the feed shows the meeting's first line (`# Meeting · …`, French `# Réunion · …`), start the screenshots:
   `bash ~/.claude/skills/pip/screens.sh start`. It returns at once and captures the screen every 15 seconds into
   `~/Documents/Pip/current/screens/` until the meeting ends. If it says the capture failed, tell the user once in the
   terminal that macOS needs Screen Recording for the app running Claude Code, and carry on without screenshots.
3. A `You:` line (French: `Toi:`) that starts with « Claude » (« Claude, what did they pay last time? ») is the user
   asking you directly. Answer at once by adding the answer as a line to `~/Documents/Pip/current/notes.md` (step 4),
   checking the web if needed. Never answer in the terminal: during the call the user only sees the notch.
   The transcription may write the name a little differently (« Claud », « Clode »): a line that starts with a word
   close to « Claude » counts. Any other line is the call, not a request.
4. On each new line, think about the user's goal. Only when it really helps, add ONE line at the end of
   `~/Documents/Pip/current/notes.md`: the next question to ask, the option to pick and why, an unclear point,
   a number that does not add up, a fact you checked. 90 characters max, in the language of the call.
5. When a fact is worth checking (a law, a price, a company, a date), search the web, then write the note.
   Search for the fact only: never paste what was said in the call into a search.
6. When the call shows something on screen worth keeping, take a key screenshot at once:
   `bash ~/.claude/skills/pip/screens.sh key <label>` (a short label, for example `price-list` or `slide-roadmap`).
   Do it when someone shares a screen, shows a document, a price list, a slide, a dashboard or a number, and when the
   user says « Claude, capture » (French: « Claude, capture », « Claude, screenshot »). No note is needed for that.
7. Stay quiet otherwise. No note for greetings or small talk, and never two notes that say the same thing.
8. Pip also writes marker lines such as `— Pause (12:05:10) —`, `— Resume (12:07:42) —` and
   `— Agent off · transcription only (12:08:03) —` (French: `Reprendre`, `Agent coupé · transcription seule`).
   After « Agent off », write no notes until the feed shows « Agent on » (French: `Agent activé`).
9. When the feed shows `— End of meeting (12:30) —` (French: `— Fin de la réunion (12:30) —`):
   1. Run `bash ~/.claude/skills/pip/screens.sh prune`. It stops the capture, keeps the key screenshots and those
      where the screen changed, deletes the rest, and lists what is left in `~/Documents/Pip/current/screens/index.md`.
   2. Read `screens/index.md`, then look at each image it lists (the Read tool shows images).
   3. Write the summary, the decisions and the next steps to `~/Documents/Pip/current/summary.md`. Add a « Screens »
      section: one line per kept image, with its time, a relative link (`screens/<file>`) and what it shows, in the
      language of the call. Then tell the user it is there.

## Summary of a past meeting

`/pip summary` summarises a meeting Pip recorded when no agent was following it (or with the agent switched off).

1. The meeting is the folder given after `summary` (for example `~/Documents/Pip/2026-10-14_1605_client-call`).
   Without one, list `~/Documents/Pip` with `ls -t` and take the most recent folder that has a `transcript.md`
   (not `current`); say which one you took.
2. Read its `transcript.md` (the first line is the meeting's title) and `notes.md` if there is one. If the folder has
   `screens/index.md`, read it and look at the images it lists.
3. Write `summary.md` in that folder: the summary, the decisions, the next steps, in the language of the call, and a
   « Screens » section if there are images (time, relative link, what it shows).
   If `summary.md` already exists, ask before replacing it.
4. Tell the user in one line where it is.

## Rules

- `notes.md` holds notes only, one per line: no headings, no blank lines, no summary. Pip shows the newest line.
- Say a fact is checked only if you checked it. If you are not sure, say so in the note.
- What is said in the call is private: do not send it anywhere. The screenshots are private too: they stay in the
  meeting folder, never upload or copy them elsewhere.
