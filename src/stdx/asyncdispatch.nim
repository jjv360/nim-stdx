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


proc stdx_processAwaitThread(capturedSymbols : seq[NimNode], codeBlock : NimNode) : NimNode =
    ##
    ## Processes the code for the 'awaitThread' macros. The process for this is to generate code which captures
    ## the specified variables, copies them over to the thread via a Channel, and then runs the code in the thread.
    ## After that, it will await the thread result, and copy the modifiable vars back over to the parent thread.
    ## 
    
    # Unique ident suffix
    var lastIdentSuffix {.global.} = 0
    lastIdentSuffix += 1
    let identSuffix = "_gen_" & $lastIdentSuffix
    
    # echo "===> stdx_processAwaitThread()"
    # for s in capturedSymbols: 
    #     echo "Var: " & $s 
    #     echo " - Symbol kind: " & $s.symKind
    #     echo " - Type: " & s.getTypeInst().repr

    # Var names used in multiple code blocks
    var errorVarName = ident("err" & identSuffix)
    var payloadVarName = ident("payload" & identSuffix)


    # Create definition of the data passing var. This is a tuple that contains an error field and the captured vars.
    var tupleTypeDefinition = quote do:
        tuple[`errorVarName` : ref Exception]
    for capturedSymbol in capturedSymbols:
        var tupleField = newNimNode(nnkIdentDefs, capturedSymbol)
        tupleField.add(ident($capturedSymbol))
        tupleField.add(capturedSymbol.getTypeInst())
        tupleField.add(newEmptyNode())
        tupleTypeDefinition.add(tupleField)

    # Create code to copy vars into the payload
    var varsCopyIn = newStmtList()
    varsCopyIn.add(quote do:
        `payloadVarName`.`errorVarName` = `errorVarName`
    )
    for capturedSymbol in capturedSymbols:
        let capturedSymbolIdent = ident($capturedSymbol)
        varsCopyIn.add(quote do:
            `payloadVarName`.`capturedSymbolIdent` = `capturedSymbolIdent`
        )

    # Create code to copy vars out of the payload and create new variables for them
    var varsCreateOut = newStmtList()
    varsCreateOut.add(quote do:
        var `errorVarName` = `payloadVarName`.`errorVarName`
    )
    for capturedSymbol in capturedSymbols:

        # Check if it's a writable type
        let capturedSymbolIdent = ident($capturedSymbol)
        if capturedSymbol.symKind == nskVar:

            # Create as a var
            varsCreateOut.add(quote do:
                var `capturedSymbolIdent` = `payloadVarName`.`capturedSymbolIdent`
            )

        else:

            # Create as a let
            varsCreateOut.add(quote do:
                let `capturedSymbolIdent` = `payloadVarName`.`capturedSymbolIdent`
            )

    # Create code to copy vars out of the payload into existing variables
    var varsCopyOut = newStmtList()
    varsCopyOut.add(quote do:
        `errorVarName` = `payloadVarName`.`errorVarName`
    )
    for capturedSymbol in capturedSymbols:

        # Check if it's a writable type
        let capturedSymbolIdent = ident($capturedSymbol)
        if capturedSymbol.symKind == nskVar:

            # Create as a var
            varsCopyOut.add(quote do:
                `capturedSymbolIdent` = `payloadVarName`.`capturedSymbolIdent`
            )

        else:

            # Skip it if it's not writable
            continue


    # Output code template
    var outputCode = quote do:

        # Create type definition, containing the error and captured vars
        type AwaitThreadDataPayload = `tupleTypeDefinition`

        # Create the channel var
        type DataChannel = Channel[AwaitThreadDataPayload]
        var channelInPtr = cast[ptr DataChannel](allocShared0(sizeof(DataChannel)))
        var channelOutPtr = cast[ptr DataChannel](allocShared0(sizeof(DataChannel)))

        # Open channel
        channelInPtr[].open()
        channelOutPtr[].open()
        
        # Build payload
        var `errorVarName` : ref Exception = nil 
        var `payloadVarName` : AwaitThreadDataPayload
        `varsCopyIn`

        # Send it
        channelInPtr[].send(`payloadVarName`)

        # Create thread (doing it this was to avoid the "cannot generate destructor for generic type: Thread" error)
        type DataThread = Thread[tuple[inPtr : ptr DataChannel, outPtr : ptr DataChannel]]
        var threadPtr = cast[ptr DataThread](allocShared0(sizeof(DataThread)))

        # Start the thread
        threadPtr[].createThread(proc(channels : tuple[inPtr : ptr DataChannel, outPtr : ptr DataChannel]) {.thread, nimcall.} =

            # Catch errors
            try:

                # Extract vars so they appear the same in the user's code
                var `payloadVarName` : AwaitThreadDataPayload = channels.inPtr[].recv()
                `varsCreateOut`
                
                # Run their code
                `codeBlock`

                # Send result back
                `varsCopyIn`
                channels.outPtr[].send(`payloadVarName`)
                
            except Exception:

                # Capture error and send it back
                var output : AwaitThreadDataPayload
                output.`errorVarName` = getCurrentException()
                channels.outPtr[].send(output)

        , (channelInPtr, channelOutPtr))

        # Wait for thread to finish
        while true:

            # Check if done
            let state = channelOutPtr[].tryRecv()
            if state.dataAvailable:
                `payloadVarName` = state.msg
                break

            # Not done yet, wait a bit
            await sleepAsync(1)

        # Wait for the thread to clean up
        threadPtr[].joinThread()

        # Close the channel
        channelInPtr[].close()
        channelOutPtr[].close()
        deallocShared(channelInPtr)
        deallocShared(channelOutPtr)
        deallocShared(threadPtr)

        # Check result
        if `payloadVarName`.`errorVarName` != nil:
            raise `payloadVarName`.`errorVarName`
        
        # Copy resulting vars back out to the source code
        `varsCopyOut`

    # Done
    # echo "Output code:"
    # echo outputCode.repr
    # echo ""
    return outputCode
    



macro awaitThread*(codeBlock: untyped) =
    ##
    ## Run a procedure in a separate thread and wait for it to finish. This variant has no captured vars.
    ## 

    # Process it
    return stdx_processAwaitThread(@[], codeBlock)


macro awaitThread*(capturedVars : varargs[typed], codeBlock: untyped) =
    ##
    ## Run a procedure in a separate thread and wait for it to finish. This variant captures the specified list of vars.
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