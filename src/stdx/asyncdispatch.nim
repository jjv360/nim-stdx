import std/macros
import std/asyncdispatch
export asyncdispatch



proc readLine*(fd : AsyncFD) : Future[string] {.async.} =
    ##
    ## Read a line of text from an async socket
    ## 

    # Loop and build string
    var line = ""
    while true:

        # Read next char
        let chr = await fd.recv(1)

        # Check if stream ended... If we have buffered data, still return it, otherwise just throw an error
        if chr.len == 0 and line.len > 0:
            return line
        elif chr.len == 0:
            raise newException(IOError, "Connection closed")
        elif chr.len >= 2:
            raiseAssert("Expected 1 byte, got " & $chr.len)     # <-- Should never happen

        # Check if got a newline
        if chr == "\n":
            break

        # Add char to buffer
        line &= chr

    # Done
    return line


# proc asyncThreadProc*(code : proc() {.thread.}) : Future[void] {.async.} =
#     ##
#     ## Run a procedure in a separate thread.
#     ## This example is literally in the docs, not sure why it's not part of the standard...
#     ## https://nim-lang.org/docs/system.html#example
#     ## 

#     # Create a channel to communicate with the thread
#     var channel : Channel[ref Exception]

#     # Start the thread
#     var thread : Thread[void]
#     thread.createThread(proc() {.thread, nimcall.} =

#         # Catch errors
#         try:

#             # Run their code
#             code()

#             # Send the successful result
#             channel.send(nil)

#         except:

#             # Send the error
#             var err = getCurrentException()
#             channel.send(err)

#     )

#     # Wait for thread to finish
#     var outputError : ref Exception = nil
#     while true:

#         # Check if done
#         let state = channel.tryRecv()
#         if state.dataAvailable:
#             outputError = state.msg
#             break

#         # Not done yet, wait a bit
#         await sleepAsync(10)

#     # Wait for the thread to clean up
#     thread.joinThread()

#     # Close the channel
#     channel.close()

#     # Check result
#     if outputError != nil:
#         raise outputError


# proc asyncThreadProc* [T] (code : proc() : T {.thread.}) : Future[T] {.async.} =
#     ##
#     ## Run a procedure in a separate thread with a result type.
#     ## This example is literally in the docs, not sure why it's not part of the standard...
#     ## https://nim-lang.org/docs/system.html#example
#     ## 
    
#     # Async thread result type
#     type AsyncThreadResultType = object
#         error : ref Exception
#         result : T

#     # Create a channel to communicate with the thread
#     var channelOut : Channel[AsyncThreadResultType]

#     # Start the thread
#     var thread : Thread[void]
#     thread.createThread(proc() {.thread.} =

#         # Catch errors
#         try:

#             # Run their code
#             var output : AsyncThreadResultType
#             output.result = code()

#             # Send the successful result
#             channel.send(output)

#         except:

#             # Send the error
#             var output : AsyncThreadResultType
#             output.error = getCurrentException()
#             channel.send(output)

#     )

#     # Wait for thread to finish
#     var output : AsyncThreadResultType
#     while true:

#         # Check if done
#         let state = channel.tryRecv()
#         if state.dataAvailable:
#             output = state.msg
#             break

#         # Not done yet, wait a bit
#         await sleepAsync(10)

#     # Wait for the thread to clean up
#     thread.joinThread()

#     # Close the channel
#     channel.close()

#     # Check result
#     if output.error != nil:
#         raise output.error
#     else:
#         return output.result


# template asyncThread* [T] (code : untyped) : untyped =
#     ##
#     ## Run a procedure in a separate thread.
#     ## This example is literally in the docs, not sure why it's not part of the standard...
#     ## https://nim-lang.org/docs/system.html#example
#     ## 
    
#     asyncThreadProc[T](proc() : T {.thread.} = code)


proc stdx_processAwaitThread(capturedSymbols : seq[NimNode], codeBlock : NimNode) : NimNode =
    ##
    ## Processes the code for the 'awaitThread' macros. The process for this is to generate code which captures
    ## the specified variables, copies them over to the thread via a Channel, and then runs the code in the thread.
    ## After that, it will await the thread result, and copy the modifiable vars back over to the parent thread.
    ## 
    
    echo "===> stdx_processAwaitThread()"
    for s in capturedSymbols: 
        echo "Var: " & $s 
        echo " - Symbol kind: " & $s.symKind
        echo " - Type: " & s.getTypeInst().repr

    # Create statement list
    var outputCode = newStmtList()

    # Create definition of the data passing var. This is a tuple that contains an error field and the captured vars.
    var DataType = genSym(nskType, "AsyncThreadDataType")
    var typeDefinition = quote do:
        type `DataType` = tuple[err : ref Exception]
    for capturedSymbol in capturedSymbols:
        var tupleField = newNimNode(nnkIdentDefs, capturedSymbol)
        tupleField.add(ident($capturedSymbol))
        tupleField.add(capturedSymbol.getTypeInst())
        tupleField.add(newEmptyNode())
        typeDefinition[0][2].add(tupleField)
    outputCode.add(typeDefinition)

    # Create the channel var
    var channelOutVar = genSym(nskVar, "awaitThreadChannelOut")
    var channelInVar = genSym(nskVar, "awaitThreadChannelIn")
    outputCode.add(quote do:
        var `channelOutVar` : Channel[`DataType`]
        var `channelInVar` : Channel[`DataType`]
    )

    # Create the thread var
    var threadVar = genSym(nskVar, "awaitThreadThread")
    outputCode.add(quote do:
        var `threadVar` : Thread[void]
    )

    # Build the data payload with the current var content and send to the thread

    # Create thread code
    outputCode.add(quote do:
        `threadVar`.createThread(proc() {.thread, nimcall.} =

            # Catch errors
            try:

                # Extract vars so they appear the same in the user's code
                var output : `DataType`
                PULL_VARS   # <-- Will be replaced later
                
                # Run their code
                `codeBlock`

                # Send result back
                PUSH_VARS   # <-- Will be replaced later
                `channelInVar`.send(output)

            except:

                # Capture error
                var output : `DataType`
                output.err = getCurrentException()
                `channelInVar`.send(output)

        )
    )


    # Done
    echo "Output code:"
    echo outputCode.repr
    echo ""
    return outputCode
    



macro awaitThread*(codeBlock: untyped) =
    ##
    ## Run a procedure in a separate thread and wait for it to finish. This variant has no captured vars.
    ## 

    # Process it
    return stdx_processAwaitThread(@[], codeBlock)


macro awaitThread*(capturedVars : varargs[typed], codeBlock: untyped) =
    ##
    ## Run a procedure in a separate thread and wait for it to finish. This variant captured the specified list of vars.
    ## 
    
    # List of supported symbol types that can be captured
    const capturableSymbolTypes = @[

        # Writable types
        nskVar,

        # Read only types
        nskConst,
        nskLet,
        nskParam,

    ]

    # Var list
    var capturedSymbols : seq[NimNode]
    for v in capturedVars:

        # Ensure it's a symbol
        if v.kind != nnkSym: error("You can only pass vars to be captured in awaitThread(). Got " & $v.kind, v)
        if capturableSymbolTypes.find(v.symKind) == -1: error("You can only pass vars to be captured in awaitThread(). Got " & $v.symKind, v)

        # Skip consts, since they can be accessed from thread procs already
        if v.symKind == nskConst: continue

        # Add it
        capturedSymbols.add(v)

    # Process it
    return stdx_processAwaitThread(capturedSymbols, codeBlock)