use crossterm::{
    cursor::{Hide, Show},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use ratatui_sb3_datatable::{
    buffer_text, expected_selected_tsv, row_id, visible_capacity, Sb3TableApp,
};
use serde_json::{json, Value};
use std::cmp::Ordering;
use std::env;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const SCHEMA_VERSION: u64 = 1;
const PEER_ID: &str = "ratatui";
const PEER_NAME: &str = "Ratatui";
const PEER_VERSION: &str = "0.30.0";
const PEER_URL: &str = "https://crates.io/crates/ratatui";
const SCENARIO_ID: &str = "SB.3";
const DEFAULT_WARMUPS: usize = 1;
const DEFAULT_ITERATIONS: usize = 10;
const DEFAULT_ROWS: usize = 100_000;
const DEFAULT_WIRE_STEPS: usize = 5;
const DEFAULT_WIRE_INTERVAL_MS: u64 = 80;
const DEFAULT_COLUMNS: u16 = 120;
const DEFAULT_TERMINAL_ROWS: u16 = 32;

#[derive(Clone, Debug)]
struct Options {
    warmup_iterations: usize,
    measured_iterations: usize,
    rows: usize,
    terminal_columns: u16,
    terminal_rows: u16,
    print_json: bool,
    output_path: Option<String>,
    wire: bool,
    wire_steps: usize,
    wire_interval_ms: u64,
}

#[derive(Clone, Debug)]
struct Sample {
    mount_us: u128,
    first_render_us: u128,
    arrow_move_us: u128,
    page_move_us: u128,
    jump_to_end_us: u128,
    copy_selected_row_us: u128,
    semantic_or_test_query_us: u128,
    rss_delta_bytes: i64,
    row_count: usize,
    visible_window_rows: usize,
    visible_start: usize,
    visible_end: usize,
    selected_row: usize,
    selected_row_id: String,
    visible_window_bounded: bool,
    selection_correct: bool,
    copy_exact: bool,
}

fn main() -> Result<(), String> {
    let options = parse_args()?;
    if options.wire {
        return run_wire(&options);
    }

    let run_rss_before = current_rss_bytes();
    for _ in 0..options.warmup_iterations {
        let _ = run_sample(&options);
    }

    let samples = (0..options.measured_iterations)
        .map(|_| run_sample(&options))
        .collect::<Vec<_>>();
    let run_rss_delta_bytes = (current_rss_bytes() - run_rss_before).max(0);
    let artifact = build_artifact(&options, &samples, run_rss_delta_bytes);
    let json_text = serde_json::to_string_pretty(&artifact).map_err(|error| error.to_string())?;

    if let Some(output_path) = &options.output_path {
        if let Some(parent) = Path::new(output_path).parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        fs::write(output_path, format!("{json_text}\n")).map_err(|error| error.to_string())?;
    }

    if options.print_json {
        println!("{json_text}");
    } else {
        println!("Ratatui SB.3 DataTable fixture");
        println!("Rows: {}", options.rows);
        println!("Iterations: {}", options.measured_iterations);
        println!(
            "pageMoveUs p95: {}",
            artifact["metrics"]["pageMoveUs"]["p95"]
        );
        println!(
            "copySelectedRowUs p95: {}",
            artifact["metrics"]["copySelectedRowUs"]["p95"]
        );
        if let Some(output_path) = &options.output_path {
            println!("Saved {output_path}");
        }
    }

    Ok(())
}

fn run_wire(options: &Options) -> Result<(), String> {
    let mut app = Sb3TableApp::new(options.rows);
    let capacity = visible_capacity(options.terminal_rows);
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
    let interval = Duration::from_millis(options.wire_interval_ms);

    let result = (|| -> Result<(), String> {
        terminal
            .draw(|frame| app.render_to_frame(frame))
            .map_err(|error| error.to_string())?;
        thread::sleep(interval);
        for step in 0..options.wire_steps {
            match step % 5 {
                0 => app.arrow_down(capacity),
                1 => app.page_down(capacity),
                2 => {
                    for _ in 0..8 {
                        app.page_down(capacity);
                    }
                }
                3 => app.jump_to_end(capacity),
                _ => {
                    let _ = app.copy_selected_tsv();
                }
            }
            terminal
                .draw(|frame| app.render_to_frame(frame))
                .map_err(|error| error.to_string())?;
            thread::sleep(interval);
        }
        Ok(())
    })();

    let cleanup_result = execute!(terminal.backend_mut(), Show, LeaveAlternateScreen)
        .map_err(|error| error.to_string())
        .and_then(|_| disable_raw_mode().map_err(|error| error.to_string()));

    result.and(cleanup_result)
}

fn run_sample(options: &Options) -> Sample {
    let rss_before = current_rss_bytes();
    let mount_start = Instant::now();
    let mut app = Sb3TableApp::new(options.rows);
    let mount_us = elapsed_us(mount_start);
    let rss_after_mount = current_rss_bytes();

    let first_render_start = Instant::now();
    let _initial = app.render_to_buffer(options.terminal_columns, options.terminal_rows);
    let first_render_us = elapsed_us(first_render_start);

    let capacity = visible_capacity(options.terminal_rows);

    let arrow_start = Instant::now();
    app.arrow_down(capacity);
    let _arrow = app.render_to_buffer(options.terminal_columns, options.terminal_rows);
    let arrow_move_us = elapsed_us(arrow_start);

    let page_start = Instant::now();
    app.page_down(capacity);
    let _page = app.render_to_buffer(options.terminal_columns, options.terminal_rows);
    let page_move_us = elapsed_us(page_start);

    let jump_start = Instant::now();
    app.jump_to_end(capacity);
    let final_render = app.render_to_buffer(options.terminal_columns, options.terminal_rows);
    let jump_to_end_us = elapsed_us(jump_start);

    let copy_start = Instant::now();
    let copied = app.copy_selected_tsv();
    let copy_selected_row_us = elapsed_us(copy_start);

    let expected_id = row_id(options.rows - 1);
    let expected_copy = expected_selected_tsv(options.rows - 1);
    let query_start = Instant::now();
    let state = final_render.state.clone();
    let buffer_contains_selected_row = buffer_text(&final_render.buffer).contains(&expected_id);
    let semantic_or_test_query_us = elapsed_us(query_start);

    let selected_row_id = state.selected_row_id.clone();
    Sample {
        mount_us,
        first_render_us,
        arrow_move_us,
        page_move_us,
        jump_to_end_us,
        copy_selected_row_us,
        semantic_or_test_query_us,
        rss_delta_bytes: (rss_after_mount - rss_before).max(0),
        row_count: state.row_count,
        visible_window_rows: state.visible_window_rows,
        visible_start: state.visible_start,
        visible_end: state.visible_end,
        selected_row: state.selected_row,
        selected_row_id,
        visible_window_bounded: state.visible_window_rows <= usize::from(options.terminal_rows),
        selection_correct: state.selected_row == options.rows - 1
            && state.selected_row_id == expected_id
            && state.buffer_contains_selected_row
            && buffer_contains_selected_row,
        copy_exact: copied == expected_copy && !copied.contains('\u{1b}'),
    }
}

fn build_artifact(options: &Options, samples: &[Sample], run_rss_delta_bytes: i64) -> Value {
    let captured_at = Timestamp::now();
    let run_id = format!("ratatui-sb3-datatable-{}", captured_at.for_id);
    let last = samples.last().expect("at least one sample");
    let all_visible_bounded = samples.iter().all(|sample| sample.visible_window_bounded);
    let all_selection_correct = samples.iter().all(|sample| sample.selection_correct);
    let all_copy_exact = samples.iter().all(|sample| sample.copy_exact);
    let app_lines = source_line_count("src/lib.rs");
    let benchmark_lines = source_line_count("src/main.rs");
    let test_lines = source_line_count("tests/sb3_datatable_test.rs");

    json!({
        "schemaVersion": SCHEMA_VERSION,
        "kind": "fleuryPeerBenchmarkRun",
        "runId": run_id,
        "peerId": PEER_ID,
        "scenarioId": SCENARIO_ID,
        "capturedAt": captured_at.iso,
        "source": {
            "name": PEER_NAME,
            "version": PEER_VERSION,
            "url": PEER_URL,
        },
        "environment": {
            "machine": hostname(),
            "operatingSystem": env::consts::OS,
            "operatingSystemVersion": os_version(),
            "runtime": format!("{} / Ratatui {}", rustc_version(), PEER_VERSION),
            "terminalMode": "ratatui-buffer-render-harness",
            "terminalSize": {
                "columns": options.terminal_columns,
                "rows": options.terminal_rows,
            },
        },
        "fixture": {
            "workingDirectory": "peer-fixtures/ratatui/sb3_datatable",
            "command": [
                "cargo",
                "run",
                "--release",
                "--",
                format!("--warmup={}", options.warmup_iterations),
                format!("--iterations={}", options.measured_iterations),
                format!("--rows={}", options.rows),
                "--json".to_string(),
            ],
            "warmupIterations": options.warmup_iterations,
            "measuredIterations": options.measured_iterations,
        },
        "metrics": {
            "mountUs": stats(samples.iter().map(|sample| sample.mount_us)),
            "firstRenderUs": stats(samples.iter().map(|sample| sample.first_render_us)),
            "arrowMoveUs": stats(samples.iter().map(|sample| sample.arrow_move_us)),
            "pageMoveUs": stats(samples.iter().map(|sample| sample.page_move_us)),
            "jumpToEndUs": stats(samples.iter().map(|sample| sample.jump_to_end_us)),
            "copySelectedRowUs": stats(samples.iter().map(|sample| sample.copy_selected_row_us)),
            "semanticOrTestQueryUs": stats(samples.iter().map(|sample| sample.semantic_or_test_query_us)),
            "rssDeltaBytes": samples
                .iter()
                .map(|sample| sample.rss_delta_bytes)
                .max()
                .unwrap_or(0)
                .max(run_rss_delta_bytes),
            "lineOfCodeCount": app_lines,
            "benchmarkLineOfCodeCount": benchmark_lines,
            "testLineOfCodeCount": test_lines,
            "rowCount": options.rows,
            "observedRowCount": last.row_count,
            "visibleWindowRowEstimate": last.visible_window_rows,
            "visibleRangeStart": last.visible_start,
            "visibleRangeEnd": last.visible_end,
            "finalSelectedRow": last.selected_row,
            "finalSelectedRowId": last.selected_row_id,
        },
        "correctness": [
            {
                "gate": "visible window stays bounded",
                "pass": all_visible_bounded,
                "evidence": "Fixture-owned visible-row slice stayed within the render-buffer height.",
            },
            {
                "gate": "selection is correct after jump",
                "pass": all_selection_correct,
                "evidence": format!("Jump-to-end selected {} and rendered it in the Ratatui buffer.", row_id(options.rows - 1)),
            },
            {
                "gate": "copy/export is sanitized and exact",
                "pass": all_copy_exact,
                "evidence": "Selected row TSV matched generated source row and contained no escape bytes.",
            },
        ],
        "ergonomics": {
            "lineOfCodeCount": app_lines,
            "benchmarkLineOfCodeCount": benchmark_lines,
            "testLineOfCodeCount": test_lines,
            "appFile": "src/lib.rs",
            "benchmarkFile": "src/main.rs",
            "testFile": "tests/sb3_datatable_test.rs",
            "peerOwnedTableWidget": true,
            "appOwnedVisibleRowSlicing": true,
            "appOwnedSelectionState": true,
            "appOwnedCopyExport": true,
            "semanticGraphAvailable": false,
            "testQueryViaAppStateAndBuffer": true,
        },
        "artifacts": [
            {
                "kind": "source",
                "path": "peer-fixtures/ratatui/sb3_datatable/src/lib.rs",
            },
            {
                "kind": "benchmark",
                "path": "peer-fixtures/ratatui/sb3_datatable/src/main.rs",
            },
            {
                "kind": "test",
                "path": "peer-fixtures/ratatui/sb3_datatable/tests/sb3_datatable_test.rs",
            },
        ],
        "notes": [
            "This is a Ratatui buffer-render peer fixture, not a real-terminal run.",
            "Ratatui 0.30.0 supplies Table rendering, TableState selection highlighting, and Buffer rendering.",
            "The fixture owns the retained data model, visible-row slicing, navigation policy, selected-row copy/export, and state query because Ratatui is an immediate rendering library rather than a retained app framework.",
            "Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
        ],
    })
}

fn parse_args() -> Result<Options, String> {
    let mut options = Options {
        warmup_iterations: DEFAULT_WARMUPS,
        measured_iterations: DEFAULT_ITERATIONS,
        rows: DEFAULT_ROWS,
        terminal_columns: DEFAULT_COLUMNS,
        terminal_rows: DEFAULT_TERMINAL_ROWS,
        print_json: false,
        output_path: None,
        wire: false,
        wire_steps: DEFAULT_WIRE_STEPS,
        wire_interval_ms: DEFAULT_WIRE_INTERVAL_MS,
    };

    for arg in env::args().skip(1) {
        if arg == "--json" {
            options.print_json = true;
        } else if arg == "--wire" {
            options.wire = true;
        } else if let Some(value) = arg.strip_prefix("--warmup=") {
            options.warmup_iterations = parse_usize(value, "warmup")?;
        } else if let Some(value) = arg.strip_prefix("--iterations=") {
            options.measured_iterations = parse_usize(value, "iterations")?;
        } else if let Some(value) = arg.strip_prefix("--rows=") {
            options.rows = parse_usize(value, "rows")?;
        } else if let Some(value) = arg.strip_prefix("--steps=") {
            options.wire_steps = parse_usize(value, "steps")?;
        } else if let Some(value) = arg.strip_prefix("--interval-ms=") {
            options.wire_interval_ms = parse_u64(value, "interval-ms")?;
        } else if let Some(value) = arg.strip_prefix("--size=") {
            let (columns, rows) = parse_size(value)?;
            options.terminal_columns = columns;
            options.terminal_rows = rows;
        } else if let Some(value) = arg.strip_prefix("--output=") {
            options.output_path = Some(value.to_string());
        } else {
            return Err(format!("unknown argument: {arg}"));
        }
    }

    if options.measured_iterations == 0 {
        return Err("--iterations must be positive".to_string());
    }
    if options.rows == 0 {
        return Err("--rows must be positive".to_string());
    }
    if options.wire_steps == 0 {
        return Err("--steps must be positive".to_string());
    }
    if options.wire_interval_ms == 0 {
        return Err("--interval-ms must be positive".to_string());
    }
    Ok(options)
}

fn parse_usize(value: &str, label: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("--{label} must be an integer"))?;
    Ok(parsed)
}

