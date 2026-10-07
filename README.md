# Wordzel

<img src="wordzel.png" alt="Wordzel icon" width="120" align="right">

A Wordle-style word game for kids, built with Lazarus / Free Pascal - with a
great deal of poop.

**Wordle + Hazel = Wordzel.** Made for Hazel, who discovered that the best
thing to guess in Wordle is FARTS, and the second best is POOPS.

## Features

- **Difficulty levels** (secret words come from the eligible pool; any
  dictionary word of the right length is still a legal guess):
  - Easy (3 letters - 4 tries) - 299 possible answers
  - Medium (4 letters - 5 tries) - 1,021
  - Normal (5 letters - 6 tries) - 1,677
  - Hard (6 letters - 7 tries) - 2,294
  - Expert (7 letters - 8 tries) - 2,558
  - Master (8 letters - 9 tries) - 2,325
  - Insane (9 letters - 10 tries) - 1,886

- **Your own secret word** - any letters, any length, real word or not. A
  made-up word switches off the dictionary check on guesses, because no
  dictionary word could ever match it. Long words shrink the tiles to fit;
  past about 100 letters the row runs off the sides - fine for a joke word.

- **Classic Wordle play** - green for right letter / right spot, yellow for
  right letter / wrong spot, grey for not in the word, with the on-screen
  keyboard coloured to match.

- **Look any word up** - hold a finger on a row (or right-click it) to see what
  its word means, *including the row you are still typing*, so a guess can be
  checked before a turn is spent on it. **🔍 Look up** takes any word at all.

- **Hourglass timer** - off, by level (30 seconds per letter plus 30: 2:00 for
  3 letters up to 5:00 for 9), 1 / 2 / 3 / 5 / 10 minutes, or a custom time
  (`90` or `2:30`). The sand runs down, turns orange and throbs in the last
  fifth, and ticks through the last ten seconds. It pauses while a definition
  or a text prompt is open. Running out of sand loses the game.

- **Potty words** - guessing any of ~200 poop and toilet words (POOPS, FARTS,
  TOILET, PLUNGER, DIARRHEA, PLUMBER...) sets off the show: a fart, the board
  shakes, poop fountains out of the row and bounces around, a giant toilet
  rises, swallows a whirlpool of poop and toilet paper with a flush, and
  blasts off out of the top. **SHART**, **DOODOO**, **CACA**, **PEEPEE** and
  friends are house words: legal guesses here, whatever the dictionary says.

- **Sounds** - key clicks, three win jingles, five fail sounds, a fart and a
  flush for potty words, and a tick at the end of the hourglass - picked at
  random where there is a choice. Both sounds and key clicks can be switched
  off from **☰**.

- **Animations** - tiles pop as you type and flip in turn to reveal a guess,
  the row shakes when a guess is not a word, the winning row bounces and
  throws confetti, and a poop storm rains down on a loss.

- **Family game server** - the same binary can serve a web version of the
  game to the whole house. Set a player name, a family passphrase and a
  port under **☰**, switch on **Run family server**, and anyone on the
  network can play at `http://<your-ip>:<port>` - same look, same potty
  words, same sounds. One shared passphrase lets people in; each player
  picks a name and a low-security PIN. Every finished game, on desktop or
  web, earns points toward the **family leaderboard** (daily and monthly):
  a win is worth `word length x (guesses remaining + 1)` points, a loss is
  worth 1, and totals simply add up - so playing a lot beats one lucky
  first try. The leaderboard pops up after every game and lives under ☰
  too. Scores are kept in plain CSVs in the config folder. There is no TLS
  in the game itself: keep it on the LAN, or put a TLS proxy in front.

## Controls

The **top bar**: **↻ New** · **Level ▾** · **⏳ Timer ▾** · **🔍 Look up** · **☰**,
with the hourglass and the score on the right. On narrow screens it squeezes in
stages - icons instead of words, then Look up drops out (it is under ☰ too),
then tighter buttons, and finally the score, if the hourglass needs the room.

The **keyboard**: letters in a staggered block, with **⌫** at the top right
and **ENTER** at the bottom right in a column of their own. ENTER becomes **⏎**
when the keys are too small for the word.

**☰** has your own secret word, look up, give up, the sound switches, how to
play, about and quit.

