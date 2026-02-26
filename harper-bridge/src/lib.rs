use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

use harper_core::linting::{LintGroup, Linter};
use harper_core::{Dialect, Document, FstDictionary};
use serde::Serialize;

#[derive(Serialize)]
struct LintResult {
    word: String,
    start: usize,
    end: usize,
    kind: String,
    message: String,
    suggestions: Vec<String>,
}

/// Lint the given text and return a JSON array of issues.
/// Caller must free the returned string with `harper_free_string`.
#[no_mangle]
pub extern "C" fn harper_lint(text: *const c_char) -> *mut c_char {
    if text.is_null() {
        return to_c_string("[]");
    }

    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return to_c_string("[]"),
    };

    let dictionary = Arc::new(FstDictionary::curated());
    let document = Document::new_plain_english(text_str, &dictionary);
    let mut lint_group = LintGroup::new_curated(dictionary.clone(), Dialect::American);
    let lints = lint_group.lint(&document);

    let source: Vec<char> = text_str.chars().collect();

    let mut results: Vec<LintResult> = Vec::new();

    for lint in &lints {
        let span = lint.span;

        // Bounds check
        if span.start >= source.len() || span.end > source.len() || span.start >= span.end {
            continue;
        }

        // Convert char span to byte offsets for NSRange (UTF-16 length) compatibility
        let start_byte: usize = source[..span.start].iter().collect::<String>().len();
        let end_byte: usize = source[..span.end].iter().collect::<String>().len();

        let word: String = source[span.start..span.end].iter().collect();

        let kind = format!("{:?}", lint.lint_kind);
        let kind_lower = if kind.contains("Spelling") {
            "spelling".to_string()
        } else if kind.contains("Capitalization") || kind.contains("Grammar") {
            "grammar".to_string()
        } else {
            "style".to_string()
        };

        let suggestions: Vec<String> = lint
            .suggestions
            .iter()
            .filter_map(|s| match s {
                harper_core::linting::Suggestion::ReplaceWith(chars) => {
                    Some(chars.iter().collect::<String>())
                }
                _ => None,
            })
            .collect();

        let message = lint.message.clone();

        results.push(LintResult {
            word,
            start: start_byte,
            end: end_byte,
            kind: kind_lower,
            message,
            suggestions,
        });
    }

    let json = serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

/// Free a string returned by `harper_lint`.
#[no_mangle]
pub extern "C" fn harper_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}
