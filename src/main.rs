use hidapi::HidApi;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::Duration;

const VENDOR_ID: u16 = 0x5131;
const PRODUCT_ID: u16 = 0x2007;
const UPDATE_INTERVAL: Duration = Duration::from_secs(2);

fn get_cpu_temp() -> Option<u8> {
    let mut paths: Vec<_> = fs::read_dir("/sys/class/hwmon")
        .ok()?
        .flatten()
        .flat_map(|hwmon| {
            fs::read_dir(hwmon.path())
                .ok()
                .into_iter()
                .flatten()
                .flatten()
                .filter(|e| {
                    e.file_name()
                        .to_string_lossy()
                        .starts_with("temp")
                        && e.file_name().to_string_lossy().ends_with("_input")
                })
        })
        .map(|e| e.path())
        .collect();

    paths.sort();

    for path in &paths {
        if let Some(parent) = path.parent() {
            let name_path = parent.join("name");
            if let Ok(name) = fs::read_to_string(&name_path) {
                let name = name.trim();
                if matches!(name, "k10temp" | "coretemp" | "zenpower") {
                    if let Some(temp) = read_temp(path) {
                        return Some(temp);
                    }
                }
            }
        }
    }

    for path in &paths {
        if let Some(temp) = read_temp(path) {
            if temp > 20 {
                return Some(temp);
            }
        }
    }

    None
}

fn read_temp(path: &Path) -> Option<u8> {
    let raw: i64 = fs::read_to_string(path).ok()?.trim().parse().ok()?;
    let celsius = raw / 1000;
    if celsius > 0 && celsius < 120 {
        Some(celsius as u8)
    } else {
        None
    }
}

fn send_temp(dev: &hidapi::HidDevice, temp: u8) -> bool {
    let tens = temp / 10;
    let mut packet = [0u8; 64];
    packet[0] = tens;
    packet[1] = temp;
    dev.write(&packet).is_ok()
}

fn main() {
    println!("Redragon CCW-3017 LCD Temperature Monitor");
    println!("Looking for device {:04x}:{:04x}...", VENDOR_ID, PRODUCT_ID);

    ctrlc::set_handler(|| {
        println!("\nShutting down...");
        std::process::exit(0);
    })
    .ok();

    loop {
        let api = match HidApi::new() {
            Ok(a) => a,
            Err(e) => {
                eprintln!("HID init error: {e}, retrying in 5s...");
                thread::sleep(Duration::from_secs(5));
                continue;
            }
        };

        let dev = match api.open(VENDOR_ID, PRODUCT_ID) {
            Ok(d) => d,
            Err(_) => {
                eprintln!("Device not found, retrying in 5s...");
                thread::sleep(Duration::from_secs(5));
                continue;
            }
        };

        println!("Connected to LCD.");

        loop {
            match get_cpu_temp() {
                Some(temp) => {
                    if !send_temp(&dev, temp) {
                        eprintln!("Write failed, reconnecting...");
                        break;
                    }
                    print!("CPU Temp: {temp}°C\r");
                }
                None => eprintln!("Could not read CPU temp"),
            }
            thread::sleep(UPDATE_INTERVAL);
        }

        thread::sleep(Duration::from_secs(5));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cpu_temp_readable() {
        let temp = get_cpu_temp();
        assert!(temp.is_some(), "Should be able to read CPU temp");
        let t = temp.unwrap();
        assert!(t > 0 && t < 120, "Temp {t} out of sane range");
    }

    #[test]
    fn test_packet_format() {
        let temp: u8 = 75;
        let tens = temp / 10;
        assert_eq!(tens, 7);
    }
}