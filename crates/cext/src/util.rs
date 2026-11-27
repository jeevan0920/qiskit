// This code is part of Qiskit.
//
// (C) Copyright IBM 2026
//
// This code is licensed under the Apache License, Version 2.0. You may
// obtain a copy of this license in the LICENSE.txt file in the root directory
// of this source tree or at https://www.apache.org/licenses/LICENSE-2.0.
//
// Any modifications or derivative works of this code must retain this
// copyright notice, and modified files need to carry a notice indicating
// that they have been altered from the originals.

use std::ffi::{CStr, CString};
use std::path::PathBuf;

/// Convert the `utf8` string into an owned [`CString`], replacing any interior nul bytes with a
/// literal two-byte `\0` marker.
pub fn cstring_from_utf8_lossy(utf8: impl Into<String>) -> CString {
    #[expect(clippy::disallowed_methods, reason = "this _is_ the helper")]
    match CString::new(utf8.into()) {
        Ok(out) => out,
        Err(e) => {
            // SAFETY: `e.into_vec()` reproduces `utf8.into()`, which was a `String` and therefore
            // valid UTF-8.
            let msg = unsafe { String::from_utf8_unchecked(e.into_vec()) };
            // SAFETY: the `msg.replace` call replaces all interior nul bytes with `\\0`.
            unsafe { CString::from_vec_unchecked(msg.replace("\0", "\\0").into_bytes()) }
        }
    }
}

/// Convert the bytes of a C string into the path they denote, without requiring them to be valid
/// UTF-8.
///
/// A path is not text, so it is built in the platform's own representation rather than by first
/// decoding a string: on Unix a path is an arbitrary sequence of non-nul bytes, which is accepted
/// verbatim.  On Windows the native representation is UTF-16 and a `char *` is read as UTF-8, so
/// bytes that are not valid UTF-8 have no unambiguous meaning and produce `None`.
pub fn path_from_c_str(path: &CStr) -> Option<PathBuf> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Some(PathBuf::from(std::ffi::OsStr::from_bytes(path.to_bytes())))
    }
    #[cfg(not(unix))]
    {
        std::str::from_utf8(path.to_bytes()).ok().map(PathBuf::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cstring_from_string_with_interior_nuls() {
        assert_eq!(c"hello\\0world", &*cstring_from_utf8_lossy("hello\0world"),);
        assert_eq!(
            c"\\0how\\0are\\0we\\0doing?\\0",
            &*cstring_from_utf8_lossy("\0how\0are\0we\0doing?\0")
        );
    }

    #[cfg(unix)]
    #[test]
    fn path_from_c_str_is_not_limited_to_utf8() {
        use std::os::unix::ffi::OsStrExt;

        let path = path_from_c_str(c"inc-\xff").unwrap();
        assert_eq!(path.as_os_str().as_bytes(), b"inc-\xff");
    }
}
