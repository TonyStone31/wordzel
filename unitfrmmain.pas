unit unitfrmmain;

{ Wordzel - a Wordle-ish word game for kids.

  Everything is drawn onto three TPaintBoxes - the top bar, the board and the
  keyboard - plus one status label. Menus, dropdowns, text entry and info
  cards are drawn inside the window as well: there are no system menus, popup
  windows or dialogs. That is deliberate. The game is played on phones and
  touchscreens, where right-click and modal dialogs are awkward.

  Tile geometry is recomputed from the paint box size on every repaint (so it
  cannot drift between games), animation is a repaint instead of widget
  resizes, and nothing blocks the message loop - every effect is advanced by
  one 60fps TTimer. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, LCLType,
  unitdictionary, unittouch;

type
  TTileState = (tsEmpty, tsFilled, tsCorrect, tsPresent, tsAbsent);
  TAnimKind = (akNone, akPop, akFlip, akBounce);
  TGamePhase = (gpPlaying, gpRevealing, gpWon, gpLost);
  TLoseReason = (lrOutOfTries, lrGaveUp, lrTimeUp);
  TKeyKind = (kkLetter, kkEnter, kkBack);
  TTimerMode = (tmOff, tmLevel, tmFixed);
  TPromptKind = (prWord, prTime);
  TParticleKind = (ptFly, ptBounce, ptVortex, ptText);

  TTileInfo = record
    Letter: Char;
    State: TTileState;
    NextState: TTileState;
    Anim: TAnimKind;
    T0: QWord;          // animation start, may be in the future (stagger)
    Dur: Integer;
  end;

  TKeyInfo = record
    Bounds: TRect;
    Kind: TKeyKind;
    Ch: Char;
    Text: string;
  end;

  TCardLineKind = (clkPhonetic, clkPart, clkSense, clkError, clkGap);

  TCardLine = record
    Kind: TCardLineKind;
    Text: string;
    Indent: Integer;
  end;

  TParticle = record
    Kind: TParticleKind;
    X, Y, VX, VY, Grav: Double;
    Life: Double;
    Size, Grow: Double;
    Glyph: string;
    Color: TColor;
    CX, CY, Ang, Rad, AngVel: Double;   // ptVortex: circling a centre
  end;

  TMenuEntry = record
    Caption: string;
    Shortcut: string;
    Action: Integer;
    Enabled, Checked, Separator: Boolean;
    Bounds: TRect;      // filled in when the menu is drawn
  end;

  TBarButton = record
    Bounds: TRect;
    Caption: string;
    Action: Integer;
  end;

  { TForm1 }

  TForm1 = class(TForm)
    LabelStatus: TLabel;
    PaintBoxBar: TPaintBox;
    PaintBoxBoard: TPaintBox;
    PaintBoxKeys: TPaintBox;
    PanelHeader: TPanel;
    PanelKeys: TPanel;
    TimerAnim: TTimer;
    TimerClock: TTimer;
    TimerHold: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: char);
    procedure FormResize(Sender: TObject);
    procedure PaintBoxBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBarMouseLeave(Sender: TObject);
    procedure PaintBoxBarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBarPaint(Sender: TObject);
    procedure PaintBoxBoardMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBoardMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBoardMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxBoardPaint(Sender: TObject);
    procedure PaintBoxKeysMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxKeysMouseLeave(Sender: TObject);
    procedure PaintBoxKeysMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxKeysMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxKeysPaint(Sender: TObject);
    procedure TimerAnimTimer(Sender: TObject);
    procedure TimerClockTimer(Sender: TObject);
    procedure TimerHoldTimer(Sender: TObject);
  private
    // Game state
    FTiles: array of array of TTileInfo;
    FRowWords: array of string;
    FKeyState: array['A'..'Z'] of TTileState;
    FTargetWord: string;
    FCurrentGuess: string;
    FCurrentRow, FCurrentCol: Integer;
    FWordLength, FMaxGuesses: Integer;
    FDifficulty: Integer;        // word length for random games; a custom word brings its own
    FAnyGuess: Boolean;          // made-up secret word, so guesses skip the dictionary
    FCustomGame: Boolean;
    FPhase: TGamePhase;
    FLoseReason: TLoseReason;
    FWins, FTotalGames: Integer;
    FDebugMode: Boolean;

    // Board geometry, recomputed from the paint box on every repaint
    FTileSize, FTileGap, FBoardX, FBoardY, FBoardW, FBoardH: Integer;

    // Animation
    FRevealRow: Integer;
    FRevealDone: QWord;
    FShakeRow, FShakeOffset: Integer;
    FShakeT0: QWord;
    FParticles: array of TParticle;
    FRainSeed: Integer;
    FRaining: Boolean;
    FQuakeOn: Boolean;
    FQuakeT0: QWord;
    FQuakeDX, FQuakeDY: Integer;
    FToiletOn, FFlushPlayed: Boolean;
    FToiletT0: QWord;
    FToiletFrame: Integer;

    // Keyboard widget
    FKeys: array of TKeyInfo;
    FHotKey, FPressedKey, FFlashKey: Integer;
    FFlashT0: QWord;
    FKeysDirty: Boolean;

    // Definition / info card
    FLookupThread: TLookupThread;
    FCardResult: TDefResult;
    FCardLines: array of TCardLine;
    FCardWord: string;
    FCardVisible, FCardLoading, FCardNumbered: Boolean;
    FCardT0: QWord;

    // In-window menus (bar dropdowns and the row menu)
    FMenuItems: array of TMenuEntry;
    FMenuOpen: Boolean;
    FMenuRect: TRect;
    FMenuAnchor: TPoint;
    FMenuHot: Integer;
    FMenuSource: Integer;
    FMenuRowWord: string;

    // In-window text prompt
    FPromptOpen: Boolean;
    FPromptKind: TPromptKind;
    FPromptAction: Integer;
    FPromptTitle, FPromptHint, FPromptText, FPromptError: string;
    FPromptMax: Integer;
    FPromptOKRect, FPromptCancelRect: TRect;

    // Top bar
    FBarButtons: array of TBarButton;
    FBarHot, FBarPressed: Integer;
    FBarCompact, FBarHideScore: Boolean;

    // Press-and-hold on the board
    FHoldPt: TPoint;
    FHoldArmed, FHoldFired: Boolean;

    // Touchscreen
    FTouchSeq: Pointer;
    FTouchTarget: TControl;
    FInTouch: Boolean;
    FLastTouchT: QWord;
    FTouchInstalled: Boolean;

    // Hourglass
    FTimerMode: TTimerMode;
    FTimerSecs: Integer;
    FTimeTotalMs, FTimeLeftMs: Int64;
    FClockLast: QWord;
    FLastTickSec: Integer;

    // Sound
    FSoundOn, FClicksOn: Boolean;
    FSoundProcs: TList;
    FPlayer: string;
    FSoundDir: string;
    FLastClickT: QWord;

    // Board
    procedure ComputeBoardMetrics;
    function TileRect(Row, Col: Integer): TRect;
    function RowAtPoint(X, Y: Integer): Integer;
    procedure DrawTile(C: TCanvas; Row, Col: Integer);
    procedure DrawParticles(C: TCanvas);
    procedure ToiletPose(Elapsed: Int64; out X, Y, Size: Double);
    procedure DrawToilet(C: TCanvas);
    procedure DrawEndBanner(C: TCanvas);
    procedure BoardClick(X, Y: Integer);
    procedure CancelHold;

    // Keyboard
    procedure LayoutKeys;
    procedure AddKey(const R: TRect; Kind: TKeyKind; Ch: Char; const ALabel: string);
    procedure DrawKey(C: TCanvas; Index: Integer);
    function KeyAtPoint(X, Y: Integer): Integer;
    function KeyIndexOf(Kind: TKeyKind; Ch: Char): Integer;
    procedure UpdateCheatHint(KeyIndex: Integer; Shift: TShiftState);

    // Top bar
    function TimerCaption(Compact: Boolean): string;
    function ScoreText(Compact: Boolean): string;
    function TimerShowing: Boolean;
    function BarRightWidth(C: TCanvas; Compact, HideScore: Boolean): Integer;
    procedure LayoutBar(C: TCanvas);
    procedure DrawBarButton(C: TCanvas; Index: Integer);
    procedure DrawBarRight(C: TCanvas);
    procedure DrawHourglass(C: TCanvas; const R: TRect; Frac: Double; Running: Boolean);
    function BarButtonAt(X, Y: Integer): Integer;
    procedure BarClick(Index: Integer);

    // Menus
    procedure ClearMenu;
    procedure AddMenuItem(const ACaption: string; AAction: Integer;
      AEnabled: Boolean = True; AChecked: Boolean = False; const AShortcut: string = '');
    procedure AddMenuSep;
    procedure ShowMenu(ASource, AX, AY: Integer);
    procedure CloseMenu;
    procedure OpenBarMenu(AMenu, AX: Integer);
    procedure OpenRowMenu(AX, AY: Integer);
    procedure DrawMenu(C: TCanvas);
    function MenuItemAt(X, Y: Integer): Integer;
    procedure MoveMenuHot(Dir: Integer);
    procedure ActivateMenuItem(Index: Integer);
    procedure RunAction(Act: Integer);

    // Prompt
    procedure OpenPrompt(AKind: TPromptKind; AAction: Integer;
      const ATitle, AHint, AInitial: string; AMaxLen: Integer);
    procedure ClosePrompt;
    procedure PromptType(Ch: Char);
    procedure PromptBack;
    procedure PromptAccept;
    procedure DrawPrompt(C: TCanvas);

    // Input
    procedure TypeLetter(Ch: Char);
    procedure PressBack;
    procedure PressEnter;
    function IgnoreMouse: Boolean;
    function TouchTargetAt(SX, SY: Integer): TControl;
    procedure HandleTouch(Phase: TTouchPhase; Seq: Pointer; SX, SY: Integer);
    procedure FormFirstShow(Sender: TObject);

    // Game flow
    procedure StartNewGame(WordLength: Integer; const ManualWord: string = '');
    function MaxGuessesFor(WordLength: Integer): Integer;
    procedure AddLetter(Letter: Char);
    procedure RemoveLetter;
    procedure SubmitGuess;
    procedure EvaluateGuess(Row: Integer; const Guess: string);
    procedure StartReveal(Row: Integer);
    procedure FinishReveal;
    procedure ApplyKeyboardStates(Row: Integer);
    procedure WinGame;
    procedure LoseGame(Reason: TLoseReason);
    procedure ShowStatus(const Msg: string; Tone: Integer = 0);
    procedure SetTimerMode(AMode: TTimerMode; ASecs: Integer);
    procedure ResetGameClock;

    // Effects
    procedure StartAnim;
    function AnimationPending: Boolean;
    procedure ShakeRow(Row: Integer);
    procedure FlashKey(Kind: TKeyKind; Ch: Char);
    function AddParticle(AX, AY, AVX, AVY, AGrav, ALife: Double;
      ASize: Integer; const AGlyph: string): Integer;
    procedure SpawnConfetti(Row: Integer);
    procedure SpawnPoopStorm;
    procedure TopUpRain;
    procedure SpawnComicWord;
    procedure UpdateParticles;
    procedure StartPoopShow(Row: Integer);
    procedure UpdateToilet(Now0: QWord);
    procedure MaybeEasterEgg(const Guess: string);

    // Sound
    procedure ExtractSounds;
    procedure ExtractSoundsAsync(Data: PtrInt);
    procedure ReapSounds(All: Boolean);
    procedure PlayASound(const SoundFile: string);
    procedure PlayClick(const SoundFile: string);
    procedure PlayRandom(const Files: array of string);

    // Cards
    procedure ShowInfoCard(const ATitle: string; const AInfo: TDefResult);
    procedure ShowHelpCard;
    procedure ShowAboutCard;
    procedure ShowPoolInfo;
    function WordInRow(Row: Integer): string;
    procedure StartLookup(const AWord: string);
    procedure CancelLookup;
    procedure PollLookup;
    procedure CloseCard;
    procedure WrapInto(C: TCanvas; const S: string; MaxWidth: Integer;
      Kind: TCardLineKind; Indent, ContIndent: Integer);
    procedure BuildCardLines(C: TCanvas; TextWidth: Integer);
    procedure DrawDefinitionCard(C: TCanvas);
  public

  end;

var
  Form1: TForm1;

implementation

uses
  LCLIntf, Math, unitwordpicker
  {$IFDEF WINDOWS}, MMSystem{$ELSE}, Process{$ENDIF};

{$R *.lfm}

