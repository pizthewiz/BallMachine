
# Ball Machine
a small command-line tool to load and run a Quartz Composer composition for Mac OS X 10.7

### GENERAL
- the canvas size, max framerate and input key:value pairs (as heavily escaped JSON) can be defined through a command-line arguments
- the composition input and output keys with minimum, maximum, default and current values (where applicable) can be printed via the --print-attributes switch
- by default the composition is rendered off screen, but the --display switch can present the composition full screen on a given display. when the presentation mode is used, the canvas size argument is ignored and the display's native size is used and the maximum framerate argument is ignored in favor of the display's native refresh rate. if no display unit number is provided, the main display will be used. when an unaccelerated display is selected, the float software renderer is used, otherwise a hardware renderer with [multisample anti-aliasing](http://en.wikipedia.org/wiki/Multisample_anti-aliasing).
- the tool can be run in a 'gui' mode which renders off screen but provides a connection to the window server, which some plug-ins may require
- while in presentation mode, the cursor is hidden, idle sleep is disabled for all displays and the window level is set to hide alerts. the application can be quit with command-q or changed via the application switcher.

### EXAMPLE
to render directly to a display:

    % ballmachine ~/ProjectX/MoviePlayer.qtz --inputs "'{\"Movie_Source\": \"http://trailers.apple.com/movies/paramount/adventuresoftintin/tintin-tlr1_r640s.mov\", \"Volume\": 0.8}'" --plugin-path ~/ProjectX/PlugIns --display
to render offline:

    % ballmachine ~/ProjectY/ProcessToSyphon.qtz --canvas-size 1920x1080 --max-framerate 60 --inputs "'{\"Live_Image_Directory\": \"~/ProjectY/Images\", \"Debug\": 1}'" --plugin-path ~/ProjectY/PlugIns

### THANKS
- Anton Marini (vade) for [Syphon](http://syphon.v002.info/), [QCPlayerPlus](http://sourceforge.net/projects/qcadvancedplaye/) and perpetual help, even when undeserved
- Mike Ash for his GCD Timer [MABGTimer](https://github.com/mikeash/MABGTimer/)
