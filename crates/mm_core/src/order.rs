//! Manga-friendly natural ordering.

use std::cmp::Ordering;
use std::iter::Peekable;
use std::str::Chars;

/// Compare strings in a natural order where digit runs are compared as numbers.
///
/// This keeps page names such as `page_2.jpg` before `page_10.jpg`.
#[must_use]
pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let mut left = a.chars().peekable();
    let mut right = b.chars().peekable();

    loop {
        match (left.peek().copied(), right.peek().copied()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(l), Some(r)) if l.is_ascii_digit() && r.is_ascii_digit() => {
                let l_digits = take_digit_run(&mut left);
                let r_digits = take_digit_run(&mut right);
                let order = cmp_digit_runs(&l_digits, &r_digits);
                if order != Ordering::Equal {
                    return order;
                }
            }
            (Some(l), Some(r)) => {
                left.next();
                right.next();

                let insensitive = l.to_ascii_lowercase().cmp(&r.to_ascii_lowercase());
                if insensitive != Ordering::Equal {
                    return insensitive;
                }

                let exact = l.cmp(&r);
                if exact != Ordering::Equal {
                    return exact;
                }
            }
        }
    }
}

fn take_digit_run(chars: &mut Peekable<Chars<'_>>) -> String {
    let mut out = String::new();
    while let Some(ch) = chars.peek().copied() {
        if ch.is_ascii_digit() {
            out.push(ch);
            chars.next();
        } else {
            break;
        }
    }
    out
}

fn cmp_digit_runs(left: &str, right: &str) -> Ordering {
    let left_trimmed = trim_leading_zeroes(left);
    let right_trimmed = trim_leading_zeroes(right);

    match left_trimmed.len().cmp(&right_trimmed.len()) {
        Ordering::Equal => {}
        order => return order,
    }

    match left_trimmed.cmp(right_trimmed) {
        Ordering::Equal => left.len().cmp(&right.len()),
        order => order,
    }
}

fn trim_leading_zeroes(value: &str) -> &str {
    let trimmed = value.trim_start_matches('0');
    if trimmed.is_empty() {
        "0"
    } else {
        trimmed
    }
}

#[cfg(test)]
mod tests {
    use super::natural_cmp;

    #[test]
    fn orders_simple_page_numbers() {
        let mut pages = vec!["page_10.jpg", "page_2.jpg", "page_1.jpg", "page_20.jpg"];
        pages.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(pages, vec!["page_1.jpg", "page_2.jpg", "page_10.jpg", "page_20.jpg"]);
    }

    #[test]
    fn orders_mixed_chapter_names() {
        let mut pages = vec!["ch1_p10.jpg", "ch1_p2.jpg", "ch2_p1.jpg", "ch1_p1.jpg"];
        pages.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(pages, vec!["ch1_p1.jpg", "ch1_p2.jpg", "ch1_p10.jpg", "ch2_p1.jpg"]);
    }

    #[test]
    fn handles_large_numbers_without_overflow() {
        let mut pages = vec![
            "page_999999999999999999999999999999.jpg",
            "page_1000000000000000000000000000000.jpg",
            "page_2.jpg",
        ];
        pages.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(
            pages,
            vec![
                "page_2.jpg",
                "page_999999999999999999999999999999.jpg",
                "page_1000000000000000000000000000000.jpg",
            ],
        );
    }
}