const
  // TColor is $00BBGGRR
  CLR_BG          = $00161212;  // #121216 page background
  CLR_PANEL       = $00211B1B;  // #1B1B21 header / cards
  CLR_SHADOW      = $00080606;  // drop shadows under floating cards
  CLR_TILE_BG     = $001C1717;  // #17171C empty tile
  CLR_TILE_EDGE   = $003E3A3A;  // #3A3A3E empty tile border
  CLR_TILE_EDGE_HI= $005C5656;  // #56565C tile holding a letter
  CLR_CORRECT     = $0063A34F;  // #4FA363 right letter, right spot
  CLR_PRESENT     = $0027A2C9;  // #C9A227 right letter, wrong spot
  CLR_ABSENT      = $003E3A3A;  // #3A3A3E not in the word
  CLR_KEY         = $00463E3E;  // #3E3E46 keyboard key
  CLR_KEY_ALT     = $00564C4C;  // #4C4C56 ENTER / BACK
  CLR_KEY_DEAD    = $002E2A2A;  // #2A2A2E used-up key
  CLR_TEXT        = $00F4F2F2;  // #F2F2F4
  CLR_DIM         = $00A69A9A;  // #9A9AA6
  CLR_ACCENT      = $00457AFF;  // #FF7A45

  FLIP_MS = 300;
  FLIP_STAGGER_MS = 130;
  REVEAL_SPAN_MS = 1400;       // a long custom word still flips in about this long
  POP_MS = 130;
  BOUNCE_MS = 520;
  BOUNCE_STAGGER_MS = 70;
  SHAKE_MS = 420;
  KEYFLASH_MS = 130;
  FRAME_MS = 16;
  QUAKE_MS = 700;
  TOILET_MS = 2800;
  HOLD_SLOP = 12;              // px a held finger may wander before it counts as a drag
  TOUCH_MOUSE_GUARD_MS = 700;  // ignore emulated mouse events this soon after a touch
  MAX_CUSTOM_LEN = 60;
  MAX_LOOKUP_LEN = 40;

  TONE_NORMAL = 0;
  TONE_WARN = 1;
  TONE_GOOD = 2;

  ACT_NONE = 0;
  ACT_NEW = 1;
  ACT_TIMER_OFF = 2;
  ACT_TIMER_LEVEL = 3;
  ACT_TIMER_CUSTOM = 4;
  ACT_CUSTOM_WORD = 5;
  ACT_LOOKUP_ANY = 6;
  ACT_LOOKUP_ROW = 7;
  ACT_GIVE_UP = 8;
  ACT_HELP = 9;
  ACT_SOUND = 10;
  ACT_CLICKS = 11;
  ACT_QUIT = 12;
  ACT_ABOUT = 13;
  ACT_LEVEL = 100;             // + word length
  ACT_TIMER_SECS = 1000;       // + seconds
  MENU_LEVEL = 200;            // top-bar dropdowns
  MENU_TIMER = 201;
  MENU_MORE = 202;

  LEVEL_NAMES: array[MIN_WORD_LEN..MAX_WORD_LEN] of string =
    ('Easy', 'Medium', 'Normal', 'Hard', 'Expert', 'Master', 'Insane');

  TIMER_PRESETS: array[0..4] of Integer = (60, 120, 180, 300, 600);

  { Guessing any of these sets off the toilet. }
  POOP_WORDS: array[0..201] of string = (
    { poop }
    'POO', 'POOS', 'POOP', 'POOPS', 'POOPED', 'POOPING', 'POOPY', 'TURD',
    'TURDS', 'DUNG', 'DUNGS', 'CRAP', 'CRAPPY', 'CRAPS', 'STOOL', 'STOOLS',
    'MANURE', 'FECES', 'FECAL', 'FAECES', 'SCAT', 'SCATS', 'GUANO', 'SPOOR',
    'DROPPING', 'DROPPINGS', 'EXCRETA', 'EXCRETE', 'EXCRETES', 'EXCRETED',
    'ORDURE', 'DEFECATE', 'DIARRHEA', 'DIARRHOEA',
    { gas }
    'FART', 'FARTS', 'FARTED', 'FARTING', 'FARTY', 'SHART', 'SHARTS',
    'SHARTED', 'SHARTING', 'TOOT', 'TOOTS', 'TOOTED', 'TOOTING', 'FLATULENT',
    'GASSY', 'BURP', 'BURPS', 'BURPED', 'BELCH',
    { porcelain and plumbing }
    'TOILET', 'TOILETS', 'POTTY', 'POTTIES', 'LOO', 'LOOS', 'LATRINE',
    'LATRINES', 'OUTHOUSE', 'OUTHOUSES', 'PRIVY', 'PRIVIES', 'PLUNGER',
    'PLUNGERS', 'BIDET', 'BIDETS', 'COMMODE', 'COMMODES', 'URINAL', 'URINALS',
    'BEDPAN', 'BEDPANS', 'LAVATORY', 'WASHROOM', 'RESTROOM', 'FLUSH',
    'FLUSHED', 'FLUSHES', 'FLUSHING', 'SEWER', 'SEWERS', 'SEWAGE', 'SEWERAGE',
    'SLUDGE', 'CESSPOOL', 'CESSPOOLS', 'SEPTIC', 'PLUMBER', 'PLUMBERS',
    'PLUMBING', 'CISTERN', 'CISTERNS',
    { pee }
    'PEE', 'PEED', 'PEES', 'PEEING', 'WEE', 'WEES', 'PIDDLE', 'PIDDLES',
    'PIDDLED', 'TINKLE', 'TINKLES', 'TINKLED', 'URINE', 'URINATE', 'URINATES',
    'URINATED', 'BLADDER', 'BLADDERS',
    { bottoms }
    'BUTT', 'BUTTS', 'BUM', 'BUMS', 'RUMP', 'RUMPS', 'BUTTOCK', 'BUTTOCKS',
    'TUSH', 'BOWEL', 'BOWELS', 'RECTUM', 'RECTAL', 'COLON', 'ANUS', 'DIAPER',
    'DIAPERS',
    { stink }
    'STINK', 'STINKS', 'STINKY', 'STANK', 'STUNK', 'STINKER', 'STINKERS',
    'STINKING', 'SMELLY', 'SMELLIER', 'WHIFF', 'WHIFFS', 'REEK', 'REEKS',
    'REEKED', 'REEKING', 'ODOR', 'ODORS', 'STENCH', 'STENCHES', 'FETID',
    'PUTRID', 'RANCID',
    { mess and gross }
    'PLOP', 'PLOPS', 'PLOPPED', 'SPLAT', 'SPLATS', 'SQUIRT', 'SQUIRTS',
    'MUCK', 'MUCKY', 'FILTH', 'FILTHY', 'SLOP', 'SLOPS', 'DUMP', 'DUMPS',
    'DUMPED', 'DUMPING', 'PUKE', 'PUKES', 'PUKED', 'PUKING', 'VOMIT',
    'VOMITS', 'VOMITED', 'BARF', 'BARFS', 'BARFED', 'RETCH', 'SPEW', 'SPEWS',
    'SPEWED', 'SPEWING', 'SNOT', 'SNOTS', 'SNOTTY', 'MUCUS', 'PHLEGM',
    'GROSS', 'GROSSER', 'GROSSEST', 'YUCKY', 'ICKY',
    { house words - see EXTRA_WORDS }
    'DOODOO', 'DOODIE', 'DOOKIE', 'CACA', 'PEEPEE', 'WEEWEE', 'TUSHY'
  );

  POOP_GLYPHS: array[0..6] of string = ('💩', '💨', '🧻', '🚽', '😖', '🤢', '💥');
  VORTEX_GLYPHS: array[0..3] of string = ('💩', '🧻', '💨', '💩');
  PARTY_GLYPHS: array[0..7] of string = ('🎉', '✨', '🎊', '⭐', '💫', '🥳', '🏆', '🌟');
  COMIC_WORDS: array[0..6] of string =
    ('PLOP!', 'BRRRT!', 'SPLOOSH!', 'FLUSH!', 'PFFFT!', 'KER-PLUNK!', 'GLUG GLUG!');
  COMIC_COLORS: array[0..3] of TColor = (CLR_PRESENT, CLR_ACCENT, CLR_CORRECT, CLR_TEXT);
  POOP_CHEERS: array[0..4] of string = (
    '💨 PFFFFFT! You stinky genius!',
    '🚽 FLUSH! Right down the drain!',
    '💩 Ker-plunk! What a potty word!',
    '🧻 Somebody grab the toilet paper!',
    '😖 PEE-YEW! What a smell!'
  );

  WIN_SOUNDS: array[0..2] of string = ('win1.wav', 'win2.wav', 'win3.wav');
  LOSE_SOUNDS: array[0..4] of string =
    ('lose1.wav', 'lose2.wav', 'lose3.wav', 'poop1.wav', 'poop2.wav');
  FART_SOUNDS: array[0..2] of string = ('fart1.wav', 'fart2.wav', 'fart3.wav');

  { Everything above plus the one-offs - the full set compiled into the
    binary as RCDATA resources (see the Resources list in wordzel.lpi). }
  ALL_SOUNDS: array[0..15] of string = (
    'back.wav', 'enter.wav', 'key.wav', 'tick.wav', 'flush.wav',
    'fart1.wav', 'fart2.wav', 'fart3.wav',
    'win1.wav', 'win2.wav', 'win3.wav',
    'lose1.wav', 'lose2.wav', 'lose3.wav', 'poop1.wav', 'poop2.wav');

{ ------------------------------------------------------------------ }
{ Small helpers                                                       }
{ ------------------------------------------------------------------ }

function Shade(Col: TColor; Amount: Integer): TColor;
var
  R, G, B: Integer;
begin
  Col := ColorToRGB(Col);
  R := EnsureRange((Col and $FF) + Amount, 0, 255);
  G := EnsureRange(((Col shr 8) and $FF) + Amount, 0, 255);
  B := EnsureRange(((Col shr 16) and $FF) + Amount, 0, 255);
  Result := TColor((B shl 16) or (G shl 8) or R);
end;

{ Rounded rectangle as a single closed polygon.

  Canvas.RoundRect under LCL-gtk3 leaves the cairo path open, so consecutive
  calls get joined by stray diagonals across the board. One Polygon per tile
  side-steps that and looks the same. }
procedure RoundBox(C: TCanvas; const R: TRect; Radius: Integer; Fill, Border: TColor);
const
  STEPS = 5;                       // segments per corner
var
  Pts: array[0..4 * (STEPS + 1) - 1] of TPoint;
  Corner, I, K, Rad, CenterX, CenterY: Integer;
  Start, Angle: Double;
begin
  Rad := EnsureRange(Radius, 0, Min(R.Right - R.Left, R.Bottom - R.Top) div 2);

  K := 0;
  for Corner := 0 to 3 do
  begin
    case Corner of
      0: begin CenterX := R.Left + Rad;      CenterY := R.Top + Rad;         Start := Pi;       end;
      1: begin CenterX := R.Right - 1 - Rad; CenterY := R.Top + Rad;         Start := 1.5 * Pi; end;
      2: begin CenterX := R.Right - 1 - Rad; CenterY := R.Bottom - 1 - Rad;  Start := 0;        end;
    else
         begin CenterX := R.Left + Rad;      CenterY := R.Bottom - 1 - Rad;  Start := 0.5 * Pi; end;
    end;
    for I := 0 to STEPS do
    begin
      Angle := Start + (I / STEPS) * (Pi / 2);
      Pts[K].X := CenterX + Round(Cos(Angle) * Rad);
      Pts[K].Y := CenterY + Round(Sin(Angle) * Rad);
      Inc(K);
    end;
  end;

  C.Brush.Style := bsSolid;
  C.Brush.Color := Fill;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  if Border = clNone then
    C.Pen.Color := Fill
  else
    C.Pen.Color := Border;
  C.Polygon(Pts);
end;

procedure CenterText(C: TCanvas; const R: TRect; const S: string;
  FontHeight: Integer; Col: TColor; Bold: Boolean);
var
  TW, TH: Integer;
begin
  if S = '' then
    Exit;
  C.Font.Height := FontHeight;
  if Bold then
    C.Font.Style := [fsBold]
  else
    C.Font.Style := [];
  C.Font.Color := Col;
  C.Brush.Style := bsClear;
  TW := C.TextWidth(S);
  TH := C.TextHeight(S);
  C.TextOut(R.Left + (R.Right - R.Left - TW) div 2,
            R.Top + (R.Bottom - R.Top - TH) div 2, S);
  C.Brush.Style := bsSolid;
end;

{ Largest font, from StartPx down to MinPx, at which S fits in MaxW. Leaves
  the canvas set to it and returns the (negative) font height. }
function FitFont(C: TCanvas; const S: string; MaxW, StartPx, MinPx: Integer;
  Bold: Boolean): Integer;
var
  Px: Integer;
begin
  if Bold then
    C.Font.Style := [fsBold]
  else
    C.Font.Style := [];
  Px := StartPx;
  C.Font.Height := -Px;
  while (Px > MinPx) and (C.TextWidth(S) > MaxW) do
  begin
    Dec(Px);
    C.Font.Height := -Px;
  end;
  Result := -Px;
end;

function TileFill(St: TTileState): TColor;
begin
  case St of
    tsCorrect: Result := CLR_CORRECT;
    tsPresent: Result := CLR_PRESENT;
    tsAbsent:  Result := CLR_ABSENT;
  else
    Result := CLR_TILE_BG;
  end;
end;

function TileBorder(St: TTileState): TColor;
begin
  case St of
    tsEmpty:  Result := CLR_TILE_EDGE;
    tsFilled: Result := CLR_TILE_EDGE_HI;
  else
    Result := Shade(TileFill(St), 14);
  end;
end;

function FormatSecs(Secs: Integer): string;
begin
  if Secs < 0 then
    Secs := 0;
  Result := Format('%d:%.2d', [Secs div 60, Secs mod 60]);
end;

{ Hourglass length when the timer follows the level: 30s per letter plus one. }
function LevelSecs(Len: Integer): Integer;
begin
  Result := EnsureRange(30 * (Len + 1), 60, 900);
end;

{ "90" -> 90, "2:30" -> 150, anything else -> -1. }
function ParseClock(const S: string): Integer;
var
  P, M, Sec: Integer;
begin
  P := Pos(':', S);
  if P = 0 then
    Exit(StrToIntDef(S, -1));
  M := StrToIntDef(Copy(S, 1, P - 1), -1);
  Sec := StrToIntDef(Copy(S, P + 1, MaxInt), -1);
  if (M < 0) or (Sec < 0) or (Sec > 59) then
    Exit(-1);
  Result := M * 60 + Sec;
end;

procedure AddInfo(var R: TDefResult; const APart: string; const ALines: array of string);
var
  N, I: Integer;
begin
  N := Length(R.Entries);
  SetLength(R.Entries, N + 1);
  R.Entries[N].PartOfSpeech := APart;
  SetLength(R.Entries[N].Senses, Length(ALines));
  for I := 0 to High(ALines) do
    R.Entries[N].Senses[I] := ALines[I];
end;

{$IFNDEF WINDOWS}
function FindSoundPlayer: string;
const
  {$IFDEF DARWIN}
  CANDIDATES: array[0..0] of string = ('afplay');
  {$ELSE}
  CANDIDATES: array[0..2] of string = ('paplay', 'pw-play', 'aplay');
  {$ENDIF}
var
  I: Integer;
  SearchPath: string;
begin
  SearchPath := GetEnvironmentVariable('PATH');
  if SearchPath = '' then
    SearchPath := '/usr/bin:/bin:/usr/local/bin';
  for I := 0 to High(CANDIDATES) do
  begin
    Result := FileSearch(CANDIDATES[I], SearchPath);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ Form lifecycle                                                      }
{ ------------------------------------------------------------------ }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Randomize;

  Color := CLR_BG;
  PanelHeader.Color := CLR_PANEL;
  PanelKeys.Color := CLR_BG;
  LabelStatus.Font.Color := CLR_TEXT;
  DoubleBuffered := True;

  KeyPreview := True;
  FDebugMode := True;          // gates the Shift-hover-BACK answer peek

  // An empty Hint shows nothing, so this can stay on and be filled in on demand.
  PaintBoxKeys.ShowHint := True;
  PaintBoxKeys.Hint := '';

  // Deliberately no Constraints: under LCL-gtk3 setting a minimum size makes
  // the window open AT that minimum. The board and keyboard scale themselves
  // to whatever room they get, so a floor is not needed.

  FDifficulty := 5;
  FSoundOn := True;
  FClicksOn := True;
  FTimerMode := tmOff;
  FTimerSecs := 180;
  FHotKey := -1;
  FPressedKey := -1;
  FFlashKey := -1;
  FShakeRow := -1;
  FBarHot := -1;
  FBarPressed := -1;
  FMenuHot := -1;
  FLastTickSec := -1;

  {$IFNDEF WINDOWS}
  FSoundProcs := TList.Create;
  FPlayer := FindSoundPlayer;
  {$ENDIF}

  { Fall back to a sounds folder beside the executable if the embedded
    copies cannot be unpacked. Unpacking waits until the window is up -
    see FormFirstShow - so a virus scanner poking at the files cannot
    hold the window back. }
  FSoundDir := ExtractFilePath(Application.ExeName) + 'sounds' + PathDelim;

  // Touch is hooked on the window once it exists - see FormFirstShow.
  // Forcing the handle here instead (HandleNeeded) makes gtk3 open the
  // window at 0.8x its designed size.
  OnShow := @FormFirstShow;

  StartNewGame(FDifficulty);
end;

procedure TForm1.FormFirstShow(Sender: TObject);
begin
  if FTouchInstalled then
    Exit;
  FTouchInstalled := True;
  // Touchscreens under gtk3 need their taps caught by hand - see unittouch.
  InstallTouchHandler(Self, @HandleTouch);
  // After the window is on screen, not before.
  Application.QueueAsyncCall(@ExtractSoundsAsync, 0);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  // Give the keyboard a share of the window instead of a fixed slab, so a
  // short window does not end up as all keyboard and no board.
  PanelKeys.Height := EnsureRange(ClientHeight * 28 div 100, 120, 240);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TimerAnim.Enabled := False;
  TimerClock.Enabled := False;
  TimerHold.Enabled := False;
  CancelLookup;    // it finishes into its own fields and frees itself
  ReapSounds(True);
  FreeAndNil(FSoundProcs);
  { The unpacked sounds stay in the temp folder on purpose - the next run
    reuses them, and the OS owns cleaning its temp space. }
end;

function TForm1.MaxGuessesFor(WordLength: Integer): Integer;
begin
  // One more try for each extra letter.
  Result := EnsureRange(WordLength + 1, 4, 10);
end;

{ ------------------------------------------------------------------ }
{ Board geometry and painting                                         }
{ ------------------------------------------------------------------ }

{ Derived purely from the paint box size and the current word, so it
  produces the same answer every time it runs - measuring live layout
  mid-resize is what makes tiles drift between games. }
procedure TForm1.ComputeBoardMetrics;
var
  AvailW, AvailH, SizeW, SizeH: Integer;
begin
  FTileSize := 0;
  if (FWordLength <= 0) or (FMaxGuesses <= 0) then
    Exit;

  AvailW := PaintBoxBoard.Width - 32;
  AvailH := PaintBoxBoard.Height - 24;
  if (AvailW <= 0) or (AvailH <= 0) then
    Exit;

  // A long custom word needs the gaps to shrink with the tiles, or the gaps
  // alone would eat the row.
  FTileGap := 6;
  SizeW := (AvailW - (FWordLength - 1) * FTileGap) div FWordLength;
  if SizeW < 36 then
  begin
    FTileGap := EnsureRange(SizeW div 8, 1, 6);
    SizeW := (AvailW - (FWordLength - 1) * FTileGap) div FWordLength;
  end;
  SizeH := (AvailH - (FMaxGuesses - 1) * FTileGap) div FMaxGuesses;

  // No real lower bound: a silly-long word gets silly-small tiles, and past
  // about 4px the row simply runs off the sides - fine for a joke word.
  FTileSize := EnsureRange(Min(SizeW, SizeH), 4, 84);
  FBoardW := FWordLength * FTileSize + (FWordLength - 1) * FTileGap;
  FBoardH := FMaxGuesses * FTileSize + (FMaxGuesses - 1) * FTileGap;
  FBoardX := (PaintBoxBoard.Width - FBoardW) div 2;
  FBoardY := (PaintBoxBoard.Height - FBoardH) div 2;
