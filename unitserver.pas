unit unitserver;

{ The family game server: an HTTP server on its own thread, serving the web
  version of the game out of the same resources everything else is compiled
  into, plus a small JSON API over unitscores.

  One shared family passphrase is the door: POST /api/join trades it for a
  cookie, and everything but the login page's own files wants that cookie.
  Players then pick a name and a low-security PIN - see unitscores.

  There is no TLS in this process. Keep it on the LAN, or put a proxy that
  terminates TLS in front of it. }

{$mode objfpc}{$H+}

interface

uses
  Classes;

type
  TWordzelServer = class
  private
    FThread: TThread;
    FPort: Word;
    function GetError: string;
  public
    constructor Create(APort: Word; const APassphrase: string);
    destructor Destroy; override;
    property Port: Word read FPort;
    { '' while serving; the reason otherwise (port taken, no permission).
      Binding fails within moments, so check shortly after Create. }
    property Error: string read GetError;
  end;

implementation

uses
  SysUtils, ssockets, fphttpserver, httpdefs, md5, unitscores;

const
  RT_RCDATA = PChar(10);

type
  TServerThread = class(TThread)
  private
    FServer: TFPHTTPServer;
    FFamToken: string;
    FError: string;
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; const APassphrase: string);
    destructor Destroy; override;
  end;

{ ------------------------------------------------------------------ }

constructor TServerThread.Create(APort: Word; const APassphrase: string);
begin
  FFamToken := MD5Print(MD5String('wordzel-family:' + APassphrase));
  FServer := TFPHTTPServer.Create(nil);
  FServer.Port := APort;
  FServer.Threaded := True;
  FServer.OnRequest := @HandleRequest;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TServerThread.Destroy;
begin
  FServer.Free;
  inherited Destroy;
end;

procedure TServerThread.Execute;
begin
  try
    FServer.Active := True;   // blocks until Active := False
  except
    on E: Exception do
      FError := E.Message;    // port taken, permissions - the GUI reports it
  end;
end;

{ ------------------------------------------------------------------ }

procedure SendJSON(var AResponse: TFPHTTPConnectionResponse; const S: string;
  ACode: Integer = 200);
begin
  AResponse.Code := ACode;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.Content := S;
end;

procedure SendError(var AResponse: TFPHTTPConnectionResponse; ACode: Integer;
  const Msg: string);
