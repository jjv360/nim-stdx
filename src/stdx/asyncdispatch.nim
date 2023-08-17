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