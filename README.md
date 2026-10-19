# Wordzel

<img src="wordzel.png" alt="Wordzel icon" width="120" align="right">

A Wordle-style word game for kids - with a great deal of poop.

**Wordle + Hazel = Wordzel.** Made for Hazel, who discovered that the best
thing to guess in Wordle is FARTS, and the second best is POOPS.

## Download

Grab the latest from the [releases page](https://github.com/TonyStone31/wordzel/releases):

- **Windows** - unzip and run `wordzel.exe`.
- **Linux** - untar and run `./wordzel`.

It is one file with everything inside, sounds included. Nothing to install.

## How to play

Guess the secret word. After each guess the tiles turn **green** for the
right letter in the right spot, **yellow** for a letter that is in the word
somewhere else, and **gray** for a letter that is not in it at all. The
keyboard colors itself to match.

- **Pick a level** - from Easy (3 letters, 4 tries) up to Insane (9 letters,
  10 tries).
- **Make up your own secret word** for someone else to guess - any letters,
  any length, real word or not.
- **Look up a word** - hold a finger on a row, or right-click it, to see what
  the word means before you spend a turn on it.
- **Race the hourglass** if you like - by level, a few minutes, or your own
  time.
- **Guess a potty word** - POOPS, FARTS, TOILET, PLUNGER and about two
  hundred more - and see what happens.

It works with a mouse, a keyboard or a finger, on a phone-sized window or a
big screen.

| Key | |
|---|---|
| letters, ENTER, BACKSPACE | play |
| Esc | close a menu or card |
| Ctrl+N | new game |
| Ctrl+M | your own secret word |
| Ctrl+L | look up a word |
| F1 | how to play |

## Play together

The game can host a web version for the whole house, with a family
leaderboard:

1. On the computer that will host, open **☰** and set your **Player name**,
   a **Family passphrase** and a **Server port**, then switch on
   **Run family server**.
2. On any phone, tablet or computer at home, open
   `http://<that computer's address>:<port>` - for example
   `http://192.168.1.10:8181`.
3. Type the family passphrase, then pick your name or add a new one with a
   PIN.

Every finished game counts toward the daily and monthly leaderboard: a win
scores more the longer the word and the fewer the guesses, and a loss still
scores a point, so playing a lot pays off. Keep the server on your own home
network.

## Building it yourself

Open `wordzel.lpi` in [Lazarus](https://www.lazarus-ide.org) and press F9.

## Credits

- The secret words are chosen with help from the
  [FrequencyWords](https://github.com/hermitdave/FrequencyWords) English list
  by Hermit Dave, built from the OpenSubtitles2018 corpus and licensed
  CC BY-SA 4.0.
- Word definitions come from [Wiktionary](https://en.wiktionary.org), with
  [Free Dictionary API](https://dictionaryapi.dev) as a fallback.

## License

[0BSD](LICENSE) - do whatever you want with it.
