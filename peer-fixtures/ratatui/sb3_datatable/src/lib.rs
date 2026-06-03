use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::widgets::{Cell, Row, StatefulWidget, Table, TableState};

const COLUMNS: [(&str, &str, u16); 8] = [
    ("id", "ID", 12),
    ("status", "Status", 8),
    ("title", "Title", 24),
    ("owner", "Owner", 12),
    ("duration", "Duration", 10),
    ("progress", "Progress", 8),
    ("warnings", "Warnings", 8),
    ("updated", "Updated", 14),
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RowRecord {
    pub id: String,
    pub status: String,
    pub title: String,
    pub owner: String,
    pub duration: String,
    pub progress: String,
    pub warnings: String,
    pub updated: String,
}

impl RowRecord {
    fn new(index: usize) -> Self {
        Self {
            id: row_id(index),
            status: if index % 5 == 0 { "failed" } else { "ok" }.to_string(),
            title: format!("Build pipeline {index}"),
            owner: format!("user-{}", index % 17),
            duration: format!("{}s", 30 + index % 400),
            progress: format!("{}%", index % 101),
            warnings: format!("{}", index % 4),
            updated: format!("2026-06-{:02}", 1 + index % 28),
        }
    }

    pub fn cells(&self) -> Vec<String> {
        vec![
            self.id.clone(),
            self.status.clone(),
            self.title.clone(),
            self.owner.clone(),
            self.duration.clone(),
            self.progress.clone(),
            self.warnings.clone(),
            self.updated.clone(),
        ]
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TableStateSnapshot {
    pub row_count: usize,
    pub selected_row: usize,
    pub selected_row_id: String,
    pub visible_start: usize,
    pub visible_end: usize,
    pub visible_window_rows: usize,
    pub buffer_contains_selected_row: bool,
}

#[derive(Clone, Debug)]
pub struct RenderSnapshot {
    pub buffer: Buffer,
    pub state: TableStateSnapshot,
}

#[derive(Clone, Debug)]
pub struct Sb3TableApp {
    rows: Vec<RowRecord>,
    selected_row: usize,
    visible_start: usize,
    last_copied_tsv: String,
}

impl Sb3TableApp {
    pub fn new(row_count: usize) -> Self {
        let rows = (0..row_count).map(RowRecord::new).collect();
        Self {
            rows,
            selected_row: 0,
            visible_start: 0,
            last_copied_tsv: String::new(),
        }
    }

    pub fn row_count(&self) -> usize {
        self.rows.len()
    }

    pub fn selected_row(&self) -> usize {
        self.selected_row
    }

    pub fn last_copied_tsv(&self) -> &str {
        &self.last_copied_tsv
    }

    pub fn arrow_down(&mut self, visible_capacity: usize) {
        if self.rows.is_empty() {
            return;
        }
        self.selected_row = (self.selected_row + 1).min(self.rows.len() - 1);
        self.keep_selected_visible(visible_capacity);
    }

    pub fn page_down(&mut self, visible_capacity: usize) {
        if self.rows.is_empty() {
            return;
        }
        let page = visible_capacity.max(1);
        self.selected_row = (self.selected_row + page).min(self.rows.len() - 1);
        self.visible_start = self
            .max_visible_start(visible_capacity)
            .min(self.selected_row);
        self.keep_selected_visible(visible_capacity);
    }

    pub fn jump_to_end(&mut self, visible_capacity: usize) {
        if self.rows.is_empty() {
            return;
        }
        self.selected_row = self.rows.len() - 1;
        self.visible_start = self.max_visible_start(visible_capacity);
    }

    pub fn copy_selected_tsv(&mut self) -> String {
        let copied = self
            .rows
            .get(self.selected_row)
            .map(tsv_for_row)
            .unwrap_or_default();
        self.last_copied_tsv = copied.clone();
        copied
    }

    pub fn render_to_buffer(&self, columns: u16, rows: u16) -> RenderSnapshot {
        let area = Rect::new(0, 0, columns, rows);
        let mut buffer = Buffer::empty(area);
        let visible_capacity = visible_capacity(rows);
        let visible_end = self.visible_end(visible_capacity);
        let visible_rows = self.rows[self.visible_start..visible_end]
            .iter()
            .map(|record| Row::new(record.cells()));
        let header = Row::new(COLUMNS.iter().map(|column| Cell::from(column.1)))
            .style(Style::default().add_modifier(Modifier::BOLD));
        let widths: Vec<Constraint> = COLUMNS
            .iter()
            .map(|column| Constraint::Length(column.2))
            .collect();
        let table = Table::new(visible_rows, widths)
            .header(header)
            .row_highlight_style(Style::default().add_modifier(Modifier::REVERSED));
        let mut table_state = TableState::default();
        let relative_selected = self.selected_row.saturating_sub(self.visible_start);
        if relative_selected < visible_end.saturating_sub(self.visible_start) {
            table_state.select(Some(relative_selected));
        }
        StatefulWidget::render(table, area, &mut buffer, &mut table_state);
        let selected_id = self
            .rows
            .get(self.selected_row)
            .map(|row| row.id.clone())
            .unwrap_or_default();
        let buffer_contains_selected_row = buffer_contains(&buffer, &selected_id);
        RenderSnapshot {
            buffer,
            state: TableStateSnapshot {
                row_count: self.rows.len(),
                selected_row: self.selected_row,
                selected_row_id: selected_id,
                visible_start: self.visible_start,
                visible_end,
                visible_window_rows: visible_end.saturating_sub(self.visible_start),
                buffer_contains_selected_row,
            },
        }
    }

    fn visible_end(&self, visible_capacity: usize) -> usize {
        (self.visible_start + visible_capacity).min(self.rows.len())
    }

    fn keep_selected_visible(&mut self, visible_capacity: usize) {
        let capacity = visible_capacity.max(1);
        if self.selected_row < self.visible_start {
            self.visible_start = self.selected_row;
        } else if self.selected_row >= self.visible_start + capacity {
            self.visible_start = self.selected_row + 1 - capacity;
        }
        self.visible_start = self
            .visible_start
            .min(self.max_visible_start(visible_capacity));
    }

    fn max_visible_start(&self, visible_capacity: usize) -> usize {
        self.rows.len().saturating_sub(visible_capacity.max(1))
    }
}

pub fn row_id(index: usize) -> String {
    format!("RUN-{index:06}")
}

pub fn expected_selected_tsv(index: usize) -> String {
    tsv_for_row(&RowRecord::new(index))
}

pub fn visible_capacity(rows: u16) -> usize {
    usize::from(rows).saturating_sub(1).max(1)
}

pub fn tsv_for_row(row: &RowRecord) -> String {
    let headings = COLUMNS
        .iter()
        .map(|column| column.1)
        .collect::<Vec<_>>()
        .join("\t");
    let cells = row
        .cells()
        .into_iter()
        .map(|value| sanitize_tsv_cell(&value))
        .collect::<Vec<_>>()
        .join("\t");
    format!("{headings}\n{cells}")
}

pub fn sanitize_tsv_cell(value: &str) -> String {
    value
        .chars()
        .map(|character| match character {
            '\t' | '\n' | '\r' => ' ',
            _ => character,
        })
        .collect()
}

pub fn buffer_text(buffer: &Buffer) -> String {
    let area = buffer.area;
    let mut text = String::new();
    for y in area.y..area.y + area.height {
        for x in area.x..area.x + area.width {
            text.push_str(buffer[(x, y)].symbol());
        }
        text.push('\n');
    }
    text
}

pub fn buffer_contains(buffer: &Buffer, needle: &str) -> bool {
    buffer_text(buffer).contains(needle)
}
