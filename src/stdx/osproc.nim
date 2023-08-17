import ./dynlib
import std/os
import std/osproc
import std/asyncdispatch
when defined(windows):
    import winim/mean

# Export original
export osproc


## Winows exit code which means the process is still running
const STILL_ACTIVE = 259


proc exec*(args: varargs[string]) =
    ##
    ## Run a process and throw an error if it fails
    ## 

    # Run command
    let cmd = args.quoteShellCommand()
    let exitCode = execCmd(cmd)

    # Raise error if failed
    if exitCode != 0:
        raise newException(OSError, "Command '" & lastPathPart(args[0]) & "' failed with code " & $exitCode & ".")


proc execElevated*(args: varargs[string]) =
    ##
    ## Run a process as administrator and throw an error if it fails
    ## 
    
    # Currently windows-only
    when not defined(windows):
        raiseAssert("The execAdmin() function is only available on Windows currently.")

    # Prepare commands
    var exeName = args[0]
    var exeArgs : seq[string]
    if args.len >= 1:
        exeArgs = args[1 ..< ^0]

    # Run command
    var info : SHELLEXECUTEINFOW
    info.cbSize = info.sizeof.DWORD
    info.fMask = SEE_MASK_NO_CONSOLE or SEE_MASK_NOASYNC or SEE_MASK_NOCLOSEPROCESS
    info.lpVerb = "runas"
    info.lpFile = exeName
    info.lpParameters = exeArgs.quoteShellCommand
    info.nShow = SW_HIDE
    let success = ShellExecuteExW(info)
    if success == 0:
        raiseAssert("Failed to run '" & lastPathPart(exeName) & "' as administrator.")

    # Wait for the process to exit and get the error code
    var exitCode: DWORD
    WaitForSingleObject(info.hProcess, INFINITE)
    GetExitCodeProcess(info.hProcess, exitCode.addr)
    CloseHandle(info.hProcess)

    # Check if failed
    if exitCode != 0:
        raiseAssert("Command '" & lastPathPart(exeName) & "' failed with code " & $exitCode & ".")

        
proc execAsync*(args: seq[string]) {.async.} =
    ##
    ## Run a process and throw an error if it fails
    ## 

    # Run command
    let cmd = args.quoteShellCommand()
    let p = startProcess(cmd, workingDir = "", args = @[], env = nil, options = { poParentStreams, poStdErrToStdOut, poEvalCommand })

    # Wait for process to end
    while p.running: await sleepAsync(100)
    let exitCode = p.waitForExit()

    # Raise error if failed
    if exitCode != 0:
        raise newException(OSError, "Command '" & lastPathPart(args[0]) & "' failed with code " & $exitCode & ".")

        
proc execAsync*(args: varargs[string]) : Future[void] =
    ##
    ## Run a process and throw an error if it fails
    ## 
    
    # Capture args
    let a : seq[string] = args[0 ..< ^0]
    
    # Run it, return the promise
    return execAsync(a)
    




proc execElevatedAsync*(args: seq[string]) {.async.} =
    ##
    ## Run a process as administrator and throw an error if it fails
    ## 
    
    # Currently windows-only
    when not defined(windows):
        raiseAssert("The execAdmin() function is only available on Windows currently.")

    # Prepare commands
    var exeName = args[0]
    var exeArgs : seq[string]
    if args.len >= 1:
        exeArgs = args[1 ..< ^0]

    # Run command
    var info : SHELLEXECUTEINFOW
    info.cbSize = info.sizeof.DWORD
    info.fMask = SEE_MASK_NO_CONSOLE or SEE_MASK_NOASYNC or SEE_MASK_NOCLOSEPROCESS
    info.lpVerb = "runas"
    info.lpFile = exeName
    info.lpParameters = exeArgs.quoteShellCommand
    info.nShow = SW_HIDE
    let success = ShellExecuteExW(info)
    if success == 0:
        raiseAssert("Failed to run '" & lastPathPart(exeName) & "' as administrator.")

    # Wait for the process to exit and get the error code
    var exitCode: DWORD
    while true:

        # Check if still running
        GetExitCodeProcess(info.hProcess, exitCode.addr)

        # Wait a bit if still running
        if exitCode == STILL_ACTIVE:
            await sleepAsync(100)
        else:
            break

    # Close process handle
    CloseHandle(info.hProcess)

    # Check if failed
    if exitCode != 0:
        raiseAssert("Command '" & lastPathPart(exeName) & "' failed with code " & $exitCode & ".")

        
proc execElevatedAsync*(args: varargs[string]) : Future[void] =
    ##
    ## Run a process as administrator and throw an error if it fails
    ## 
    
    # Capture args
    let a : seq[string] = args[0 ..< ^0]
    
    # Run it, return the promise
    return execElevatedAsync(a)