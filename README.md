# Nim Extras (`stdx`)

This is a library of extra utility functions for the Nim standard library. Each extension to the standard lib is named after the module it extends, and is placed in the `stdx` package. It also exports the standard lib package, so you only need to replace `std` with `stdx`. For example, to use extra `seq` utils, you would do:

```nim
# Instead of this
import std/sequtils

# Do this
import stdx/sequtils
```

You can install `stdx` by running `nimble install stdx`

## Why this?

Because I keep finding myself adding little one-line functions to my projects, and I'm tired of copy-pasting them around. So why not wrap them all up into a single package?

## API Reference

### `stdx/asyncdispatch`

- `awaitThread()`

    Runs the clode block in a new thread and waits for it to finish with asyncdispatch. The specified vars are copied to the thread and are copied back afterwards.

    ```nim
    # Captured vars
    var myVar = 0

    # Run the thread and `await` it
    awaitThread(myVar):
        myVar = 1

    # Results are copied back
    echo myVar # 1
    ```

### `stdx/dynlib`

- `dynamicImport()`

    Allows you to dynamically import functions from a shared library. The library will only be loaded the first time
    one of the functions is called.

    If a function can't be loaded, or the lib was not found, it will throw a standard Nim error when it's called.

    > **Extra pragmas:**
    >
    > - `importc` pragma can be used to specify the name of the function to include, if it's different from the Nim proc name.
    > - `winapiOrdinal` pragma can be used to load a function by it's ordinal number. _(Windows only)_
    > - `winapiVersion` pragma can be used to fail if the current Windows version doesn't match. Can either be a single number in Major.Minor.Build format, or two versions separated by `-` to include all versions between them excluding the last one. See [here](https://en.wikipedia.org/wiki/List_of_Microsoft_Windows_versions) for a list of Windows versions and [here](https://github.com/euantorano/semver.nim) for the semver comparison lib used. _(Windows only)_

    ```nim
    # Import functions from an existing library on the system or next to the binary
    dynamicImport("user32.dll"):
        proc MessageBoxW(hWnd : uint, lpText : cstring, lpCaption : cstring, uType : uint) : int {.stdcall.}

    # Import functions from a library that will be embedded inside your application
    # Also optionally specify the name of the function to import
    dynamicImportFromData("mylib.dll", staticRead("mylib.dll")):
        proc MyFunction() {.stdcall, importc:"MyLib_MyFunction".}

    # Special case for Windows, load via ordinal number and limit to specific Windows versions
    dynamicImport("uxtheme.dll"):
        proc SetPreferredAppMode(mode : int) {.stdcall, winapiOrdinal: 135, winapiVersion: "10.0.17763".}
    ```

### `stdx/httpclient`

- `downloadFile()` with progress updates

    Asynchronously download a file from a URL, with progress callbacks.

    ```nim
    await newAsyncHttpClient().downloadFile(
        "https://example.com/file.txt", 
        "file.txt", 
        proc(currentBytes : uint64, totalBytes : uint64) =
            echo "Downloaded ", currentBytes, " of ", totalBytes, " bytes"
    )
    ```

### `stdx/os`

- `startNativeEventLoop()` with async support

    Starts the system event loop (ie GetMessage/TranslateMessage/DispatchMessage on Windows) in a way that's compatible with asyncdispatch. If it's called multiple times, it will still only start the loop once.

    ```nim
    # Start the loop in parallel
    asyncCheck startNativeEventLoop()

    # Ensure asyncdispatch is running
    drain(int.high)
    ```


### `stdx/osproc`

- `exec()`, `execElevated()`, `execAsync()`, `execElevatedAsync()`

    Executes a command and raises an error if the process exited with a non-zero exit code. The exe name and args must be provided individually. This comes in a few flavors:

    - `exec` - Standard run.
    - `execElevated` - Run with admin privileges. _(Windows only)_
    - `execAsync` - Run asynchronously.
    - `execElevatedAsync` - Run asynchronously with admin privileges. _(Windows only)_

    <br/>

    > **Note:** On Windows, it's impossible to attach to the stdout/stderr streams of a higher-level process, so you won't see the output from elevated commands.

    ```nim
    # Standard run
    exec "notepad", "file.txt"

    # Elevated run
    execElevated "notepad", "file.txt"

    # Run asynchronously
    await execAsync("notepad", "file.txt")

    # Run elevated command asynchronously
    await execElevatedAsync("notepad", "file.txt")
    ```

### `stdx/sequtils`

- `findIt()`

    Find an item inside a sequence using a predicate. Returns `nil` if not found.

    ```nim
    var items = @[1, 2, 3, 4, 5]
    var item = items.findIt(it == 3)
    ```

- `indexIt()`

    Find an item inside a sequence using a predicate, and return it's index. Returns `-1` if not found.

    ```nim
    var items = @[1, 2, 3, 4, 5]
    var item = items.indexIt(it == 3)
    ```

- `allZero()`

    Returns true if all items in the `seq` are zeroed or null. Works with strings too.

    ```nim
    var items = @[0, 0, 0, 0, 0]
    if items.allZero:
        echo "All items are zero!"
    ```

### `stdx/strutils`

- `newString()` with filled bytes
    
    Creates a string of the specified length with all bytes set to a value.
    
    ```nim
    var str = newString(512, filledWith = 'A')
    ```