import std/asyncdispatch
import std/os
export os

## Windows stuff
when defined(windows):
    import winim/lean


proc startNativeEventLoop*() {.async.} =
    ##
    ## Runs the Windows event loop in a manner that's compatible with async dispatch. Stops when WM_QUIT is received.
    ## 

    # More planned, but for now stop if not on Windows
    when not defined(windows):
        return
    else:

        # Only allow it to run once at a time
        var isRunning {.global.} = false
        if isRunning: return
        isRunning = true

        # Catch errors
        try:

            # Loop until WM_QUIT is received
            var msg: MSG
            while true:

                # Get the next message
                var peekResult = PeekMessage(msg, 0, 0, 0, PM_REMOVE)
                if peekResult == 0:

                    # No message received, yield to asyncdispatch
                    await sleepAsync(1)
                    continue

                # Dispatch the message
                TranslateMessage(msg)
                DispatchMessage(msg)

                # Check for WM_QUIT
                if msg.message == WM_QUIT: 
                    break

        finally:

            # No longer running
            isRunning = false
