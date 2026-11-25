# Se incluye con `source` al principio de los scripts que abren la app de Linux (tests de integración y capturas):
# vuelve a lanzar el script entero en una pantalla virtual (Xvfb), así la ventana no aparece en ningún monitor.
#   VER=1 <script>  -> la ventana se ve, como antes
# Si no está xvfb-run (paquete xvfb), sigue en la pantalla de siempre.
if [ -z "$VYNOTE_XVFB" ] && [ "${VER:-0}" != 1 ] && command -v xvfb-run >/dev/null 2>&1; then
  export VYNOTE_XVFB=1 GDK_BACKEND=x11
  exec xvfb-run -a -s "-screen 0 2560x1600x24" "$0" "$@"
fi
