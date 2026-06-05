use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, widgets::Paragraph, Terminal};
use std::{env, io, thread, time::Duration};

const DEFAULT_ROWS: usize = 2_000;
const DEFAULT_STEPS: usize = 8;
const DEFAULT_INTERVAL_MS: u64 = 60;
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
struct LayoutApp {
    rows: usize,
    step: usize,
    counter: usize,
    accent: bool,
    text_variant: bool,
}

fn main() -> Result<(), String> {
    run_wire(&parse_args()?)
}

fn run_wire(options: &Options) -> Result<(), String> {
    let mut app = LayoutApp {
        rows: options.rows,
        step: 0,
        counter: 0,
        accent: false,
        text_variant: false,
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
            match app.step % 4 {
                0 => app.counter += 1,
                1 => app.accent = !app.accent,
                2 => app.text_variant = !app.text_variant,
                _ => {}
            }
            app.step += 1;
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
    app: &LayoutApp,
) -> Result<(), String> {
    let text = render_layout(app);
    terminal
        .draw(|frame| frame.render_widget(Paragraph::new(text), frame.area()))
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn render_layout(app: &LayoutApp) -> String {
    let visible = app.rows.max(1).min(26);
    let start = app.rows.saturating_sub(visible);
    let variant = if app.text_variant { "B" } else { "A" };
    let mut out = String::new();
    out.push_str(&format!(
        "SB.12 layout step={} counter={} accent={} variant={}\n\n",
        app.step, app.counter, app.accent, app.text_variant
    ));
    out.push_str(&format!(
        "hot region counter={:04}  paint-only text variant={}\n\n",
        app.counter, variant
    ));
    for i in 0..visible {
        let row = start + i;
        out.push_str(&format!(
            "row {row:06} stable payload owner=layout shard={} checksum={}\n",
            row % 31,
            row * 17 % 997
        ));
    }
    out
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
