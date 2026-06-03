package main

import (
	"strings"
	"unicode/utf8"

	"charm.land/bubbles/v2/textarea"
	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"
)

const (
	defaultColumns       = 120
	defaultRows          = 32
	selectionNeedle      = "segment-alpha"
	selectionReplacement = "selection-replaced"
	secretValue          = "secret-bubbletea-sb2"
	completionQuery      = "git che"
	completionAccepted   = "git checkout"
	pasteMarker          = "paste-marker-final"
)

type replaceSelectionMsg struct{}
type insertDeleteMsg struct{}
type undoMsg struct{}
type redoMsg struct{}
type historyPreviousMsg struct{}
type historyNextMsg struct{}
type prepareCompletionMsg struct{}
type acceptCompletionMsg struct{}

type EditingState struct {
	EditorLength              int
	EditorLineCount           int
	EditorLine                int
	EditorColumn              int
	ComposerValue             string
	CurrentSuggestion         string
	SecretRawVisible          bool
	MixedWidthValid           bool
	SelectionReplacementValid bool
	UndoRedoCorrect           bool
	HistoryNavigationCorrect  bool
	CompletionAccepted        bool
	PasteInserted             bool
}

type Sb2TextEditingModel struct {
	editor      textarea.Model
	composer    textinput.Model
	secret      textinput.Model
	width       int
	height      int
	undoStack   []string
	redoStack   []string
	history     []string
	historyPos  int
	undoValue   string
	redoValue   string
	lastHistory string
}

func NewSb2TextEditingModel(textChars int, width int, height int) Sb2TextEditingModel {
	editor := textarea.New()
	editor.Prompt = ""
	editor.ShowLineNumbers = false
	editor.SetWidth(width)
	editor.SetHeight(max(4, height-8))
	editor.SetValue(mixedText(textChars))
	_ = editor.Focus()
	editor.MoveToEnd()

	composer := textinput.New()
	composer.Prompt = ""
	composer.Placeholder = "command"
	composer.ShowSuggestions = true
	composer.SetSuggestions([]string{completionAccepted, "git cherry-pick", "git commit"})
	composer.SetWidth(width)
	composer.SetValue(completionQuery)
	_ = composer.Focus()

	secret := textinput.New()
	secret.Prompt = ""
	secret.EchoMode = textinput.EchoPassword
	secret.EchoCharacter = '*'
	secret.SetWidth(width)
	secret.SetValue(secretValue)

	return Sb2TextEditingModel{
		editor:     editor,
		composer:   composer,
		secret:     secret,
		width:      width,
		height:     height,
		history:    []string{"status --short", "git branch --show-current", completionQuery},
		historyPos: -1,
	}
}

func (m Sb2TextEditingModel) Init() tea.Cmd {
	return nil
}

func (m Sb2TextEditingModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case replaceSelectionMsg:
		m.recordUndo()
		value := m.editor.Value()
		start := runeIndexOf(value, selectionNeedle)
		if start >= 0 {
			end := start + len([]rune(selectionNeedle))
			m.editor.SetValue(replaceRuneRange(value, start, end, selectionReplacement))
			m.editor.MoveToEnd()
		}
	case insertDeleteMsg:
		m.editor, _ = m.editor.Update(tea.KeyPressMsg{Code: 'x', Text: "x"})
		m.editor, _ = m.editor.Update(tea.KeyPressMsg{Code: tea.KeyBackspace})
	case undoMsg:
		m.undo()
	case redoMsg:
		m.redo()
	case historyPreviousMsg:
		m.historyPrevious()
	case historyNextMsg:
		m.historyNext()
	case prepareCompletionMsg:
		m.prepareCompletion()
	case acceptCompletionMsg:
		m.composer, _ = m.composer.Update(tea.KeyPressMsg{Code: tea.KeyTab})
	default:
		switch msg := msg.(type) {
		case tea.KeyPressMsg, tea.PasteMsg:
			m.editor, _ = m.editor.Update(msg)
		}
	}
	return m, nil
}

func (m Sb2TextEditingModel) View() tea.View {
	return tea.NewView(strings.Join([]string{
		"Bubble Tea SB.2 Text Editing",
		m.editor.View(),
		m.composer.View(),
		m.secret.View(),
	}, "\n"))
}

func (m Sb2TextEditingModel) Apply(msg tea.Msg) Sb2TextEditingModel {
	next, _ := m.Update(msg)
	return next.(Sb2TextEditingModel)
}

