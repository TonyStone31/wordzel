# Sound Effects for Wordzel Easter Egg

## Sound Files

This directory contains the WAV sound files used for the easter egg animation.
The sounds are loaded at runtime from this directory and play when you type "POOPS" or "FARTS".

**Cross-Platform Support:**
- **Windows**: Uses built-in `sndPlaySound` API from MMSystem
- **Linux**: Auto-detects and uses `paplay` (PulseAudio) or `aplay` (ALSA)
- **macOS**: Uses built-in `afplay` command

Sound files included:
1. `fart1.wav` - Short fart sound (61KB)
2. `fart2.wav` - Medium fart sound (82KB)
3. `fart3.wav` - Long fart sound (94KB)
4. `poop1.wav` - Splash/plop sound (191KB)
5. `poop2.wav` - Toilet flush sound (208KB)

Total size: ~636KB

## Where to Get Free Fart Sounds

### Option 1: Freesound.org (Requires free account)
- https://freesound.org/search/?q=fart
- https://freesound.org/search/?q=toilet
- Download as WAV format

### Option 2: Zapsplat.com (Free with attribution)
- https://www.zapsplat.com/sound-effect-category/farts/
- https://www.zapsplat.com/sound-effect-category/toilet/

### Option 3: Create your own
Use online tone generators or mouth sounds and record with Audacity

## Converting to WAV

If you download MP3 files, convert them to WAV:

```bash
ffmpeg -i fart.mp3 fart1.wav
```

## File Requirements

- Format: WAV (16-bit PCM preferred)
- Sample Rate: 44100 Hz or 48000 Hz
- Channels: Mono or Stereo
- Keep files small (< 100KB each for quick loading)
