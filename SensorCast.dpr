program SensorCast;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {frmMain},
  uSensorServer in 'uSensorServer.pas',
  uAndroidSensors in 'uAndroidSensors.pas',
  uScene3D in 'uScene3D.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
