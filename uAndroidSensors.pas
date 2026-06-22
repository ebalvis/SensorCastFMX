unit uAndroidSensors;

{
  Reading of accelerometer, magnetometer and gyroscope.

  On Android, android.hardware.SensorManager is accessed directly via JNI
  (TYPE_ACCELEROMETER, TYPE_MAGNETIC_FIELD, TYPE_GYROSCOPE). Raw X/Y/Z values:
    - Accelerometer: m/s^2
    - Magnetic field: microteslas (uT)
    - Gyroscope: rad/s (angular velocity)

  POLLING model, NOT events: the sensor callback (background thread) only stores
  the latest value under a lock; whoever wants data calls GetLatest from the main
  thread. This avoids flooding the UI thread with TThread.Queue (which made the
  queue grow unbounded and closed the app after ~60 s).

  On desktop, a stub that simulates the three sensors with a TTimer is compiled.
}

interface

uses
  System.Classes, uSensorServer;

type
  ISensorReader = interface
    ['{B3A1F2C0-7E4D-4C2A-9F1B-2D5E6A7C8B90}']
    procedure StartListening;
    procedure StopListening;
    // Copies the latest reading. Returns True if data is already available.
    function GetLatest(out AAcc, AMag, AGyro: TAxis3): Boolean;
  end;

// Factory: returns the implementation appropriate for the platform
function CreateSensorReader: ISensorReader;

// Real local IPv4 (wlan0) on Android. '' on other platforms (use fallback).
function GetLocalIPv4: string;

implementation

uses
  System.SysUtils, System.SyncObjs
  {$IFDEF ANDROID}
  , Androidapi.JNIBridge, Androidapi.JNI.JavaTypes, Androidapi.JNI.Hardware
  , Androidapi.JNI.GraphicsContentViewText, Androidapi.JNI.Java.Net, Androidapi.Helpers
  {$ELSE}
  , FMX.Types
  {$ENDIF}
  ;

{$IFDEF ANDROID}
//==============================================================================
//  Android implementation (JNI, polling)
//==============================================================================
type
  TAndroidSensorReader = class;

  TInternalListener = class(TJavaLocal, JSensorEventListener)
  private
    FOwner: TAndroidSensorReader;
  public
    constructor Create(AOwner: TAndroidSensorReader);
    procedure onAccuracyChanged(sensor: JSensor; accuracy: Integer); cdecl;
    procedure onSensorChanged(event: JSensorEvent); cdecl;
  end;

  TAndroidSensorReader = class(TInterfacedObject, ISensorReader)
  private
    FManager: JSensorManager;
    FAccel: JSensor;
    FMag: JSensor;
    FGyro: JSensor;
    FListener: TInternalListener;
    FLock: TCriticalSection;
    FAcc: TAxis3;
    FMagV: TAxis3;
    FGyroV: TAxis3;
    FHasData: Boolean;
    FListening: Boolean;
    procedure HandleSensorChanged(event: JSensorEvent);
  public
    constructor Create;
    destructor Destroy; override;
    procedure StartListening;
    procedure StopListening;
    function GetLatest(out AAcc, AMag, AGyro: TAxis3): Boolean;
  end;

{ TInternalListener }

constructor TInternalListener.Create(AOwner: TAndroidSensorReader);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TInternalListener.onAccuracyChanged(sensor: JSensor; accuracy: Integer);
begin
  // Not used
end;

procedure TInternalListener.onSensorChanged(event: JSensorEvent);
begin
  if FOwner <> nil then
    FOwner.HandleSensorChanged(event);
end;

{ TAndroidSensorReader }

constructor TAndroidSensorReader.Create;
var
  Obj: JObject;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  Obj := TAndroidHelper.Context.getSystemService(TJContext.JavaClass.SENSOR_SERVICE);
  FManager := TJSensorManager.Wrap((Obj as ILocalObject).GetObjectID);
  FAccel := FManager.getDefaultSensor(TJSensor.JavaClass.TYPE_ACCELEROMETER);
  FMag := FManager.getDefaultSensor(TJSensor.JavaClass.TYPE_MAGNETIC_FIELD);
  FGyro := FManager.getDefaultSensor(TJSensor.JavaClass.TYPE_GYROSCOPE);
  FListener := TInternalListener.Create(Self);
end;

destructor TAndroidSensorReader.Destroy;
begin
  StopListening;
  FListener.Free;
  FLock.Free;
  inherited;
end;

// Runs on a system background thread. Only stores; does not touch the UI.
procedure TAndroidSensorReader.HandleSensorChanged(event: JSensorEvent);
var
  T: Integer;
  V: TJavaArray<Single>;
