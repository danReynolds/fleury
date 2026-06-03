package main

import "testing"

func TestNavigationCopyFilterAndSafety(t *testing.T) {
	const rowCount = 1_000
	const appendCount = 128
	model := NewSb4LogRegionModel(rowCount, defaultColumns, defaultRows)

	initial := model.StateSnapshot()
	if initial.EntryCount != rowCount {
		t.Fatalf("entry count = %d, want %d", initial.EntryCount, rowCount)
	}
	if !initial.TailAnchored {
		t.Fatalf("initial model is not tail anchored: %+v", initial)
	}
	if initial.UnsafeArtifactLeakCount != 0 {
		t.Fatalf("unsafe leak count = %d", initial.UnsafeArtifactLeakCount)
	}

	model = model.Apply(appendBurstMsg{Count: appendCount})
	appended := model.StateSnapshot()
	if appended.EntryCount != rowCount+appendCount {
		t.Fatalf("entry count after append = %d", appended.EntryCount)
	}
	if !appended.TailAnchored {
		t.Fatalf("append did not keep tail anchored: %+v", appended)
	}
	if appended.SelectedKey != logKey(rowCount+appendCount-1) {
		t.Fatalf("selected key after append = %q", appended.SelectedKey)
	}

	model = model.Apply(jumpToScrollbackMsg{SourceIndex: rowCount / 2})
	scrollback := model.StateSnapshot()
	if scrollback.SelectedKey != logKey(rowCount/2) {
		t.Fatalf("scrollback selected key = %q", scrollback.SelectedKey)
	}
	if scrollback.ScrollY > scrollback.MaxScrollY {
		t.Fatalf("scroll y = %d, max = %d", scrollback.ScrollY, scrollback.MaxScrollY)
	}

	model = model.Apply(tailMsg{})
	model = model.Apply(copyEntryMsg{})
	copied := model.LastCopiedText()
	expected := expectedCopiedText(rowCount + appendCount - 1)
	if copied != expected {
		t.Fatalf("copied row mismatch\n got: %q\nwant: %q", copied, expected)
	}
	if unsafeCountText(copied) != 0 {
		t.Fatalf("copied row leaked unsafe content: %q", copied)
	}

	model = model.Apply(filterQueryMsg{Query: appendFilterQuery(rowCount)})
	filtered := model.StateSnapshot()
	if filtered.DisplayedCount != appendCount {
		t.Fatalf("filtered count = %d, want %d", filtered.DisplayedCount, appendCount)
	}
	if filtered.SelectedKey != logKey(rowCount+appendCount-1) {
		t.Fatalf("filtered selected key = %q", filtered.SelectedKey)
	}
	if filtered.UnsafeArtifactLeakCount != 0 {
		t.Fatalf("unsafe leak count after filter = %d", filtered.UnsafeArtifactLeakCount)
	}
}