end;

function TForm1.TileRect(Row, Col: Integer): TRect;
begin
  Result.Left := FBoardX + Col * (FTileSize + FTileGap);
  Result.Top := FBoardY + Row * (FTileSize + FTileGap);
  Result.Right := Result.Left + FTileSize;
  Result.Bottom := Result.Top + FTileSize;
end;

function TForm1.RowAtPoint(X, Y: Integer): Integer;
begin
  Result := -1;
  if FTileSize <= 0 then
    Exit;
  if (X < FBoardX) or (X > FBoardX + FBoardW) or (Y < FBoardY) then
    Exit;
  Result := (Y - FBoardY) div (FTileSize + FTileGap);
  if (Result < 0) or (Result >= FMaxGuesses) then
    Result := -1;
end;

procedure TForm1.DrawTile(C: TCanvas; Row, Col: Integer);
var
  R: TRect;
  T: TTileInfo;
  St: TTileState;
  Elapsed: Int64;
  P, ScaleX, ScaleY: Double;
  CX, CY, HalfW, HalfH, DX, DY: Integer;
begin
  T := FTiles[Row, Col];
  R := TileRect(Row, Col);
  St := T.State;
  ScaleX := 1; ScaleY := 1;
  DX := FQuakeDX; DY := FQuakeDY;

  if T.Anim <> akNone then
  begin
    Elapsed := Int64(GetTickCount64) - Int64(T.T0);
    if Elapsed < 0 then
      Elapsed := 0;                      // staggered start not reached yet
    if T.Dur <= 0 then
      P := 1
    else
      P := Min(1.0, Elapsed / T.Dur);

    case T.Anim of
      akPop:
        begin
          ScaleX := 1 + 0.18 * Sin(P * Pi);
          ScaleY := ScaleX;
        end;
      akFlip:
        // Squash to nothing showing the old colour, spring back with the new.
        if P < 0.5 then
          ScaleY := 1 - 1.92 * P
        else
        begin
          St := T.NextState;
          ScaleY := 0.04 + 1.92 * (P - 0.5);
        end;
      akBounce:
        begin
          Dec(DY, Round(Sin(P * Pi) * FTileSize * 0.45));
          ScaleX := 1 + 0.10 * Sin(P * Pi);
          ScaleY := ScaleX;
        end;
      else
        ;
    end;
  end;

  if Row = FShakeRow then
    Inc(DX, FShakeOffset);

  CX := (R.Left + R.Right) div 2 + DX;
  CY := (R.Top + R.Bottom) div 2 + DY;
  HalfW := Max(1, Round(FTileSize * ScaleX / 2));
  HalfH := Max(1, Round(FTileSize * ScaleY / 2));
  R := Rect(CX - HalfW, CY - HalfH, CX + HalfW, CY + HalfH);

  RoundBox(C, R, Max(2, FTileSize div 7), TileFill(St), TileBorder(St));

  // Skip the letter while the tile is edge-on, or once a silly-long custom
  // word has shrunk the tiles past the point where a letter could be read.
  if (T.Letter <> #0) and (HalfH > FTileSize div 4) and (FTileSize >= 9) then
    CenterText(C, R, T.Letter, -Round(FTileSize * 0.56 * ScaleX), CLR_TEXT, True);
end;

procedure TForm1.DrawParticles(C: TCanvas);
var
  I, X, Y: Integer;
begin
  C.Brush.Style := bsClear;
  for I := 0 to High(FParticles) do
  begin
    X := Round(FParticles[I].X);
    Y := Round(FParticles[I].Y);
    C.Font.Height := -Max(6, Round(FParticles[I].Size));
    if FParticles[I].Kind = ptText then
    begin
      // Comic-book lettering: a dark drop shadow keeps it readable over tiles.
      C.Font.Style := [fsBold];
      C.Font.Color := CLR_SHADOW;
      C.TextOut(X + 2, Y + 2, FParticles[I].Glyph);
      C.Font.Color := FParticles[I].Color;
      C.TextOut(X, Y, FParticles[I].Glyph);
    end
    else
    begin
      C.Font.Style := [];
      C.Font.Color := CLR_TEXT;
      C.TextOut(X, Y, FParticles[I].Glyph);
    end;
  end;
  C.Brush.Style := bsSolid;
end;

{ Where the giant toilet is: rises from the bottom, sits there shuddering
  while everything spirals into it, then blasts off out of the top. }
procedure TForm1.ToiletPose(Elapsed: Int64; out X, Y, Size: Double);
var
  RestY, P: Double;
begin
  Size := Min(PaintBoxBoard.Width, PaintBoxBoard.Height) * 0.30;
  if Size < 60 then Size := 60;
  if Size > 150 then Size := 150;
  X := PaintBoxBoard.Width / 2;
  RestY := PaintBoxBoard.Height * 0.58;

  if Elapsed < 350 then
  begin
    P := 1 - Sqr(1 - Elapsed / 350);            // ease out
    Y := PaintBoxBoard.Height + Size - (PaintBoxBoard.Height + Size - RestY) * P;
  end
  else if Elapsed < 2000 then
  begin
    X := X + Sin(Elapsed / 45) * 6;
    Y := RestY + Sin(Elapsed / 60) * 4;
  end
  else
  begin
    P := (Elapsed - 2000) / (TOILET_MS - 2000);
    Y := RestY - Sqr(P) * (RestY + Size * 2);
  end;
end;

procedure TForm1.DrawToilet(C: TCanvas);
const
  GLYPH = '🚽';
var
  X, Y, Size: Double;
  TW, TH: Integer;
begin
  if not FToiletOn then
    Exit;
  ToiletPose(Int64(GetTickCount64 - FToiletT0), X, Y, Size);
  C.Brush.Style := bsClear;
  C.Font.Style := [];
  C.Font.Height := -Round(Size);
  TW := C.TextWidth(GLYPH);
  TH := C.TextHeight(GLYPH);
  C.TextOut(Round(X) - TW div 2, Round(Y) - TH div 2, GLYPH);
  C.Brush.Style := bsSolid;
end;

procedure TForm1.DrawEndBanner(C: TCanvas);
var
  R, Line: TRect;
  W, H, FontH: Integer;
  Title, Sub: string;
begin
  // Sit low in the board so that on a quick win the banner covers the rows
  // that were never used rather than the guesses the player wants to see.
  W := Min(PaintBoxBoard.Width - 40, 440);
  H := 116;
  R := Rect((PaintBoxBoard.Width - W) div 2, PaintBoxBoard.Height - H - 12,
            (PaintBoxBoard.Width + W) div 2, PaintBoxBoard.Height - 12);

  RoundBox(C, R, 16, CLR_PANEL, CLR_TILE_EDGE_HI);

  if FPhase = gpWon then
  begin
    Title := '🎉  NAILED IT!';
    Sub := Format('%s in %d %s', [FTargetWord, FCurrentRow + 1,
      specialize IfThen<string>(FCurrentRow = 0, 'try', 'tries')]);
  end
  else
  begin
    if FLoseReason = lrTimeUp then
      Title := '⌛  TIME''S UP!'
    else
      Title := '💩  BUSTED!';
    Sub := 'The word was ' + FTargetWord;
  end;

  Line := Rect(R.Left, R.Top + 14, R.Right, R.Top + 52);
  CenterText(C, Line, Title, -24, CLR_TEXT, True);

  // A long custom word has to shrink to fit.
  Line := Rect(R.Left, R.Top + 52, R.Right, R.Top + 82);
  FontH := FitFont(C, Sub, W - 24, 16, 8, True);
  CenterText(C, Line, Sub, FontH,
    specialize IfThen<TColor>(FPhase = gpWon, CLR_CORRECT, CLR_ACCENT), True);

  Line := Rect(R.Left, R.Top + 82, R.Right, R.Bottom - 8);
  CenterText(C, Line, 'Tap here or press ENTER to play again', -12, CLR_DIM, False);
end;

procedure TForm1.PaintBoxBoardPaint(Sender: TObject);
var
  C: TCanvas;
  Row, Col: Integer;
begin
  C := PaintBoxBoard.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := CLR_BG;
  C.FillRect(0, 0, PaintBoxBoard.Width, PaintBoxBoard.Height);

  ComputeBoardMetrics;
  if (FTileSize > 0) and (Length(FTiles) > 0) then
    for Row := 0 to FMaxGuesses - 1 do
      for Col := 0 to FWordLength - 1 do
        DrawTile(C, Row, Col);

  DrawParticles(C);
  DrawToilet(C);

  if FPhase in [gpWon, gpLost] then
    DrawEndBanner(C);

  // Overlays, in stacking order.
  if FCardVisible then
    DrawDefinitionCard(C);
  if FPromptOpen then
    DrawPrompt(C);
  if FMenuOpen then
    DrawMenu(C);
end;

procedure TForm1.PaintBoxBoardMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if IgnoreMouse or (Button <> mbLeft) then
    Exit;
  FHoldFired := False;
  FHoldPt := Point(X, Y);
  // A press held still on the board opens the lookup menu - the touchscreen
  // stand-in for right-click. Not while something is already on top.
  FHoldArmed := not (FMenuOpen or FPromptOpen or FCardVisible);
  TimerHold.Enabled := False;
  TimerHold.Enabled := FHoldArmed;
end;

procedure TForm1.PaintBoxBoardMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Hot: Integer;
  Hand: Boolean;
begin
  if IgnoreMouse then
    Exit;

  if FHoldArmed and ((Abs(X - FHoldPt.X) > HOLD_SLOP) or (Abs(Y - FHoldPt.Y) > HOLD_SLOP)) then
    CancelHold;

  if FMenuOpen then
  begin
    Hot := MenuItemAt(X, Y);
    if Hot <> FMenuHot then
    begin
      FMenuHot := Hot;
      PaintBoxBoard.Invalidate;
    end;
    Hand := Hot >= 0;
  end
  else if FPromptOpen then
    Hand := PtInRect(FPromptOKRect, Point(X, Y)) or PtInRect(FPromptCancelRect, Point(X, Y))
  else
    Hand := FCardVisible or (FPhase in [gpWon, gpLost]);

  if Hand then
    PaintBoxBoard.Cursor := crHandPoint
  else
    PaintBoxBoard.Cursor := crDefault;
end;

procedure TForm1.PaintBoxBoardMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if IgnoreMouse then
    Exit;
  CancelHold;

  if Button = mbRight then
  begin
    if not FPromptOpen then
      OpenRowMenu(X, Y);
    Exit;
  end;
  if Button <> mbLeft then
    Exit;

  if FHoldFired then
  begin
    FHoldFired := False;   // this release belongs to the hold that opened the menu
    Exit;
  end;
  BoardClick(X, Y);
end;

procedure TForm1.BoardClick(X, Y: Integer);
var
  I: Integer;
begin
  if FMenuOpen then
  begin
    if PtInRect(FMenuRect, Point(X, Y)) then
    begin
      I := MenuItemAt(X, Y);
      if I >= 0 then
        ActivateMenuItem(I);           // a greyed-out item just stays put
    end
    else
      CloseMenu;
    Exit;
  end;

  if FPromptOpen then
  begin
    if PtInRect(FPromptOKRect, Point(X, Y)) then
      PromptAccept
    else if PtInRect(FPromptCancelRect, Point(X, Y)) then
      ClosePrompt;
    Exit;
  end;

  if FCardVisible then
  begin
    CloseCard;
    Exit;
  end;

  if FPhase in [gpWon, gpLost] then
    StartNewGame(FDifficulty);
end;

procedure TForm1.CancelHold;
begin
  TimerHold.Enabled := False;
  FHoldArmed := False;
end;

procedure TForm1.TimerHoldTimer(Sender: TObject);
begin
  TimerHold.Enabled := False;
  if not FHoldArmed then
    Exit;
  FHoldArmed := False;
  FHoldFired := True;
  OpenRowMenu(FHoldPt.X, FHoldPt.Y);
end;

{ ------------------------------------------------------------------ }
{ On-screen keyboard                                                  }
{ ------------------------------------------------------------------ }

procedure TForm1.AddKey(const R: TRect; Kind: TKeyKind; Ch: Char; const ALabel: string);
var
  N: Integer;
begin
  N := Length(FKeys);
  SetLength(FKeys, N + 1);
  FKeys[N].Bounds := R;
  FKeys[N].Kind := Kind;
  FKeys[N].Ch := Ch;
  FKeys[N].Text := ALabel;
end;

{ The letters sit in a tidy block - each row centred under the one above, the
  way phone keyboards do it - and the two big keys get a column of their own
  to the right, past a gap: BACK level with the top row, ENTER with the
  bottom one, both the same size. }
procedure TForm1.LayoutKeys;
const
  Rows: array[0..2] of string = ('QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM');
  Stagger: array[0..2] of Double = (0, 0.5, 1.5);   // in key widths
var
  W, H, Gap, KeyW, KeyH, SpecW, SplitGap, BlockW, BlockX, SpecX: Integer;
  X, Y, R, I, N: Integer;
  EnterText: string;
begin
  SetLength(FKeys, 0);
  W := PaintBoxKeys.Width;
  H := PaintBoxKeys.Height;
  if (W < 80) or (H < 40) then
    Exit;

  Gap := EnsureRange(W div 110, 3, 8);
  // Ten letters, a half-key gap, then a key and a half for BACK / ENTER:
  // twelve key widths across the widest row.
  KeyW := Min((W - 11 * Gap) div 12, 62);
  KeyH := EnsureRange((H - 4 * Gap) div 3, 20, 62);
  { On a narrow, tall screen the panel is generous but the keys are not: left
    alone they become slivers far taller than they are wide, which no finger
    aims at and no letter fits inside.  Keep them roughly key-shaped. }
  KeyH := Min(KeyH, Max(20, KeyW * 8 div 5));
  SpecW := (KeyW * 3) div 2;
  SplitGap := Max(Gap, KeyW div 2);

  BlockW := 10 * KeyW + 9 * Gap;
  BlockX := (W - (BlockW + SplitGap + SpecW)) div 2;
  SpecX := BlockX + BlockW + SplitGap;

  // "ENTER" will not fit a phone-sized key; the return arrow will.
  if SpecW < 52 then
    EnterText := '⏎'
  else
    EnterText := 'ENTER';

  Y := Max(Gap, (H - (3 * KeyH + 2 * Gap)) div 2);
  for R := 0 to 2 do
  begin
    N := Length(Rows[R]);
    X := BlockX + Round(Stagger[R] * (KeyW + Gap));
    for I := 1 to N do
    begin
      AddKey(Rect(X, Y, X + KeyW, Y + KeyH), kkLetter, Rows[R][I], Rows[R][I]);
      Inc(X, KeyW + Gap);
    end;
    case R of
      0: AddKey(Rect(SpecX, Y, SpecX + SpecW, Y + KeyH), kkBack, #8, '⌫');
      2: AddKey(Rect(SpecX, Y, SpecX + SpecW, Y + KeyH), kkEnter, #13, EnterText);
    end;
    Inc(Y, KeyH + Gap);
  end;
end;

function TForm1.KeyAtPoint(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FKeys) do
    if PtInRect(FKeys[I].Bounds, Point(X, Y)) then
      Exit(I);
  Result := -1;
end;

function TForm1.KeyIndexOf(Kind: TKeyKind; Ch: Char): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FKeys) do
    if (FKeys[I].Kind = Kind) and ((Kind <> kkLetter) or (FKeys[I].Ch = Ch)) then
      Exit(I);
  Result := -1;
end;

{ The secret cheat: hold Shift and hover the BACK key to peek at the answer.
  Nothing hints that it exists, which is the point. }
procedure TForm1.UpdateCheatHint(KeyIndex: Integer; Shift: TShiftState);
var
  Want: string;
begin
  if FDebugMode and (ssShift in Shift) and (FTargetWord <> '') and
     (KeyIndex >= 0) and (FKeys[KeyIndex].Kind = kkBack) then
    Want := '🤫 Answer: ' + FTargetWord
  else
    Want := '';

  if Want = PaintBoxKeys.Hint then
    Exit;

  PaintBoxKeys.Hint := Want;
  if Want = '' then
    Application.HideHint   // drop the tooltip the moment Shift or the mouse leaves
  else
    // Windows only pops a hint when the mouse newly enters a control, and
    // the mouse is already sitting on the key - so show it by hand.
    Application.ActivateHint(Mouse.CursorPos);
end;

procedure TForm1.DrawKey(C: TCanvas; Index: Integer);
var
  K: TKeyInfo;
  R: TRect;
  Fill, Txt: TColor;
  Grow: Integer;
  FontH: Integer;
begin
  K := FKeys[Index];
  R := K.Bounds;
  Txt := CLR_TEXT;

  if K.Kind = kkLetter then
  begin
    case FKeyState[K.Ch] of
      tsCorrect: Fill := CLR_CORRECT;
      tsPresent: Fill := CLR_PRESENT;
      tsAbsent:  begin Fill := CLR_KEY_DEAD; Txt := CLR_DIM; end;
    else
      Fill := CLR_KEY;
    end;
  end
  else
    Fill := CLR_KEY_ALT;

  if Index = FHotKey then
    Fill := Shade(Fill, 22);

  if Index = FPressedKey then
  begin
    Fill := Shade(Fill, -16);
    InflateRect(R, -2, -2);
  end
  else if Index = FFlashKey then
  begin
    Fill := Shade(Fill, 46);
    Grow := Max(2, (R.Bottom - R.Top) div 12);
    InflateRect(R, Grow, Grow);
  end;

  RoundBox(C, R, 7, Fill, clNone);

  { Size the glyph to whichever way round the key is tighter.  Sizing on the
    height alone overflows the sides as soon as the keys are narrow, which is
    exactly what happens on a phone. }
  if Length(K.Text) > 1 then
    FontH := -Max(8, Min((R.Bottom - R.Top) * 40 div 100,
                         (R.Right - R.Left) * 2 div (Length(K.Text) + 1)))
  else
    FontH := -Max(9, Min((R.Bottom - R.Top) * 50 div 100,
                         (R.Right - R.Left) * 62 div 100));
  // ...and never let a word run past the edges of its key.
  C.Font.Style := [fsBold];
  C.Font.Height := FontH;
  while (FontH < -8) and (C.TextWidth(K.Text) > R.Right - R.Left - 8) do
  begin
    Inc(FontH);
    C.Font.Height := FontH;
  end;
  CenterText(C, R, K.Text, FontH, Txt, True);
end;

procedure TForm1.PaintBoxKeysPaint(Sender: TObject);
var
  C: TCanvas;
  I: Integer;
begin
  C := PaintBoxKeys.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := CLR_BG;
  C.FillRect(0, 0, PaintBoxKeys.Width, PaintBoxKeys.Height);

  LayoutKeys;
  for I := 0 to High(FKeys) do
    DrawKey(C, I);

  FKeysDirty := False;
end;

procedure TForm1.PaintBoxKeysMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Hit: Integer;
begin
  if IgnoreMouse then
    Exit;
  if Length(FKeys) = 0 then
    LayoutKeys;
  Hit := KeyAtPoint(X, Y);
  UpdateCheatHint(Hit, Shift);

  if Hit <> FHotKey then
  begin
    FHotKey := Hit;
    if Hit >= 0 then
      PaintBoxKeys.Cursor := crHandPoint
    else
      PaintBoxKeys.Cursor := crDefault;
    PaintBoxKeys.Invalidate;
  end;
end;

procedure TForm1.PaintBoxKeysMouseLeave(Sender: TObject);
begin
  if (FHotKey >= 0) or (FPressedKey >= 0) then
  begin
    FHotKey := -1;
    FPressedKey := -1;
    PaintBoxKeys.Invalidate;
  end;
end;

procedure TForm1.PaintBoxKeysMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if IgnoreMouse or (Button <> mbLeft) then
    Exit;
  if Length(FKeys) = 0 then
    LayoutKeys;
  FPressedKey := KeyAtPoint(X, Y);
  if FPressedKey >= 0 then
    PaintBoxKeys.Invalidate;
end;

procedure TForm1.PaintBoxKeysMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  if IgnoreMouse or (Button <> mbLeft) then
    Exit;
  Hit := KeyAtPoint(X, Y);

  if FMenuOpen then
  begin
    CloseMenu;     // tapping away from a menu only closes it
    Hit := -1;
  end;

  // Only fire if press and release landed on the same key.
  if (Hit >= 0) and (Hit = FPressedKey) then
    case FKeys[Hit].Kind of
      kkLetter: TypeLetter(FKeys[Hit].Ch);
      kkEnter:  PressEnter;
      kkBack:   PressBack;
    end;
  FPressedKey := -1;
  PaintBoxKeys.Invalidate;
end;

{ ------------------------------------------------------------------ }
{ Top bar                                                             }
{ ------------------------------------------------------------------ }

function TForm1.TimerCaption(Compact: Boolean): string;
begin
  if Compact then
    Exit('⏳');
  case FTimerMode of
    tmOff:   Result := '⏳ Timer';
    tmLevel: Result := '⏳ By level';
  else
    Result := '⏳ ' + FormatSecs(FTimerSecs);
  end;
end;

function TForm1.ScoreText(Compact: Boolean): string;
begin
  if FTotalGames = 0 then
    Exit('0 / 0');
  if Compact then
    Result := Format('%d/%d', [FWins, FTotalGames])
  else
    Result := Format('%d / %d  ·  %.0f%%', [FWins, FTotalGames, FWins / FTotalGames * 100]);
end;

function TForm1.TimerShowing: Boolean;
begin
  Result := FTimeTotalMs > 0;
end;

function TForm1.BarRightWidth(C: TCanvas; Compact, HideScore: Boolean): Integer;
begin
  C.Font.Height := -14;
  C.Font.Style := [fsBold];
  Result := 12;
  if not HideScore then
    Inc(Result, C.TextWidth(ScoreText(Compact)) + 4);
  if TimerShowing then
    Inc(Result, 22 + 6 + C.TextWidth('00:00') + 14);
end;

{ Squeezes in stages until everything fits: icons instead of words, then the
  Look Up button goes (it is in the menu as well), then tighter buttons, and
  on the very narrowest screens with the hourglass up, the score. }
procedure TForm1.LayoutBar(C: TCanvas);
const
  MARGIN = 8;
  BTN_H = 36;
var
  Acts: array[0..4] of Integer;
  Caps: array[0..4] of string;
  I, N, X, BtnTop, Pad, MinW, Gap, Step: Integer;
  DropLookup: Boolean;

  procedure Fill(Compact: Boolean);
  begin
    if Compact then
    begin
      Caps[0] := '↻';
      Caps[1] := IntToStr(FDifficulty) + ' ▾';
      Caps[2] := TimerCaption(True) + ' ▾';
      Caps[3] := '🔍';
    end
    else
    begin
      Caps[0] := '↻ New';
      Caps[1] := Format('%d letters ▾', [FDifficulty]);
      Caps[2] := TimerCaption(False) + ' ▾';
      Caps[3] := '🔍 Look up';
    end;
    Caps[4] := '☰';
  end;

  function ButtonW(const S: string): Integer;
  begin
    Result := Max(MinW, C.TextWidth(S) + 2 * Pad);
  end;

  function Needed: Integer;
  var
    J: Integer;
  begin
    Result := BarRightWidth(C, FBarCompact, FBarHideScore) + MARGIN;
    for J := 0 to 4 do
      if not (DropLookup and (J = 3)) then
        Inc(Result, ButtonW(Caps[J]) + Gap);
  end;

begin
  for I := 0 to 4 do
    Caps[I] := '';               // Fill() sets them, but the compiler cannot see into it
  Acts[0] := ACT_NEW;
  Acts[1] := MENU_LEVEL;
  Acts[2] := MENU_TIMER;
  Acts[3] := ACT_LOOKUP_ANY;
  Acts[4] := MENU_MORE;

  for Step := 0 to 4 do
  begin
    FBarCompact := Step >= 1;
    DropLookup := Step >= 2;
    if Step >= 3 then
    begin
      Pad := 7; MinW := 34; Gap := 4;
    end
    else
    begin
      Pad := 12; MinW := 40; Gap := 6;
    end;
    FBarHideScore := Step >= 4;
    Fill(FBarCompact);
    if Needed <= PaintBoxBar.Width then
      Break;
  end;

  C.Font.Height := -14;
  C.Font.Style := [fsBold];
  SetLength(FBarButtons, 0);
  BtnTop := (PaintBoxBar.Height - BTN_H) div 2;
  X := MARGIN;
  for I := 0 to 4 do
  begin
    if DropLookup and (I = 3) then
      Continue;
    N := Length(FBarButtons);
    SetLength(FBarButtons, N + 1);
    FBarButtons[N].Action := Acts[I];
    FBarButtons[N].Caption := Caps[I];
    FBarButtons[N].Bounds := Rect(X, BtnTop, X + ButtonW(Caps[I]), BtnTop + BTN_H);
    X := FBarButtons[N].Bounds.Right + Gap;
  end;
end;

procedure TForm1.DrawBarButton(C: TCanvas; Index: Integer);
var
  B: TBarButton;
  Fill, Edge: TColor;
  R: TRect;
begin
  B := FBarButtons[Index];
  R := B.Bounds;
  if B.Action = ACT_NEW then
    Fill := Shade(CLR_CORRECT, -30)
  else
    Fill := CLR_KEY;
  Edge := clNone;
  if FMenuOpen and (FMenuSource = B.Action) then
  begin
    Fill := CLR_KEY_ALT;
    Edge := CLR_ACCENT;
  end;
  if Index = FBarHot then
    Fill := Shade(Fill, 18);
  if Index = FBarPressed then
  begin
    Fill := Shade(Fill, -16);
    InflateRect(R, -1, -1);
  end;
  RoundBox(C, R, 9, Fill, Edge);
  CenterText(C, R, B.Caption, -14, CLR_TEXT, True);
end;

{ Sand runs from top to bottom as the clock goes. The bulbs are triangles, so
  the sand's height goes with the square root of how much of it there is. }
procedure TForm1.DrawHourglass(C: TCanvas; const R: TRect; Frac: Double; Running: Boolean);
var
  GX, GTop, GBot, GMid, HW, BulbH, HS, WS, HF, WF: Integer;
  Sand: TColor;
begin
  GX := (R.Left + R.Right) div 2;
  GTop := R.Top + 4;
  GBot := R.Bottom - 4;
  GMid := (GTop + GBot) div 2;
  HW := (R.Right - R.Left) div 2 - 1;
  BulbH := Max(1, GMid - GTop);

  if Frac < 0.2 then
  begin
    // Running low: the sand turns orange and throbs.
    if (GetTickCount64 div 300) mod 2 = 0 then
      Sand := CLR_ACCENT
    else
      Sand := Shade(CLR_ACCENT, -45);
  end
  else
    Sand := CLR_PRESENT;

  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := CLR_DIM;
  C.Brush.Style := bsSolid;
  C.Brush.Color := CLR_BG;
  C.Polygon([Point(GX - HW, GTop), Point(GX + HW, GTop), Point(GX + 2, GMid),
             Point(GX + HW, GBot), Point(GX - HW, GBot), Point(GX - 2, GMid)]);

  C.Pen.Color := Sand;
  C.Brush.Color := Sand;

  HS := Round(BulbH * Sqrt(Frac));
  if HS > 1 then
  begin
    WS := Round((HW - 2) * HS / BulbH);
    C.Polygon([Point(GX - WS, GMid - HS), Point(GX + WS, GMid - HS), Point(GX, GMid)]);
  end;

  HF := Round(BulbH * (1 - Sqrt(Frac)));
  if HF > 0 then
  begin
    WF := Round((HW - 2) * (1 - HF / BulbH));
    C.Polygon([Point(GX - HW + 2, GBot - 1), Point(GX + HW - 2, GBot - 1),
               Point(GX + WF, GBot - HF), Point(GX - WF, GBot - HF)]);
  end;

  if Running and (Frac > 0) and (Frac < 1) then
    C.Line(GX, GMid, GX, GBot - HF);

  RoundBox(C, Rect(R.Left - 1, R.Top, R.Right + 1, R.Top + 4), 2, CLR_KEY_ALT, clNone);
  RoundBox(C, Rect(R.Left - 1, R.Bottom - 4, R.Right + 1, R.Bottom), 2, CLR_KEY_ALT, clNone);
end;

procedure TForm1.DrawBarRight(C: TCanvas);
var
  X, MidY: Integer;
  S: string;
  Frac: Double;
begin
  C.Font.Height := -14;
  C.Font.Style := [fsBold];
  MidY := PaintBoxBar.Height div 2;
  X := PaintBoxBar.Width - 12;

  if not FBarHideScore then
  begin
    S := ScoreText(FBarCompact);
    Dec(X, C.TextWidth(S));
    C.Brush.Style := bsClear;
    C.Font.Color := CLR_DIM;
    C.TextOut(X, MidY - C.TextHeight(S) div 2, S);
    Dec(X, 14);
  end;

  if TimerShowing then
  begin
    Frac := FTimeLeftMs / FTimeTotalMs;
    if Frac < 0 then Frac := 0;
    if Frac > 1 then Frac := 1;

    S := FormatSecs(Integer((FTimeLeftMs + 999) div 1000));
    Dec(X, C.TextWidth(S));
    if Frac < 0.2 then
      C.Font.Color := CLR_ACCENT
    else
      C.Font.Color := CLR_TEXT;
    C.Brush.Style := bsClear;
    C.TextOut(X, MidY - C.TextHeight(S) div 2, S);

    Dec(X, 6 + 22);
    DrawHourglass(C, Rect(X, MidY - 19, X + 22, MidY + 19), Frac,
      (FPhase in [gpPlaying, gpRevealing]) and not (FCardVisible or FPromptOpen));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TForm1.PaintBoxBarPaint(Sender: TObject);
var
  C: TCanvas;
  I: Integer;
begin
  C := PaintBoxBar.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := CLR_PANEL;
  C.FillRect(0, 0, PaintBoxBar.Width, PaintBoxBar.Height);

  LayoutBar(C);
  for I := 0 to High(FBarButtons) do
    DrawBarButton(C, I);
  DrawBarRight(C);
end;

function TForm1.BarButtonAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FBarButtons) do
    if PtInRect(FBarButtons[I].Bounds, Point(X, Y)) then
      Exit(I);
  Result := -1;
end;

procedure TForm1.PaintBoxBarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if IgnoreMouse or (Button <> mbLeft) then
    Exit;
  FBarPressed := BarButtonAt(X, Y);
  PaintBoxBar.Invalidate;
end;

procedure TForm1.PaintBoxBarMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Hit: Integer;
begin
  if IgnoreMouse then
    Exit;
  Hit := BarButtonAt(X, Y);
  if Hit <> FBarHot then
  begin
    FBarHot := Hit;
    if Hit >= 0 then
      PaintBoxBar.Cursor := crHandPoint
    else
      PaintBoxBar.Cursor := crDefault;
    PaintBoxBar.Invalidate;
  end;
end;

procedure TForm1.PaintBoxBarMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  if IgnoreMouse or (Button <> mbLeft) then
    Exit;
  Hit := BarButtonAt(X, Y);
  if (Hit >= 0) and (Hit = FBarPressed) then
    BarClick(Hit)
  else if (Hit < 0) and FMenuOpen then
    CloseMenu;
  FBarPressed := -1;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.PaintBoxBarMouseLeave(Sender: TObject);
begin
  if (FBarHot >= 0) or (FBarPressed >= 0) then
  begin
    FBarHot := -1;
    FBarPressed := -1;
    PaintBoxBar.Invalidate;
  end;
end;

procedure TForm1.BarClick(Index: Integer);
var
  A: Integer;
begin
  if FPromptOpen then
    Exit;                // finish or cancel the prompt first
  A := FBarButtons[Index].Action;
  if (A >= MENU_LEVEL) and (A <= MENU_MORE) then
  begin
    if FMenuOpen and (FMenuSource = A) then
      CloseMenu
    else
      OpenBarMenu(A, FBarButtons[Index].Bounds.Left);
    Exit;
  end;
  CloseMenu;
  if FCardVisible then
    CloseCard;
  RunAction(A);
end;

{ ------------------------------------------------------------------ }
{ In-window menus                                                     }
{ ------------------------------------------------------------------ }

procedure TForm1.ClearMenu;
begin
  SetLength(FMenuItems, 0);
end;

procedure TForm1.AddMenuItem(const ACaption: string; AAction: Integer;
  AEnabled: Boolean; AChecked: Boolean; const AShortcut: string);
var
  N: Integer;
begin
  N := Length(FMenuItems);
  SetLength(FMenuItems, N + 1);
  FMenuItems[N] := Default(TMenuEntry);
  FMenuItems[N].Caption := ACaption;
  FMenuItems[N].Action := AAction;
  FMenuItems[N].Enabled := AEnabled;
  FMenuItems[N].Checked := AChecked;
  FMenuItems[N].Shortcut := AShortcut;
end;

procedure TForm1.AddMenuSep;
var
  N: Integer;
begin
  N := Length(FMenuItems);
  SetLength(FMenuItems, N + 1);
  FMenuItems[N] := Default(TMenuEntry);
  FMenuItems[N].Separator := True;
end;

procedure TForm1.ShowMenu(ASource, AX, AY: Integer);
begin
  if FCardVisible then
    CloseCard;
  FMenuSource := ASource;
  FMenuAnchor := Point(AX, AY);
  FMenuHot := -1;
  FMenuOpen := True;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.CloseMenu;
begin
  if not FMenuOpen then
    Exit;
  FMenuOpen := False;
  FMenuHot := -1;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.OpenBarMenu(AMenu, AX: Integer);
var
  L, I: Integer;
  OnPreset: Boolean;
begin
  ClearMenu;
  case AMenu of
    MENU_LEVEL:
      for L := MIN_WORD_LEN to MAX_WORD_LEN do
        AddMenuItem(Format('%s  ·  %d letters, %d tries',
          [LEVEL_NAMES[L], L, MaxGuessesFor(L)]), ACT_LEVEL + L, True, L = FDifficulty);

    MENU_TIMER:
      begin
        AddMenuItem('No timer', ACT_TIMER_OFF, True, FTimerMode = tmOff);
        AddMenuItem(Format('By level  ·  %s for %d letters',
          [FormatSecs(LevelSecs(FDifficulty)), FDifficulty]),
          ACT_TIMER_LEVEL, True, FTimerMode = tmLevel);
        AddMenuSep;
        OnPreset := False;
        for I := 0 to High(TIMER_PRESETS) do
        begin
          AddMenuItem(Format('%d minute%s', [TIMER_PRESETS[I] div 60,
            specialize IfThen<string>(TIMER_PRESETS[I] = 60, '', 's')]),
            ACT_TIMER_SECS + TIMER_PRESETS[I], True,
            (FTimerMode = tmFixed) and (FTimerSecs = TIMER_PRESETS[I]));
          if (FTimerMode = tmFixed) and (FTimerSecs = TIMER_PRESETS[I]) then
            OnPreset := True;
        end;
        AddMenuSep;
        if (FTimerMode = tmFixed) and not OnPreset then
          AddMenuItem(Format('Custom  ·  %s...', [FormatSecs(FTimerSecs)]),
            ACT_TIMER_CUSTOM, True, True)
        else
          AddMenuItem('Custom time...', ACT_TIMER_CUSTOM);
      end;

    MENU_MORE:
      begin
        AddMenuItem('Your own secret word...', ACT_CUSTOM_WORD, True, False, 'Ctrl+M');
        AddMenuItem('Look up any word...', ACT_LOOKUP_ANY, True, False, 'Ctrl+L');
        AddMenuItem('Give up', ACT_GIVE_UP, FPhase = gpPlaying);
        AddMenuSep;
        AddMenuItem('Sound effects', ACT_SOUND, True, FSoundOn);
        AddMenuItem('Key click sounds', ACT_CLICKS, FSoundOn, FClicksOn);
        AddMenuSep;
        AddMenuItem('How to play', ACT_HELP, True, False, 'F1');
        AddMenuItem('About', ACT_ABOUT);
        AddMenuItem('Quit', ACT_QUIT);
      end;
  end;
  ShowMenu(AMenu, AX, 4);
end;

{ The right-click / press-and-hold menu for a row. }
procedure TForm1.OpenRowMenu(AX, AY: Integer);
var
  W: string;
begin
  W := WordInRow(RowAtPoint(AX, AY));
  FMenuRowWord := W;
  ClearMenu;
  if (W <> '') and IsValidWord(W) then
    AddMenuItem(Format('Look up "%s"', [W]), ACT_LOOKUP_ROW)
  else if W <> '' then
    AddMenuItem(Format('"%s" is not a word', [W]), ACT_NONE, False)
  else
    AddMenuItem('Nothing in this row yet', ACT_NONE, False);
  AddMenuSep;
  AddMenuItem('Look up any word...', ACT_LOOKUP_ANY);
  // Just below and right of the finger, so the finger does not hide it.
  ShowMenu(0, AX + 6, AY + 6);
end;

procedure TForm1.DrawMenu(C: TCanvas);
const
  ITEM_H = 38;       // finger-sized
  SEP_H = 11;
  PAD = 8;
  CHECK_W = 32;
var
  I, W, H, X, Y, IY, TW, TH: Integer;
  R: TRect;
begin
  C.Font.Height := -15;
  C.Font.Style := [fsBold];      // measure bold: checked items are drawn bold
  W := 0;
  H := 2 * PAD;
  for I := 0 to High(FMenuItems) do
    if FMenuItems[I].Separator then
      Inc(H, SEP_H)
    else
    begin
      TW := C.TextWidth(FMenuItems[I].Caption);
      if FMenuItems[I].Shortcut <> '' then
        Inc(TW, C.TextWidth(FMenuItems[I].Shortcut) + 24);
      W := Max(W, TW);
      Inc(H, ITEM_H);
    end;
  W := EnsureRange(W + CHECK_W + 24, 180, Max(180, PaintBoxBoard.Width - 16));

  X := EnsureRange(FMenuAnchor.X, 8, Max(8, PaintBoxBoard.Width - W - 8));
  Y := FMenuAnchor.Y;
  if Y + H > PaintBoxBoard.Height - 8 then
    Y := Max(4, PaintBoxBoard.Height - H - 8);
  FMenuRect := Rect(X, Y, X + W, Y + H);

  RoundBox(C, Rect(X + 4, Y + 5, X + W + 4, Y + H + 5), 12, CLR_SHADOW, clNone);
  RoundBox(C, FMenuRect, 12, CLR_PANEL, CLR_TILE_EDGE_HI);

  IY := Y + PAD;
  for I := 0 to High(FMenuItems) do
  begin
    if FMenuItems[I].Separator then
    begin
      C.Pen.Style := psSolid;
      C.Pen.Color := CLR_TILE_EDGE;
      C.Line(X + 12, IY + SEP_H div 2, X + W - 12, IY + SEP_H div 2);
      FMenuItems[I].Bounds := Rect(0, 0, 0, 0);
      Inc(IY, SEP_H);
      Continue;
    end;

    R := Rect(X + 5, IY, X + W - 5, IY + ITEM_H);
    FMenuItems[I].Bounds := R;
    if (I = FMenuHot) and FMenuItems[I].Enabled then
      RoundBox(C, R, 8, CLR_KEY, clNone);

    C.Brush.Style := bsClear;
    if FMenuItems[I].Checked then
    begin
      C.Font.Height := -15;
      C.Font.Style := [fsBold];
      C.Font.Color := CLR_CORRECT;
      TH := C.TextHeight('✓');
      C.TextOut(R.Left + 10, R.Top + (ITEM_H - TH) div 2, '✓');
    end;

    C.Font.Height := -15;
    if FMenuItems[I].Checked then
      C.Font.Style := [fsBold]
    else
      C.Font.Style := [];
    if FMenuItems[I].Enabled then
      C.Font.Color := CLR_TEXT
    else
      C.Font.Color := CLR_DIM;
    TH := C.TextHeight(FMenuItems[I].Caption);
    C.TextOut(R.Left + CHECK_W, R.Top + (ITEM_H - TH) div 2, FMenuItems[I].Caption);

    if FMenuItems[I].Shortcut <> '' then
    begin
      C.Font.Height := -12;
      C.Font.Style := [];
      C.Font.Color := CLR_DIM;
      TW := C.TextWidth(FMenuItems[I].Shortcut);
      TH := C.TextHeight(FMenuItems[I].Shortcut);
      C.TextOut(R.Right - 10 - TW, R.Top + (ITEM_H - TH) div 2, FMenuItems[I].Shortcut);
    end;
    C.Brush.Style := bsSolid;
    Inc(IY, ITEM_H);
  end;
end;

function TForm1.MenuItemAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FMenuItems) do
    if (not FMenuItems[I].Separator) and FMenuItems[I].Enabled and
       PtInRect(FMenuItems[I].Bounds, Point(X, Y)) then
      Exit(I);
  Result := -1;
end;

procedure TForm1.MoveMenuHot(Dir: Integer);
var
  N, I, Tries: Integer;
begin
  N := Length(FMenuItems);
  if N = 0 then
    Exit;
  I := FMenuHot;
  if I < 0 then
    if Dir > 0 then I := -1 else I := N;
  for Tries := 1 to N do
  begin
    Inc(I, Dir);
    if I >= N then I := 0;
    if I < 0 then I := N - 1;
    if (not FMenuItems[I].Separator) and FMenuItems[I].Enabled then
    begin
      FMenuHot := I;
      PaintBoxBoard.Invalidate;
      Exit;
    end;
  end;
end;

procedure TForm1.ActivateMenuItem(Index: Integer);
var
  A: Integer;
begin
  if (Index < 0) or (Index > High(FMenuItems)) then
    Exit;
  if FMenuItems[Index].Separator or not FMenuItems[Index].Enabled then
    Exit;
  A := FMenuItems[Index].Action;
  CloseMenu;
  RunAction(A);
end;

procedure TForm1.RunAction(Act: Integer);
begin
  case Act of
    ACT_NONE: ;
    ACT_NEW:
      StartNewGame(FDifficulty);
    ACT_LEVEL + MIN_WORD_LEN .. ACT_LEVEL + MAX_WORD_LEN:
      begin
        FDifficulty := Act - ACT_LEVEL;
        StartNewGame(FDifficulty);
      end;
    ACT_TIMER_OFF:
      SetTimerMode(tmOff, FTimerSecs);
    ACT_TIMER_LEVEL:
      SetTimerMode(tmLevel, FTimerSecs);
    ACT_TIMER_CUSTOM:
      OpenPrompt(prTime, ACT_TIMER_CUSTOM, 'Custom timer',
        'Seconds (like 90) or minutes:seconds (like 2:30)', FormatSecs(FTimerSecs), 6);
    ACT_CUSTOM_WORD:
      OpenPrompt(prWord, ACT_CUSTOM_WORD, 'Your own secret word',
        'Any letters, any length. It does not have to be a real word!', '', MAX_CUSTOM_LEN);
    ACT_LOOKUP_ANY:
      OpenPrompt(prWord, ACT_LOOKUP_ANY, 'Look up a word',
        'Type any word to see what it means', '', MAX_LOOKUP_LEN);
    ACT_LOOKUP_ROW:
      StartLookup(FMenuRowWord);
    ACT_GIVE_UP:
      if FPhase = gpPlaying then
        LoseGame(lrGaveUp);
    ACT_HELP:
      ShowHelpCard;
    ACT_ABOUT:
      ShowAboutCard;
    ACT_SOUND:
      FSoundOn := not FSoundOn;
    ACT_CLICKS:
      FClicksOn := not FClicksOn;
    ACT_QUIT:
      Close;
  else
    if Act >= ACT_TIMER_SECS then
      SetTimerMode(tmFixed, Act - ACT_TIMER_SECS);
  end;
  PaintBoxBar.Invalidate;
end;

{ ------------------------------------------------------------------ }
{ In-window text prompt                                               }
{ ------------------------------------------------------------------ }

procedure TForm1.OpenPrompt(AKind: TPromptKind; AAction: Integer;
  const ATitle, AHint, AInitial: string; AMaxLen: Integer);
begin
  CloseMenu;
  if FCardVisible then
    CloseCard;
  CancelHold;
  FPromptKind := AKind;
  FPromptAction := AAction;
  FPromptTitle := ATitle;
  FPromptHint := AHint;
  FPromptText := AInitial;
  FPromptMax := AMaxLen;
  FPromptError := '';
  FPromptOpen := True;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;     // the hourglass pauses
end;

procedure TForm1.ClosePrompt;
begin
  if not FPromptOpen then
    Exit;
  FPromptOpen := False;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.PromptType(Ch: Char);
begin
  case FPromptKind of
    prWord: if not (Ch in ['A'..'Z']) then Exit;
    prTime: if not (Ch in ['0'..'9', ':']) then Exit;
  end;
  if Length(FPromptText) >= FPromptMax then
  begin
    FPromptError := Format('That is the most it takes - %d', [FPromptMax]);
    PaintBoxBoard.Invalidate;
    Exit;
  end;
  FPromptText := FPromptText + Ch;
  FPromptError := '';
  if Ch in ['A'..'Z'] then
    FlashKey(kkLetter, Ch);
  PlayClick('key.wav');
  PaintBoxBoard.Invalidate;
end;

procedure TForm1.PromptBack;
begin
  if FPromptText = '' then
    Exit;
  Delete(FPromptText, Length(FPromptText), 1);
  FPromptError := '';
  FlashKey(kkBack, #8);
  PlayClick('back.wav');
  PaintBoxBoard.Invalidate;
end;

procedure TForm1.PromptAccept;
var
  S: string;
  Secs: Integer;
begin
  S := Trim(FPromptText);
  case FPromptAction of
    ACT_CUSTOM_WORD, ACT_LOOKUP_ANY:
      begin
        if S = '' then
        begin
          FPromptError := 'Type a word first';
          PaintBoxBoard.Invalidate;
          Exit;
        end;
        PlayClick('enter.wav');
        ClosePrompt;
        if FPromptAction = ACT_CUSTOM_WORD then
          StartNewGame(Length(S), S)
        else
          StartLookup(S);
      end;
    ACT_TIMER_CUSTOM:
      begin
        Secs := ParseClock(S);
        if Secs < 10 then
        begin
          FPromptError := 'Try something like 90 or 2:30 (10 seconds or more)';
          PaintBoxBoard.Invalidate;
          Exit;
        end;
        PlayClick('enter.wav');
        ClosePrompt;
        SetTimerMode(tmFixed, Secs);
      end;
  else
    ClosePrompt;
  end;
end;

procedure TForm1.DrawPrompt(C: TCanvas);
const
  PAD = 20;
var
  W, H, X, Y, FieldW, TH, CaretX: Integer;
  R, Field: TRect;
  Disp, Counter: string;
  Cut: Boolean;
begin
  W := Min(PaintBoxBoard.Width - 24, 460);
  H := 200;
  X := (PaintBoxBoard.Width - W) div 2;
  Y := Max(8, (PaintBoxBoard.Height - H) div 2);
  R := Rect(X, Y, X + W, Y + H);
  RoundBox(C, Rect(X + 4, Y + 5, X + W + 4, Y + H + 5), 16, CLR_SHADOW, clNone);
  RoundBox(C, R, 16, CLR_PANEL, CLR_TILE_EDGE_HI);

  C.Brush.Style := bsClear;
  C.Font.Height := -20;
  C.Font.Style := [fsBold];
  C.Font.Color := CLR_ACCENT;
  C.TextOut(X + PAD, Y + 16, FPromptTitle);

  FitFont(C, FPromptHint, W - 2 * PAD, 13, 9, False);
  C.Font.Color := CLR_DIM;
  C.TextOut(X + PAD, Y + 46, FPromptHint);

  Field := Rect(X + PAD, Y + 72, X + W - PAD, Y + 120);
  RoundBox(C, Field, 8, CLR_BG, CLR_TILE_EDGE_HI);

  // Show the end of a long entry - the part being typed.
  C.Brush.Style := bsClear;
  C.Font.Height := -24;
  C.Font.Style := [fsBold];
  C.Font.Color := CLR_TEXT;
  FieldW := Field.Right - Field.Left - 40;
  Disp := FPromptText;
  Cut := False;
  while (Disp <> '') and (C.TextWidth(Disp) > FieldW) do
  begin
    Delete(Disp, 1, 1);
    Cut := True;
  end;
  if Cut then
    Disp := '…' + Disp;
  TH := C.TextHeight('W');
  C.TextOut(Field.Left + 12, Field.Top + (Field.Bottom - Field.Top - TH) div 2, Disp);
  CaretX := Field.Left + 12 + C.TextWidth(Disp) + 2;
  C.Brush.Style := bsSolid;
  C.Brush.Color := CLR_ACCENT;
  C.FillRect(CaretX, Field.Top + 10, CaretX + 3, Field.Bottom - 10);

  if (FPromptKind = prWord) and (FPromptText <> '') then
  begin
    Counter := IntToStr(Length(FPromptText));
    C.Brush.Style := bsClear;
    C.Font.Height := -11;
    C.Font.Style := [];
    C.Font.Color := CLR_DIM;
    C.TextOut(Field.Right - 8 - C.TextWidth(Counter), Field.Top + 4, Counter);
  end;

  if FPromptError <> '' then
  begin
    C.Brush.Style := bsClear;
    FitFont(C, FPromptError, W - 2 * PAD, 12, 8, False);
    C.Font.Color := CLR_ACCENT;
    C.TextOut(X + PAD, Y + 126, FPromptError);
  end;

  FPromptOKRect := Rect(X + W - PAD - 96, Y + H - 50, X + W - PAD, Y + H - 14);
  FPromptCancelRect := Rect(FPromptOKRect.Left - 10 - 96, FPromptOKRect.Top,
                            FPromptOKRect.Left - 10, FPromptOKRect.Bottom);
  RoundBox(C, FPromptCancelRect, 9, CLR_KEY, clNone);
  CenterText(C, FPromptCancelRect, 'Cancel', -14, CLR_TEXT, True);
  RoundBox(C, FPromptOKRect, 9, Shade(CLR_CORRECT, -20), clNone);
  CenterText(C, FPromptOKRect, 'OK', -15, CLR_TEXT, True);
  C.Brush.Style := bsSolid;
end;

{ ------------------------------------------------------------------ }
{ Input                                                               }
{ ------------------------------------------------------------------ }

{ Keyboard and on-screen keys both come through these three, so a prompt,
  a menu or a card on top gets first say whatever the input came from. }
procedure TForm1.TypeLetter(Ch: Char);
begin
  if FPromptOpen then
  begin
    PromptType(Ch);
    Exit;
  end;
  if FMenuOpen then
  begin
    CloseMenu;
    Exit;
  end;
  if FCardVisible then
    CloseCard;               // carry on typing straight through it
  if (FPhase = gpPlaying) and (FCurrentCol < FWordLength) then
    PlayClick('key.wav');
  AddLetter(Ch);
end;

procedure TForm1.PressBack;
begin
  if FPromptOpen then
  begin
    PromptBack;
    Exit;
  end;
  if FMenuOpen then
  begin
    CloseMenu;
    Exit;
  end;
  if FCardVisible then
    CloseCard;
  if (FPhase = gpPlaying) and (FCurrentCol > 0) then
    PlayClick('back.wav');
  RemoveLetter;
end;

procedure TForm1.PressEnter;
begin
  if FPromptOpen then
  begin
    PromptAccept;
    Exit;
  end;
  if FMenuOpen then
  begin
    if FMenuHot >= 0 then
      ActivateMenuItem(FMenuHot)
    else
      CloseMenu;
    Exit;
  end;
  if FCardVisible then
  begin
    CloseCard;
    Exit;
  end;
  if FPhase in [gpWon, gpLost] then
  begin
    StartNewGame(FDifficulty);
    Exit;
  end;
  if FPhase = gpPlaying then
    PlayClick('enter.wav');
  SubmitGuess;
end;

procedure TForm1.FormKeyPress(Sender: TObject; var Key: char);
var
  Ch: Char;
begin
  // Ctrl shortcuts are handled in FormKeyDown. Ctrl+M still arrives here as
  // #13 and Ctrl+H as #8, which would otherwise also guess or delete.
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Key := #0;
    Exit;
  end;

  Ch := UpCase(Key);
  if FPromptOpen and (FPromptKind = prTime) and (Ch in ['0'..'9', ':']) then
  begin
    PromptType(Ch);
    Key := #0;
    Exit;
  end;

  case Ch of
    'A'..'Z': TypeLetter(Ch);
    #13:      PressEnter;
    #8:       PressBack;
  else
    Exit;
  end;
  Key := #0;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if FMenuOpen then
      CloseMenu
    else if FPromptOpen then
      ClosePrompt
    else if FCardVisible then
      CloseCard;
    Key := 0;
    Exit;
  end;

  if FMenuOpen and ((Key = VK_UP) or (Key = VK_DOWN)) then
  begin
    if Key = VK_UP then
      MoveMenuHot(-1)
    else
      MoveMenuHot(1);
    Key := 0;
    Exit;
  end;

  if FPromptOpen then
    Exit;                    // shortcuts wait until the prompt is dealt with

  if Key = VK_F1 then
  begin
    RunAction(ACT_HELP);
    Key := 0;
    Exit;
  end;

  if ssCtrl in Shift then
  begin
    case Key of
      VK_N: RunAction(ACT_NEW);
      VK_M: RunAction(ACT_CUSTOM_WORD);
      VK_L: RunAction(ACT_LOOKUP_ANY);
      VK_D:
        // Hidden developer info: Ctrl+Shift+D
        if ssShift in Shift then
          ShowPoolInfo
        else
          Exit;
    else
      Exit;
    end;
    Key := 0;
  end;
end;

{ ------------------------------------------------------------------ }
{ Touchscreen                                                         }
{ ------------------------------------------------------------------ }

{ A touchscreen that also emulates a mouse would deliver every tap twice -
  once through HandleTouch, once as a click - and type every letter twice. }
function TForm1.IgnoreMouse: Boolean;
begin
  Result := (not FInTouch) and (FLastTouchT <> 0) and
            (GetTickCount64 - FLastTouchT < TOUCH_MOUSE_GUARD_MS);
end;

function TForm1.TouchTargetAt(SX, SY: Integer): TControl;

  function Hit(PB: TPaintBox): Boolean;
  var
    P: TPoint;
  begin
    P := PB.ScreenToClient(Point(SX, SY));
    Result := PB.IsVisible and PtInRect(Rect(0, 0, PB.Width, PB.Height), P);
  end;

begin
  if Hit(PaintBoxKeys) then
    Exit(PaintBoxKeys);
  if Hit(PaintBoxBar) then
    Exit(PaintBoxBar);
  if Hit(PaintBoxBoard) then
    Exit(PaintBoxBoard);
  Result := nil;
end;

{ Touch arrives here from unittouch and is replayed through the same mouse
  handlers a click uses, so taps, drags and press-and-hold all behave alike. }
procedure TForm1.HandleTouch(Phase: TTouchPhase; Seq: Pointer; SX, SY: Integer);
var
  P: TPoint;
  Target: TControl;
begin
  // Follow one finger; others landing mid-gesture are ignored.
  if Phase = tpBegin then
  begin
    if FTouchSeq <> nil then
      Exit;
    FTouchSeq := Seq;
    FTouchTarget := TouchTargetAt(SX, SY);
  end
  else if Seq <> FTouchSeq then
    Exit;

  FLastTouchT := GetTickCount64;
  Target := FTouchTarget;
  if Phase in [tpEnd, tpCancel] then
  begin
    FTouchSeq := nil;
    FTouchTarget := nil;
  end;
  if Target = nil then
    Exit;

  P := Target.ScreenToClient(Point(SX, SY));
  FInTouch := True;
  try
    if Target = PaintBoxKeys then
      case Phase of
        tpBegin:
          begin
            PaintBoxKeysMouseMove(PaintBoxKeys, [], P.X, P.Y);
            PaintBoxKeysMouseDown(PaintBoxKeys, mbLeft, [], P.X, P.Y);
          end;
        tpMove:
          PaintBoxKeysMouseMove(PaintBoxKeys, [], P.X, P.Y);
        tpEnd:
          begin
            PaintBoxKeysMouseUp(PaintBoxKeys, mbLeft, [], P.X, P.Y);
            PaintBoxKeysMouseLeave(PaintBoxKeys);   // a finger leaves no hover behind
          end;
        tpCancel:
          PaintBoxKeysMouseLeave(PaintBoxKeys);
      end
    else if Target = PaintBoxBar then
      case Phase of
        tpBegin:
          begin
            PaintBoxBarMouseMove(PaintBoxBar, [], P.X, P.Y);
            PaintBoxBarMouseDown(PaintBoxBar, mbLeft, [], P.X, P.Y);
          end;
        tpMove:
          PaintBoxBarMouseMove(PaintBoxBar, [], P.X, P.Y);
        tpEnd:
          begin
            PaintBoxBarMouseUp(PaintBoxBar, mbLeft, [], P.X, P.Y);
            PaintBoxBarMouseLeave(PaintBoxBar);
          end;
        tpCancel:
          PaintBoxBarMouseLeave(PaintBoxBar);
      end
    else
      case Phase of
        tpBegin:
          begin
            PaintBoxBoardMouseMove(PaintBoxBoard, [], P.X, P.Y);
            PaintBoxBoardMouseDown(PaintBoxBoard, mbLeft, [], P.X, P.Y);
          end;
        tpMove:
          PaintBoxBoardMouseMove(PaintBoxBoard, [], P.X, P.Y);
        tpEnd:
          PaintBoxBoardMouseUp(PaintBoxBoard, mbLeft, [], P.X, P.Y);
        tpCancel:
          CancelHold;
      end;
  finally
    FInTouch := False;
  end;
end;

{ ------------------------------------------------------------------ }
{ Game flow                                                           }
{ ------------------------------------------------------------------ }

procedure TForm1.StartNewGame(WordLength: Integer; const ManualWord: string);
var
  Row, Col: Integer;
  C: Char;
begin
  TimerAnim.Enabled := False;
  CloseCard;
  CloseMenu;
  ClosePrompt;
  CancelHold;
  SetLength(FParticles, 0);
  FRaining := False;
  FToiletOn := False;
  FQuakeOn := False;
  FQuakeDX := 0;
  FQuakeDY := 0;
  FShakeRow := -1;
  FShakeOffset := 0;
  FFlashKey := -1;
  FPressedKey := -1;

  if ManualWord <> '' then
  begin
    FTargetWord := UpperCase(ManualWord);
    // A made-up word could never be matched by a dictionary guess, so for
    // those, any guess of the right length is allowed.
    FAnyGuess := not IsValidWord(FTargetWord);
    FCustomGame := True;
  end
  else
  begin
    FTargetWord := PickWord(WordLength);
    FAnyGuess := False;
    FCustomGame := False;
  end;

  // A custom word brings its own length; the level only drives random words.
  FWordLength := Length(FTargetWord);
  if FWordLength = 0 then
  begin
    ShowStatus('Could not find a word of that length!', TONE_WARN);
    FPhase := gpWon;   // nothing playable; do not lock up the UI
    Exit;
  end;
  FMaxGuesses := MaxGuessesFor(FWordLength);

  SetLength(FTiles, FMaxGuesses, FWordLength);
  SetLength(FRowWords, FMaxGuesses);
  for Row := 0 to FMaxGuesses - 1 do
  begin
    FRowWords[Row] := '';
    for Col := 0 to FWordLength - 1 do
    begin
      FTiles[Row, Col].Letter := #0;
      FTiles[Row, Col].State := tsEmpty;
      FTiles[Row, Col].NextState := tsEmpty;
      FTiles[Row, Col].Anim := akNone;
      FTiles[Row, Col].Dur := 0;
      FTiles[Row, Col].T0 := 0;
    end;
  end;

  for C := 'A' to 'Z' do
    FKeyState[C] := tsEmpty;

  FCurrentRow := 0;
  FCurrentCol := 0;
  FCurrentGuess := '';
  FPhase := gpPlaying;
  ResetGameClock;

  if not FCustomGame then
    ShowStatus(Format('%d letters, %d tries. Good luck!', [FWordLength, FMaxGuesses]))
  else if FAnyGuess then
    ShowStatus(Format('Secret word: %d letters, %d tries. Any guess counts!',
      [FWordLength, FMaxGuesses]))
  else
    ShowStatus(Format('Secret word: %d letters, %d tries. Good luck!',
      [FWordLength, FMaxGuesses]));

  PaintBoxBoard.Invalidate;
  PaintBoxKeys.Invalidate;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.AddLetter(Letter: Char);
begin
  if FPhase <> gpPlaying then
    Exit;
  if (FCurrentRow >= FMaxGuesses) or (FCurrentCol >= FWordLength) then
    Exit;

  FTiles[FCurrentRow, FCurrentCol].Letter := Letter;
  FTiles[FCurrentRow, FCurrentCol].State := tsFilled;
  FTiles[FCurrentRow, FCurrentCol].Anim := akPop;
  FTiles[FCurrentRow, FCurrentCol].Dur := POP_MS;
  FTiles[FCurrentRow, FCurrentCol].T0 := GetTickCount64;

  FCurrentGuess := FCurrentGuess + Letter;
  Inc(FCurrentCol);

  FlashKey(kkLetter, Letter);
  StartAnim;
end;

procedure TForm1.RemoveLetter;
begin
  if FPhase <> gpPlaying then
    Exit;
  if FCurrentCol <= 0 then
    Exit;

  Dec(FCurrentCol);
  FTiles[FCurrentRow, FCurrentCol].Letter := #0;
  FTiles[FCurrentRow, FCurrentCol].State := tsEmpty;
  FTiles[FCurrentRow, FCurrentCol].Anim := akNone;
  Delete(FCurrentGuess, Length(FCurrentGuess), 1);

  FlashKey(kkBack, #8);
  PaintBoxBoard.Invalidate;
end;

procedure TForm1.SubmitGuess;
begin
  FlashKey(kkEnter, #13);

  if FPhase <> gpPlaying then
    Exit;

  if Length(FCurrentGuess) <> FWordLength then
  begin
    ShakeRow(FCurrentRow);
    ShowStatus(Format('Needs %d letters', [FWordLength]), TONE_WARN);
    Exit;
  end;

  if (not FAnyGuess) and not IsValidWord(FCurrentGuess) then
  begin
    ShakeRow(FCurrentRow);
    ShowStatus(Format('"%s" is not in the dictionary', [FCurrentGuess]), TONE_WARN);
    Exit;
  end;

  FRowWords[FCurrentRow] := FCurrentGuess;
  EvaluateGuess(FCurrentRow, FCurrentGuess);
  MaybeEasterEgg(FCurrentGuess);
  StartReveal(FCurrentRow);
end;

{ Standard two-pass Wordle scoring: exact matches first so a repeated letter
  is only marked "present" as many times as it actually occurs. }
procedure TForm1.EvaluateGuess(Row: Integer; const Guess: string);
var
  Col: Integer;
  GuessChar: Char;
  Remaining: array['A'..'Z'] of Integer;
  Matched: array of Boolean;
  C: Char;
begin
  SetLength(Matched, FWordLength);
  for C := 'A' to 'Z' do
    Remaining[C] := 0;
  for Col := 1 to FWordLength do
    Inc(Remaining[FTargetWord[Col]]);

  for Col := 0 to FWordLength - 1 do
  begin
    Matched[Col] := Guess[Col + 1] = FTargetWord[Col + 1];
    if Matched[Col] then
    begin
      FTiles[Row, Col].NextState := tsCorrect;
      Dec(Remaining[Guess[Col + 1]]);
    end;
  end;

  for Col := 0 to FWordLength - 1 do
    if not Matched[Col] then
    begin
      GuessChar := Guess[Col + 1];
      if Remaining[GuessChar] > 0 then
      begin
        FTiles[Row, Col].NextState := tsPresent;
        Dec(Remaining[GuessChar]);
      end
      else
        FTiles[Row, Col].NextState := tsAbsent;
    end;
end;

procedure TForm1.StartReveal(Row: Integer);
var
  Col, Stagger: Integer;
  Now0: QWord;
begin
  FPhase := gpRevealing;
  FRevealRow := Row;
  Now0 := GetTickCount64;
  // Squeeze the stagger for long words so a 30-letter row does not take
  // four seconds to turn over.
  Stagger := Min(FLIP_STAGGER_MS, REVEAL_SPAN_MS div Max(1, FWordLength - 1));
  for Col := 0 to FWordLength - 1 do
  begin
    FTiles[Row, Col].Anim := akFlip;
    FTiles[Row, Col].Dur := FLIP_MS;
    FTiles[Row, Col].T0 := Now0 + QWord(Col * Stagger);
  end;
  FRevealDone := Now0 + QWord((FWordLength - 1) * Stagger + FLIP_MS);
  StartAnim;
end;

procedure TForm1.FinishReveal;
var
  Col: Integer;
begin
  for Col := 0 to FWordLength - 1 do
  begin
    FTiles[FRevealRow, Col].State := FTiles[FRevealRow, Col].NextState;
    FTiles[FRevealRow, Col].Anim := akNone;
  end;
  ApplyKeyboardStates(FRevealRow);

  if FCurrentGuess = FTargetWord then
  begin
    WinGame;
    Exit;
  end;

  Inc(FCurrentRow);
  FCurrentCol := 0;
  FCurrentGuess := '';

  if FCurrentRow >= FMaxGuesses then
    LoseGame(lrOutOfTries)
  else
  begin
    FPhase := gpPlaying;
    if not FToiletOn then      // do not trample the potty cheer
      ShowStatus(Format('Try %d of %d', [FCurrentRow + 1, FMaxGuesses]));
  end;
end;

{ A key only ever gets better news, never worse: correct beats present
  beats absent. }
procedure TForm1.ApplyKeyboardStates(Row: Integer);
var
  Col: Integer;
  C: Char;
  New: TTileState;
begin
  for Col := 0 to FWordLength - 1 do
  begin
    C := FTiles[Row, Col].Letter;
    if not (C in ['A'..'Z']) then
      Continue;
    New := FTiles[Row, Col].State;
    if (FKeyState[C] = tsCorrect) then
      Continue;
    if (FKeyState[C] = tsPresent) and (New <> tsCorrect) then
      Continue;
    FKeyState[C] := New;
  end;
  FKeysDirty := True;
  PaintBoxKeys.Invalidate;
end;

procedure TForm1.WinGame;
var
  Col, Stagger: Integer;
  Now0: QWord;
begin
  FPhase := gpWon;
  TimerClock.Enabled := False;
  Inc(FTotalGames);
  Inc(FWins);

  Now0 := GetTickCount64;
  Stagger := Min(BOUNCE_STAGGER_MS, 700 div Max(1, FWordLength - 1));
  for Col := 0 to FWordLength - 1 do
  begin
    FTiles[FCurrentRow, Col].Anim := akBounce;
    FTiles[FCurrentRow, Col].Dur := BOUNCE_MS;
    FTiles[FCurrentRow, Col].T0 := Now0 + QWord(Col * Stagger);
  end;

  SpawnConfetti(FCurrentRow);
  PlayRandom(WIN_SOUNDS);
  ShowStatus(Format('🎉 Solved "%s" in %d!', [FTargetWord, FCurrentRow + 1]), TONE_GOOD);
  PaintBoxBar.Invalidate;
  StartAnim;
end;

procedure TForm1.LoseGame(Reason: TLoseReason);
begin
  FPhase := gpLost;
  FLoseReason := Reason;
  TimerClock.Enabled := False;
  Inc(FTotalGames);
  SpawnPoopStorm;
  PlayRandom(LOSE_SOUNDS);
  case Reason of
    lrGaveUp:
      ShowStatus(Format('You gave up. It was "%s"', [FTargetWord]), TONE_WARN);
    lrTimeUp:
      ShowStatus(Format('⌛ Time''s up! It was "%s"', [FTargetWord]), TONE_WARN);
  else
    ShowStatus(Format('💩 Out of tries! It was "%s"', [FTargetWord]), TONE_WARN);
  end;
  PaintBoxBar.Invalidate;
  StartAnim;
end;

procedure TForm1.ShowStatus(const Msg: string; Tone: Integer);
begin
  LabelStatus.Caption := Msg;
  case Tone of
    TONE_WARN: LabelStatus.Font.Color := CLR_ACCENT;
    TONE_GOOD: LabelStatus.Font.Color := CLR_CORRECT;
  else
    LabelStatus.Font.Color := CLR_TEXT;
  end;
end;

{ ------------------------------------------------------------------ }
{ Hourglass                                                           }
{ ------------------------------------------------------------------ }

procedure TForm1.SetTimerMode(AMode: TTimerMode; ASecs: Integer);
begin
  FTimerMode := AMode;
  FTimerSecs := EnsureRange(ASecs, 10, 3600);
  // Takes effect straight away: the word on the board gets a fresh clock.
  if FPhase in [gpPlaying, gpRevealing] then
    ResetGameClock;

  case AMode of
    tmOff:   ShowStatus('Timer off');
    tmLevel: ShowStatus(Format('Timer: %s for %d letters',
               [FormatSecs(LevelSecs(FWordLength)), FWordLength]));
  else
    ShowStatus(Format('Timer: %s', [FormatSecs(FTimerSecs)]));
  end;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.ResetGameClock;
begin
  TimerClock.Enabled := False;
  FLastTickSec := -1;
  case FTimerMode of
    tmLevel: FTimeTotalMs := Int64(LevelSecs(FWordLength)) * 1000;
    tmFixed: FTimeTotalMs := Int64(FTimerSecs) * 1000;
  else
    FTimeTotalMs := 0;
  end;
  FTimeLeftMs := FTimeTotalMs;
  if FTimeTotalMs > 0 then
  begin
    FClockLast := GetTickCount64;
    TimerClock.Enabled := True;
  end;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.TimerClockTimer(Sender: TObject);
var
  Now0: QWord;
  Delta: Int64;
  Sec: Integer;
begin
  ReapSounds(False);

  Now0 := GetTickCount64;
  Delta := Int64(Now0 - FClockLast);
  FClockLast := Now0;

  if (FTimeTotalMs <= 0) or (FPhase in [gpWon, gpLost]) then
  begin
    // No clock to run - carry on ticking only while players need reaping.
    TimerClock.Enabled := (FSoundProcs <> nil) and (FSoundProcs.Count > 0);
    PaintBoxBar.Invalidate;
    Exit;
  end;

  // Paused while the kids read a definition or type into a prompt.
  if FCardVisible or FPromptOpen then
    Exit;

  Dec(FTimeLeftMs, Delta);
  if FTimeLeftMs <= 0 then
  begin
    FTimeLeftMs := 0;
    // Mid-reveal the flip is allowed to land first - it might be the winner.
    if FPhase = gpPlaying then
      LoseGame(lrTimeUp);
    PaintBoxBar.Invalidate;
    Exit;
  end;

  // Tick through the last ten seconds.
  Sec := Integer((FTimeLeftMs + 999) div 1000);
  if (Sec <= 10) and (Sec <> FLastTickSec) then
  begin
    FLastTickSec := Sec;
    PlayASound('tick.wav');
  end;
  PaintBoxBar.Invalidate;
end;

{ ------------------------------------------------------------------ }
{ Effects                                                             }
{ ------------------------------------------------------------------ }

procedure TForm1.StartAnim;
begin
  if not TimerAnim.Enabled then
  begin
    TimerAnim.Interval := FRAME_MS;
    TimerAnim.Enabled := True;
  end;
end;

function TForm1.AnimationPending: Boolean;
var
  Row, Col: Integer;
begin
  Result := True;
  if (FPhase = gpRevealing) or FRaining or FCardLoading or FToiletOn or FQuakeOn then
    Exit;
  if (FShakeRow >= 0) or (FFlashKey >= 0) or (Length(FParticles) > 0) then
    Exit;
  for Row := 0 to High(FTiles) do
    for Col := 0 to High(FTiles[Row]) do
      if FTiles[Row, Col].Anim <> akNone then
        Exit;
  Result := False;
end;

procedure TForm1.ShakeRow(Row: Integer);
begin
  FShakeRow := Row;
  FShakeT0 := GetTickCount64;
  StartAnim;
end;

procedure TForm1.FlashKey(Kind: TKeyKind; Ch: Char);
var
  Idx: Integer;
begin
  if Length(FKeys) = 0 then
    LayoutKeys;
  Idx := KeyIndexOf(Kind, Ch);
  if Idx < 0 then
    Exit;
  FFlashKey := Idx;
  FFlashT0 := GetTickCount64;
  FKeysDirty := True;
  PaintBoxKeys.Invalidate;
  StartAnim;
end;

{ Returns the new particle's index so callers can turn it into another kind,
  or -1 when the screen is already busy enough. }
function TForm1.AddParticle(AX, AY, AVX, AVY, AGrav, ALife: Double;
  ASize: Integer; const AGlyph: string): Integer;
var
  N: Integer;
begin
  Result := -1;
  N := Length(FParticles);
  if N >= 220 then
    Exit;
  SetLength(FParticles, N + 1);
  FParticles[N] := Default(TParticle);
  FParticles[N].Kind := ptFly;
  FParticles[N].X := AX;
  FParticles[N].Y := AY;
  FParticles[N].VX := AVX;
  FParticles[N].VY := AVY;
  FParticles[N].Grav := AGrav;
  FParticles[N].Life := ALife;
  FParticles[N].Size := ASize;
  FParticles[N].Glyph := AGlyph;
  FParticles[N].Color := CLR_TEXT;
  Result := N;
end;

procedure TForm1.SpawnConfetti(Row: Integer);
var
  I, Col: Integer;
  R: TRect;
begin
  for I := 0 to 43 do
  begin
    Col := Random(FWordLength);
    R := TileRect(Row, Col);
    AddParticle((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
      (Random - 0.5) * 10, -(3 + Random * 9), 0.32,
      1.6 + Random, 14 + Random(16), PARTY_GLYPHS[Random(Length(PARTY_GLYPHS))]);
  end;
end;

procedure TForm1.SpawnPoopStorm;
var
  I: Integer;
begin
  FRainSeed := 0;
  FRaining := True;
  for I := 0 to 17 do
    AddParticle(Random(Max(1, PaintBoxBoard.Width)), -60 - Random(300),
      (Random - 0.5) * 1.6, 1 + Random * 2.5, 0.05,
      99, 22 + Random(22), POOP_GLYPHS[Random(Length(POOP_GLYPHS))]);
end;

{ Keep the rain going while the loss banner is up, without letting the
  particle list grow forever. }
procedure TForm1.TopUpRain;
begin
  Inc(FRainSeed);
  if FRainSeed > 420 then      // roughly seven seconds, then let it settle
  begin
    FRaining := False;
    Exit;
  end;
  if (FRainSeed mod 7 <> 0) or (Length(FParticles) >= 22) then
    Exit;
  AddParticle(Random(Max(1, PaintBoxBoard.Width)), -50,
    (Random - 0.5) * 1.6, 1 + Random * 2.5, 0.05,
    99, 22 + Random(22), POOP_GLYPHS[Random(Length(POOP_GLYPHS))]);
end;

procedure TForm1.SpawnComicWord;
var
  N: Integer;
begin
  N := AddParticle(16 + Random(Max(1, PaintBoxBoard.Width - 170)),
    16 + Random(Max(1, PaintBoxBoard.Height div 2)),
    0, 0, 0, 0.9, 16, COMIC_WORDS[Random(Length(COMIC_WORDS))]);
  if N < 0 then
    Exit;
  FParticles[N].Kind := ptText;
  FParticles[N].Grow := 0.7;
  FParticles[N].Color := COMIC_COLORS[Random(Length(COMIC_COLORS))];
end;

procedure TForm1.UpdateParticles;
var
  I, Kept: Integer;
  P: TParticle;
  Floor: Double;
begin
  Kept := 0;
  for I := 0 to High(FParticles) do
  begin
    P := FParticles[I];
    case P.Kind of
      ptVortex:
        begin
          // Round and round the bowl, tighter every frame, until it goes down.
          P.Ang := P.Ang + P.AngVel;
          P.Rad := P.Rad * 0.962;
          P.X := P.CX + Cos(P.Ang) * P.Rad - P.Size / 2;
          P.Y := P.CY + Sin(P.Ang) * P.Rad * 0.45 - P.Size / 2;
          if P.Rad < 6 then
            P.Life := 0;
        end;
      ptText:
        begin
          P.Size := P.Size + P.Grow;
          P.Y := P.Y - 0.4;
        end;
    else
      P.X := P.X + P.VX;
      P.Y := P.Y + P.VY;
      P.VY := P.VY + P.Grav;
      if P.Kind = ptBounce then
      begin
        Floor := PaintBoxBoard.Height - P.Size - 2;
        if (P.Y > Floor) and (P.VY > 0) then
        begin
          P.Y := Floor;
          P.VY := -P.VY * 0.6;
          P.VX := P.VX * 0.85;
        end;
      end;
    end;

    P.Life := P.Life - FRAME_MS / 1000;
    if (P.Life > 0) and (P.Y < PaintBoxBoard.Height + 80) then
    begin
      FParticles[Kept] := P;
      Inc(Kept);
    end;
  end;
  SetLength(FParticles, Kept);
end;

{ The potty-word show: a fart, the board shakes, poop fountains out of the
  row and bounces around, a giant toilet rises, swallows a whirlpool of poop
  and toilet paper with a flush, and blasts off out of the top. }
procedure TForm1.StartPoopShow(Row: Integer);
var
  I, Col, N: Integer;
  R: TRect;
begin
  PlayRandom(FART_SOUNDS);
  FToiletOn := True;
  FToiletT0 := GetTickCount64;
  FToiletFrame := 0;
  FFlushPlayed := False;
  FQuakeOn := True;
  FQuakeT0 := FToiletT0;

  for I := 0 to 27 do
  begin
    Col := Random(FWordLength);
    R := TileRect(Row, Col);
    N := AddParticle((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
      (Random - 0.5) * 9, -(3 + Random * 8), 0.35,
      2.6 + Random, 18 + Random(18), POOP_GLYPHS[Random(Length(POOP_GLYPHS))]);
    if N >= 0 then
      FParticles[N].Kind := ptBounce;
  end;
  SpawnComicWord;
  ShowStatus(POOP_CHEERS[Random(Length(POOP_CHEERS))], TONE_WARN);
  StartAnim;
end;

procedure TForm1.UpdateToilet(Now0: QWord);
var
  El: Int64;
  X, Y, Size: Double;
  N: Integer;
begin
  El := Int64(Now0 - FToiletT0);
  if El >= TOILET_MS then
  begin
    FToiletOn := False;
    Exit;
  end;
  Inc(FToiletFrame);
  ToiletPose(El, X, Y, Size);

  if (El >= 350) and not FFlushPlayed then
  begin
    FFlushPlayed := True;
    PlayASound('flush.wav');
  end;

  // The whirlpool.
  if (El >= 350) and (El < 1850) and (FToiletFrame mod 3 = 0) then
  begin
    N := AddParticle(X, Y, 0, 0, 0, 3, 16 + Random(16),
      VORTEX_GLYPHS[Random(Length(VORTEX_GLYPHS))]);
    if N >= 0 then
    begin
      FParticles[N].Kind := ptVortex;
      FParticles[N].CX := X;
      FParticles[N].CY := Y - Size * 0.1;
      FParticles[N].Ang := Random * 2 * Pi;
      FParticles[N].Rad := Size * (1.1 + Random * 0.9);
      FParticles[N].AngVel := 0.16 + Random * 0.12;
    end;
  end;

  if (El >= 450) and (El < 1800) and (FToiletFrame mod 20 = 0) then
    SpawnComicWord;

  // Exhaust trail as it launches.
  if (El >= 2000) and (FToiletFrame mod 2 = 0) then
    AddParticle(X - 14 + Random(28), Y + Size * 0.4, (Random - 0.5) * 3,
      2 + Random * 3, 0.1, 0.8, 20 + Random(12), '💨');
end;

procedure TForm1.MaybeEasterEgg(const Guess: string);
var
  I: Integer;
begin
  for I := 0 to High(POOP_WORDS) do
    if Guess = POOP_WORDS[I] then
    begin
      StartPoopShow(FCurrentRow);
      Exit;
    end;
end;

procedure TForm1.TimerAnimTimer(Sender: TObject);
var
  Row, Col: Integer;
  Now0: QWord;
  P: Double;
  El: Int64;
begin
  Now0 := GetTickCount64;

  for Row := 0 to High(FTiles) do
    for Col := 0 to High(FTiles[Row]) do
      if FTiles[Row, Col].Anim <> akNone then
        if Now0 >= FTiles[Row, Col].T0 + QWord(FTiles[Row, Col].Dur) then
        begin
          if FTiles[Row, Col].Anim = akFlip then
            FTiles[Row, Col].State := FTiles[Row, Col].NextState;
          FTiles[Row, Col].Anim := akNone;
        end;

  if FShakeRow >= 0 then
  begin
    if Now0 - FShakeT0 >= SHAKE_MS then
    begin
      FShakeRow := -1;
      FShakeOffset := 0;
    end
    else
    begin
      P := (Now0 - FShakeT0) / SHAKE_MS;
      FShakeOffset := Round(Sin(P * Pi * 5) * FTileSize * 0.16 * (1 - P));
    end;
  end;

  if FQuakeOn then
  begin
    El := Int64(Now0 - FQuakeT0);
    if El >= QUAKE_MS then
    begin
      FQuakeOn := False;
      FQuakeDX := 0;
      FQuakeDY := 0;
    end
    else
    begin
      P := 1 - El / QUAKE_MS;
      FQuakeDX := Round((Random - 0.5) * 16 * P);
      FQuakeDY := Round((Random - 0.5) * 12 * P);
    end;
  end;

  if (FFlashKey >= 0) and (Now0 - FFlashT0 >= KEYFLASH_MS) then
  begin
    FFlashKey := -1;
    FKeysDirty := True;
  end;

  if FToiletOn then
    UpdateToilet(Now0);
  if Length(FParticles) > 0 then
    UpdateParticles;
  if FRaining then
    TopUpRain;

  if (FPhase = gpRevealing) and (Now0 >= FRevealDone) then
    FinishReveal;

  PollLookup;

  PaintBoxBoard.Invalidate;
  if FKeysDirty or (FFlashKey >= 0) then
    PaintBoxKeys.Invalidate;

  TimerAnim.Enabled := AnimationPending;
end;

{ ------------------------------------------------------------------ }
{ Sound                                                               }
{ ------------------------------------------------------------------ }

{ Finished players are freed here. Checking Running polls waitpid, which is
  what stops them lingering as zombie processes - one per key click adds up. }
{ The wavs are compiled into the binary as RCDATA resources and unpacked to
  a temp folder once the window is up, so the game ships as a single file.
  Copies left by an earlier run are reused, which keeps virus scanners from
  re-checking sixteen fresh files on every start. Any failure leaves
  FSoundDir pointing at the folder beside the executable instead. }
{ Size of a file on disk, -1 when there is none. }
function SizeOnDisk(const Path: string): Int64;
var
  SR: TSearchRec;
begin
  Result := -1;
  if FindFirst(Path, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

procedure TForm1.ExtractSounds;
var
  I: Integer;
  R: TResourceStream;
  Dir, Dest, ResName: string;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'wordzel-sounds' + PathDelim;
  try
    if not ForceDirectories(Dir) then
      Exit;
    for I := 0 to High(ALL_SOUNDS) do
    begin
      ResName := 'SND_' + UpperCase(ChangeFileExt(ALL_SOUNDS[I], ''));
      R := TResourceStream.Create(HINSTANCE, ResName, RT_RCDATA);
      try
        Dest := Dir + ALL_SOUNDS[I];
        if SizeOnDisk(Dest) <> R.Size then
          R.SaveToFile(Dest);
      finally
        R.Free;
      end;
    end;
    FSoundDir := Dir;
  except
    // Audio is decoration; never let it break the game.
  end;
end;

procedure TForm1.ExtractSoundsAsync(Data: PtrInt);
begin
  ExtractSounds;
end;

procedure TForm1.ReapSounds(All: Boolean);
{$IFNDEF WINDOWS}
var
  I: Integer;
  P: TProcess;
{$ENDIF}
begin
  {$IFNDEF WINDOWS}
  if FSoundProcs = nil then
    Exit;
  for I := FSoundProcs.Count - 1 downto 0 do
  begin
    P := TProcess(FSoundProcs[I]);
    if All or not P.Running then
    begin
      P.Free;
      FSoundProcs.Delete(I);
    end;
  end;
  {$ENDIF}
end;

procedure TForm1.PlayASound(const SoundFile: string);
var
  SoundPath: string;
  {$IFNDEF WINDOWS}
  P: TProcess;
  {$ENDIF}
begin
  if not FSoundOn then
    Exit;
  SoundPath := FSoundDir + SoundFile;
  if not FileExists(SoundPath) then
    Exit;

  try
    {$IFDEF WINDOWS}
    sndPlaySound(PChar(SoundPath), SND_ASYNC or SND_NODEFAULT);
    {$ELSE}
    if (FPlayer = '') or (FSoundProcs = nil) then
      Exit;
    ReapSounds(False);
    // Fast typing could otherwise stack up a crowd of players.
    if FSoundProcs.Count >= 12 then
      Exit;
    P := TProcess.Create(nil);
    try
      P.Executable := FPlayer;
      if ExtractFileName(FPlayer) = 'aplay' then
        P.Parameters.Add('-q');
      P.Parameters.Add(SoundPath);
      P.Options := [poNoConsole];
      P.Execute;
      FSoundProcs.Add(P);
      // Keep the clock ticking until this player has been reaped.
      TimerClock.Enabled := True;
    except
      P.Free;
      raise;
    end;
    {$ENDIF}
  except
    // Audio is decoration; never let it break the game.
  end;
end;

procedure TForm1.PlayClick(const SoundFile: string);
begin
  if not FClicksOn then
    Exit;
  if GetTickCount64 - FLastClickT < 30 then
    Exit;
  FLastClickT := GetTickCount64;
  PlayASound(SoundFile);
end;

procedure TForm1.PlayRandom(const Files: array of string);
begin
  if Length(Files) > 0 then
    PlayASound(Files[Random(Length(Files))]);
end;

{ ------------------------------------------------------------------ }
{ Info cards                                                          }
{ ------------------------------------------------------------------ }

procedure TForm1.ShowInfoCard(const ATitle: string; const AInfo: TDefResult);
begin
  CloseMenu;
  ClosePrompt;
  CancelLookup;
  FCardWord := ATitle;
  FCardResult := AInfo;
  FCardLoading := False;
  FCardNumbered := False;
  FCardVisible := True;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;
end;

procedure TForm1.ShowHelpCard;
var
  R: TDefResult;
begin
  R := Default(TDefResult);
  AddInfo(R, 'the colours', [
    'GREEN - right letter in the right spot',
    'YELLOW - right letter, wrong spot',
    'GREY - that letter is not in the word']);
  AddInfo(R, 'playing', [
    'Type, or tap the keys on screen. ENTER guesses and ⌫ deletes.',
    'Hold a finger on a row (or right-click it) to look up its word.',
    'The ☰ button has your own secret words, sounds and more.']);
  AddInfo(R, 'shortcuts', [
    'Ctrl+N new game  ·  Ctrl+M your own word',
    'Ctrl+L look up a word  ·  F1 this help']);
  ShowInfoCard('HOW TO PLAY', R);
end;

procedure TForm1.ShowAboutCard;
var
  R: TDefResult;
begin
  R := Default(TDefResult);
  AddInfo(R, 'the name', [
    'Wordle + Hazel = WORDZEL.',
    'Made for Hazel, who discovered that the best thing to guess',
    'in Wordle is FARTS, and the second best is POOPS.']);
  AddInfo(R, 'credits', [
    'Chief game tester and potty word researcher: Hazel',
    'Built with Lazarus and Free Pascal.']);
  ShowInfoCard('ABOUT WORDZEL', R);
end;

procedure TForm1.ShowPoolInfo;
var
  R: TDefResult;
  Pools, Sample: array of string;
  L, I, J: Integer;
  Line: string;
begin
  R := Default(TDefResult);
  SetLength(Pools, MAX_WORD_LEN - MIN_WORD_LEN + 1);
  for L := MIN_WORD_LEN to MAX_WORD_LEN do
    Pools[L - MIN_WORD_LEN] := Format('%d letters: %d eligible (top %d everyday words)',
      [L, PoolSize(L), PoolThreshold(L)]);
  AddInfo(R, 'word pools', Pools);

  SetLength(Sample, 4);
  for I := 0 to 3 do
  begin
    Line := '';
    for J := 1 to 6 do
      Line := Line + PickWord(FDifficulty) + ' ';
    Sample[I] := Trim(Line);
  end;
  AddInfo(R, Format('sample at %d letters', [FDifficulty]), Sample);

  if FDebugMode then
    AddInfo(R, 'current answer', [FTargetWord]);
  ShowInfoCard('WORD POOLS', R);
end;

{ ------------------------------------------------------------------ }
{ Dictionary lookup                                                   }
{ ------------------------------------------------------------------ }

{ Whatever letters are sitting in a row: the submitted guess, or for the row
  still being typed, the letters entered so far. Kids want to check a word
  before spending a turn on it. }
function TForm1.WordInRow(Row: Integer): string;
var
  Col: Integer;
begin
  Result := '';
  if (Row < 0) or (Row >= FMaxGuesses) or (Length(FTiles) = 0) then
    Exit;
  if (Row < Length(FRowWords)) and (FRowWords[Row] <> '') then
    Exit(FRowWords[Row]);

  for Col := 0 to FWordLength - 1 do
  begin
    if FTiles[Row, Col].Letter = #0 then
      Break;
    Result := Result + FTiles[Row, Col].Letter;
  end;
end;

{ Kicks off a background fetch. The card goes up straight away showing a
  spinner, and TimerAnimTimer collects the result when it lands. }
procedure TForm1.StartLookup(const AWord: string);
begin
  if Trim(AWord) = '' then
    Exit;

  CloseMenu;
  ClosePrompt;
  CancelLookup;

  FCardWord := UpperCase(Trim(AWord));
  FCardResult := Default(TDefResult);
  FCardResult.Word := FCardWord;
  FCardLoading := True;
  FCardNumbered := True;
  FCardVisible := True;
  FCardT0 := GetTickCount64;

  FLookupThread := TLookupThread.Create(FCardWord);
  StartAnim;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;
end;

{ The thread never calls into the form, so letting go of it is enough - it
  finishes into its own fields and frees itself. }
procedure TForm1.CancelLookup;
begin
  if not Assigned(FLookupThread) then
    Exit;
  FLookupThread.FreeOnTerminate := True;
  FLookupThread := nil;
end;

procedure TForm1.PollLookup;
var
  R: TDefResult;
begin
  if not Assigned(FLookupThread) then
    Exit;
  if not FLookupThread.TryTakeResult(R) then
    Exit;

  FLookupThread.Free;         // Execute has returned, so this does not block
  FLookupThread := nil;

  FCardResult := R;
  FCardLoading := False;
  PaintBoxBoard.Invalidate;
end;

procedure TForm1.CloseCard;
begin
  CancelLookup;
  if not FCardVisible then
    Exit;
  FCardVisible := False;
  FCardLoading := False;
  PaintBoxBoard.Invalidate;
  PaintBoxBar.Invalidate;     // the hourglass resumes
end;

{ Greedy word wrap measured against the real canvas, so it fits the card
  rather than guessing at a character count. }
procedure TForm1.WrapInto(C: TCanvas; const S: string; MaxWidth: Integer;
  Kind: TCardLineKind; Indent, ContIndent: Integer);
var
  Words: TStringList;
  Line, Candidate: string;
  I: Integer;
  First: Boolean;

  procedure Emit(const T: string);
  var
    N: Integer;
  begin
    if T = '' then
      Exit;
    N := Length(FCardLines);
    SetLength(FCardLines, N + 1);
    FCardLines[N].Kind := Kind;
    FCardLines[N].Text := T;
    if First then
      FCardLines[N].Indent := Indent
    else
      FCardLines[N].Indent := ContIndent;   // hang under the sense number
    First := False;
  end;

begin
  if Trim(S) = '' then
    Exit;

  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.QuoteChar := #0;      // definitions contain quotes; do not parse them
    Words.DelimitedText := Trim(S);

    First := True;
    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      if Words[I] = '' then
        Continue;
      if Line = '' then
        Candidate := Words[I]
      else
        Candidate := Line + ' ' + Words[I];

      if (Line <> '') and (C.TextWidth(Candidate) > MaxWidth) then
      begin
        Emit(Line);
        Line := Words[I];
      end
      else
        Line := Candidate;
    end;
    Emit(Line);
  finally
    Words.Free;
  end;
end;

{ Turns the fetched result into styled lines. Fonts are set before measuring
  so the wrap matches what actually gets drawn. }
procedure TForm1.BuildCardLines(C: TCanvas; TextWidth: Integer);
var
  I, J: Integer;
  Dots: string;

  procedure Plain(const S: string; Kind: TCardLineKind; Indent: Integer = 0);
  var
    N: Integer;
  begin
    N := Length(FCardLines);
    SetLength(FCardLines, N + 1);
    FCardLines[N].Kind := Kind;
    FCardLines[N].Text := S;
    FCardLines[N].Indent := Indent;
  end;

begin
  SetLength(FCardLines, 0);

  if FCardLoading then
  begin
    Dots := StringOfChar('.', 1 + ((GetTickCount64 - FCardT0) div 350) mod 3);
    Plain('Looking up' + Dots, clkPhonetic);
    Exit;
  end;

  if FCardResult.Error <> '' then
  begin
    C.Font.Height := -15;
    C.Font.Style := [];
    WrapInto(C, FCardResult.Error, TextWidth, clkError, 0, 0);
    Exit;
  end;

  if FCardResult.Phonetic <> '' then
    Plain(FCardResult.Phonetic, clkPhonetic);

  for I := 0 to High(FCardResult.Entries) do
  begin
    if I > 0 then
      Plain('', clkGap);
    Plain(FCardResult.Entries[I].PartOfSpeech, clkPart);

    for J := 0 to High(FCardResult.Entries[I].Senses) do
    begin
      C.Font.Height := -15;
      C.Font.Style := [];
      if FCardNumbered then
        WrapInto(C, IntToStr(J + 1) + '.  ' + FCardResult.Entries[I].Senses[J],
                 TextWidth - 16, clkSense, 16, 16 + C.TextWidth('1.  '))
      else
        WrapInto(C, FCardResult.Entries[I].Senses[J],
                 TextWidth - 16, clkSense, 16, 16);
    end;
  end;
end;

procedure TForm1.DrawDefinitionCard(C: TCanvas);
const
  PAD = 20;
  TITLE_H = 40;
var
  CardW, CardX, TextW, LineH, Y, I, ContentH, MaxCardH, CardH: Integer;
  R, Line: TRect;
  Col: TColor;
begin
  CardW := Min(PaintBoxBoard.Width - 32, 470);
  TextW := CardW - 2 * PAD;
  CardX := (PaintBoxBoard.Width - CardW) div 2;

  BuildCardLines(C, TextW);

  // Height: title block, then one line per wrapped line, then the footer.
  LineH := 21;
  ContentH := PAD + TITLE_H + Length(FCardLines) * LineH + 14 + 18 + PAD;
  MaxCardH := PaintBoxBoard.Height - 16;
  CardH := Min(ContentH, MaxCardH);

  R := Rect(CardX, (PaintBoxBoard.Height - CardH) div 2,
            CardX + CardW, (PaintBoxBoard.Height + CardH) div 2);
  RoundBox(C, Rect(R.Left + 4, R.Top + 5, R.Right + 4, R.Bottom + 5), 16, CLR_SHADOW, clNone);
  RoundBox(C, R, 16, CLR_PANEL, CLR_TILE_EDGE_HI);

  // The word itself, in the accent colour.
  Line := Rect(R.Left + PAD, R.Top + PAD, R.Right - PAD, R.Top + PAD + TITLE_H);
  FitFont(C, FCardWord, TextW, 26, 12, True);
  C.Font.Color := CLR_ACCENT;
  C.Brush.Style := bsClear;
  C.TextOut(Line.Left, Line.Top, FCardWord);
  C.Brush.Style := bsSolid;

  Y := R.Top + PAD + TITLE_H;
  for I := 0 to High(FCardLines) do
  begin
    if Y + LineH > R.Bottom - PAD - 18 then
    begin
      // Ran out of card. Say so rather than cutting a sentence dead.
      C.Font.Height := -14;
      C.Font.Style := [];
      C.Font.Color := CLR_DIM;
      C.Brush.Style := bsClear;
      C.TextOut(R.Left + PAD, Y, '...');
      C.Brush.Style := bsSolid;
      Break;
    end;

    case FCardLines[I].Kind of
      clkPhonetic:
        begin
          C.Font.Height := -14;
          C.Font.Style := [fsItalic];
          Col := CLR_DIM;
        end;
      clkPart:
        begin
          C.Font.Height := -15;
          C.Font.Style := [fsBold];
          Col := CLR_PRESENT;        // gold, matches a "present letter" tile
        end;
      clkError:
        begin
          C.Font.Height := -15;
          C.Font.Style := [];
          Col := CLR_ACCENT;
        end;
    else
      C.Font.Height := -15;
      C.Font.Style := [];
      Col := CLR_TEXT;
    end;

    if FCardLines[I].Text <> '' then
    begin
      C.Font.Color := Col;
      C.Brush.Style := bsClear;
      C.TextOut(R.Left + PAD + FCardLines[I].Indent, Y, FCardLines[I].Text);
      C.Brush.Style := bsSolid;
    end;
    Inc(Y, LineH);
  end;

  // Footer
  Line := Rect(R.Left, R.Bottom - PAD - 16, R.Right, R.Bottom - PAD + 2);
  if FCardResult.Source <> '' then
    CenterText(C, Line, FCardResult.Source + '  ·  tap or press ESC to close',
      -11, CLR_DIM, False)
  else
    CenterText(C, Line, 'tap or press ESC to close', -11, CLR_DIM, False);
end;

end.
