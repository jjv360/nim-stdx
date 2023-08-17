import std/asyncdispatch
import std/uri
import std/strutils
import std/times
import std/httpclient
export httpclient

## Download callback
type AsyncHttpClientDownloadCallback* =
    proc(savedBytes : uint64, totalBytes : uint64)

proc downloadFile*(client : AsyncHttpClient, url : Uri | string, filename : string, callback : AsyncHttpClientDownloadCallback) {.async.} =
    ##
    ## Download a file asynchronously to the specified location, and return process inside a callback.
    ## Note that the `totalBytes` could be 0 if the size is unknown.
    ## 

    # Open URL
    var req = await client.request(url)

    # Get response code
    var statusCode = 0
    let statusCodeIdx = req.status.find(' ')
    if statusCodeIdx >= 0:
        statusCode = req.status[0 ..< statusCodeIdx].parseInt()
    if statusCode < 200 or statusCode >= 400:
        raise newException(IOError, "HTTP error " & req.status)

    # Open file for writing, and close it when this function ends
    let file = open(filename, fmWrite)
    defer: close(file)

    # Try get file size
    var totalSize : uint64 = 0
    try:
        totalSize = req.headers["Content-Length"].parseUInt()
    except:
        discard
    
    # Get response and send to file
    var amountRead : uint64 = 0
    var lastProgressUpdate = 0.0
    while true:

        # Read next batch of data
        var ( gotData, newData ) = await req.bodyStream.read()
        if not gotData:
            break

        # Append to file
        file.write(newData)
        amountRead += newData.len.uint64

        # Notify progress if enough time has passed
        let now = cpuTime()
        if now - lastProgressUpdate > 0.2:
            lastProgressUpdate = now
            callback(amountRead, totalSize)