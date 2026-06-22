unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math.Vectors,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Layouts, FMX.Objects, FMX.Viewport3D,
  uSensorServer, uAndroidSensors, uScene3D;

type
  TfrmMain = class(TForm)
    rectTop: TRectangle;
    lblIP: TLabel;
    lblAcc: TLabel;
    lblMag: TLabel;
    lblGyro: TLabel;
    lblAxes: TLabel;
    lblStatus: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
  private
    FServer: TSensorServer;
    FReader: ISensorReader;
    FUITimer: TTimer;        // refreshes UI + 3D (~20 fps)
    FNetTimer: TTimer;       // UDP broadcast (200 ms)
    FViewport: TViewport3D;
    FScene: TSensorScene;
    FAcc: TAxis3;
    FMag: TAxis3;
    FGyro: TAxis3;
    procedure UITick(Sender: TObject);
    procedure NetTick(Sender: TObject);
    procedure ServerLog(const AMsg: string);
    procedure ClientRegistered(const AHost: string; ACount: Integer);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

function Ax2P3(const A: TAxis3): TPoint3D;
begin
  Result := Point3D(A.X, A.Y, A.Z);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FServer := TSensorServer.Create(51042, 51043);
  FServer.OnLog := ServerLog;
  FServer.OnClientRegistered := ClientRegistered;
  FServer.Start;

  var ip := GetLocalIPv4;        // real IPv4 (wlan0) on Android
  if ip = '' then
    ip := FServer.LocalIP;       // Indy fallback (desktop)
  lblIP.Text := 'IP: ' + ip + '   puerto ' + IntToStr(FServer.ListenPort);
  lblStatus.Text := 'Arrastra para rotar / rueda: zoom';
  lblAxes.Text := 'Gyro: anillo amarillo  (acc = vertical)';

  // 3D view: fills the rest of the form below the top panel.
  FViewport := TViewport3D.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := TAlignLayout.Client;
  FScene := TSensorScene.Create(FViewport);

  FReader := CreateSensorReader;

  // 3D rendering is decoupled from sampling: the sensor only stores the value
  // (polling); this timer reads it and refreshes the screen at ~20 fps.
  FUITimer := TTimer.Create(Self);
  FUITimer.Interval := 50;
  FUITimer.Enabled := False;
  FUITimer.OnTimer := UITick;

  FNetTimer := TTimer.Create(Self);
  FNetTimer.Interval := 200;
  FNetTimer.Enabled := False;
  FNetTimer.OnTimer := NetTick;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FUITimer.Free;
  FNetTimer.Free;
  FReader := nil;
  FScene.Free;
  FServer.Free;
end;

procedure TfrmMain.FormActivate(Sender: TObject);
begin
  FReader.StartListening;
  FUITimer.Enabled := True;
  FNetTimer.Enabled := True;
end;

procedure TfrmMain.FormDeactivate(Sender: TObject);
begin
  FUITimer.Enabled := False;
  FNetTimer.Enabled := False;
  FReader.StopListening;
end;

procedure TfrmMain.UITick(Sender: TObject);
begin
  if not FReader.GetLatest(FAcc, FMag, FGyro) then
    Exit;

  lblAcc.Text  := Format('Acc  (m/s2):  %.2f   %.2f   %.2f', [FAcc.X, FAcc.Y, FAcc.Z]);
  lblMag.Text  := Format('Mag  (uT):    %.2f   %.2f   %.2f', [FMag.X, FMag.Y, FMag.Z]);
  lblGyro.Text := Format('Gyro (rad/s): %.2f   %.2f   %.2f', [FGyro.X, FGyro.Y, FGyro.Z]);

  FScene.UpdateVectors(Ax2P3(FAcc), Ax2P3(FMag), Ax2P3(FGyro));
end;

procedure TfrmMain.NetTick(Sender: TObject);
begin
  FServer.Broadcast(FAcc, FMag, FGyro);
end;

procedure TfrmMain.ServerLog(const AMsg: string);
begin
  lblStatus.Text := AMsg;
end;

procedure TfrmMain.ClientRegistered(const AHost: string; ACount: Integer);
begin
  lblStatus.Text := Format('Clientes conectados: %d', [ACount]);
end;

end.