fn parse_u64(value: &str, label: &str) -> Result<u64, String> {
    let parsed = value
        .parse::<u64>()
        .map_err(|_| format!("--{label} must be an integer"))?;
    Ok(parsed)
}

fn parse_size(value: &str) -> Result<(u16, u16), String> {
    let Some((columns, rows)) = value.split_once('x') else {
        return Err("--size must be COLUMNSxROWS".to_string());
    };
    let columns = columns
        .parse::<u16>()
        .map_err(|_| "--size columns must fit u16".to_string())?;
    let rows = rows
        .parse::<u16>()
        .map_err(|_| "--size rows must fit u16".to_string())?;
    if columns == 0 || rows == 0 {
        return Err("--size dimensions must be positive".to_string());
    }
    Ok((columns, rows))
}

fn elapsed_us(start: Instant) -> u128 {
    start.elapsed().as_micros()
}

fn stats(values: impl Iterator<Item = u128>) -> Value {
    let mut ordered = values.collect::<Vec<_>>();
    ordered.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
    if ordered.is_empty() {
        return json!({"min": 0, "median": 0, "p95": 0, "p99": 0, "max": 0, "samples": 0});
    }
    json!({
        "min": ordered[0],
        "median": percentile(&ordered, 0.50),
        "p95": percentile(&ordered, 0.95),
        "p99": percentile(&ordered, 0.99),
        "max": ordered[ordered.len() - 1],
        "samples": ordered.len(),
    })
}

