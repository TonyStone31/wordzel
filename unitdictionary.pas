unit unitdictionary;

{ Word definitions, fetched off the UI thread.

  Nothing in here touches the LCL, so TLookupThread can run the whole fetch
  and parse in the background. The thread never calls back into the form
  either - it drops the finished result in a locked field and the form's
  existing animation timer picks it up. That way a form closing mid-request
  cannot be called into by a thread that outlives it.

  Two sources are tried in order. Wiktionary first: api.dictionaryapi.dev is
  a free service that goes dark for long stretches, and when it does its
  socket hangs until the timeout rather than refusing the connection. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, SyncObjs;

type
  { One part of speech and the senses listed under it. }
  TDefEntry = record
    PartOfSpeech: string;
    Senses: array of string;
  end;

  TDefResult = record
    Word: string;
    Phonetic: string;
    Entries: array of TDefEntry;
    Error: string;       // '' when the lookup succeeded
    Source: string;      // which service answered, for the card footer
  end;

  { Blocking. Safe to call from a worker thread. }
  function FetchDefinition(const AWord: string): TDefResult;

type
  TLookupThread = class(TThread)
  private
    FWord: string;
    FResult: TDefResult;
    FDone: Boolean;
    FLock: TCriticalSection;
  protected
    procedure Execute; override;
  public
    constructor Create(const AWord: string);
    destructor Destroy; override;
    { True once, when the result is ready; hands it over. }
    function TryTakeResult(out AResult: TDefResult): Boolean;
    property LookupWord: string read FWord;
  end;

implementation

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ELSE}
  fphttpclient, opensslsockets,
  {$ENDIF}
  fpjson, jsonparser;

const
  MAX_PARTS = 3;         // parts of speech shown
  MAX_SENSES = 3;        // senses shown per part of speech
  CONNECT_TIMEOUT = 4000;
  IO_TIMEOUT = 6000;

{ Drops a whole element including its content, for <style>/<script> whose
  bodies are not text we want. Tag stripping alone leaves the CSS behind. }
function RemoveElement(const S, Tag: string): string;
var
  OpenAt, CloseAt, Scan: Integer;
  Lower: string;
begin
  Result := S;
  repeat
    Lower := LowerCase(Result);
    OpenAt := Pos('<' + Tag, Lower);
    if OpenAt = 0 then
      Break;
    CloseAt := PosEx('</' + Tag, Lower, OpenAt);
    if CloseAt = 0 then
    begin
      // Unclosed - drop the rest rather than leaking it.
      Result := Copy(Result, 1, OpenAt - 1);
      Break;
    end;
    Scan := PosEx('>', Lower, CloseAt);
    if Scan = 0 then
      Scan := Length(Result);
    Delete(Result, OpenAt, Scan - OpenAt + 1);
  until False;
end;

{ Wiktionary returns definitions with Parsoid markup embedded in them. }
function StripHtml(const S: string): string;
var
  I, Depth: Integer;
  Src: string;
begin
  Src := RemoveElement(S, 'style');
  Src := RemoveElement(Src, 'script');

  Result := '';
  Depth := 0;
  for I := 1 to Length(Src) do
  begin
    if Src[I] = '<' then
      Inc(Depth)
    else if Src[I] = '>' then
    begin
      if Depth > 0 then
        Dec(Depth);
    end
    else if Depth = 0 then
      Result := Result + Src[I];
  end;

  Result := StringReplace(Result, '&nbsp;', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&#39;', #39, [rfReplaceAll]);
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);

  { Collapse the whitespace the markup leaves behind. }
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  Result := Trim(Result);
end;

const
  USER_AGENT = 'Wordzel word game';

{$IFDEF WINDOWS}

{ Windows ships no OpenSSL, so the fetch goes through WinHTTP instead: the
  system's certificate store, proxy settings and security patches, with
  nothing to ship beside the executable. }

const
  WINHTTP = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY   = 0;
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;   // Windows 8.1 and later
  WINHTTP_FLAG_SECURE                 = $00800000;
  WINHTTP_QUERY_STATUS_CODE           = 19;
  WINHTTP_QUERY_FLAG_NUMBER           = $20000000;

type
  HINTERNET = Pointer;

