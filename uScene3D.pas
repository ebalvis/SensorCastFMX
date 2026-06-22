unit uScene3D;

{
  3D scene (native FMX) to visualize the sensor vectors in WORLD FRAME: the cube
  (the phone) tilts according to its real orientation and gravity always points down.

  How it is achieved without complex matrices/Euler: the whole scene (cube + axes +
  arrows, all in the phone's body frame) hangs from two tilt dummies. Each frame the
  scene is tilted so the accelerometer vector (which at rest points "up", against
  gravity) ends up pointing to world +Y. Result: the cube tilts like the phone and
  the vertical (gravity) is kept. The SAME math as OrientTo is used, but inverted
  (-pitch, -yaw) in nested dummies.

  Contents:
    - Wireframe cube (the phone) + body axes X(red) Y(green) Z(blue).
    - Acc (orange): at rest it stays vertical (gravity reference).
    - Mag (magenta) and Gyro (yellow ring + axis arrow) tilt with the cube.

  The accelerometer is smoothed (low-pass) so the cube does not jitter.
  The camera orbits by dragging; wheel = zoom (desktop).
}

interface

uses
  System.Classes, System.UITypes, System.Math, System.Math.Vectors,
  FMX.Types, FMX.Viewport3D, FMX.Controls3D, FMX.Objects3D,
  FMX.MaterialSources;

// Orients the dummy pair (Yaw around Y, Pitch around X) so that the local +Y
// axis points to direction d (unit vector, left-handed FMX frame).
procedure OrientTo(AYaw, APitch: TDummy; const d: TPoint3D);

type
  TArrow3D = record
    Yaw: TDummy;
    Pitch: TDummy;
    ShaftScale: TDummy;
    Shaft: TCylinder;
    Head: TCone;
    procedure Update(const V: TPoint3D; RefMax, MaxLen: Single);
  end;

  TGyroViz = record
    Yaw: TDummy;
    Pitch: TDummy;
    ShaftScale: TDummy;
    Shaft: TCylinder;
    Head: TCone;
    RingPos: TDummy;
    procedure Update(const V: TPoint3D; RefMax: Single);
  end;

  TSensorScene = class
  private
    FViewport: TViewport3D;
    FWorld: TDummy;       // world node (Y up)
    FTiltOuter: TDummy;   // tilt: -pitch (X)
    FTiltInner: TDummy;   // tilt: -yaw (Y); holds the WHOLE scene
    FCamPivot: TDummy;
    FCamera: TCamera;
    FArrowAcc: TArrow3D;
    FArrowMag: TArrow3D;
    FGyro: TGyroViz;
    FYaw, FPitch: Single;
    FDragging: Boolean;
    FLastX, FLastY: Single;
    FAccF: TPoint3D;      // smoothed accelerometer
    FHasAccF: Boolean;
    function MakeMaterial(AColor: TAlphaColor): TColorMaterialSource;
    function BuildArrow(AParent: TFmxObject; AColor: TAlphaColor; AShaftR, AHeadR: Single): TArrow3D;
    function BuildGyro(AColor: TAlphaColor): TGyroViz;
    procedure BuildAxis(const Dir: TPoint3D; AColor: TAlphaColor; const ALabel: string);
    procedure ApplyOrbit;
    procedure ApplyTilt(const AAcc: TPoint3D);
    procedure VPMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure VPMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure VPMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure VPMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
  public
    constructor Create(AViewport: TViewport3D);
    procedure UpdateVectors(const AAcc, AMag, AGyro: TPoint3D);
  end;

implementation

const
  ACC_REF   = 12.0;
  MAG_REF   = 60.0;
  GYRO_REF  = 3.0;
  MAX_LEN   = 1.5;
  CUBE_SIZE = 2.0;
  RING_R    = 0.28;
  RING_N    = 16;
  ACC_SMOOTH = 0.15;   // accelerometer low-pass factor (0..1)

procedure OrientTo(AYaw, APitch: TDummy; const d: TPoint3D);
begin
  AYaw.RotationAngle.Y := RadToDeg(ArcTan2(d.X, -d.Z));
  APitch.RotationAngle.X := RadToDeg(ArcCos(EnsureRange(d.Y, -1.0, 1.0)));
end;

{ TArrow3D }

procedure TArrow3D.Update(const V: TPoint3D; RefMax, MaxLen: Single);
var
  m, L: Single;
begin
  m := V.Length;
  if m < 1E-6 then
  begin
    Yaw.Visible := False;
    Exit;
  end;
  Yaw.Visible := True;
  OrientTo(Yaw, Pitch, V * (1.0 / m));
  L := EnsureRange((m / RefMax) * MaxLen, 0.08, MaxLen);
  ShaftScale.Scale.Y := L;
  Head.Position.Y := L + Head.Height / 2;
end;

{ TGyroViz }

procedure TGyroViz.Update(const V: TPoint3D; RefMax: Single);
var
  m, L: Single;
begin
  m := V.Length;
  if m < 0.05 then
  begin
    Yaw.Visible := False;
    Exit;
  end;
  Yaw.Visible := True;
  OrientTo(Yaw, Pitch, V * (1.0 / m));
  L := EnsureRange((m / RefMax) * 0.9, 0.2, 0.9);
  ShaftScale.Scale.Y := L;
  Head.Position.Y := L + Head.Height / 2;
  RingPos.Position.Y := L;
end;

{ TSensorScene }

constructor TSensorScene.Create(AViewport: TViewport3D);
var
  Cube: TStrokeCube;
begin
  inherited Create;
  FViewport := AViewport;
  FViewport.Color := TAlphaColors.Black;
  FViewport.UsingDesignCamera := False;

  // World with Y pointing up (FMX is Y-down)
  FWorld := TDummy.Create(FViewport);
  FWorld.Parent := FViewport;
  FWorld.RotationAngle.X := 180;

  // Tilt dummies (the scene hangs inside them)
  FTiltOuter := TDummy.Create(FViewport);
  FTiltOuter.Parent := FWorld;
  FTiltInner := TDummy.Create(FViewport);
  FTiltInner.Parent := FTiltOuter;

  // Orbital camera
  FCamPivot := TDummy.Create(FViewport);
  FCamPivot.Parent := FViewport;
  FCamera := TCamera.Create(FViewport);
  FCamera.Parent := FCamPivot;
  FCamera.Position.Point := Point3D(0, 0, -9);
  FCamera.Target := FCamPivot;
  FViewport.Camera := FCamera;

  FYaw := 25;
  FPitch := -15;
  ApplyOrbit;

  // Cube = the phone
  Cube := TStrokeCube.Create(FViewport);
  Cube.Parent := FTiltInner;
  Cube.Width := CUBE_SIZE;
  Cube.Height := CUBE_SIZE;
  Cube.Depth := CUBE_SIZE;
  Cube.Color := TAlphaColors.Dimgray;

  // Phone body axes with X/Y/Z labels in 3D
  BuildAxis(Point3D(1, 0, 0), TAlphaColors.Red, 'X');
  BuildAxis(Point3D(0, 1, 0), TAlphaColors.Lime, 'Y');
  BuildAxis(Point3D(0, 0, 1), TAlphaColors.Deepskyblue, 'Z');

  FArrowAcc := BuildArrow(FTiltInner, TAlphaColors.Orange,  0.05, 0.16);
  FArrowMag := BuildArrow(FTiltInner, TAlphaColors.Magenta, 0.05, 0.16);
  FGyro := BuildGyro(TAlphaColors.Yellow);

  FViewport.OnMouseDown := VPMouseDown;
  FViewport.OnMouseMove := VPMouseMove;
  FViewport.OnMouseUp := VPMouseUp;
  FViewport.OnMouseWheel := VPMouseWheel;
end;

function TSensorScene.MakeMaterial(AColor: TAlphaColor): TColorMaterialSource;
begin
  Result := TColorMaterialSource.Create(FViewport);
  Result.Color := AColor;
end;

function TSensorScene.BuildArrow(AParent: TFmxObject; AColor: TAlphaColor;
  AShaftR, AHeadR: Single): TArrow3D;
var
  Mat: TColorMaterialSource;
begin
  Mat := MakeMaterial(AColor);

  Result.Yaw := TDummy.Create(FViewport);
  Result.Yaw.Parent := AParent;

  Result.Pitch := TDummy.Create(FViewport);
  Result.Pitch.Parent := Result.Yaw;

  Result.ShaftScale := TDummy.Create(FViewport);
  Result.ShaftScale.Parent := Result.Pitch;

  Result.Shaft := TCylinder.Create(FViewport);
  Result.Shaft.Parent := Result.ShaftScale;
  Result.Shaft.SetSize(AShaftR, 1.0, AShaftR);
  Result.Shaft.Position.Y := 0.5;
  Result.Shaft.MaterialSource := Mat;

  Result.Head := TCone.Create(FViewport);
  Result.Head.Parent := Result.Pitch;
  Result.Head.SetSize(AHeadR, AHeadR * 1.4, AHeadR);
  // FMX's cone points to -Y by default: rotate 180 so the tip points to +Y (outward)
  Result.Head.RotationAngle.Z := 180;
  Result.Head.MaterialSource := Mat;
end;

function TSensorScene.BuildGyro(AColor: TAlphaColor): TGyroViz;
var
  Mat: TColorMaterialSource;
  i: Integer;
  ang: Single;
  Bead: TSphere;
  Arr: TArrow3D;
begin
  Arr := BuildArrow(FTiltInner, AColor, 0.04, 0.12);
  Result.Yaw := Arr.Yaw;
  Result.Pitch := Arr.Pitch;
  Result.ShaftScale := Arr.ShaftScale;
  Result.Shaft := Arr.Shaft;
  Result.Head := Arr.Head;

  Result.RingPos := TDummy.Create(FViewport);
  Result.RingPos.Parent := Result.Pitch;

  Mat := MakeMaterial(AColor);
  for i := 0 to RING_N - 1 do
  begin
    ang := 2 * Pi * i / RING_N;
    Bead := TSphere.Create(FViewport);
    Bead.Parent := Result.RingPos;
    Bead.SetSize(0.05, 0.05, 0.05);
    Bead.Position.Point := Point3D(RING_R * Cos(ang), 0, RING_R * Sin(ang));
    Bead.MaterialSource := Mat;
  end;
end;

procedure TSensorScene.BuildAxis(const Dir: TPoint3D; AColor: TAlphaColor; const ALabel: string);
var
  A: TArrow3D;
  Txt: TText3D;
begin
  A := BuildArrow(FTiltInner, AColor, 0.025, 0.10);
  A.Update(Dir, 1.0, 1.0);

  // 3D text label hung from the axis arrow (its local +Y), so it always sits at
  // the real tip of the axis, regardless of OrientTo's sign.
  Txt := TText3D.Create(FViewport);
  Txt.Parent := A.Pitch;
  Txt.MaterialSource := MakeMaterial(AColor);
  Txt.WordWrap := False;
  Txt.Stretch := True;        // fits the text to Width/Height (otherwise it is huge)
  Txt.Width := 0.35;
  Txt.Height := 0.35;
  Txt.Depth := 0.03;
  Txt.Text := ALabel;
  Txt.Position.Point := Point3D(0, 1.3, 0);
end;

procedure TSensorScene.ApplyOrbit;
begin
  FCamPivot.RotationAngle.Y := FYaw;
  FCamPivot.RotationAngle.X := FPitch;
end;

// Tilts the whole scene so the (smoothed) accelerometer points to world +Y. It is
// the INVERSE rotation of OrientTo(acc): -pitch on X (outer), -yaw on Y (inner).
// This keeps acc vertical and the cube tilts like the phone.
procedure TSensorScene.ApplyTilt(const AAcc: TPoint3D);
var
  m, yaw, pitch: Single;
  d: TPoint3D;
begin
  if not FHasAccF then
  begin
    FAccF := AAcc;
    FHasAccF := True;
  end
  else
    FAccF := FAccF * (1 - ACC_SMOOTH) + AAcc * ACC_SMOOTH;

  m := FAccF.Length;
  if m < 0.5 then
    Exit;   // free fall / odd data: do not reorient
  d := FAccF * (1.0 / m);

  yaw := RadToDeg(ArcTan2(d.X, -d.Z));
  pitch := RadToDeg(ArcCos(EnsureRange(d.Y, -1.0, 1.0)));
  FTiltOuter.RotationAngle.X := -pitch;
  FTiltInner.RotationAngle.Y := -yaw;
end;

procedure TSensorScene.UpdateVectors(const AAcc, AMag, AGyro: TPoint3D);
begin
  ApplyTilt(AAcc);
  FArrowAcc.Update(AAcc, ACC_REF, MAX_LEN);
  FArrowMag.Update(AMag, MAG_REF, MAX_LEN);
  FGyro.Update(AGyro, GYRO_REF);
end;

procedure TSensorScene.VPMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FDragging := True;
  FLastX := X;
  FLastY := Y;
end;

procedure TSensorScene.VPMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if not FDragging then
    Exit;
  FYaw := FYaw + (X - FLastX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastY) * 0.5, -89, 89);
  FLastX := X;
  FLastY := Y;
  ApplyOrbit;
end;

procedure TSensorScene.VPMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FDragging := False;
end;

procedure TSensorScene.VPMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  z: Single;
begin
  z := FCamera.Position.Z * (1.0 - WheelDelta / 1200.0);
  FCamera.Position.Z := EnsureRange(z, -30, -3);
  Handled := True;
end;

end.
