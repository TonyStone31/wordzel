program wordzel_server;

{ The family game server with no window: the same server the game runs from
  its menu, for a machine that stays on. It reads the [family] passphrase and
  port from wordzel.ini, the same keys the game writes, keeps the score book
  in family/ beside it, and serves until it is stopped.

    wordzel-server                  the game's own config folder
    wordzel-server --config=DIR     wordzel.ini and family/ in DIR

  Scores are written as each game ends, so stopping it any way is safe. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, BaseUnix,
  {$ENDIF}
  SysUtils, CustApp, IniFiles, unitscores, unitserver;

{ The game's resource file: the web pages and sounds are listed once, in
  wordzel.lpi, and the game's build keeps this file current. }
{$R wordzel.res}

type
  TServerApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  end;

var
  Stopping: Boolean = False;

{$IFDEF UNIX}
procedure HandleStop(Sig: cint); cdecl;
begin
  Stopping := True;
end;
{$ENDIF}

{ The game's name, so GetAppConfigDir finds the game's folder. }
function WordzelName: string;
begin
  Result := 'wordzel';
end;

procedure TServerApp.DoRun;
var
  Dir, Pass: string;
  Port: Integer;
  Ini: TIniFile;
  Server: TWordzelServer;
begin
  Terminate;
  Dir := GetOptionValue('c', 'config');
  if Dir = '' then
    Dir := GetAppConfigDir(False);
  Dir := IncludeTrailingPathDelimiter(ExpandFileName(Dir));

  Ini := TIniFile.Create(Dir + 'wordzel.ini');
  try
    Pass := Ini.ReadString('family', 'passphrase', '');
    Port := Ini.ReadInteger('family', 'port', 8080);
  finally
    Ini.Free;
  end;
  if Pass = '' then
  begin
    WriteLn(StdErr, 'No family passphrase: put passphrase= under [family] in ',
      Dir, 'wordzel.ini');
    ExitCode := 1;
    Exit;
  end;

  ScoresInit(Dir + 'family');
  Server := TWordzelServer.Create(Port, Pass);
  try
    Sleep(400);   // binding fails within moments, see TWordzelServer.Error
    if Server.Error <> '' then
    begin
      WriteLn(StdErr, Format('Port %d did not work: %s', [Port, Server.Error]));
      ExitCode := 1;
      Exit;
    end;
    WriteLn(Format('Wordzel family server on port %d, scores in %sfamily',
      [Port, Dir]));
    Flush(Output);   // a service's log is a pipe, not a terminal
    {$IFDEF UNIX}
    fpSignal(SIGTERM, @HandleStop);
    fpSignal(SIGINT, @HandleStop);
    {$ENDIF}
    while not Stopping do
      Sleep(250);
  finally
    Server.Free;
    ScoresDone;
  end;
end;

var
  App: TServerApp;
begin
  OnGetApplicationName := @WordzelName;
  App := TServerApp.Create(nil);
  try
    App.Run;
  finally
    App.Free;
  end;
end.
