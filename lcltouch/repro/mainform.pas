unit mainform;

{ Tap the panel and the button with a finger, on a touchscreen.

  The top half counts ordinary LCL mouse events. The log underneath also
  listens for GTK's own "touch-event" signal on the window (via
  ../workaround/unittouch.pas), which only fires for touches LCL did not
  handle.

  Stock LCL-gtk3:
    the counters stay at 0 and every tap shows up in the log as
    "GTK touch BEGIN / END" - GTK is delivering the touches and LCL is
    dropping them.

  With patches/0001 applied to LCL:
    the counters move and the "GTK touch" lines stop, because LCL now turns
    the touches into mouse messages and handles them itself.

  With a mouse, the counters always work - this is only about touch. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, unittouch;

type
  TFormTouch = class(TForm)
  private
    FPanel: TPanel;
    FButton: TButton;
    FCounts: TLabel;
    FLog: TMemo;
    FPanelDowns, FPanelClicks, FButtonClicks, FTouches: Integer;
    FSpyInstalled: Boolean;
    procedure FormShowOnce(Sender: TObject);
    procedure PanelMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PanelClick(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
    procedure SpyTouch(Phase: TTouchPhase; Seq: Pointer; SX, SY: Integer);
    procedure UpdateCounts;
    procedure Log(const S: string);
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

var
  FormTouch: TFormTouch;

implementation

const
  PHASE_NAMES: array[TTouchPhase] of string = ('BEGIN', 'UPDATE', 'END', 'CANCEL');

constructor TFormTouch.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := 'LCL-gtk3 touch repro';
  SetBounds(0, 0, 520, 560);
  Position := poScreenCenter;

  // alTop controls stack by Top, so give them an explicit order.
  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.SetBounds(0, 0, 520, 200);
  FPanel.Align := alTop;
  FPanel.Caption := 'Tap here with a finger';
  FPanel.Font.Height := -22;
  FPanel.OnMouseDown := @PanelMouseDown;
  FPanel.OnClick := @PanelClick;

  FButton := TButton.Create(Self);
  FButton.Parent := Self;
  FButton.SetBounds(0, 210, 520, 64);
  FButton.Align := alTop;
  FButton.Caption := 'Tap this button';
  FButton.OnClick := @ButtonClick;

  FCounts := TLabel.Create(Self);
  FCounts.Parent := Self;
  FCounts.SetBounds(0, 290, 520, 30);
  FCounts.Align := alTop;
  FCounts.Font.Height := -15;

  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.Align := alClient;
  FLog.ReadOnly := True;
  FLog.ScrollBars := ssVertical;

  // Hooking the window needs its handle; forcing it here would make gtk3
  // open the window at the wrong size, so wait for the first show.
  OnShow := @FormShowOnce;

  UpdateCounts;
  Log('Tap the panel and the button with a finger.');
end;

procedure TFormTouch.FormShowOnce(Sender: TObject);
begin
  if FSpyInstalled then
    Exit;
  FSpyInstalled := InstallTouchHandler(Self, @SpyTouch);
  if FSpyInstalled then
    Log('Also listening for GTK touch-event on the window.')
  else
    Log('Not listening for GTK touch-event (not the gtk3 widgetset?).');
end;

procedure TFormTouch.PanelMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Inc(FPanelDowns);
  Log(Format('LCL  panel OnMouseDown at %d,%d', [X, Y]));
  UpdateCounts;
end;

procedure TFormTouch.PanelClick(Sender: TObject);
begin
  Inc(FPanelClicks);
  Log('LCL  panel OnClick');
  UpdateCounts;
end;

procedure TFormTouch.ButtonClick(Sender: TObject);
begin
  Inc(FButtonClicks);
  Log('LCL  button OnClick');
  UpdateCounts;
end;

procedure TFormTouch.SpyTouch(Phase: TTouchPhase; Seq: Pointer; SX, SY: Integer);
begin
  Inc(FTouches);
  Log(Format('GTK  touch %s at screen %d,%d  (sequence %p) - LCL did not handle it',
    [PHASE_NAMES[Phase], SX, SY, Seq]));
  UpdateCounts;
end;

procedure TFormTouch.UpdateCounts;
begin
  FCounts.Caption := Format('  Panel: %d presses, %d clicks    Button: %d clicks    Unhandled touches: %d',
    [FPanelDowns, FPanelClicks, FButtonClicks, FTouches]);
end;

procedure TFormTouch.Log(const S: string);
begin
  FLog.Lines.Add(FormatDateTime('hh:nn:ss.zzz  ', Now) + S);
end;

end.
