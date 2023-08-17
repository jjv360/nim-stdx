import std/sequtils
import std/strutils
export strutils

## Array with convertible types
# type ConvertibleArrayString* = openarray[int8 | uint8 | int16 | uint16 | int32 | uint32 | int64 | uint64 | float32 | float64]


proc toString* (bytes: openarray[int8 | uint8]): string =
    ##
    ## Convert an array to a string of raw bytes.
    ## 

    let itemSize = bytes[0].sizeof
    if bytes.len == 0: return ""
    result = newString(bytes.len * itemSize)
    copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len * itemSize)


proc toBytes*(str: string): seq[byte] =
    ##
    ## Convert a string to a byte array with no zero terminator
    ## 
    
    # TODO: Why doesn't `openarray` work here?
    return str.toOpenArrayByte(0, str.len - 1).toSeq()