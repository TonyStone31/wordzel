program wordtest;

{ Console harness for unitwordpicker: prints the eligible pool size and a
  random sample per difficulty so word quality can be eyeballed without
  launching the GUI.

  Build (adjust the fpc path to taste):
    fpc -Fu. -FU/tmp/wt tools/wordtest.pas

  Args: no args        -> summary + sample per length
        dump <length>   -> the entire eligible pool for that length }

{$mode objfpc}{$H+}

uses
  SysUtils, unitwordpicker;

procedure Sample;
var
  L, I: Integer;
  S: string;
begin
  for L := MIN_WORD_LEN to MAX_WORD_LEN do
  begin
    Write(Format('%d letters | pool %5d | threshold %3d | ',
      [L, PoolSize(L), PoolThreshold(L)]));
    S := '';
    for I := 1 to 16 do
      S := S + PickWord(L) + ' ';
    WriteLn(S);
  end;
end;

procedure Dump(L: Integer);
var
  I: Integer;
begin
  for I := 0 to PoolSize(L) - 1 do
    WriteLn(PoolItem(L, I));
end;

const
  { A plain "for W in ['HOUSE', 'AARDVARK', ...]" makes the compiler size the
    element type from the first literal and silently truncates the rest. }
  CHECKS: array[0..5] of string =
    ('HOUSE', 'ZZZZZ', 'AARDVARK', 'house', 'A', 'QI');
var
  W: string;
  I: Integer;
begin
  Randomize;
  if (ParamCount = 2) and (ParamStr(1) = 'dump') then
  begin
    Dump(StrToInt(ParamStr(2)));
    Exit;
  end;

  Sample;
  WriteLn;
  WriteLn('IsValidWord checks:');
  for I := Low(CHECKS) to High(CHECKS) do
    WriteLn('  ', CHECKS[I]:10, ' -> ', IsValidWord(CHECKS[I]));
end.
