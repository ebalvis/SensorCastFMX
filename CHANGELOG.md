# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-06-22

First working version. Delphi FireMonkey port of the B4A project `SensorCast`,
extended with gyroscope and 3D visualization.

### Added
- Reading of **accelerometer, magnetometer and gyroscope** on Android via JNI
  (`android.hardware.SensorManager`), by polling with a lock.
- **UDP server** (Indy 10): listens on 51042, registers clients with `HOLA`,
  broadcasts a JSON with the three sensors to port 51043 every 200 ms.
- Detection of the **real local IP (wlan0)** by enumerating JNI interfaces
  (`java.net.NetworkInterface`), with an Indy fallback on desktop.
- **3D visualization** (`TViewport3D`): reference cube with labeled X/Y/Z axes,
  accelerometer (orange) and magnetometer (magenta) arrows, and the gyroscope as
  a ring perpendicular to the axis + an axis arrow.
- **World frame**: the cube tilts according to the phone's real orientation and
  gravity stays vertical (smoothed accelerometer as reference, with no need for a
  rotation matrix nor heading).
- Orbital camera (drag = rotate, wheel = zoom) and a top panel with IP, port and
  live readings of the three sensors.
- Simulated sensor *stub* on desktop to debug network and 3D without a phone.

### Technical notes
- Arrow length is controlled by **scale**, not by changing the mesh height, to
  avoid per-frame rebuilds (which caused out-of-memory closes on Android).
- Arrow orientation adapted to FMX's **left-handed** system (Y pointing down); the
  FMX cone is rotated 180° so the tip points outward.

[0.1.0]: https://github.com/ebalvis/SensorCastFMX/releases/tag/v0.1.0
