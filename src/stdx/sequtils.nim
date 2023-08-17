import std/sequtils
export sequtils


proc findIf* [T] (s: openarray[T], pred: proc(it: T): bool): T =
    ##
    ## Find an item using a predicate. Returns null if not found.
    ## 

    for item in s:
        if pred(item):
            return item
    return cast[T](0)


proc findIf* [T] (s: openarray[T], pred: proc(it: T, idx : int): bool): T =
    ##
    ## Find an item using a predicate. Returns null if not found.
    ## 

    for idx, item in s:
        if pred(item, idx):
            return item
    return cast[T](0)


proc findIndexIf* [T] (s: openarray[T], pred: proc(it: T): bool): int =
    ##
    ## Find an item's index using a predicate. Returns null if not found.
    ## 

    for idx, item in s:
        if pred(item):
            return idx
    return -1


proc findIndexIf* [T] (s: openarray[T], pred: proc(it: T, idx : int): bool): int =
    ##
    ## Find an item's index using a predicate. Returns null if not found.
    ## 

    for idx, item in s:
        if pred(item, idx):
            return idx
    return -1


template findIt* [T] (s: openarray[T], pred: untyped) : T = 
    ##
    ## Find an item inside a sequence using a predicate. Returns `nil` if not found.
    ## 

    findIf(s, proc(it {.inject.} : T, idx {.inject.} : int) : bool = pred)


template indexIt* [T] (s: openarray[T], pred: untyped) : int = 
    ##
    ## Find an item inside a sequence using a predicate, and return it's index. Returns `-1` if not found.
    ## 
    
    findIndexIf(s, proc(it {.inject.} : T, idx {.inject.} : int) : bool = pred)


## Get the requested index, or return the default value if out of bounds.
proc getOrDefault* [T] (this: openarray[T], idx: int, default: T = nil): T =
    if idx < 0: return default
    if idx >= this.len: return default
    else: return this[idx]


proc allZero* [T] (data : openarray[T]) : bool =
    ##
    ## Check if a sequence of items is filled with zero or null data.
    ##

    for i in 0 ..< data.len:
        if data[i] != 0: return false

    return true


proc allZero* (data : string) : bool =
    ##
    ## Check if a string is filled with null bytes.
    ##

    for i in 0 ..< data.len:
        if data[i] != 0.char: return false

    return true