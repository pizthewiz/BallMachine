
### NOW
- sort out how or if to throttle the display link
- cursor can be seen over content when not the active app
- consider using proper fullscreen and not friendly maxi-window

### LATER
- somehow calculate fps
- respect canvas size switch for online rendering
- respect max framerate for online rendering
- fetch display's native refresh rate when max framerate >=, use CVDisplayLink
- consider setting up offline context manually to enable MSAA
- add switch to accept JSON settings file
- look into a pure processing -[QCRenderer initWithComposition:colorSpace:]
- flip back to using a raw runloop once a [build of Syphon is released](http://code.google.com/p/syphon-implementations/downloads/list) that [no longer requires an NSApplication](http://code.google.com/p/syphon-framework/issues/detail?id=18)
- offer command-line option to load source composition inside Syphon Server composition
