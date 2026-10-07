unit unitscores;

{ The family score book.

  Players and finished games live in two append-friendly CSVs under the
  config folder. Everything is behind one lock, so the server threads and
  the game can write at the same time without stepping on each other.

  Scoring rewards showing up as much as being right: every win is worth
  WordLength * (guesses remaining + 1) points, every loss is worth 1, and
  the leaderboard is the plain sum - so eight wins out of fifteen games
  always beats one lucky first-try. }

{$mode objfpc}{$H+}

interface

uses
  Classes;

procedure ScoresInit(const ADir: string);
procedure ScoresDone;

function ScorePoints(Len, MaxG, Used: Integer; Won: Boolean): Integer;

{ Letters and digits only, up to 12 of them. '' means unusable. }
function SanitizeName(const S: string): string;

{ True when the name+PIN pair is good. An unknown name is created on the
  spot (that is how you join); a known name must bring its own PIN. }
function TryLogin(const AName, APin: string; out Err: string): Boolean;

procedure AddScore(const AName: string; Len, MaxG, Used: Integer; Won: Boolean);

{ A JSON array of names, for the login screen's pick list. }
function PlayersJSON: string;

{ Day and month rollups as JSON, each sorted by points. }
function BoardJSON: string;

{ The same rollup as text lines for the in-game card. }
procedure BoardLines(Day, Month: TStrings);

implementation

uses
  SysUtils, DateUtils, syncobjs, md5, fpjson;

type
  TPlayer = record
    Name: string;
    PinHash: string;
  end;

  TGame = record
    When: TDateTime;
    Name: string;
    Len, MaxG, Used, Points: Integer;
    Won: Boolean;
  end;

var
  Lock: TCriticalSection;
  Dir: string = '';
  Players: array of TPlayer;
  Games: array of TGame;

function ScorePoints(Len, MaxG, Used: Integer; Won: Boolean): Integer;
begin
  if Won then
    Result := Len * (MaxG - Used + 1)
  else
    Result := 1;
  if Result < 1 then
    Result := 1;
end;

function SanitizeName(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['A'..'Z', 'a'..'z', '0'..'9'] then
    begin
      Result := Result + S[I];
      if Length(Result) = 12 then
        Break;
    end;
end;

function PinHash(const AName, APin: string): string;
begin
  Result := MD5Print(MD5String('wzpin:' + UpperCase(AName) + ':' + APin));
end;

function FindPlayer(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Players) do
    if SameText(Players[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

{ ------------------------------------------------------------------ }
{ Files                                                               }
{ ------------------------------------------------------------------ }

procedure SavePlayers;
var
  L: TStringList;
  I: Integer;
begin
  if Dir = '' then
    Exit;
  L := TStringList.Create;
  try
    for I := 0 to High(Players) do
      L.Add(Players[I].Name + ',' + Players[I].PinHash);
    L.SaveToFile(Dir + 'players.csv');
  finally
    L.Free;
  end;
end;

procedure AppendGame(const G: TGame);
var
  F: TextFile;
begin
  if Dir = '' then
    Exit;
  AssignFile(F, Dir + 'scores.csv');
  if FileExists(Dir + 'scores.csv') then
    Append(F)
  else
    Rewrite(F);
  try
    WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', G.When), ',', G.Name, ',',
      G.Len, ',', G.MaxG, ',', G.Used, ',', Ord(G.Won), ',', G.Points);
  finally
    CloseFile(F);
  end;
end;

procedure LoadAll;
var
  L, P: TStringList;
  I, N: Integer;
  G: TGame;
begin
  SetLength(Players, 0);
  SetLength(Games, 0);

  L := TStringList.Create;
  P := TStringList.Create;
  try
    P.StrictDelimiter := True;
    P.Delimiter := ',';

    if FileExists(Dir + 'players.csv') then
    begin
      L.LoadFromFile(Dir + 'players.csv');
      for I := 0 to L.Count - 1 do
      begin
        P.DelimitedText := L[I];
        if P.Count >= 2 then
        begin
          N := Length(Players);
          SetLength(Players, N + 1);
          Players[N].Name := P[0];
          Players[N].PinHash := P[1];
        end;
      end;
    end;

    if FileExists(Dir + 'scores.csv') then
    begin
      L.LoadFromFile(Dir + 'scores.csv');
      for I := 0 to L.Count - 1 do
      begin
        P.DelimitedText := L[I];
        if P.Count >= 7 then
        begin
          G.When := ScanDateTime('yyyy-mm-dd hh:nn:ss', P[0]);
          G.Name := P[1];
          G.Len := StrToIntDef(P[2], 0);
          G.MaxG := StrToIntDef(P[3], 0);
          G.Used := StrToIntDef(P[4], 0);
          G.Won := P[5] = '1';
          G.Points := StrToIntDef(P[6], 0);
          N := Length(Games);
          SetLength(Games, N + 1);
          Games[N] := G;
        end;
      end;
    end;
  finally
    P.Free;
    L.Free;
  end;
end;

procedure ScoresInit(const ADir: string);
begin
  Lock.Acquire;
  try
    Dir := IncludeTrailingPathDelimiter(ADir);
    ForceDirectories(Dir);
    try
      LoadAll;
    except
      // a mangled line in a CSV must not kill the game
      SetLength(Players, 0);
      SetLength(Games, 0);
    end;
  finally
    Lock.Release;
  end;
end;

procedure ScoresDone;
begin
  Lock.Acquire;
  try
    Dir := '';
    SetLength(Players, 0);
    SetLength(Games, 0);
  finally
    Lock.Release;
  end;
end;

{ ------------------------------------------------------------------ }
{ Players and games                                                   }
{ ------------------------------------------------------------------ }

function TryLogin(const AName, APin: string; out Err: string): Boolean;
var
  Name: string;
  I, N: Integer;
begin
  Result := False;
  Err := '';
  Name := SanitizeName(AName);
  if Name = '' then
  begin
    Err := 'Names are letters and numbers, up to 12.';
    Exit;
  end;
  if (Length(APin) < 3) or (Length(APin) > 6) then
  begin
    Err := 'PINs are 3 to 6 digits.';
    Exit;
  end;
  for I := 1 to Length(APin) do
    if not (APin[I] in ['0'..'9']) then
    begin
      Err := 'PINs are 3 to 6 digits.';
      Exit;
    end;

  Lock.Acquire;
  try
    I := FindPlayer(Name);
    if I < 0 then
    begin
      N := Length(Players);
      SetLength(Players, N + 1);
      Players[N].Name := Name;
      Players[N].PinHash := PinHash(Name, APin);
      SavePlayers;
      Result := True;
    end
    else if Players[I].PinHash = PinHash(Name, APin) then
      Result := True
    else
      Err := 'Wrong PIN for ' + Players[I].Name + '.';
  finally
    Lock.Release;
  end;
end;

procedure AddScore(const AName: string; Len, MaxG, Used: Integer; Won: Boolean);
var
  G: TGame;
  N: Integer;
begin
  G.When := Now;
  G.Name := SanitizeName(AName);
  if G.Name = '' then
    Exit;
  G.Len := Len;
  G.MaxG := MaxG;
  G.Used := Used;
  G.Won := Won;
  G.Points := ScorePoints(Len, MaxG, Used, Won);

  Lock.Acquire;
  try
    N := Length(Games);
    SetLength(Games, N + 1);
    Games[N] := G;
    try
      AppendGame(G);
    except
      // the in-memory board still works
    end;
  finally
    Lock.Release;
  end;
end;

function PlayersJSON: string;
var
  A: TJSONArray;
  I: Integer;
begin
  Lock.Acquire;
  try
    A := TJSONArray.Create;
    try
      for I := 0 to High(Players) do
        A.Add(Players[I].Name);
      Result := A.AsJSON;
    finally
      A.Free;
    end;
  finally
    Lock.Release;
  end;
end;

{ ------------------------------------------------------------------ }
{ The leaderboard                                                     }
{ ------------------------------------------------------------------ }

type
  TRow = record
    Name: string;
    Points, Played, Won: Integer;
  end;
  TRows = array of TRow;

{ Caller holds the lock. }
function Rollup(FromDay: TDateTime): TRows;
var
  I, J, N: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to High(Games) do
  begin
    if Games[I].When < FromDay then
      Continue;
    N := -1;
    for J := 0 to High(Result) do
      if SameText(Result[J].Name, Games[I].Name) then
      begin
        N := J;
        Break;
      end;
    if N < 0 then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Name := Games[I].Name;
      Result[N].Points := 0;
      Result[N].Played := 0;
      Result[N].Won := 0;
    end;
    Inc(Result[N].Points, Games[I].Points);
    Inc(Result[N].Played);
    if Games[I].Won then
      Inc(Result[N].Won);
  end;
end;

{ Largest first; family-sized, so a bubble will do. }
procedure SortRows(var R: TRows);
var
  I, J: Integer;
  T: TRow;
begin
  for I := 0 to High(R) do
    for J := 0 to High(R) - 1 - I do
      if R[J].Points < R[J + 1].Points then
      begin
        T := R[J];
        R[J] := R[J + 1];
        R[J + 1] := T;
      end;
end;

function RowsJSON(const R: TRows): TJSONArray;
var
  I: Integer;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(R) do
  begin
    O := TJSONObject.Create;
    O.Add('name', R[I].Name);
    O.Add('points', R[I].Points);
    O.Add('played', R[I].Played);
    O.Add('won', R[I].Won);
    Result.Add(O);
  end;
end;

function BoardJSON: string;
var
  Root: TJSONObject;
  D, M: TRows;
begin
  Lock.Acquire;
  try
    D := Rollup(Date);
    SortRows(D);
    M := Rollup(EncodeDate(YearOf(Date), MonthOf(Date), 1));
    SortRows(M);
    Root := TJSONObject.Create;
    try
      Root.Add('day', RowsJSON(D));
      Root.Add('month', RowsJSON(M));
      Result := Root.AsJSON;
    finally
      Root.Free;
    end;
  finally
    Lock.Release;
  end;
end;

procedure RowsToLines(const R: TRows; L: TStrings);
var
  I: Integer;
begin
  if Length(R) = 0 then
  begin
    L.Add('Nobody yet - go play!');
    Exit;
  end;
  for I := 0 to High(R) do
    L.Add(Format('%d. %s - %d pts (%d won of %d)',
      [I + 1, R[I].Name, R[I].Points, R[I].Won, R[I].Played]));
end;

procedure BoardLines(Day, Month: TStrings);
var
  D, M: TRows;
begin
  Lock.Acquire;
  try
    D := Rollup(Date);
    SortRows(D);
    M := Rollup(EncodeDate(YearOf(Date), MonthOf(Date), 1));
    SortRows(M);
    RowsToLines(D, Day);
    RowsToLines(M, Month);
  finally
    Lock.Release;
  end;
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  Lock.Free;

end.
