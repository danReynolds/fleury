use ratatui_sb3_datatable::{expected_selected_tsv, row_id, visible_capacity, Sb3TableApp};

#[test]
fn navigation_copy_and_buffer_query_are_correct() {
    let row_count = 1_000;
    let terminal_rows = 24;
    let capacity = visible_capacity(terminal_rows);
    let mut app = Sb3TableApp::new(row_count);

    let initial = app.render_to_buffer(120, terminal_rows);
    assert_eq!(initial.state.row_count, row_count);
    assert_eq!(initial.state.selected_row, 0);
    assert_eq!(initial.state.selected_row_id, row_id(0));
    assert!(initial.state.visible_window_rows <= usize::from(terminal_rows));
    assert!(initial.state.buffer_contains_selected_row);

    app.arrow_down(capacity);
    let arrow = app.render_to_buffer(120, terminal_rows);
    assert_eq!(arrow.state.selected_row, 1);
    assert_eq!(arrow.state.selected_row_id, row_id(1));

    app.page_down(capacity);
    let page = app.render_to_buffer(120, terminal_rows);
    assert!(page.state.selected_row > 1);
    assert!(page.state.buffer_contains_selected_row);

    app.jump_to_end(capacity);
    let final_render = app.render_to_buffer(120, terminal_rows);
    assert_eq!(final_render.state.selected_row, row_count - 1);
    assert_eq!(final_render.state.selected_row_id, row_id(row_count - 1));
    assert!(final_render.state.buffer_contains_selected_row);
    assert!(final_render.state.visible_window_rows <= usize::from(terminal_rows));

    let copied = app.copy_selected_tsv();
    assert_eq!(copied, expected_selected_tsv(row_count - 1));
    assert!(!copied.contains('\u{1b}'));
}
