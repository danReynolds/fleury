use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, widgets::Paragraph, Terminal};
use std::{env, io, thread, time::Duration};

const DEFAULT_ROWS: usize = 100_000;
const DEFAULT_STEPS: usize = 120;
const DEFAULT_INTERVAL_MS: u64 = 16;
const DEFAULT_COLS: u16 = 120;
const DEFAULT_PTY_ROWS: u16 = 32;

#[derive(Clone, Debug)]
struct Options {
    rows: usize,
    steps: usize,
    interval_ms: u64,
    cols: u16,
    pty_rows: u16,
}

#[derive(Clone, Debug)]
struct Dashboard {
    rows: usize,
    step: usize,
    history: Vec<usize>,
}

fn main() -> Result<(), String> {
    let options = parse_args()?;
    run_wire(&options)
}

fn run_wire(options: &Options) -> Result<(), String> {
    let mut app = Dashboard {
        rows: options.rows,
        step: 0,
        history: (0..48).map(|index| 40 + index % 17).collect(),
    };
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
        draw(&mut terminal, &app)?;
        thread::sleep(interval);
        for _ in 0..options.steps {
            app.step += 1;
            app.history.remove(0);
            app.history.push(20 + (app.step * 13) % 80);
            draw(&mut terminal, &app)?;
            thread::sleep(interval);
        }
        Ok(())
    })();
    let cleanup = execute!(terminal.backend_mut(), Show, LeaveAlternateScreen)
        .map_err(|error| error.to_string())
        .and_then(|_| disable_raw_mode().map_err(|error| error.to_string()));
    result.and(cleanup)
}

fn draw(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &Dashboard,
) -> Result<(), String> {
    let text = render_dashboard(app);
    terminal
        .draw(|frame| frame.render_widget(Paragraph::new(text), frame.area()))
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn render_dashboard(app: &Dashboard) -> String {
    let cpu = (app.step * 17) % 100;
    let mem = (app.step * 29 + 15) % 100;
    let disk = (app.step * 7 + 30) % 100;
    let completed = app.rows.min(app.step * (app.rows / 80).max(1));
    let mut out = String::new();
    out.push_str(&format!(
        "SB.6 dashboard tick={} rows={} active={}\n\n",
        app.step,
        app.rows,
        20 + (app.step * 7) % 900
    ));
    out.push_str(&format!("CPU {:<36} {:>3}%\n", bar(cpu, 32), cpu));
    out.push_str(&format!("MEM {:<36} {:>3}%\n", bar(mem, 32), mem));
    out.push_str(&format!("IO  {:<36} {:>3}%\n\n", bar(disk, 32), disk));
    out.push_str(&format!("build queue {:>6} / {}\n", completed, app.rows));
    out.push_str(&format!("{}\n\n", bar(percent(completed, app.rows), 76)));
    out.push_str(&format!("spark {}\n\n", spark(&app.history, 76)));
    for i in 0..14 {
        let id = (app.step * 10 + i) % app.rows.max(1);
        let statuses = ["queued", "running", "passed", "failed", "blocked"];
        out.push_str(&format!(
            "RUN-{id:06} {:<7} shard={:02} owner=worker-{:02} latency={}ms\n",
            statuses[(id + app.step) % statuses.len()],
            id % 31,
            id % 17,
            20 + id % 900
        ));
    }
    out
}

fn bar(value: usize, width: usize) -> String {
    let value = value.min(100);
    let filled = value * width / 100;
    format!("{}{}", "#".repeat(filled), ".".repeat(width - filled))
}

fn spark(values: &[usize], width: usize) -> String {
    let levels = b"._-~=+*#";
    let start = values.len().saturating_sub(width);
    values[start..]
        .iter()
        .map(|value| levels[(value * (levels.len() - 1) / 100).min(levels.len() - 1)] as char)
        .collect()
}

fn percent(value: usize, total: usize) -> usize {
    if total == 0 {
        0
    } else {
        value * 100 / total
    }
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options {
        rows: DEFAULT_ROWS,
        steps: DEFAULT_STEPS,
        interval_ms: DEFAULT_INTERVAL_MS,
        cols: DEFAULT_COLS,
        pty_rows: DEFAULT_PTY_ROWS,
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
        } else if let Some(value) = arg.strip_prefix("--size=") {
            let (cols, rows) = parse_size(value)?;
            options.cols = cols;
            options.pty_rows = rows;
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

fn parse_size(value: &str) -> Result<(u16, u16), String> {
    let (cols, rows) = value
        .split_once('x')
        .ok_or_else(|| "--size must be COLSxROWS".to_string())?;
    Ok((
        positive(cols, "--size columns")?,
        positive(rows, "--size rows")?,
    ))
}
