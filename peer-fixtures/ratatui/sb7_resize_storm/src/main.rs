use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, widgets::Paragraph, Terminal};
use std::{env, io, thread, time::Duration};

#[derive(Clone, Debug)]
struct Options {
    rows: usize,
    steps: usize,
    interval_ms: u64,
}

fn main() -> Result<(), String> {
    run_wire(&parse_args()?)
}

fn run_wire(options: &Options) -> Result<(), String> {
    enable_raw_mode().map_err(|error| error.to_string())?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, Hide).map_err(|error| {
        let _ = disable_raw_mode();
        error.to_string()
    })?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).map_err(|error| {
        let _ = disable_raw_mode();
        error.to_string()
    })?;
    let interval = Duration::from_millis(options.interval_ms);
    let result = (|| -> Result<(), String> {
        for step in 0..=options.steps {
            terminal
                .draw(|frame| {
                    let area = frame.area();
                    frame.render_widget(
                        Paragraph::new(render_body(options, step, area.width, area.height)),
                        area,
                    );
                })
                .map_err(|error| error.to_string())?;
            thread::sleep(interval);
        }
        Ok(())
    })();
    let cleanup = execute!(terminal.backend_mut(), Show, LeaveAlternateScreen)
        .map_err(|error| error.to_string())
        .and_then(|_| disable_raw_mode().map_err(|error| error.to_string()));
    result.and(cleanup)
}

fn render_body(options: &Options, step: usize, width: u16, height: u16) -> String {
    let visible_logs = ((height as usize) / 3).clamp(2, 10);
    let visible_rows = (height as usize)
        .saturating_sub(visible_logs + 4)
        .clamp(3, 14);
    let mut lines = vec![
        format!(
            "SB.7 resize step={step} rows={} size={}x{}",
            options.rows, width, height
        ),
        "filter status:failed".to_string(),
        String::new(),
    ];
    for row in 0..visible_rows {
        let index = (step * 7 + row) % options.rows;
        lines.push(format!(
            "RUN-{} {:8} owner={:5} duration={:02}:{:02} Resize shard {}",
            100000 + index,
            status(index),
            owner(index),
            index % 3,
            index % 60,
            index % 2048
        ));
    }
    lines.push(String::new());
    for row in 0..visible_logs {
        let index = step * visible_logs + row;
        let unsafe_payload = if index % 17 == 0 {
            format!(" secret-{index} payload")
        } else {
            String::new()
        };
        lines.push(format!(
            "resize log {index} shard={} status={}{}",
            index % 31,
            status(index),
            unsafe_payload
        ));
    }
    lines.join("\n")
}

fn status(row: usize) -> &'static str {
    ["queued", "running", "passed", "failed", "blocked"][row % 5]
}

fn owner(row: usize) -> &'static str {
    ["agent", "ops", "qa", "infra", "cli"][row % 5]
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options {
        rows: 100_000,
        steps: 8,
        interval_ms: 80,
    };
    for arg in env::args().skip(1) {
        if arg == "--wire" {
            continue;
        } else if let Some(value) = arg.strip_prefix("--rows=") {
            options.rows = positive(value, "--rows")?;
        } else if let Some(value) = arg.strip_prefix("--steps=") {
            options.steps = positive(value, "--steps")?;
        } else if let Some(value) = arg.strip_prefix("--interval-ms=") {
            options.interval_ms = positive(value, "--interval-ms")?;
        } else if arg.starts_with("--size=") {
            continue;
        } else {
            return Err(format!("unknown argument: {arg}"));
        }
    }
    Ok(options)
}

fn positive<T>(value: &str, name: &str) -> Result<T, String>
where
    T: std::str::FromStr + PartialOrd + From<u8>,
{
    let parsed = value
        .parse::<T>()
        .map_err(|_| format!("{name} expects a positive integer"))?;
    if parsed <= T::from(0) {
        return Err(format!("{name} expects a positive integer"));
    }
    Ok(parsed)
}
