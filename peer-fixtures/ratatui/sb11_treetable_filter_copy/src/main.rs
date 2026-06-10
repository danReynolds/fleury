use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, widgets::Paragraph, Terminal};
use std::{env, io, thread, time::Duration};

const DEFAULT_ROWS: usize = 100_000;
const DEFAULT_STEPS: usize = 6;
const DEFAULT_INTERVAL_MS: u64 = 80;
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
struct TreeApp {
    rows: usize,
    step: usize,
    selected: usize,
    filtering: bool,
    copied_bytes: usize,
    group_size: usize,
    group_count: usize,
}

fn main() -> Result<(), String> {
    run_wire(&parse_args()?)
}

fn run_wire(options: &Options) -> Result<(), String> {
    let group_size = options.rows.clamp(1, 1000);
    let mut app = TreeApp {
        rows: options.rows,
        step: 0,
        selected: 1,
        filtering: false,
        copied_bytes: 0,
        group_size,
        group_count: options.rows.div_ceil(group_size),
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
            match app.step % 6 {
                0 => app.selected = app.group_size + 1,
                1 => app.selected = (app.selected + 20).min(app.visible_row_count() - 1),
                2 => app.selected = app.visible_row_count() - 1,
                3 => {
                    app.filtering = true;
                    app.selected = 1;
                }
                4 => app.copied_bytes = copy_selected_row(&app).len(),
                _ => {
                    app.filtering = false;
                    app.selected = 1;
                }
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
    app: &TreeApp,
) -> Result<(), String> {
    let text = render_tree(app);
    terminal
        .draw(|frame| frame.render_widget(Paragraph::new(text), frame.area()))
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn render_tree(app: &TreeApp) -> String {
    let query = if app.filtering {
        target_query(app.rows)
    } else {
        "none".to_string()
    };
    let mut lines = vec![
        format!(
            "SB.11 tree step={} rows={} filter={} copied={}",
            app.step, app.rows, query, app.copied_bytes
        ),
        String::new(),
    ];

    if app.filtering {
        lines.push(group_line(app.group_count - 1));
        lines.push(row_line(app.rows - 1, true, app.rows));
        return lines.join("\n");
    }

    lines.push(group_line(0));
    for row in 0..app.rows.min(12) {
        lines.push(row_line(row, app.selected == row + 1, app.rows));
    }
    if app.group_count > 1 {
        lines.push(group_line(1));
        let start = app.group_size;
        for row in start..(start + 10).min(app.rows) {
            lines.push(row_line(row, app.selected == row + 2, app.rows));
        }
    }
    if app.selected >= app.visible_row_count().saturating_sub(2) {
        lines.push(group_line(app.group_count - 1));
        for row in app.rows.saturating_sub(8)..app.rows {
            lines.push(row_line(row, row == app.rows - 1, app.rows));
        }
    }
    lines.join("\n")
}

impl TreeApp {
    fn visible_row_count(&self) -> usize {
        let expanded_leaf_count = self.rows.min(self.group_size * self.group_count.min(2));
        (self.group_count + expanded_leaf_count).min(self.rows + self.group_count)
    }
}

fn copy_selected_row(app: &TreeApp) -> String {
    let row = if app.filtering {
        app.rows - 1
    } else {
        app.selected.min(app.rows - 1)
    };
    format!(
        "Component\tStatus\tOwner\tDuration\tNotes\n{}\t{}\t{}\t{}\t{}",
        leaf_key(row),
        status(row),
        owner(row),
        duration(row),
        notes(row)
    )
}

fn group_line(group: usize) -> String {
    format!(
        "GROUP-{group:03} ready owner={} duration={:02}:00 1000 tasks",
        owner(group),
        group % 7
    )
}

fn row_line(row: usize, selected: bool, rows: usize) -> String {
    let marker = if selected { ">" } else { " " };
    let unsafe_payload = if row % 97 == 0 {
        format!(" unsafe secret-{row} payload")
    } else {
        String::new()
    };
    let target = if row == rows - 1 {
        format!(" {}", target_query(rows))
    } else {
        String::new()
    };
    format!(
        "{marker} {} {:8} {:5} {:>5} {}{}{}",
        leaf_key(row),
        status(row),
        owner(row),
        duration(row),
        notes(row),
        target,
        unsafe_payload
    )
}

fn leaf_key(row: usize) -> String {
    format!("TASK-{}", 100000 + row)
}

fn target_query(rows: usize) -> String {
    format!("zz-target-{}", 100000 + rows - 1)
}

fn status(row: usize) -> &'static str {
    ["queued", "running", "passed", "failed", "blocked"][row % 5]
}

fn owner(row: usize) -> &'static str {
    ["agent", "ops", "qa", "infra", "cli"][row % 5]
}

fn duration(row: usize) -> String {
    format!("{:02}:{:02}", row % 4, row % 60)
}

fn notes(row: usize) -> String {
    format!(
        "shard {} {}",
        row % 4096,
        ["core", "widgets", "unicode", "deploy"][row % 4]
    )
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