function WinHttpOpen(pszAgentW: PWideChar; dwAccessType: DWORD;
  pszProxyW, pszProxyBypassW: PWideChar; dwFlags: DWORD): HINTERNET; stdcall;
  external WINHTTP name 'WinHttpOpen';
function WinHttpConnect(hSession: HINTERNET; pswzServerName: PWideChar;
  nServerPort: Word; dwReserved: DWORD): HINTERNET; stdcall;
  external WINHTTP name 'WinHttpConnect';
function WinHttpOpenRequest(hConnect: HINTERNET;
  pwszVerb, pwszObjectName, pwszVersion, pwszReferrer: PWideChar;
  ppwszAcceptTypes: Pointer; dwFlags: DWORD): HINTERNET; stdcall;
  external WINHTTP name 'WinHttpOpenRequest';
function WinHttpSendRequest(hRequest: HINTERNET; pwszHeaders: PWideChar;
  dwHeadersLength: DWORD; lpOptional: Pointer;
  dwOptionalLength, dwTotalLength: DWORD; dwContext: PtrUInt): BOOL; stdcall;
  external WINHTTP name 'WinHttpSendRequest';
function WinHttpReceiveResponse(hRequest: HINTERNET;
  lpReserved: Pointer): BOOL; stdcall;
  external WINHTTP name 'WinHttpReceiveResponse';
function WinHttpQueryHeaders(hRequest: HINTERNET; dwInfoLevel: DWORD;
  pwszName: PWideChar; lpBuffer: Pointer; lpdwBufferLength: PDWORD;
  lpdwIndex: PDWORD): BOOL; stdcall;
  external WINHTTP name 'WinHttpQueryHeaders';
function WinHttpQueryDataAvailable(hRequest: HINTERNET;
  lpdwNumberOfBytesAvailable: PDWORD): BOOL; stdcall;
  external WINHTTP name 'WinHttpQueryDataAvailable';
function WinHttpReadData(hRequest: HINTERNET; lpBuffer: Pointer;
  dwNumberOfBytesToRead: DWORD; lpdwNumberOfBytesRead: PDWORD): BOOL; stdcall;
  external WINHTTP name 'WinHttpReadData';
function WinHttpSetTimeouts(hInternet: HINTERNET;
  nResolveTimeout, nConnectTimeout, nSendTimeout,
  nReceiveTimeout: Integer): BOOL; stdcall;
  external WINHTTP name 'WinHttpSetTimeouts';
function WinHttpCloseHandle(hInternet: HINTERNET): BOOL; stdcall;
  external WINHTTP name 'WinHttpCloseHandle';

{ True only if the server answered 2xx with a body, matching the OpenSSL
  side: anything else - DNS, TLS, 404, timeout - is just "no answer". }
function HttpGet(const URL: string; out Body: string): Boolean;
var
  Host, Path: string;
  Sess, Conn, Req: HINTERNET;
  Avail, Got, Code, CodeLen: DWORD;
  Status, I: Integer;
  Buf: array[0..16383] of Byte;
