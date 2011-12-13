
# Ball Machine
a small command-line tool to load and run a Quartz Composer composition off-screen for Mac OS X 10.7

### GENERAL
- the canvas size, max framerate and input key:value pairs (as heavily escaped JSON) can be defined through a command-line arguments
- the composition input and output keys and default, minimum and maximum can be printed via the --print-attributes switch
- the tool can be run in an alternate GUI mode to provide a connection to the window server which some plug-ins may require

### EXAMPLE
% ballmachine ~/ProjectX/MoviePlayer.qtz --canvas-size 1920x1080 --max-framerate 60 --inputs "'{\"Movie_Source\": \"http://trailers.apple.com/movies/paramount/adventuresoftintin/tintin-tlr1_r640s.mov\", \"Volume\": 0.333}'" --plugin-path ~/ProjectX/PlugIns

### THANKS
- Anton Marini (vade) for [Syphon](http://syphon.v002.info/) and perpetual help, even when undeserved
- Mike Ash for his GCD Timer [MABGTimer](https://github.com/mikeash/MABGTimer/)
