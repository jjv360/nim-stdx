import system/memory
import std/strutils
export strutils


proc newString*(len : Natural, filledWith : char | byte | int8 | uint8) : string =
    ##
    ## Creates a new string and fills it with the specified character.
    ## 
    
    # Create uninitialized string
    var s = newString(len)

    # Set memory
    if len > 0:
        nimSetMem(s[0].addr, filledWith.cint, len)

    # Done
    return s