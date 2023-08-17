import std/os
import std/tempfiles
import std/exitprocs
import std/dynlib
import std/macros
import std/strutils

# Export things that users of our macro need
export tempfiles, exitprocs, os, dynlib

## Custom pragma to mark a function that needs to be imported via a ordinal offset. This only works on Windows.
template winapiOrdinal*(ordinal: static[int], versionCheck: static[string]) {.pragma.}

## Custom pragma to fail if the current Windows version is outside of the specified range. This only works on Windows.
## Can specify either a single version (ie "10.0.17763") or two versions separated by "-".
template winapiVersion*(ordinal: static[int], versionCheck: static[string]) {.pragma.}

## Proc to get the current Windows version as a string.
## See: https://github.com/nim-lang/Nim/issues/11481#issuecomment-502156661
when defined(windows):
    import std/winlean
    import semver
    type
        USHORT = uint16
        WCHAR = distinct int16
        UCHAR = uint8
        NTSTATUS = int32

    type OSVersionInfoExW {.importc: "OSVERSIONINFOEXW", header: "<windows.h>".} = object
        dwOSVersionInfoSize: ULONG
        dwMajorVersion: ULONG
        dwMinorVersion: ULONG
        dwBuildNumber: ULONG
        dwPlatformId: ULONG
        szCSDVersion: array[128, WCHAR]
        wServicePackMajor: USHORT
        wServicePackMinor: USHORT
        wSuiteMask: USHORT
        wProductType: UCHAR
        wReserved: UCHAR

    proc rtlGetVersion(lpVersionInformation: var OSVersionInfoExW): NTSTATUS {.cdecl, importc: "RtlGetVersion", dynlib: "ntdll.dll".}

    proc stdxGetWindowsVersion() : string =
        var versionInfo: OSVersionInfoExW
        if rtlGetVersion(versionInfo) != 0: return ""
        return $versionInfo.dwMajorVersion & "." & $versionInfo.dwMinorVersion & "." & $versionInfo.dwBuildNumber

    ## Throws an error if the current Windows version is outside of the specified range.
    proc stdxCheckWindowsVersion*(requiredVersion : string) =

        # Get current Windows version
        let currentVersion = stdxGetWindowsVersion()

        # Check if it's a single or a range
        var startVersion = requiredVersion
        var endVersion = ""
        var versionRangeIdx = requiredVersion.find('-')
        if versionRangeIdx != -1:
            startVersion = requiredVersion[0 ..< versionRangeIdx].strip
            endVersion = requiredVersion[versionRangeIdx+1 ..< ^0].strip

        # Check if our version is equal or higher than the start version
        if currentVersion.v < startVersion.v:
            raise newException(OSError, "This function requires a later version of Windows. Windows version " & currentVersion & " is lower than required version " & startVersion)

        # Check if our version is lower than the end version
        if endVersion != "" and currentVersion.v >= endVersion.v:
            raise newException(OSError, "This function requires an earlier version of Windows. Windows version " & currentVersion & " is higher than maximum version " & endVersion)



