TV VIDEO CONVERTER
==================

Versión 1.1.1

Incluye:
- Interfaz gráfica WinForms.
- Conversión por lotes.
- Perfil "TV vieja (predeterminado)" basado en el formato que funcionó en la TV del usuario.
- Perfiles para TV HD, TV 1080p60, Android/tablets, iPhone/iPad, web/redes, TV muy antigua 480p y HEVC.
- Personalización de resolución, FPS, códec, perfil, level, CRF, escalado, audio, bitrate, frecuencia de muestreo, canales, metadatos, FastStart y sufijo.
- Barra de progreso por archivo y total.
- Cancelación.
- Detección de FFmpeg portátil.
- Descarga automática del paquete FFmpeg Essentials si no se encuentra.
- Descarga en %LOCALAPPDATA%\TVVideoConverter\ffmpeg.
- Compatible con Windows PowerShell 5.1 y PS2EXE.

FFMPEG
------
La herramienta descarga el build Windows "release essentials" desde:
https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip

Se eligió este paquete porque la página de builds de Gyan indica que el essentials build contiene los componentes habituales de FFmpeg y que requiere Windows 10 o posterior.

EJECUTAR COMO PS1
-----------------
powershell -ExecutionPolicy Bypass -File .\TVVideoConverter.ps1

CREAR EXE
---------
1. Abre Windows PowerShell.
2. Ve a esta carpeta.
3. Ejecuta:
   powershell -ExecutionPolicy Bypass -File .\Build-EXE.ps1

El script instala PS2EXE para el usuario actual si hace falta y genera:
TVVideoConverter.exe

PS2EXE
------
El empaquetado está preparado para PS2EXE y usa un ejecutable GUI sin consola.
FFmpeg no se incrusta en el EXE; se usa una copia portable junto a la app o se descarga automáticamente.

ESTRUCTURA PORTÁTIL OPCIONAL
-----------------------------
TVVideoConverter.exe
ffmpeg\
  bin\
    ffmpeg.exe
    ffprobe.exe

Cuando la carpeta "ffmpeg" está junto al EXE, la aplicación la usa antes de descargar nada.

NOTA
----
La descarga automática requiere Internet durante el primer uso si no existe FFmpeg.