func (m Sb2TextEditingModel) StateSnapshot() EditingState {
	value := m.editor.Value()
	return EditingState{
		EditorLength:              len([]rune(value)),
		EditorLineCount:           m.editor.LineCount(),
		EditorLine:                m.editor.Line(),
		EditorColumn:              m.editor.Column(),
		ComposerValue:             m.composer.Value(),
		CurrentSuggestion:         m.composer.CurrentSuggestion(),
		SecretRawVisible:          strings.Contains(m.secret.View(), secretValue),
		MixedWidthValid:           mixedWidthValid(value),
		SelectionReplacementValid: strings.Contains(value, selectionReplacement) && !strings.Contains(value, selectionNeedle),
		UndoRedoCorrect:           m.undoValue != "" && m.redoValue != "" && strings.Contains(m.redoValue, selectionReplacement) && strings.Contains(m.undoValue, selectionNeedle),
		HistoryNavigationCorrect:  m.lastHistory == "git branch --show-current",
		CompletionAccepted:        m.composer.Value() == completionAccepted,
		PasteInserted:             strings.Contains(value, pasteMarker),
	}
}

func (m *Sb2TextEditingModel) recordUndo() {
	m.undoStack = append(m.undoStack, m.editor.Value())
	m.redoStack = nil
}

func (m *Sb2TextEditingModel) undo() {
	if len(m.undoStack) == 0 {
		return
	}
	current := m.editor.Value()
	previous := m.undoStack[len(m.undoStack)-1]
	m.undoStack = m.undoStack[:len(m.undoStack)-1]
	m.redoStack = append(m.redoStack, current)
	m.editor.SetValue(previous)
	m.editor.MoveToEnd()
	m.undoValue = previous
}

func (m *Sb2TextEditingModel) redo() {
	if len(m.redoStack) == 0 {
		return
	}
	current := m.editor.Value()
	next := m.redoStack[len(m.redoStack)-1]
	m.redoStack = m.redoStack[:len(m.redoStack)-1]
	m.undoStack = append(m.undoStack, current)
	m.editor.SetValue(next)
	m.editor.MoveToEnd()
	m.redoValue = next
}

func (m *Sb2TextEditingModel) historyPrevious() {
	if len(m.history) == 0 {
		return
	}
	if m.historyPos < 0 || m.historyPos > len(m.history) {
		m.historyPos = len(m.history)
	}
	if m.historyPos > 0 {
		m.historyPos--
	}
	m.composer.SetValue(m.history[m.historyPos])
	m.lastHistory = m.composer.Value()
}

func (m *Sb2TextEditingModel) historyNext() {
	if len(m.history) == 0 {
		return
	}
	if m.historyPos < 0 {
		m.historyPos = len(m.history)
	}
	if m.historyPos < len(m.history)-1 {
		m.historyPos++
		m.composer.SetValue(m.history[m.historyPos])
		m.lastHistory = m.composer.Value()
		return
	}
	m.historyPos = len(m.history)
	m.composer.SetValue("")
	m.lastHistory = m.composer.Value()
}

func (m *Sb2TextEditingModel) prepareCompletion() {
	m.composer.Reset()
	_ = m.composer.Focus()
	for _, r := range completionQuery {
		m.composer, _ = m.composer.Update(tea.KeyPressMsg{
			Code: r,
			Text: string(r),
		})
	}
}

func mixedText(targetRunes int) string {
	if targetRunes < 256 {
		targetRunes = 256
	}
	var builder strings.Builder
	builder.WriteString(selectionNeedle)
	builder.WriteString(" ascii words ")
	parts := []string{
		"segment-beta ascii words ",
		"cafe\u0301 combining mark ",
		"界面 表格 入力 ",
		"emoji🙂 cursor ",
		"line-wrap sample text\n",
	}
	for len([]rune(builder.String())) < targetRunes {
		for _, part := range parts {
			builder.WriteString(part)
			if len([]rune(builder.String())) >= targetRunes {
				break
			}
		}
	}
	return builder.String()
}

func largePasteText() string {
	return strings.Repeat("paste🙂界 cafe\u0301 ", 128) + pasteMarker
}

func mixedWidthValid(value string) bool {
	return utf8.ValidString(value) &&
		strings.Contains(value, "cafe\u0301") &&
		strings.Contains(value, "界面") &&
		strings.Contains(value, "emoji🙂")
}

func runeIndexOf(value string, needle string) int {
	index := strings.Index(value, needle)
	if index < 0 {
		return -1
	}
	return len([]rune(value[:index]))
}

func replaceRuneRange(value string, start int, end int, replacement string) string {
	runes := []rune(value)
	start = clamp(start, 0, len(runes))
	end = clamp(end, start, len(runes))
	return string(runes[:start]) + replacement + string(runes[end:])
}

func clamp(value int, low int, high int) int {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}