| Key | |
|---|---|
| letters / ENTER / BACKSPACE | play |
| ESC | close a menu, prompt or card |
| Ctrl+N | new game |
| Ctrl+M | your own secret word |
| Ctrl+L | look up a word |
| F1 | how to play |

## Setup

1. **Build the word lists** (optional - only needed if regenerating):
   ```bash
   ./tools/generate_wordlist_unit.sh      # unitwordlist.pas from the system dictionary
   ./tools/generate_commonwords_unit.sh   # unitcommonwords.pas from the frequency list
   ```
   Both units are already included in the source, so this is only needed to
   rebuild them - say, for another language.

2. **Open in Lazarus:** open `wordzel.lpi` and press F9.

   Or from the command line:
   ```bash
   lazbuild --ws=gtk3 wordzel.lpi
   ./wordzel
   ```

Developed against **Lazarus main `b9cfd22ae9` with FPC 3.3.1** (gtk3), so that
anything that turns out to be a toolchain bug can be reported against what the
FPC and Lazarus developers are working on. It also builds with
Lazarus 4.0 / FPC 3.2.2.

The sounds are compiled into the binary (as RCDATA resources, unpacked to a
temp folder at startup), so the executable is the whole game - nothing else
needs to be distributed. A `sounds/` folder beside the executable is used as
a fallback if the embedded copies cannot be unpacked.

## Files

- `unitfrmmain.pas` / `.lfm` - the game: board, keyboard, top bar, menus,
  prompts, cards, animation, timer, sound
- `unitwordpicker.pas` - word validation and secret-word selection
- `unitwordlist.pas` - embedded guess list (44,857 words, 3-9 letters)
- `unitcommonwords.pas` - embedded secret-word pool (24,116 everyday words,
  most common first)
- `unitdictionary.pas` - definition lookups on a background thread
- `unittouch.pas` - touchscreen taps under LCL-gtk3 (see below)
- `unitserver.pas` - the family game server (HTTP, on its own thread)
- `unitscores.pas` - players, PINs and the leaderboard, in plain CSVs
- `www/` - the web version of the game, compiled in as resources;
  `words.js` is generated from the Pascal word units by
  `tools/generate_words_js.sh`, so web and desktop can never disagree
- `sounds/` - `fart*.wav` and `poop*.wav` are the originals; the rest are
  generated by `tools/makesounds.py`
