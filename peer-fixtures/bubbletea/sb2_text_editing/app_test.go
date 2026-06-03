package main

import (
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestTextEditingHistoryCompletionPasteAndRedaction(t *testing.T) {
	model := NewSb2TextEditingModel(2_000, defaultColumns, defaultRows)

	initial := model.StateSnapshot()
	if !initial.MixedWidthValid {
		t.Fatalf("initial mixed-width content is invalid: %+v", initial)
	}
	if initial.SecretRawVisible {
		t.Fatalf("password input view leaked raw secret")
	}

	for range 8 {
		model = model.Apply(tea.KeyPressMsg{Code: tea.KeyLeft})
	}
	for range 4 {
		model = model.Apply(tea.KeyPressMsg{Code: tea.KeyRight})
	}
	model = model.Apply(tea.KeyPressMsg{Code: tea.KeyUp})
	model = model.Apply(tea.KeyPressMsg{Code: tea.KeyDown})
	model = model.Apply(insertDeleteMsg{})
	model = model.Apply(replaceSelectionMsg{})
	afterSelection := model.StateSnapshot()
	if !afterSelection.SelectionReplacementValid {
		t.Fatalf("selection replacement failed: %+v", afterSelection)
	}

	model = model.Apply(undoMsg{})
	model = model.Apply(redoMsg{})
	afterUndoRedo := model.StateSnapshot()
	if !afterUndoRedo.UndoRedoCorrect {
		t.Fatalf("undo/redo state invalid: %+v", afterUndoRedo)
	}

	model = model.Apply(historyPreviousMsg{})
	model = model.Apply(historyPreviousMsg{})
	afterHistory := model.StateSnapshot()
	if !afterHistory.HistoryNavigationCorrect {
		t.Fatalf("history navigation invalid: %+v", afterHistory)
	}

	model = model.Apply(prepareCompletionMsg{})
	model = model.Apply(acceptCompletionMsg{})
	afterCompletion := model.StateSnapshot()
	if !afterCompletion.CompletionAccepted {
		t.Fatalf("completion not accepted: %+v", afterCompletion)
	}

	model = model.Apply(tea.PasteMsg{Content: largePasteText()})
	afterPaste := model.StateSnapshot()
	if !afterPaste.PasteInserted {
		t.Fatalf("paste marker missing: %+v", afterPaste)
	}
	if !afterPaste.MixedWidthValid {
		t.Fatalf("mixed-width content invalid after paste: %+v", afterPaste)
	}
	if afterPaste.SecretRawVisible {
		t.Fatalf("password input view leaked raw secret after paste")
	}
}