begin
  Result := False;
  Body := '';

  { The two dictionary URLs are always https://host/path. }
  if CompareText(Copy(URL, 1, 8), 'https://') <> 0 then
    Exit;
  Host := Copy(URL, 9, Length(URL));
  I := Pos('/', Host);
  if I = 0 then
    Exit;
  Path := Copy(Host, I, Length(Host));
  Host := Copy(Host, 1, I - 1);

  { Automatic proxy detection; before Windows 8.1 this fails and the
    machine-wide setting is used. }
  Sess := WinHttpOpen(PWideChar(UnicodeString(USER_AGENT)),
    WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, nil, nil, 0);
  if Sess = nil then
    Sess := WinHttpOpen(PWideChar(UnicodeString(USER_AGENT)),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if Sess = nil then
    Exit;

  Conn := nil;
  Req := nil;
  try
    WinHttpSetTimeouts(Sess, CONNECT_TIMEOUT, CONNECT_TIMEOUT,
      IO_TIMEOUT, IO_TIMEOUT);

    Conn := WinHttpConnect(Sess, PWideChar(UnicodeString(Host)), 443, 0);
    if Conn = nil then
      Exit;

    Req := WinHttpOpenRequest(Conn, 'GET', PWideChar(UnicodeString(Path)),
      nil, nil, nil, WINHTTP_FLAG_SECURE);
    if Req = nil then
      Exit;

    if not WinHttpSendRequest(Req, nil, 0, nil, 0, 0, 0) then
      Exit;
    if not WinHttpReceiveResponse(Req, nil) then
      Exit;

    Code := 0;
    CodeLen := SizeOf(Code);
    Status := 0;
    if WinHttpQueryHeaders(Req,
         WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
         nil, @Code, @CodeLen, nil) then
      Status := Integer(Code);
    if (Status < 200) or (Status >= 300) then
      Exit;

    repeat
      Avail := 0;
      if not WinHttpQueryDataAvailable(Req, @Avail) then
        Exit;
      if Avail = 0 then
        Break;
      if Avail > DWORD(SizeOf(Buf)) then
        Avail := SizeOf(Buf);
      Got := 0;
      if not WinHttpReadData(Req, @Buf[0], Avail, @Got) then
        Exit;
      if Got = 0 then
        Break;
      I := Length(Body);
      SetLength(Body, I + Integer(Got));
      Move(Buf[0], Body[I + 1], Got);
    until False;

    Result := Trim(Body) <> '';
  finally
    if Req <> nil then WinHttpCloseHandle(Req);
    if Conn <> nil then WinHttpCloseHandle(Conn);
    WinHttpCloseHandle(Sess);
    if not Result then
      Body := '';
  end;
end;

{$ELSE}

{ True only if the server actually answered with a body. On a timeout
  TFPHTTPClient returns nothing rather than raising, so without this check an
  unreachable service looks exactly like an unknown word. }
function HttpGet(const URL: string; out Body: string): Boolean;
var
  Client: TFPHTTPClient;
begin
  Body := '';
  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.ConnectTimeout := CONNECT_TIMEOUT;
      Client.IOTimeout := IO_TIMEOUT;
      Client.AllowRedirect := True;
      Client.AddHeader('User-Agent', USER_AGENT);
      Body := Client.Get(URL);
    except
      Body := '';    // DNS, TLS, 404, timeout - all just "no answer" here
    end;
  finally
    Client.Free;
  end;
  Result := Trim(Body) <> '';
end;

{$ENDIF}

procedure AddEntry(var R: TDefResult; const APart: string; ASenses: TStringList);
var
  N, I: Integer;
begin
  if ASenses.Count = 0 then
    Exit;
  N := Length(R.Entries);
  SetLength(R.Entries, N + 1);
  R.Entries[N].PartOfSpeech := APart;
  SetLength(R.Entries[N].Senses, ASenses.Count);
  for I := 0 to ASenses.Count - 1 do
    R.Entries[N].Senses[I] := ASenses[I];
end;

(* https://en.wiktionary.org/api/rest_v1/page/definition/<word>
   -> { "en": [ { partOfSpeech, definitions: [ { definition } ] } ] } *)
function ParseWiktionary(const Body: string; var R: TDefResult): Boolean;
var
  Data: TJSONData;
  Sections, Defs: TJSONArray;
  Section: TJSONObject;
  I, J: Integer;
  Txt: string;
  Senses: TStringList;
begin
  Result := False;
  Data := nil;
  Senses := TStringList.Create;
  try
    try
      Data := GetJSON(Body);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then
      Exit;
    if TJSONObject(Data).Find('en') = nil then
      Exit;

    Sections := TJSONArray(TJSONObject(Data).FindPath('en'));
    for I := 0 to Sections.Count - 1 do
    begin
      if Length(R.Entries) >= MAX_PARTS then
        Break;
      Section := TJSONObject(Sections[I]);
      if Section.Find('definitions') = nil then
        Continue;
      Defs := TJSONArray(Section.FindPath('definitions'));

      Senses.Clear;
      for J := 0 to Defs.Count - 1 do
      begin
        Txt := StripHtml(TJSONObject(Defs[J]).Get('definition', ''));
        if Txt = '' then       // Wiktionary emits empty placeholder entries
          Continue;
        Senses.Add(Txt);
        if Senses.Count >= MAX_SENSES then
          Break;
      end;
      AddEntry(R, LowerCase(Section.Get('partOfSpeech', '')), Senses);
    end;

    Result := Length(R.Entries) > 0;
    if Result then
      R.Source := 'Wiktionary';
  finally
    Senses.Free;
    Data.Free;
  end;
end;

(* https://api.dictionaryapi.dev/api/v2/entries/en/<word>
   -> [ { word, phonetic, meanings: [ { partOfSpeech, definitions } ] } ] *)
function ParseDictionaryApi(const Body: string; var R: TDefResult): Boolean;
var
  Data: TJSONData;
  Entries, Meanings, Defs: TJSONArray;
  Entry, Meaning: TJSONObject;
  I, J: Integer;
  Txt: string;
  Senses: TStringList;
begin
  Result := False;
  Data := nil;
  Senses := TStringList.Create;
  try
    try
      Data := GetJSON(Body);
    except
      Exit;
    end;
    if not (Data is TJSONArray) then
      Exit;
    Entries := TJSONArray(Data);
    if Entries.Count = 0 then
      Exit;

    Entry := TJSONObject(Entries[0]);
    if Entry.Find('phonetic') <> nil then
      R.Phonetic := Entry.Get('phonetic', '');
    if Entry.Find('meanings') = nil then
      Exit;

    Meanings := TJSONArray(Entry.FindPath('meanings'));
    for I := 0 to Meanings.Count - 1 do
    begin
      if Length(R.Entries) >= MAX_PARTS then
        Break;
      Meaning := TJSONObject(Meanings[I]);
      if Meaning.Find('definitions') = nil then
        Continue;
      Defs := TJSONArray(Meaning.FindPath('definitions'));

      Senses.Clear;
      for J := 0 to Defs.Count - 1 do
      begin
        Txt := Trim(TJSONObject(Defs[J]).Get('definition', ''));
        if Txt = '' then
          Continue;
        Senses.Add(Txt);
        if Senses.Count >= MAX_SENSES then
          Break;
      end;
      AddEntry(R, LowerCase(Meaning.Get('partOfSpeech', '')), Senses);
    end;

    Result := Length(R.Entries) > 0;
    if Result then
      R.Source := 'dictionaryapi.dev';
  finally
    Senses.Free;
    Data.Free;
  end;
end;

function FetchDefinition(const AWord: string): TDefResult;
var
  Body, Clean: string;
  Reached: Boolean;
begin
  Result := Default(TDefResult);
  Clean := LowerCase(Trim(AWord));
  Result.Word := UpperCase(Clean);

  if Clean = '' then
  begin
    Result.Error := 'No word to look up.';
    Exit;
  end;

  Reached := False;

  if HttpGet('https://en.wiktionary.org/api/rest_v1/page/definition/' + Clean, Body) then
  begin
    Reached := True;
    if ParseWiktionary(Body, Result) then
      Exit;
  end;

  if HttpGet('https://api.dictionaryapi.dev/api/v2/entries/en/' + Clean, Body) then
  begin
    Reached := True;
    if ParseDictionaryApi(Body, Result) then
      Exit;
  end;

  // Say which of the two actually happened rather than blaming the word.
  if Reached then
    Result.Error := 'No dictionary entry for this one.'
  else
    Result.Error := 'Could not reach a dictionary. Check the internet connection.';
end;

{ TLookupThread }

constructor TLookupThread.Create(const AWord: string);
begin
  FWord := AWord;
  { qualified: the Windows unit has a TCriticalSection record of its own }
  FLock := syncobjs.TCriticalSection.Create;
  FDone := False;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TLookupThread.Destroy;
begin
  inherited Destroy;
  FLock.Free;
end;

procedure TLookupThread.Execute;
var
  R: TDefResult;
begin
  R := FetchDefinition(FWord);
  FLock.Acquire;
  try
    FResult := R;
    FDone := True;
  finally
    FLock.Release;
  end;
end;

function TLookupThread.TryTakeResult(out AResult: TDefResult): Boolean;
begin
  FLock.Acquire;
  try
    Result := FDone;
    if Result then
      AResult := FResult;
  finally
    FLock.Release;
  end;
end;

end.