begin
  V := event.values;
  if (V = nil) or (V.Length < 3) then
    Exit;

  T := event.sensor.getType;
  FLock.Enter;
  try
    if T = TJSensor.JavaClass.TYPE_ACCELEROMETER then
    begin
      FAcc.X := V.Items[0]; FAcc.Y := V.Items[1]; FAcc.Z := V.Items[2];
    end
    else if T = TJSensor.JavaClass.TYPE_MAGNETIC_FIELD then
    begin
      FMagV.X := V.Items[0]; FMagV.Y := V.Items[1]; FMagV.Z := V.Items[2];
    end
    else if T = TJSensor.JavaClass.TYPE_GYROSCOPE then
    begin
      FGyroV.X := V.Items[0]; FGyroV.Y := V.Items[1]; FGyroV.Z := V.Items[2];
    end;
    FHasData := True;
  finally
    FLock.Leave;
  end;
end;

function TAndroidSensorReader.GetLatest(out AAcc, AMag, AGyro: TAxis3): Boolean;
begin
  FLock.Enter;
  try
    AAcc := FAcc;
    AMag := FMagV;
    AGyro := FGyroV;
    Result := FHasData;
  finally
    FLock.Leave;
  end;
end;

procedure TAndroidSensorReader.StartListening;
begin
  if FListening then
    Exit;
  if FAccel <> nil then
    FManager.registerListener(FListener, FAccel, TJSensorManager.JavaClass.SENSOR_DELAY_GAME);
  if FMag <> nil then
    FManager.registerListener(FListener, FMag, TJSensorManager.JavaClass.SENSOR_DELAY_GAME);
  if FGyro <> nil then
    FManager.registerListener(FListener, FGyro, TJSensorManager.JavaClass.SENSOR_DELAY_GAME);
  FListening := True;
end;

procedure TAndroidSensorReader.StopListening;
begin
  if not FListening then
    Exit;
  FManager.unregisterListener(FListener);
  FListening := False;
end;

function CreateSensorReader: ISensorReader;
begin
  Result := TAndroidSensorReader.Create;
end;

// Enumerates the network interfaces and returns the first non-loopback IPv4 (wlan0).
function GetLocalIPv4: string;
var
  Nets, Addrs: JEnumeration;
  Ni: JNetworkInterface;
  Addr: JInetAddress;
  S: string;
begin
  Result := '';
  try
    Nets := TJNetworkInterface.JavaClass.getNetworkInterfaces;
    if Nets = nil then
      Exit;
    while Nets.hasMoreElements do
    begin
      Ni := TJNetworkInterface.Wrap((Nets.nextElement as ILocalObject).GetObjectID);
      if Ni.isLoopback or (not Ni.isUp) then
        Continue;
      Addrs := Ni.getInetAddresses;
      while Addrs.hasMoreElements do
      begin
        Addr := TJInetAddress.Wrap((Addrs.nextElement as ILocalObject).GetObjectID);
        if Addr.isLoopbackAddress then
          Continue;
        S := JStringToString(Addr.getHostAddress);
        if (S <> '') and (Pos(':', S) = 0) then   // IPv4 (discard IPv6)
          Exit(S);
      end;
    end;
  except
    Result := '';
  end;
end;

{$ELSE}
//==============================================================================
//  Desktop stub (simulated values to debug network and 3D view)
//==============================================================================
type
  TStubSensorReader = class(TInterfacedObject, ISensorReader)
  private
    FTimer: TTimer;
    FLock: TCriticalSection;
    FAcc, FMagV, FGyroV: TAxis3;
    FHasData: Boolean;
    FT: Integer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure StartListening;
    procedure StopListening;
    function GetLatest(out AAcc, AMag, AGyro: TAxis3): Boolean;
  end;

constructor TStubSensorReader.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TStubSensorReader.Destroy;
begin
  FTimer.Free;
  FLock.Free;
  inherited;
end;

procedure TStubSensorReader.TimerTick(Sender: TObject);
var
  A: Single;
begin
  Inc(FT);
  A := FT / 10;
  FLock.Enter;
  try
    FAcc.X := Sin(A);         FAcc.Y := Cos(A);          FAcc.Z := 9.81;
    FMagV.X := 30 * Sin(A);   FMagV.Y := -15;            FMagV.Z := 22;
    FGyroV.X := 0.8 * Sin(A); FGyroV.Y := 0.8 * Cos(A);  FGyroV.Z := 0.3;
    FHasData := True;
  finally
    FLock.Leave;
  end;
end;

function TStubSensorReader.GetLatest(out AAcc, AMag, AGyro: TAxis3): Boolean;
begin
  FLock.Enter;
  try
    AAcc := FAcc;
    AMag := FMagV;
    AGyro := FGyroV;
    Result := FHasData;
  finally
    FLock.Leave;
  end;
end;

procedure TStubSensorReader.StartListening;
begin
  FTimer.Enabled := True;
end;

procedure TStubSensorReader.StopListening;
begin
  FTimer.Enabled := False;
end;

function CreateSensorReader: ISensorReader;
begin
  Result := TStubSensorReader.Create;
end;

function GetLocalIPv4: string;
begin
  Result := '';   // on desktop the Indy fallback is used (uSensorServer.LocalIP)
end;

{$ENDIF}

end.
