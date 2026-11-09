// Native iOS C-archive bridge linked into SwiftUI.
// Compiled from within github.com/londek/ipadecrypt at a pinned commit.
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
    "encoding/hex"
    "encoding/json"
    "fmt"
    "os"
    "path/filepath"
    "unsafe"

    "github.com/londek/ipadecrypt/internal/fairplay"
    "github.com/londek/ipadecrypt/internal/pipeline"
)

func response(data map[string]any) *C.char {
    bytes, err := json.Marshal(data)
    if err != nil { return C.CString("{\"ok\":false,\"error\":\"JSON serialization failure\"}") }
    return C.CString(string(bytes))
}

//export IPADecryptVerify
func IPADecryptVerify(output *C.char, original *C.char) *C.char {
    if output == nil || original == nil {
        return response(map[string]any{"ok":false,"error":"source/output paths are required"})
    }
    out, src := C.GoString(output), C.GoString(original)
    if out == "" || src == "" || out == src {
        return response(map[string]any{"ok":false,"error":"source/output paths are missing or identical"})
    }
    result, err := pipeline.Verify(out, src, false)
    if err != nil {
        return response(map[string]any{"ok":false,"error":err.Error()})
    }
    verified := result.OK() && len(result.Skipped)==0 && len(result.Missing)==0 && result.Scanned>0 && result.Compared>0
    return response(map[string]any{
        "ok":verified, "scanned":result.Scanned, "compared":result.Compared,
        "still_encrypted":result.StillEncrypted, "all_zero":result.AllZeroCrypt,
        "skipped":result.Skipped, "missing":result.Missing,
        "mismatches":result.Mismatches,
    })
}

// The upstream offline decryptor is compiled into the IPA, but this API
// deliberately requires a matching 16-byte account credential.
// It cannot mint one through a pairing file, RSD, LocalDevVPN or worse_query.
//export IPADecryptOfflineWithCredential
func IPADecryptOfflineWithCredential(src *C.char, dst *C.char, keyHex *C.char) *C.char {
    if src == nil || dst == nil || keyHex == nil {
        return C.CString("input, output and authorized credential are required")
    }
    input, output := C.GoString(src), C.GoString(dst)
    if input == "" || output == "" || input == output {
        return C.CString("invalid input/output paths")
    }
    key, err := hex.DecodeString(C.GoString(keyHex))
    if err != nil || len(key) != 16 {
        return C.CString("credential must be exactly 16 bytes (32 hex digits)")
    }
    if _, err = os.Stat(output); err == nil {
        return C.CString("output exists; refusing to overwrite")
    } else if !os.IsNotExist(err) { return C.CString(err.Error()) }
    f, err := os.CreateTemp(filepath.Dir(output), ".ipadecrypt-*.ipa")
    if err != nil { return C.CString(err.Error()) }
    temp := f.Name()
    defer os.Remove(temp)
    _, err = fairplay.Decrypt(input, f, key, false)
    if e := f.Close(); err == nil { err = e }
    if err != nil { return C.CString(err.Error()) }
    verified, err := pipeline.Verify(temp, input, false)
    if err != nil { return C.CString(err.Error()) }
    if !verified.OK() || len(verified.Skipped)>0 || len(verified.Missing)>0 || verified.Compared==0 {
        return C.CString(fmt.Sprintf("upstream output verification failed: %+v",verified))
    }
    if err = os.Rename(temp, output); err != nil { return C.CString(err.Error()) }
    return C.CString("")
}

//export IPADecryptFreeString
func IPADecryptFreeString(s *C.char) {
    if s != nil { C.free(unsafe.Pointer(s)) }
}

func main() {}
