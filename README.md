# SensorCast FMX

![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Delphi](https://img.shields.io/badge/Delphi-12_Athens-EE1F35)
![UI](https://img.shields.io/badge/UI-FireMonkey%20(FMX)-blue)
![License](https://img.shields.io/badge/license-MIT-green)

Sensor server for **Android** with **real-time 3D visualization**, written in **Delphi FireMonkey (FMX)**.

![SensorCast FMX on Android](docs/screenshot.png)

It reads the phone's **accelerometer**, **magnetometer** and **gyroscope**, broadcasts them over **UDP** as JSON to subscribed clients, and shows them in a 3D scene where the cube represents the phone and tilts with its real orientation (gravity always stays vertical).

It is a Delphi FMX *port* of the original [SensorCast](https://github.com/ebalvis) project written in **B4A (Basic4Android)**, extended with gyroscope and 3D visualization.

---

## Features

### Sensors (via JNI to `android.hardware.SensorManager`)
- **Accelerometer** (`TYPE_ACCELEROMETER`) — m/s²
- **Magnetometer** (`TYPE_MAGNETIC_FIELD`) — µT
- **Gyroscope** (`TYPE_GYROSCOPE`) — rad/s

Reading is by **polling**: the sensor callback stores the latest value under a lock and the UI reads it at its own pace. This avoids flooding the main thread.

### UDP server (identical to the B4A original)
1. Listens on port **51042**.
2. A client subscribes by sending the text `HOLA` to `PHONE_IP:51042`.
3. Every **200 ms** it sends each registered client a JSON to port **51043**:

```json
{
  "accelerometer": { "x": 0.10, "y": 0.50, "z": 9.81 },
  "magnetometer":  { "x": -51.2, "y": -58.4, "z": 22.0 },
  "gyroscope":     { "x": 0.01, "y": -0.02, "z": 0.00 }
}
```

### 3D visualization (native FMX, `TViewport3D`)
- Wireframe **cube** = the phone, with **X (red) / Y (green) / Z (blue)** axes labeled in 3D.
- **World frame**: the cube tilts according to the phone's real orientation; **gravity always points down** (the smoothed accelerometer is used as the vertical reference).
- Sensor arrows: **accelerometer (orange)**, **magnetometer (magenta)** and **gyroscope** (yellow ring perpendicular to the spin axis + axis arrow).
- Orbital camera: drag to rotate, wheel to zoom.

### Lifecycle
Sensors and timers are started in `FormActivate` and stopped in `FormDeactivate` so as not to drain battery in the background.

---

## Architecture

| File | Responsibility |
|---|---|
| `SensorCast.dpr` / `.dproj` | FMX project (Win64 for debugging + Android64) |
| `uMain.pas` / `.fmx` | UI, data panel, orchestration (timers, lifecycle) |
| `uSensorServer.pas` | UDP server + JSON serialization (Indy 10, no UI) |
| `uAndroidSensors.pas` | Sensor reading via JNI + local IP; simulated *stub* on desktop |
| `uScene3D.pas` | 3D scene: cube, axes, arrows, world-frame tilt, camera |

---

## Build and deploy

Built with **Delphi 12 Athens**. Other versions will trigger the `.dproj` upgrade dialog on open.

1. Open `SensorCast.dproj` in RAD Studio.
2. **Test on Windows**: platform **Win64**, run. A *stub* generates simulated data, so the 3D view animates and the UDP server can be tested without a phone.
3. **Android**: platform **Android 64-bit**, **Debug** configuration, connect the device (USB debugging) and run (F9).

### Android permissions
Declared in the `.dproj`: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`. The accelerometer/magnetometer/gyroscope require no runtime permission.

---

## Test client (PowerShell)

```powershell
$ip   = "PHONE_IP"        # the one shown by the app (wlan0 interface)
$udp  = New-Object System.Net.Sockets.UdpClient
$udp.Connect($ip, 51042)
$hola = [Text.Encoding]::UTF8.GetBytes("HOLA")
$udp.Send($hola, $hola.Length) | Out-Null

$recv = New-Object System.Net.Sockets.UdpClient 51043
$ep   = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any, 0)
while ($true) { [Text.Encoding]::UTF8.GetString($recv.Receive([ref]$ep)) }
```

---

## License

See [LICENSE](LICENSE).

## Credits

Eduardo Balvís. Delphi FMX port of the B4A project `SensorCast` (UVigo / SCOA).
