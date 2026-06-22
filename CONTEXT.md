# CONTEXT.md — SensorCast (Delphi FMX)
Última actualización: 2026-06-21

## Stack
- Delphi 12 Athens, FireMonkey (FMX), target Android64 (+ Win64 para depurar)
- Indy 10 (TIdUDPServer) para red UDP
- System.JSON para serialización
- JNI (Androidapi.JNI.Hardware) para sensores en Android

## Decisiones tomadas
- Port 1:1 del proyecto B4A `SensorCast` (uvigo). Mismo protocolo: escucha 51042,
  registro con "HOLA", envío JSON a clientes en 51043.
- Sensores vía JNI directo (SensorManager) en vez de System.Sensors: el campo
  magnético crudo en µT no está bien expuesto por la RTL multiplataforma.
- Difusión por TTimer de 200 ms (no en cada SensorChanged) para no saturar red.
- Stub de sensores en escritorio (valores simulados) → la red se prueba en Win64.
- Eventos del servidor marshalizados a hilo principal con TThread.Queue.
- Lógica de red y de sensores fuera del formulario (regla Delphi del usuario).

## Estado actual
- ✅ Código completo: uSensorServer, uAndroidSensors, uScene3D, uMain (+fmx), dpr, dproj
- ✅ Compila Win32 y despliega/instala/arranca en Android 64-bit real
- ✅ Giroscopio añadido (TYPE_GYROSCOPE) a lectura JNI, JSON UDP y UI
- ✅ Vista 3D FMX (uScene3D): TViewport3D + cubo wireframe + ejes XYZ + 3 flechas
     (acc rojo, mag cian, gyro amarillo). Rotación de cámara arrastrando.
- ⏳ Compilar nueva versión 3D (no verificado en este entorno)
- ⏳ Validar flujo UDP completo (HOLA -> JSON con gyroscope) y lecturas reales JNI
- Flechas "al revés" (CAUSA REAL, confirmada en la malla FMX): TCone tiene la BASE
  en +Y y el ÁPICE en -Y, o sea apunta hacia el origen. La punta salía hacia
  adentro. SOLUCIÓN: Head.RotationAngle.Z := 180 en BuildArrow (apice -> +Y/afuera).
  (FRoot.RotationAngle.X := 180 se mantiene solo por estética: vista Y-arriba.)
- Caracteres raros "Â·": los puntos medios UTF-8 se leían como Latin-1. Textos de
  labels puestos en código con ASCII ('/').
- Cierre a ~60 s en Android (2ª causa, la real): se cambiaba Shaft.Height cada
  frame -> RECONSTRUÍA la malla del cilindro 20 veces/s -> OOM/GPU en Android.
  SOLUCIÓN: la longitud se controla con ESCALA (ShaftScale.Scale.Y) y Position,
  nunca con Height. El polling (1ª causa) también se mantiene.
- Giroscopio: flecha del eje + anillo pequeño (RING_R=0.28) de esferas situado en
  la PUNTA del vector (RingPos en Position.Y := L), perpendicular al eje.
- MARCO MUNDO (elegido por el usuario): el cubo se inclina y la gravedad queda
  abajo. Sin getRotationMatrix ni Euler: toda la escena cuelga de FTiltOuter
  (X=-pitch) / FTiltInner (Y=-yaw), inclinada para que el acc apunte al +Y mundo
  (inversa de OrientTo(acc)). Solo tilt (sin heading) = "gravedad siempre abajo".
  Acc suavizado (paso bajo ACC_SMOOTH=0.15) para que el cubo no tiemble.
- PENDIENTE: lblIP muestra 127.0.0.1 (Indy GStack en Android da loopback). El
  servidor UDP sí escucha en todas las interfaces, pero hay que mostrar la IP de
  wlan0 (via JNI WifiManager/NetworkInterface). La real es 192.168.88.166.
- NOTA: al depurar, Android (ART) lanza señales POSIX que el depurador muestra como
  "raised exception class 10". Es benigno: Run Without Debugging funciona, o poner
  Native OS Exceptions = Ignore en Debugger Options.

## Archivos clave
- `uSensorServer.pas` — servidor UDP + JSON (Indy)
- `uAndroidSensors.pas` — sensores JNI ({$IFDEF ANDROID}) + stub escritorio
- `uMain.pas` / `uMain.fmx` — UI y ciclo de vida (FormActivate/FormDeactivate)
- `SensorCast.dproj` — permisos Android ya marcados

## Bugs resueltos
- Compilación Win32: 3 cláusulas `uses` en la implementation de uAndroidSensors
  (una por rama IFDEF). Solo se permite una -> fusionadas en una con condicionales.
- Deploy Android E2312 "Cannot find AndroidManifest.xml in PackagedResources.zip":
  el .dproj hecho a mano NO tenía las entradas Android_LauncherIcon* (iconos
  por defecto en $(BDS)\bin\Artwork\Android\). Sin icono @drawable/ic_launcher,
  aapt2 link dejaba el zip vacío (22 bytes). SOLUCIÓN: se reutilizó el .dproj de
  un proyecto en blanco del asistente (Projects\test2), cambiando units a
  uMain/uSensorServer/uAndroidSensors, renombrando Project28->SensorCast y
  añadiendo los permisos INTERNET/ACCESS_NETWORK_STATE/ACCESS_WIFI_STATE.
  LECCIÓN: no generar .dproj Android a mano; partir siempre del asistente.

## Mis preferencias (aprendidas)
- Mantener app como servidor de sensores en el móvil → elegido Delphi FMX sobre
  Lazarus/LAMW por madurez del soporte Android y por ser stack habitual.

## Próximos pasos
1. Abrir en RAD Studio, compilar Win64 y validar la parte de red con el cliente
   de prueba (ver README).
2. Verificar nombres JNI (JSensorManager/JSensorEvent) en la versión instalada.
3. Compilar y desplegar en Android64, comprobar lecturas reales acc/mag.
4. Opcional: mostrar nº de clientes conectados en la UI (hook ya existe).
5. Opcional: comando "ADIOS"/"UNREGISTER" para baja de clientes.
