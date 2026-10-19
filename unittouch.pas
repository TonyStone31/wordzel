unit unittouch;

{ Touchscreen taps for LCL-gtk3.

  LCL-gtk3 adds GDK_TOUCH_MASK to every widget's event mask but has no code
  for GDK_TOUCH_* events. Asking for touch events tells X/GDK to stop turning
  touches into emulated mouse clicks, so on a touchscreen taps simply vanish.
  Its event dispatcher does return False for touch events, though, so they keep
  bubbling up as GTK "touch-event" signals until they reach the top-level
  window - which is where this catches them and hands them to the form.

  On other widgetsets InstallTouchHandler does nothing: they already deliver
  touches as mouse events. }

{$mode objfpc}{$H+}

interface

uses
  Forms;

type
  TTouchPhase = (tpBegin, tpMove, tpEnd, tpCancel);

  { Seq tells fingers apart; SX, SY are screen coordinates. }
  TTouchEvent = procedure(Phase: TTouchPhase; Seq: Pointer; SX, SY: Integer) of object;

{ Needs the form's handle to exist. True if a handler was installed. }
function InstallTouchHandler(AForm: TCustomForm; AHandler: TTouchEvent): Boolean;

implementation

{$IFDEF LCLGTK3}
uses
  LazGLib2, LazGObject2, LazGdk3, LazGtk3, gtk3widgets;

type
  PTouchBinding = ^TTouchBinding;
  TTouchBinding = record
    Handler: TTouchEvent;
  end;

function TouchEventCB({%H-}Widget: PGtkWidget; Event: PGdkEventTouch;
  Data: gpointer): gboolean; cdecl;
var
  Phase: TTouchPhase;
begin
  Result := False;
  case Event^.type_ of
    GDK_TOUCH_BEGIN:  Phase := tpBegin;
    GDK_TOUCH_UPDATE: Phase := tpMove;
    GDK_TOUCH_END:    Phase := tpEnd;
    GDK_TOUCH_CANCEL: Phase := tpCancel;
  else
    Exit;
  end;
  PTouchBinding(Data)^.Handler(Phase, Event^.sequence,
    Round(Event^.x_root), Round(Event^.y_root));
  Result := True;
end;

procedure FreeTouchBinding(Data: gpointer; {%H-}Closure: PGClosure); cdecl;
begin
  Dispose(PTouchBinding(Data));
end;

function InstallTouchHandler(AForm: TCustomForm; AHandler: TTouchEvent): Boolean;
var
  Window: PGtkWidget;
  Binding: PTouchBinding;
begin
  Result := False;
  if not AForm.HandleAllocated then
    Exit;
  Window := TGtk3Widget(AForm.Handle).Widget;
  if Window = nil then
    Exit;

  gtk_widget_add_events(Window, 1 shl Ord(GDK_TOUCH_MASK));
  New(Binding);
  Binding^.Handler := AHandler;
  g_signal_connect_data(PGObject(Window), 'touch-event',
    TGCallback(@TouchEventCB), Binding, @FreeTouchBinding, G_CONNECT_DEFAULT);
  Result := True;
end;

{$ELSE}

function InstallTouchHandler(AForm: TCustomForm; AHandler: TTouchEvent): Boolean;
begin
  Result := False;
end;

{$ENDIF}

end.
