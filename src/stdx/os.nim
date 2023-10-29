import std/asyncdispatch
import std/os
import std/times
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
        static: echo "Warning: os.startNativeEventLoop() is not implemented on this platform."
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


proc cpuPercent*() : float =
    ##
    ## Gets the current CPU load in percent. This is always from 0% to 100% even in multi-core systems.
    ## 
    
    # More planned, but for now stop if not on Windows
    when not defined(windows):
        static: echo "Warning: os.cpuPercent() is not implemented on this platform."
        return 0.0
    else:

        # Last time this function was run. Since this function is dependent on the time between calls, let's just use the old value if it was called too quickly.
        var lastValue {.global.} : float = 0.0
        var lastTime {.global.} : float = 0.0
        let time = cpuTime()
        if time - lastTime < 0.5:
            return lastValue

        # Get the current CPU load
        var idleTimeStruct : FILETIME
        var kernelTimeStruct : FILETIME
        var userTimeStruct : FILETIME
        if GetSystemTimes(idleTimeStruct, kernelTimeStruct, userTimeStruct) == 0:
            return 0.0

        # Convert to a number
        let idleTime : uint64 = (idleTimeStruct.dwHighDateTime.uint64 shl 32) or idleTimeStruct.dwLowDateTime.uint64
        let kernelTime : uint64 = (kernelTimeStruct.dwHighDateTime.uint64 shl 32) or kernelTimeStruct.dwLowDateTime.uint64
        let userTime : uint64 = (userTimeStruct.dwHighDateTime.uint64 shl 32) or userTimeStruct.dwLowDateTime.uint64
        let totalTime = kernelTime + userTime

        # Store the difference since the last time this function was run
        var hasDoneFirstRun {.global.} = false
        var lastIdleTime {.global.} : uint64 = 0
        var lastTotalTime {.global.} : uint64 = 0
        let idleTimeDiff = idleTime - lastIdleTime
        let totalTimeDiff = totalTime - lastTotalTime
        lastIdleTime = idleTime
        lastTotalTime = totalTime

        # Note, the first time this function runs it will return some crazy number, so run it again after waiting a tiny bit
        if not hasDoneFirstRun:
            hasDoneFirstRun = true
            sleep(1)
            return cpuPercent()

        # Calculate the percent
        lastValue = min(100, (totalTimeDiff - idleTimeDiff).float / totalTimeDiff.float * 100)
        lastTime = time
        return lastValue


proc ramPercent*() : float =
    ##
    ## Gets the current RAM load in percent. This is always from 0% to 100%.
    ## 
    
    # More planned, but for now stop if not on Windows
    when not defined(windows):
        static: echo "Warning: os.ramPercent() is not implemented on this platform."
        return 0.0
    else:

        # Get info
        var status : MEMORYSTATUSEX
        status.dwLength = sizeof(status).DWORD
        if GlobalMemoryStatusEx(status) == 0:
            return 0.0

        # Return result
        return status.dwMemoryLoad.float