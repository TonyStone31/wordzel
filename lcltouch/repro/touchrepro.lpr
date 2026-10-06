program touchrepro;

{ Minimal repro: touchscreen taps never reach an LCL-gtk3 application.

  Build:  lazbuild --ws=gtk3 touchrepro.lpi
  Run it on a machine with a touchscreen and tap the panel and the button with
  a finger. See mainform.pas for what to expect. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, mainform;

begin
  Application.Initialize;
  Application.CreateForm(TFormTouch, FormTouch);
  Application.Run;
end.