fn percentile(ordered: &[u128], fraction: f64) -> u128 {
    if ordered.len() == 1 {
        return ordered[0];
    }
    let index = ((ordered.len() - 1) as f64 * fraction).ceil() as usize;
    ordered[index.min(ordered.len() - 1)]
}

fn current_rss_bytes() -> i64 {
    let pid = std::process::id().to_string();
    let Ok(output) = Command::new("ps").args(["-o", "rss=", "-p", &pid]).output() else {
        return 0;
    };
    if !output.status.success() {
        return 0;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    text.trim()
        .parse::<i64>()
        .map(|rss_kb| rss_kb * 1024)
        .unwrap_or(0)
}

fn source_line_count(path: &str) -> usize {
    let Ok(text) = fs::read_to_string(path) else {
        return 0;
    };
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with("//"))
        .count()
}

fn hostname() -> String {
    command_output("hostname").unwrap_or_else(|| "unknown".to_string())
}

fn os_version() -> String {
    command_output("uname -a").unwrap_or_else(|| env::consts::OS.to_string())
}

fn rustc_version() -> String {
    command_output("rustc --version").unwrap_or_else(|| "rustc unknown".to_string())
}

fn command_output(command: &str) -> Option<String> {
    let mut parts = command.split_whitespace();
    let executable = parts.next()?;
    let output = Command::new(executable).args(parts).output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

struct Timestamp {
    iso: String,
    for_id: String,
}

impl Timestamp {
    fn now() -> Self {
        let duration = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::from_secs(0));
        let seconds = duration.as_secs();
        let nanos = duration.subsec_nanos();
        let tm = unix_to_utc(seconds);
        Self {
            iso: format!(
                "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:06}Z",
                tm.year,
                tm.month,
                tm.day,
                tm.hour,
                tm.minute,
                tm.second,
                nanos / 1_000
            ),
            for_id: format!(
                "{:04}-{:02}-{:02}T{:02}-{:02}-{:02}Z",
                tm.year, tm.month, tm.day, tm.hour, tm.minute, tm.second
            ),
        }
    }
}

struct UtcParts {
    year: i32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
}

fn unix_to_utc(seconds: u64) -> UtcParts {
    let days = seconds / 86_400;
    let seconds_of_day = seconds % 86_400;
    let (year, month, day) = civil_from_days(days as i64);
    UtcParts {
        year,
        month,
        day,
        hour: (seconds_of_day / 3_600) as u32,
        minute: ((seconds_of_day % 3_600) / 60) as u32,
        second: (seconds_of_day % 60) as u32,
    }
}

fn civil_from_days(days_since_epoch: i64) -> (i32, u32, u32) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = y + if month <= 2 { 1 } else { 0 };
    (year as i32, month as u32, day as u32)
}
