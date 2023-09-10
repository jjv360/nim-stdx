
## This whole module is only for Windows
when defined(windows):

    import winim/lean
    import std/asyncdispatch
    import std/winlean
    export winlean


    proc startWindowsEventLoop*() {.async.} =
        ##
        ## Runs the Windows event loop in a manner that's compatible with async dispatch. Stops when WM_QUIT is received.
        ## 
        
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



    proc getLastErrorString*(): string =
        ##
        ## Utility to get the last Win32 error as a string
        ## 

        # Get error code
        let err = getLastError()
        if err == 0:
            return ""

        # Create string buffer and retrieve the error text
        var str = newWString(1024)
        let strLen = FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, nil, err, windef.DWORD(MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT)), str, 1024, nil)
        if strLen == 0:

            # Unable to decode error code, just convert to hex so at least there's something
            return "Unknown WinAPI error 0x" & err.toHex()

        # Done
        return $str


    proc raiseLastError*(prefix : string = "") =
        ##
        ## Raise the latest Win32 error as an exception. Include the prefix string in the exception message.
        ## 
        raise newException(OSError, prefix & " WinAPI error: 0x" & getLastError().uint.toHex & " " & getLastErrorString())