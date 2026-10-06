unit unitwordpicker;

{ Word validation and secret-word selection.

  Split out of the form so the picking logic can be exercised from a plain
  console test harness (see tools/wordtest.pas).

  Two lists, two jobs:

  - WORD_LIST (unitwordlist) is every legal guess - the whole dictionary,
    sorted, so validation is a binary search.

  - COMMON_WORDS (unitcommonwords) is the secret-word pool: the subset of
    WORD_LIST that also appears in a word frequency list built from movie
    and TV subtitles, ordered most common first. Secrets are drawn from the
    common end of it, so the answer is always a word people actually use -
    the dictionary alone is full of real-but-obscure entries (DHOTI, WROTH,
    ABACI, HELOT) that nobody would ever guess. }

{$mode objfpc}{$H+}

interface

const
  MIN_WORD_LEN = 3;
  MAX_WORD_LEN = 9;

{ True for any dictionary word - all words stay legal as guesses. }
function IsValidWord(const AWord: string): Boolean;

{ A random word of ALen letters drawn from the eligible pool.
  Always returns a word of exactly ALen letters (or '' if ALen is absurd). }
function PickWord(ALen: Integer): string;

{ Pool introspection, used by the in-game developer panel. Every pool word
  sits within the PoolThreshold most common words of the language. }
function PoolSize(ALen: Integer): Integer;
function PoolThreshold(ALen: Integer): Integer;
function PoolItem(ALen, AIndex: Integer): string;

implementation

uses
  SysUtils, Math, unitwordlist, unitcommonwords;

const
  { Fraction of each length's common words rejected as too rare. The list is
    ordered by how often people use a word, so this cuts the obscure tail.
    Because it is a fraction rather than an absolute rank, it means the same
    thing for 3-letter and 9-letter words. }
  REJECT_FRACTION = 0.50;

type
  TWordArray = array of string;

var
  Pools: array[MIN_WORD_LEN..MAX_WORD_LEN] of TWordArray;
  Thresholds: array[MIN_WORD_LEN..MAX_WORD_LEN] of Integer;
  PoolReady: array[MIN_WORD_LEN..MAX_WORD_LEN] of Boolean;

{ Index of the first entry >= S. }
function LowerBound(const S: string): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := Low(WORD_LIST);
  Hi := High(WORD_LIST) + 1;
  while Lo < Hi do
  begin
    Mid := Lo + (Hi - Lo) div 2;
    if WORD_LIST[Mid] < S then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

const
  { Words the house has decided are words, whatever the dictionary says.
    Legal as guesses; never picked as the secret word. }
  EXTRA_WORDS: array[0..10] of string = (
    'SHART', 'SHARTS', 'SHARTED', 'SHARTING',
    'DOODOO', 'DOODIE', 'DOOKIE', 'CACA', 'PEEPEE', 'WEEWEE', 'TUSHY');

function IsValidWord(const AWord: string): Boolean;
var
  I: Integer;
  U: string;
begin
  U := UpperCase(Trim(AWord));
  if U = '' then
    Exit(False);
  for I := 0 to High(EXTRA_WORDS) do
    if U = EXTRA_WORDS[I] then
      Exit(True);
  I := LowerBound(U);
  Result := (I <= High(WORD_LIST)) and (WORD_LIST[I] = U);
end;

procedure BuildPool(ALen: Integer);
var
  Cands: TWordArray;
  Ranks: array of Integer;
  I, Count, Keep: Integer;
begin
  SetLength(Cands, Length(COMMON_WORDS));
  SetLength(Ranks, Length(COMMON_WORDS));
  Count := 0;

  { COMMON_WORDS is ordered most common first, so the candidates come out
    already ranked. }
  for I := Low(COMMON_WORDS) to High(COMMON_WORDS) do
    if Length(COMMON_WORDS[I]) = ALen then
    begin
      Cands[Count] := COMMON_WORDS[I];
      Ranks[Count] := I + 1;
      Inc(Count);
    end;

  if Count = 0 then
  begin
    Pools[ALen] := nil;
    Thresholds[ALen] := 0;
    PoolReady[ALen] := True;
    Exit;
  end;

  { Drop the rarest tail. }
  Keep := Max(1, Count - Trunc(Count * REJECT_FRACTION));

  SetLength(Pools[ALen], Keep);
  for I := 0 to Keep - 1 do
    Pools[ALen][I] := Cands[I];

  Thresholds[ALen] := Ranks[Keep - 1];
  PoolReady[ALen] := True;
end;

procedure EnsurePool(ALen: Integer);
begin
  if not PoolReady[ALen] then
    BuildPool(ALen);
end;

function ClampLen(ALen: Integer): Integer; inline;
begin
  Result := Max(MIN_WORD_LEN, Min(MAX_WORD_LEN, ALen));
end;

function PickWord(ALen: Integer): string;
begin
  ALen := ClampLen(ALen);
  EnsurePool(ALen);
  if Length(Pools[ALen]) = 0 then
    Exit('');
  Result := Pools[ALen][Random(Length(Pools[ALen]))];
end;

function PoolSize(ALen: Integer): Integer;
begin
  ALen := ClampLen(ALen);
  EnsurePool(ALen);
  Result := Length(Pools[ALen]);
end;

function PoolThreshold(ALen: Integer): Integer;
begin
  ALen := ClampLen(ALen);
  EnsurePool(ALen);
  Result := Thresholds[ALen];
end;

function PoolItem(ALen, AIndex: Integer): string;
begin
  ALen := ClampLen(ALen);
  EnsurePool(ALen);
  if (AIndex < 0) or (AIndex >= Length(Pools[ALen])) then
    Exit('');
  Result := Pools[ALen][AIndex];
end;

end.
