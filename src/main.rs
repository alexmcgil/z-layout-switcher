use std::{
    collections::{HashMap, HashSet},
    env,
    error::Error,
    io::{Read, Write},
    process::{Command, Stdio},
};
use xkbcommon::xkb;

fn command(name: &str, args: &[&str]) -> Result<Vec<u8>, Box<dyn Error>> {
    let output = Command::new(name).args(args).output()?;
    if !output.status.success() {
        return Err(format!("{name} failed: {}", String::from_utf8_lossy(&output.stderr)).into());
    }
    Ok(output.stdout)
}

fn run() -> Result<(), Box<dyn Error>> {
    let mut layouts = None;
    let mut variants = "".to_owned();
    let mut options = "".to_owned();
    let mut from = None;
    let mut dry_run = false;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--layouts" => layouts = Some(args.next().ok_or("--layouts needs a value")?),
            "--variants" => variants = args.next().ok_or("--variants needs a value")?,
            "--options" => options = args.next().ok_or("--options needs a value")?,
            "--from" => {
                from = Some(
                    args.next()
                        .ok_or("--from needs an index")?
                        .parse::<usize>()?,
                )
            }
            "--dry-run" => dry_run = true,
            "--help" | "-h" => {
                println!("Usage: z-layout-switcher --layouts us,ru [--variants ,] [--options grp:caps_toggle] [--from INDEX] [--dry-run]\nSelect text, then run to replace it using the next XKB layout. --dry-run reads stdin and prints the result.");
                return Ok(());
            }
            _ => return Err(format!("unknown argument: {arg}").into()),
        }
    }
    let layouts = layouts.ok_or("--layouts is required")?;
    let count = layouts.split(',').count();
    if count < 2 || layouts.split(',').any(str::is_empty) {
        return Err("--layouts needs at least two XKB layout names".into());
    }

    let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
    let keymap = xkb::Keymap::new_from_names(
        &context,
        "",
        "",
        &layouts,
        &variants,
        Some(options),
        xkb::COMPILE_NO_FLAGS,
    )
    .ok_or("failed to compile XKB keymap")?;
    if keymap.num_layouts() as usize != count {
        return Err("XKB did not compile every requested layout".into());
    }

    let input = if dry_run {
        let mut value = String::new();
        std::io::stdin().read_to_string(&mut value)?;
        value
    } else {
        String::from_utf8(command("wl-paste", &["--primary"])?)?
    };
    if input.is_empty() {
        return Err("no text in PRIMARY selection".into());
    }
    let source = match from {
        Some(index) if index < count => index,
        Some(_) => return Err("--from index is outside --layouts".into()),
        None if dry_run => 0,
        None => detect_source(&keymap, &input)
            .or_else(|| niri_current_layout(count))
            .ok_or("cannot detect source layout; pass --from INDEX")?,
    };
    let target = (source + 1) % count;
    let output = convert(&keymap, source as u32, target as u32, &input);
    if output == input {
        return Err("selection has no characters that change between these layouts".into());
    }
    if dry_run {
        print!("{output}");
        return Ok(());
    }
    let mut child = Command::new("wl-copy")
        .args(["--primary", "--type", "text/plain;charset=utf-8"])
        .stdin(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .take()
        .ok_or("wl-copy stdin unavailable")?
        .write_all(output.as_bytes())?;
    if !child.wait()?.success() {
        return Err("wl-copy failed".into());
    }
    command(
        "wtype",
        &["-s", "200", "-M", "shift", "-k", "Insert", "-m", "shift"],
    )?;
    Ok(())
}

fn niri_current_layout(count: usize) -> Option<usize> {
    let state: serde_json::Value =
        serde_json::from_slice(&command("niri", &["msg", "-j", "keyboard-layouts"]).ok()?).ok()?;
    if state["names"].as_array()?.len() != count {
        return None;
    }
    let index = state["current_idx"].as_u64()? as usize;
    (index < count).then_some(index)
}

fn detect_source(keymap: &xkb::Keymap, input: &str) -> Option<usize> {
    let sets: Vec<HashSet<char>> = (0..keymap.num_layouts())
        .map(|layout| {
            let mut chars = HashSet::new();
            keymap.key_for_each(|map, key| {
                for level in 0..2 {
                    for symbol in map.key_get_syms_by_level(key, layout, level) {
                        let text = xkb::keysym_to_utf8(*symbol);
                        if text.chars().count() == 1 {
                            chars.insert(text.chars().next().unwrap());
                        }
                    }
                }
            });
            chars
        })
        .collect();
    let scores: Vec<usize> = sets
        .iter()
        .enumerate()
        .map(|(index, chars)| {
            input
                .chars()
                .filter(|c| {
                    chars.contains(c)
                        && sets
                            .iter()
                            .enumerate()
                            .all(|(other, set)| other == index || !set.contains(c))
                })
                .count()
        })
        .collect();
    let maximum = *scores.iter().max()?;
    if maximum == 0 || scores.iter().filter(|&&score| score == maximum).count() != 1 {
        return None;
    }
    scores.iter().position(|&score| score == maximum)
}

fn convert(keymap: &xkb::Keymap, source: u32, target: u32, input: &str) -> String {
    let mut mapping = HashMap::new();
    keymap.key_for_each(|map, key| {
        for level in 0..2 {
            let from = map.key_get_syms_by_level(key, source, level);
            let to = map.key_get_syms_by_level(key, target, level);
            if from.len() == 1 && to.len() == 1 {
                let left = xkb::keysym_to_utf8(from[0]);
                let right = xkb::keysym_to_utf8(to[0]);
                if left.chars().count() == 1 && right.chars().count() == 1 {
                    mapping.entry(left.chars().next().unwrap()).or_insert(right);
                }
            }
        }
    });
    input
        .chars()
        .map(|c| mapping.get(&c).cloned().unwrap_or_else(|| c.to_string()))
        .collect()
}

fn main() {
    if let Err(error) = run() {
        eprintln!("z-layout-switcher: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn converts_physical_keys_both_ways() {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap =
            xkb::Keymap::new_from_names(&context, "", "", "us,ru", "", None, xkb::COMPILE_NO_FLAGS)
                .unwrap();
        assert_eq!(convert(&keymap, 0, 1, "ghbdtn"), "привет");
        assert_eq!(convert(&keymap, 1, 0, "руддщ"), "hello");
        assert_eq!(detect_source(&keymap, "ghbdtn"), Some(0));
        assert_eq!(detect_source(&keymap, "руддщ"), Some(1));
    }
}
