import std/macros
import std/sugar
export sugar

## Echo the expanded result of a block of code
macro dumpExpandedCode*(body : untyped) = 

    # Keep expanding code until it stops changing
    var code = body
    var codeTxt = body.repr
    for i in 0 ..< 10:

        # Log it
        echo ""
        echo "=== Code (expaned " & $i & " times) ==="
        echo codeTxt
        echo "==="
        echo ""

        # Expand it
        code = code.expandMacros()

        # Stop if unchanged
        var newCodeTxt = code.repr
        if newCodeTxt == codeTxt: break
        else: codeTxt = newCodeTxt

    # Done, return original code unmodified
    return body