- `tools/wordtest.pas` - console harness for checking word quality
- `tools/makesounds.py` - synthesises the key, flush, tick, win and fail sounds
- `tools/freqlist/` - English word frequency list from
  [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit
  Dave (CC-BY-SA-4.0, from the OpenSubtitles2018 corpus) - see its README
- `tools/generate_wordlist_unit.sh` - regenerates the guess list from the
  system dictionary
- `tools/generate_commonwords_unit.sh` - regenerates the secret-word pool
  from the frequency list

## Built For Phones And Touchscreens

The game is played on phones and on a touchscreen laptop, so:

- **One window, nothing else.** There are no system menus, popup menus or
  dialog windows - modal dialogs and right-click are awkward on a phone. The
  top bar, the dropdowns, the row menu, the text prompts and the info cards
  are all drawn inside the window.
- **Press and hold is right-click.** Holding still on the board for 550 ms
  opens the row menu. A finger that wanders more than 12 px counts as a drag
  and cancels it, and the release that follows a hold does not also count as a
  tap.
- **The on-screen keyboard types into prompts too**, so a phone never needs its
  own keyboard. (A custom *timer* does need digits; the presets cover the
  common cases.)
- **Touchscreens work under LCL-gtk3** - see the next section.

### Touchscreens and LCL-gtk3

LCL-gtk3 adds `GDK_TOUCH_MASK` to every widget's event mask, but has no code
for `GDK_TOUCH_*` events. Asking for touch events is exactly what makes X/GDK
stop turning touches into emulated mouse clicks, so in an LCL-gtk3 app, taps on
a touchscreen simply vanish.

LCL's dispatcher does return `False` for touch events, so they keep bubbling up
as GTK `touch-event` signals to the top-level window. `unittouch.pas` catches
them there and the form replays them through the same mouse handlers a click
uses - taps, drags and press-and-hold all behave alike. One finger is followed
at a time, and mouse events arriving just after a touch are ignored in case a
system emulates them as well, which would otherwise type every letter twice.

This really wants fixing in LCL itself; `lcltouch/` has the write-up for the
Lazarus developers.

## Word Lists & Secret-Word Selection

Two lists, two jobs, both **compiled into the binary** - no external files
at runtime. Each is a Pascal unit generated by a script in `tools/`, so
porting the game to another language is a matter of pointing the scripts at
that language's dictionary and frequency list.

**Guessing** uses `unitwordlist.pas`: the system dictionary
(`/usr/share/dict/words`), 44,857 words of 3-9 letters, proper nouns and
possessives stripped. Every one of them is legal, so you can burn a turn on
an obscure word to eliminate letters. Lookup is a binary search over the
sorted list, plus a short list of house words (`EXTRA_WORDS`).

**Secret words** come from `unitcommonwords.pas`: the subset of the
dictionary that also appears in a word frequency list built from millions of
movie and TV subtitles - everyday language, ordered most common first. The
dictionary alone is full of real-but-obscure entries (DHOTI, WROTH, ABACI,
CHERUBIMS) that nobody would ever guess; requiring a word to actually be
*used* filters them out far better than any cleverness about letter patterns.
The picker keeps the most common half of each length (`REJECT_FRACTION` in
`unitwordpicker.pas`). House words are never picked.

### Checking word quality

`tools/wordtest.pas` exercises the picker without launching the GUI:

```bash
fpc -Fu. -FU/tmp/wt tools/wordtest.pas -o/tmp/wordtest
/tmp/wordtest            # pool size, rank threshold and a sample per difficulty
/tmp/wordtest dump 5     # every eligible 5-letter word, most common first
```

## Dictionary Lookups

`unitdictionary.pas` holds the fetching and parsing and touches no LCL code, so
`TLookupThread` can run the whole request in the background. **The thread never
calls back into the form.** It leaves the finished result in a locked field and
the animation timer collects it, which means a window closed mid-request cannot
be called into by a thread that outlives it - closing simply lets go of the
thread and it frees itself.

Two sources are tried in order:

1. **Wiktionary** (`en.wiktionary.org/api/rest_v1/page/definition/`) - reliable,
   but returns Parsoid markup, so `<style>`/`<script>` elements are dropped
   whole and the remaining tags and entities are stripped.
2. **api.dictionaryapi.dev** - the original source, kept as a fallback. It is a
   free service that goes dark for long stretches, and when it does its socket
   hangs until the timeout rather than refusing the connection.

A timeout leaves `TFPHTTPClient` returning an empty body rather than raising,
so "the service did not answer" and "no such word" are reported separately.

Definitions come from Wiktionary and are **not filtered** - a word looked up
gets whatever Wiktionary says about it.

## Notes On The UI

Everything is drawn onto three `TPaintBox`es - the top bar, the board and the
keyboard - plus one status label:

- Tile geometry is a pure function of the paint box size and the word,
  recomputed on every repaint, so it cannot drift between games.
- Animation is a repaint driven by one 60fps `TTimer` that stops itself when
  nothing is moving. Nothing blocks the message loop.
- The layout scales to any window size, so no mode needs a scrollbar.
- Sound players are separate processes; a second timer keeps polling until the
  last one has been reaped, so finished players do not linger as zombies.

LCL-gtk3 quirks, each commented where it is worked around:

- `Canvas.RoundRect` leaves the cairo path open, so consecutive calls get
  joined by stray diagonals. Rounded shapes are drawn as a single `Polygon`.
- Setting `Constraints.Min*` makes the window open *at* that minimum, from the
  `.lfm` or from code, so the form sets no constraints.
- Forcing the window handle in `OnCreate` (`HandleNeeded`) makes the window
  open at 0.8x its designed size, so touch is hooked up in the first `OnShow`.
- Touch events are selected but never handled - see above.

One that is **not** worked around: with no window manager at all, gtk3 centres
the window before it has been given its designed size, so it can open partly
off-screen. Any window manager puts it right.

## License

[0BSD](https://opensource.org/license/0bsd) - do whatever you want with it,
no strings attached. See `LICENSE`.