## Replace defined procs with their dynamic loader versions
proc replaceProcsIn(statements: NimNode, loaderFunctionIdent: NimNode) =

    # Go through statements
    for idx, statement in statements:

        # Check type
        if statement.kind == nnkProcDef and statement.body.kind == nnkEmpty:

            # A proc without a body, this is what we're looking for...
            let procDef = statement
            let procName = procDef.name
            var procNameStr = $procName

            # Create the proc type definition
            let typeDef = newNimNode(nnkProcTy)
            typeDef.add(procDef.params)
            typeDef.add(procDef.pragma)

            # Remove importc:"" pragma if it exists, use it to replace the function name
            if typeDef.pragma.kind != nnkEmpty:
                for idx, pragma in typeDef.pragma:
                    if pragma.kind == nnkExprColonExpr and $pragma[0] == "importc":
                        procNameStr = $pragma[1]
                        typeDef.pragma.del(idx)
                        break

            # Look for the winapiOrdinal pragma
            var winapiOrdinal : int = -1
            if typeDef.pragma.kind != nnkEmpty:
                for idx, pragma in typeDef.pragma:
                    if pragma.kind == nnkExprColonExpr and $pragma[0] == "winapiOrdinal":
                        winapiOrdinal = pragma[1].intVal
                        typeDef.pragma.del(idx)
                        break

            # Look for the winapiVersion pragma
            var winapiVersion = ""
            if typeDef.pragma.kind != nnkEmpty:
                for idx, pragma in typeDef.pragma:
                    if pragma.kind == nnkExprColonExpr and $pragma[0] == "winapiVersion":
                        winapiVersion = $pragma[1]
                        typeDef.pragma.del(idx)
                        break

            # Set wrapper code for the function
            procDef.body = quote do:

                # Var to store the actual function pointer
                type FunctionType = `typeDef`
                var functionPointer {.global.} : FunctionType = nil

                # Load the function if it's not loaded already
                if functionPointer == nil:

                    # On Windows, if a version range was specified, check the range
                    when defined(windows) and `winapiVersion` != "":
                        stdxCheckWindowsVersion(`winapiVersion`)
                        
                    # Ensure the lib is loaded
                    let handle = `loaderFunctionIdent`()

                    # Get cstring with the proc name
                    var procNameStr : cstring = `procNameStr`
                    when defined(windows) and `winapiOrdinal` > 0:

                        # Use an ordinal instead
                        procNameStr = cast[cstring](`winapiOrdinal`)

                    # Load the function from the lib
                    let p = handle.symAddr(procNameStr)
                    functionPointer = cast[FunctionType](p)

                    # Stop if not found
                    if functionPointer == nil:
                        raise newException(OSError, "Unable to find dynamic function: " & `procNameStr`)

                # Done, call and return it
                return functionPointer()

            # Inject param names into the final return statement
            for idx2, param in procDef.params:

                # Ignore the first one (it's the return type)
                if idx2 == 0:
                    continue

                # Add it
                # echo "Adding " & param[0].treeRepr
                let returnStmt = procDef.body[procDef.body.len-1]
                let callStmt = returnStmt[0]
                callStmt.add(param[0])

            # If function doesn't have a return type, remove the "return" part of the last call
            if procDef.params[0].kind == nnkEmpty:
                procDef.body[procDef.body.len-1] = procDef.body[procDef.body.len-1][0]

        else:

            # Process children as well
            replaceProcsIn(statement, loaderFunctionIdent)
            


## Define proc's to import from a dynamic library. All defined proc's will attempt to load the library the first time they're called.
macro dynamicImport*(libName: static[string], code: untyped) =

    # Sanity checks
    if code.kind != nnkStmtList: error("Expected a statement list.", code)

    # Identifiers
    let loaderFunctionIdent = genSym(nskProc, "dynamicImportLoadLib")

    # Go through all defined procs and replace them
    replaceProcsIn(code, loaderFunctionIdent)

    # Export the loader function
    code.insert(0, quote do:
        
        ## Library loader
        proc `loaderFunctionIdent`(): LibHandle =

            # Stop if already loaded
            var handle {.global.} : LibHandle = nil
            if handle != nil:
                return handle

            # Load it
            handle = loadLib(`libName`)
            if handle == nil:
                raise newException(OSError, "Unable to load library: " & `libName`)

            # Done
            return handle
        
    )

    # Done
    return code


## Define proc's to import from an embedded dynamic library. This will save the lib to a temporary folder and load it from there.
macro dynamicImportFromData*(libName: static[string], libData: static[string], code: untyped) =

    # Sanity checks
    if code.kind != nnkStmtList: error("Expected a statement list.", code)

    # Identifiers
    let loaderFunctionIdent = genSym(nskProc, "dynamicImportLoadLib")

    # Go through all defined procs and replace them
    replaceProcsIn(code, loaderFunctionIdent)

    # Export the loader function
    code.insert(0, quote do:
        
        ## Library loader
        proc `loaderFunctionIdent`(): LibHandle =

            # Stop if already loaded
            var handle {.global.} : LibHandle = nil
            if handle != nil:
                return handle

            # Save the DLL to a temporary file
            const cpu = hostCPU
            let libTempPath = genTempPath("NimReactive", "_" & cpu & "_" & `libName`)
            writeFile(libTempPath, `libData`)

            # Delete the DLL on exit
            # TODO: Why would an exit proc not be GC-safe? The app is exiting, all memory will get removed anyway...
            {.gcsafe.}:
                addExitProc(proc() =

                    # Unload the DLL so the file is deletable
                    if handle != nil:
                        handle.unloadLib()

                    # Delete it
                    var didDelete = false
                    for i in 0 ..< 5:
                        if tryRemoveFile(libTempPath): 
                            didDelete = true
                            break
                        sleep(100)   # <-- Need to wait a bit for some reason, or else we can't delete it
                    if not didDelete:
                        echo "Unable to delete temporary file: " & libTempPath

                )

            # Load it
            handle = loadLib(libTempPath)
            if handle == nil:
                raise newException(OSError, "Unable to load library: " & `libName`)

            # Done
            return handle
        
    )

    # Done
    return code