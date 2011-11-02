
# Ball Machine
a small command-line tool to load and run a Quartz Composer composition off-screen

### GENERAL
- the canvas size, max framerate and input key:value pairs (as heavily escaped JSON) can be defined through a command-line arguments

### EXAMPLE
% ballmachine ~/ProjectX/MoviePlayer.qtz --canvas-size 1920x1080 --max-framerate 60 --inputs "'{\"Movie_Source\": \"http://trailers.apple.com/movies/paramount/adventuresoftintin/tintin-tlr1_r640s.mov\", \"Volume\": 0.333}'"

### THANKS
- Anton Marini (vade) for [Syphon](http://syphon.v002.info/) and perpetual help even when i don't deserve it
- Mike Ash for his timing hints from [MABGTimer.m](https://github.com/mikeash/MABGTimer/blob/master/Source/MABGTimer.m)