begin
  SendJSON(AResponse, '{"ok":false,"error":"' +
    StringReplace(Msg, '"', '''', [rfReplaceAll]) + '"}', ACode);
end;

{ True when the named RCDATA resource went out. }
function SendResource(var AResponse: TFPHTTPConnectionResponse;
  const ResName, AMime: string): Boolean;
var
  R: TResourceStream;
begin
  Result := False;
  try
    R := TResourceStream.Create(HINSTANCE, ResName, RT_RCDATA);
  except
    Exit;
  end;
  AResponse.ContentType := AMime;
  AResponse.SetCustomHeader('Cache-Control', 'no-cache');
  AResponse.ContentStream := R;
  AResponse.FreeContentStream := True;
  Result := True;
end;

procedure SetCookie(var AResponse: TFPHTTPConnectionResponse;
  const AName, AValue: string);
begin
  AResponse.SetCustomHeader('Set-Cookie',
    AName + '=' + AValue + '; Path=/; Max-Age=31536000; SameSite=Lax');
end;

procedure TServerThread.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Path, Base, Who, Err: string;
  FamOK: Boolean;
  Len, MaxG, Used: Integer;
begin
  Path := ARequest.PathInfo;
  if (Path = '') or (Path = '/') then
    Path := '/index.html';

  FamOK := ARequest.CookieFields.Values['fam'] = FFamToken;
  Who := SanitizeName(ARequest.CookieFields.Values['who']);

  { The shell of the page is open; everything that makes it a game is not. }
  if Path = '/index.html' then
  begin
    if not SendResource(AResponse, 'WWW_INDEX', 'text/html; charset=utf-8') then
      SendError(AResponse, 500, 'page missing');
    Exit;
  end;
  if Path = '/style.css' then
  begin
    SendResource(AResponse, 'WWW_STYLE', 'text/css; charset=utf-8');
    Exit;
  end;
  if Path = '/app.js' then
  begin
    SendResource(AResponse, 'WWW_APP', 'application/javascript; charset=utf-8');
    Exit;
  end;

  if Path = '/api/join' then
  begin
    if ARequest.ContentFields.Values['pass'] <> '' then
    begin
      if MD5Print(MD5String('wordzel-family:' +
           ARequest.ContentFields.Values['pass'])) = FFamToken then
      begin
        SetCookie(AResponse, 'fam', FFamToken);
        SendJSON(AResponse, '{"ok":true}');
      end
      else
        SendError(AResponse, 403, 'That is not the family passphrase.');
    end
    else
      SendError(AResponse, 400, 'No passphrase given.');
    Exit;
  end;

  { The word list is a script, so its "not yet" answer has to be one too,
    or the browser chokes on JSON where JavaScript was promised. }
  if Path = '/words.js' then
  begin
    if FamOK then
      SendResource(AResponse, 'WWW_WORDS', 'application/javascript; charset=utf-8')
    else
    begin
      AResponse.Code := 401;
      AResponse.ContentType := 'application/javascript; charset=utf-8';
      AResponse.Content := '// join first';
    end;
    Exit;
  end;

  if not FamOK then
  begin
    SendError(AResponse, 401, 'join first');
    Exit;
  end;

  { ---- family-only from here down ---- }

  if Copy(Path, 1, 8) = '/sounds/' then
  begin
    Base := UpperCase(ChangeFileExt(ExtractFileName(Path), ''));
    if (Base <> '') and SendResource(AResponse, 'SND_' + Base, 'audio/wav') then
      Exit;
    SendError(AResponse, 404, 'no such sound');
    Exit;
  end;

  if Path = '/api/players' then
  begin
    SendJSON(AResponse, '{"ok":true,"players":' + PlayersJSON + '}');
    Exit;
  end;

  if Path = '/api/login' then
  begin
    if TryLogin(ARequest.ContentFields.Values['name'],
                ARequest.ContentFields.Values['pin'], Err) then
    begin
      Who := SanitizeName(ARequest.ContentFields.Values['name']);
      SetCookie(AResponse, 'who', Who);
      SendJSON(AResponse, '{"ok":true,"name":"' + Who + '"}');
    end
    else
      SendError(AResponse, 403, Err);
    Exit;
  end;

  if Path = '/api/board' then
  begin
    SendJSON(AResponse, '{"ok":true,"board":' + BoardJSON + '}');
    Exit;
  end;

  if Path = '/api/score' then
  begin
    if Who = '' then
    begin
      SendError(AResponse, 401, 'pick a name first');
      Exit;
    end;
    Len := StrToIntDef(ARequest.ContentFields.Values['len'], 0);
    MaxG := StrToIntDef(ARequest.ContentFields.Values['maxg'], 0);
    Used := StrToIntDef(ARequest.ContentFields.Values['used'], 0);
    if (Len < 3) or (Len > 9) or (MaxG < 4) or (MaxG > 10) or
       (Used < 1) or (Used > MaxG) then
    begin
      SendError(AResponse, 400, 'that is not a real game');
      Exit;
    end;
    AddScore(Who, Len, MaxG, Used, ARequest.ContentFields.Values['won'] = '1');
    SendJSON(AResponse, '{"ok":true,"board":' + BoardJSON + '}');
    Exit;
  end;

  SendError(AResponse, 404, 'nothing here');
end;

{ ------------------------------------------------------------------ }

function TWordzelServer.GetError: string;
begin
  Result := TServerThread(FThread).FError;
end;

constructor TWordzelServer.Create(APort: Word; const APassphrase: string);
begin
  FPort := APort;
  FThread := TServerThread.Create(APort, APassphrase);
end;

destructor TWordzelServer.Destroy;
var
  Poke: TInetSocket;
begin
  if FThread <> nil then
  begin
    TServerThread(FThread).FServer.Active := False;
    { The server thread sits blocked in accept() and only rechecks Active
      after a connection comes in - so hand it one, or closing the window
      waits for the next visitor. }
    try
      Poke := TInetSocket.Create('127.0.0.1', FPort);
      Poke.Free;
    except
      // never bound (port was taken) - nothing to wake
    end;
    FThread.WaitFor;
    FThread.Free;
  end;
  inherited Destroy;
end;

end.
