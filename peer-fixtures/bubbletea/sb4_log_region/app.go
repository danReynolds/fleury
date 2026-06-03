package main

import (
	"fmt"
	"regexp"
	"strings"

	"charm.land/bubbles/v2/viewport"
	tea "charm.land/bubbletea/v2"
)

const defaultColumns = 120
const defaultRows = 32

var (
	oscPattern    = regexp.MustCompile(`\x1b\].*?(?:\x07|\x1b\\)`)
	csiPattern    = regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]`)
	secretPattern = regexp.MustCompile(`secret-[A-Za-z0-9_-]+`)
)

type LogEntryRecord struct {
	SourceIndex int
	Key         string
	Text        string
	Sanitized   bool
}

type LogState struct {
	EntryCount              int
	DisplayedCount          int
	LineCount               int
	ScrollY                 int
	MaxScrollY              int
	VisibleWindowRows       int
	SelectedKey             string
	TailAnchored            bool
	FilteredCount           int
	FilterQuery             string
	UnsafeArtifactLeakCount int
}

type appendBurstMsg struct {
	Count int
}

type jumpToScrollbackMsg struct {
	SourceIndex int
}

type tailMsg struct{}

type copyEntryMsg struct{}

type filterQueryMsg struct {
	Query string
}

type Sb4LogRegionModel struct {
	viewport            viewport.Model
	width               int
	height              int
	entries             []LogEntryRecord
	displayedEntries    []LogEntryRecord
	filterText          string
	selectedSourceIndex int
	lastCopiedText      string
	unsafeLeakCount     int
	scrollY             int
}

func NewSb4LogRegionModel(rowCount int, width int, height int) Sb4LogRegionModel {
	model := Sb4LogRegionModel{
		viewport: viewport.New(
			viewport.WithWidth(width),
			viewport.WithHeight(height),
		),
		width:               width,
		height:              height,
		selectedSourceIndex: max(0, rowCount-1),
	}
	model.entries = make([]LogEntryRecord, rowCount)
	for index := range rowCount {
		model.entries[index] = makeLogEntry(index)
	}
	model.displayedEntries = model.entries
	model.syncViewport()
	model.scrollToTail()
	return model
}

func (m Sb4LogRegionModel) Init() tea.Cmd {
	return nil
}

func (m Sb4LogRegionModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case appendBurstMsg:
		m.appendBurst(msg.Count)
	case jumpToScrollbackMsg:
		m.jumpToScrollback(msg.SourceIndex)
	case tailMsg:
		m.scrollToTail()
	case copyEntryMsg:
		m.copySelectedEntry()
	case filterQueryMsg:
		m.filterQuery(msg.Query)
	case tea.KeyPressMsg:
		switch msg.String() {
		case "end":
			m.scrollToTail()
		case "ctrl+c":
			m.copySelectedEntry()
		case "pgup":
			m.viewport.PageUp()
			m.scrollY = m.viewport.YOffset()
		case "pgdown":
			m.viewport.PageDown()
			m.scrollY = m.viewport.YOffset()
		}
	}
	return m, nil
}

func (m Sb4LogRegionModel) View() tea.View {
	return tea.NewView(m.viewport.View())
}

func (m Sb4LogRegionModel) Apply(msg tea.Msg) Sb4LogRegionModel {
	next, _ := m.Update(msg)
	return next.(Sb4LogRegionModel)
}

func (m Sb4LogRegionModel) LastCopiedText() string {
	return m.lastCopiedText
}

func (m Sb4LogRegionModel) StateSnapshot() LogState {
	selectedKey := ""
	if entry, ok := m.selectedEntry(); ok {
		selectedKey = entry.Key
	}
	lineCount := len(m.displayedEntries)
	visibleRows := m.visibleWindowRows()
	return LogState{
		EntryCount:              len(m.entries),
		DisplayedCount:          len(m.displayedEntries),
		LineCount:               lineCount,
		ScrollY:                 min(m.viewport.YOffset(), max(0, lineCount-visibleRows)),
		MaxScrollY:              max(0, lineCount-visibleRows),
		VisibleWindowRows:       visibleRows,
		SelectedKey:             selectedKey,
		TailAnchored:            m.tailAnchored(),
		FilteredCount:           filteredCount(m.filterText, m.displayedEntries),
		FilterQuery:             m.filterText,
		UnsafeArtifactLeakCount: m.unsafeLeakCount,
	}
}

func (m *Sb4LogRegionModel) appendBurst(count int) {
	if count <= 0 {
		return
	}
	start := len(m.entries)
	for offset := range count {
		m.entries = append(m.entries, makeLogEntry(start+offset))
	}
	m.displayedEntries = m.entries
	m.filterText = ""
	m.selectedSourceIndex = len(m.entries) - 1
	m.syncViewport()
	m.scrollToTail()
}

func (m *Sb4LogRegionModel) jumpToScrollback(sourceIndex int) {
	if len(m.entries) == 0 {
		return
	}
	m.displayedEntries = m.entries
	m.filterText = ""
	m.selectedSourceIndex = clamp(sourceIndex, 0, len(m.entries)-1)
	m.syncViewport()
	m.scrollY = min(m.selectedSourceIndex, m.maxScrollY())
	m.viewport.SetYOffset(m.scrollY)
	m.scrollY = m.viewport.YOffset()
}

func (m *Sb4LogRegionModel) scrollToTail() {
	if len(m.entries) == 0 {
		return
	}
	m.displayedEntries = m.entries
	m.filterText = ""
	m.selectedSourceIndex = len(m.entries) - 1
	m.syncViewport()
	m.scrollY = m.maxScrollY()
	m.viewport.GotoBottom()
	m.scrollY = m.viewport.YOffset()
}

func (m *Sb4LogRegionModel) copySelectedEntry() {
	entry, ok := m.selectedEntry()
	if !ok {
		m.lastCopiedText = ""
		return
	}
	m.lastCopiedText = entry.Text
	m.unsafeLeakCount += unsafeCountText(m.lastCopiedText)
}

func (m *Sb4LogRegionModel) filterQuery(query string) int {
	m.filterText = query
	matches := make([]LogEntryRecord, 0)
	for _, entry := range m.entries {
		if strings.Contains(entry.Text, query) {
			matches = append(matches, entry)
		}
	}
	m.displayedEntries = matches
	if len(matches) > 0 {
		m.selectedSourceIndex = matches[len(matches)-1].SourceIndex
	}
	m.syncViewport()
	m.scrollY = m.maxScrollY()
	m.viewport.GotoBottom()
	m.scrollY = m.viewport.YOffset()
	return len(matches)
}

func (m *Sb4LogRegionModel) syncViewport() {
	lines := make([]string, len(m.displayedEntries))
	for index, entry := range m.displayedEntries {
		lines[index] = entry.Text
		m.unsafeLeakCount += unsafeCountText(entry.Text)
	}
	m.viewport.SetContentLines(lines)
}

func (m Sb4LogRegionModel) selectedEntry() (LogEntryRecord, bool) {
	if m.selectedSourceIndex < 0 || m.selectedSourceIndex >= len(m.entries) {
		return LogEntryRecord{}, false
	}
	return m.entries[m.selectedSourceIndex], true
}

func (m Sb4LogRegionModel) visibleWindowRows() int {
	visible := m.viewport.VisibleLineCount()
	if visible <= 0 {
		return max(1, m.height)
	}
	return visible
}

func (m Sb4LogRegionModel) maxScrollY() int {
	return max(0, len(m.displayedEntries)-m.visibleWindowRows())
}

func (m Sb4LogRegionModel) tailAnchored() bool {
	if len(m.entries) == 0 || m.filterText != "" {
		return false
	}
	return m.selectedSourceIndex == len(m.entries)-1 && m.viewport.YOffset() >= m.maxScrollY()
}

func filteredCount(query string, entries []LogEntryRecord) int {
	if query == "" {
		return 0
	}
	return len(entries)
}

func logKey(sourceIndex int) string {
	return fmt.Sprintf("LOG-%06d", 100_000+sourceIndex)
}

func appendFilterQuery(rowCount int) string {
	bucket := (100_000 + rowCount) / 1_000
	return fmt.Sprintf("LOG-%03d", bucket)
}

func unsafeCountText(value string) int {
	count := strings.Count(value, "\x1b")
	count += len(secretPattern.FindAllString(value, -1))
	count += strings.Count(value, "\x07")
	count += strings.Count(value, "\n")
	count += strings.Count(value, "\r")
	return count
}

func sanitizeLogText(raw string) string {
	value := oscPattern.ReplaceAllString(raw, "")
	value = csiPattern.ReplaceAllString(value, "")
	value = secretPattern.ReplaceAllString(value, "[redacted]")
	var builder strings.Builder
	for _, character := range value {
		if character == '\n' || character == '\r' || character == '\t' || character < 0x20 {
			builder.WriteRune(' ')
			continue
		}
		builder.WriteRune(character)
	}
	return strings.Join(strings.Fields(builder.String()), " ")
}

func makeLogEntry(sourceIndex int) LogEntryRecord {
	key := logKey(sourceIndex)
	severity := "INFO"
	if sourceIndex%17 == 0 {
		severity = "ERROR"
	} else if sourceIndex%7 == 0 {
		severity = "WARN"
	}
	payload := fmt.Sprintf(
		"%s %s worker-%d request=%d duration=%dms",
		key,
		severity,
		sourceIndex%23,
		sourceIndex,
		20+sourceIndex%900,
	)
	if sourceIndex%97 == 0 {
		payload += fmt.Sprintf(" \x1b[31mred\x1b[0m secret-%d \x1b]52;c;clipboard-%d\x07", sourceIndex, sourceIndex)
	}
	if sourceIndex%211 == 0 {
		payload += " multiline\ncontinued\rpayload"
	}
	text := sanitizeLogText(payload)
	return LogEntryRecord{
		SourceIndex: sourceIndex,
		Key:         key,
		Text:        text,
		Sanitized:   text != payload,
	}
}

func expectedCopiedText(sourceIndex int) string {
	return makeLogEntry(sourceIndex).Text
}

func clamp(value int, low int, high int) int {
	return max(low, min(value, high))
}
