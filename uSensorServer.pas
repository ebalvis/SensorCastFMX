unit uSensorServer;

{
  UDP sensor server. Equivalent to the network logic of the original B4A project
  (SensorCast). No UI dependencies.

  - Listens on FListenPort (51042) for "HOLA" messages from clients and registers them.
  - Sends each registered client a JSON with accelerometer + magnetometer + gyroscope
    to port FClientPort (51043).

  The OnLog / OnClientRegistered events are marshalled to the main thread, so they
  may touch the UI without additional synchronization.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs, System.JSON,
  IdGlobal, IdUDPServer, IdSocketHandle, IdUDPBase;

type
  // Triaxial reading of a sensor (X, Y, Z)
  TAxis3 = record
    X, Y, Z: Single;
  end;

  TClientRegisteredEvent = procedure(const AHost: string; ACount: Integer) of object;
  TLogEvent = procedure(const AMsg: string) of object;

  TSensorServer = class
  private
    FUDP: TIdUDPServer;
    FClients: TList<string>;
    FLock: TCriticalSection;
    FListenPort: Integer;
    FClientPort: Integer;
    FOnClientRegistered: TClientRegisteredEvent;
    FOnLog: TLogEvent;
    procedure UDPRead(AThread: TIdUDPListenerThread; const AData: TIdBytes;
      ABinding: TIdSocketHandle);
    procedure DoLog(const AMsg: string);
    procedure DoClientRegistered(const AHost: string; ACount: Integer);
  public
    constructor Create(AListenPort: Integer = 51042; AClientPort: Integer = 51043);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    // Device local IP (the one clients should use)
    function LocalIP: string;

    // Sends the latest reading to all registered clients
    procedure Broadcast(const AAcc, AMag, AGyro: TAxis3);

    property ListenPort: Integer read FListenPort;
    property ClientPort: Integer read FClientPort;
    property OnClientRegistered: TClientRegisteredEvent read FOnClientRegistered write FOnClientRegistered;
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

implementation

uses
  IdStack;

{ TSensorServer }

constructor TSensorServer.Create(AListenPort, AClientPort: Integer);
begin
  inherited Create;
  FListenPort := AListenPort;
  FClientPort := AClientPort;
  FClients := TList<string>.Create;
  FLock := TCriticalSection.Create;

  FUDP := TIdUDPServer.Create(nil);
  FUDP.DefaultPort := FListenPort;
  FUDP.ThreadedEvent := True;          // OnUDPRead on the listener thread
  FUDP.OnUDPRead := UDPRead;
end;

destructor TSensorServer.Destroy;
begin
  Stop;
  FUDP.Free;
  FLock.Free;
  FClients.Free;
  inherited;
end;

procedure TSensorServer.Start;
begin
  if not FUDP.Active then
    FUDP.Active := True;
end;

procedure TSensorServer.Stop;
begin
  if FUDP.Active then
    FUDP.Active := False;
end;

function TSensorServer.LocalIP: string;
var
  I: Integer;
begin
  Result := '';
  TIdStack.IncUsage;
  try
    // LocalAddress gives the primary one; scan the list in case there are several (WiFi)
    Result := GStack.LocalAddress;
    if (Result = '') or (Result = '127.0.0.1') then
      for I := 0 to GStack.LocalAddresses.Count - 1 do
        if GStack.LocalAddresses[I] <> '127.0.0.1' then
          Exit(GStack.LocalAddresses[I]);
  finally
    TIdStack.DecUsage;
  end;
end;

procedure TSensorServer.DoLog(const AMsg: string);
begin
  if not Assigned(FOnLog) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnLog) then
        FOnLog(AMsg);
    end);
end;

procedure TSensorServer.DoClientRegistered(const AHost: string; ACount: Integer);
begin
  if not Assigned(FOnClientRegistered) then
    Exit;
  TThread.Queue(nil,
    procedure
    begin
      if Assigned(FOnClientRegistered) then
        FOnClientRegistered(AHost, ACount);
    end);
end;

procedure TSensorServer.UDPRead(AThread: TIdUDPListenerThread;
  const AData: TIdBytes; ABinding: TIdSocketHandle);
var
  Msg, Host: string;
  Count: Integer;
  IsNew: Boolean;
begin
  Msg := Trim(BytesToString(AData, IndyTextEncoding_UTF8));
  Host := ABinding.PeerIP;
  DoLog(Format('Paquete de %s: "%s"', [Host, Msg]));

  if Msg <> 'HOLA' then
    Exit;

  FLock.Enter;
  try
    IsNew := FClients.IndexOf(Host) = -1;
    if IsNew then
      FClients.Add(Host);
    Count := FClients.Count;
  finally
    FLock.Leave;
  end;

  if IsNew then
  begin
    DoLog(Format('Nuevo cliente: %s (total %d)', [Host, Count]));
    DoClientRegistered(Host, Count);
  end
  else
    DoLog(Format('Cliente %s ya registrado', [Host]));
end;

procedure TSensorServer.Broadcast(const AAcc, AMag, AGyro: TAxis3);
var
  Root, JAcc, JMag, JGyro: TJSONObject;
  Payload: TIdBytes;
  Hosts: TArray<string>;
  Host: string;
begin
  // Snapshot of the client list under lock
  FLock.Enter;
  try
    if FClients.Count = 0 then
      Exit;
    Hosts := FClients.ToArray;
  finally
    FLock.Leave;
  end;

  Root := TJSONObject.Create;
  try
    JAcc := TJSONObject.Create;
    JAcc.AddPair('x', TJSONNumber.Create(AAcc.X));
    JAcc.AddPair('y', TJSONNumber.Create(AAcc.Y));
    JAcc.AddPair('z', TJSONNumber.Create(AAcc.Z));

    JMag := TJSONObject.Create;
    JMag.AddPair('x', TJSONNumber.Create(AMag.X));
    JMag.AddPair('y', TJSONNumber.Create(AMag.Y));
    JMag.AddPair('z', TJSONNumber.Create(AMag.Z));

    JGyro := TJSONObject.Create;
    JGyro.AddPair('x', TJSONNumber.Create(AGyro.X));
    JGyro.AddPair('y', TJSONNumber.Create(AGyro.Y));
    JGyro.AddPair('z', TJSONNumber.Create(AGyro.Z));

    Root.AddPair('accelerometer', JAcc);
    Root.AddPair('magnetometer', JMag);
    Root.AddPair('gyroscope', JGyro);

    Payload := ToBytes(Root.ToJSON, IndyTextEncoding_UTF8);
  finally
    Root.Free;
  end;

  for Host in Hosts do
    try
      FUDP.SendBuffer(Host, FClientPort, Payload);
    except
      on E: Exception do
        DoLog(Format('Error enviando a %s: %s', [Host, E.Message]));
    end;
end;

end.
