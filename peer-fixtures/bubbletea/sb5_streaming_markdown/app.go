package main

import (
	"fmt"
	"regexp"
	"strings"

	"charm.land/bubbles/v2/viewport"
	tea "charm.land/bubbletea/v2"
	"charm.land/glamour/v2"
)

const defaultColumns = 120
const defaultRows = 32

var (
	oscPattern     = regexp.MustCompile(`\x1b\].*?(?:\x07|\x1b\\)`)
	csiPattern     = regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]`)
	secretPattern  = regexp.MustCompile(`secret-[A-Za-z0-9_-]+`)
	linkPattern    = regexp.MustCompile(`\[([^\]]+)\]\(([^)]+)\)`)
	orderedPattern = regexp.MustCompile(`^\s*\d+\.\s+`)
	sgrPattern     = regexp.MustCompile(`\x1b\[[0-9:;]*m`)
	osc8Pattern    = regexp.MustCompile(`\x1b]8;.*?(?:\x07|\x1b\\)`)
)

var safeSchemes = map[string]bool{
	"http":   true,
	"https":  true,
	"mailto": true,
}

type MarkdownBlockRecord struct {
	Index      int
	Kind       string
	SourceText string
	Sanitized  bool
	Truncated  bool
}

type MarkdownDocumentRecord struct {
	Source                         string
	Blocks                         []MarkdownBlockRecord
	HeadingCount                   int
	ListItemCount                  int
	LinkCount                      int
	UnsafeLinkCount                int
	CodeBlockCount                 int
	CodeLineCount                  int
	UnsafeLinksHaveVisibleFallback bool
}

type MarkdownState struct {
	ChunkCount                     int
	SourceByteCount                int
	BlockCount                     int
	HeadingCount                   int
	ListItemCount                  int
	LinkCount                      int
	UnsafeLinkCount                int
	CodeBlockCount                 int
	CodeLineCount                  int
	SelectedBlockIndex             int
	SelectedBlockKind              string
	ScrollY                        int
	MaxScrollY                     int
	VisibleWindowRows              int
	UnsafeArtifactLeakCount        int
	SanitizedBlockCount            int
	SanitizedChunkCount            int
	TruncatedBlockCount            int
	CopiedByteCount                int
	UnsafeLinksHaveVisibleFallback bool
}

type appendChunkMsg struct {
	RawChunk string
}

type selectFinalBlockMsg struct{}

type copyBlockMsg struct{}

type MarkdownFixture struct {
	Seed int
}

func (f MarkdownFixture) Chunk(index int) string {
	chunkID := index + f.Seed
	section := index / 12
	switch index % 12 {
	case 0:
		return fmt.Sprintf("## Stream batch %d\n", section)
	case 1:
		return fmt.Sprintf("Paragraph %d starts with **bold** text, ", chunkID)
	case 2:
		return fmt.Sprintf(
			"[docs-%d](https://fleury.dev/docs/%d), `inline-code`, and mixed width text.\n",
			chunkID,
			chunkID,
		)
	case 3:
		return fmt.Sprintf("- checklist item %d keeps semantic list state\n", chunkID)
	case 4:
		return fmt.Sprintf("| field | value |\n| --- | --- |\n| chunk | %d |\n", chunkID)
	case 5:
		return fmt.Sprintf(
			"```dart\nfinal chunk%d = \"safe\";\nfinal hidden%d = \"\x1b]52;c;secret-%d\x07\";\n",
			chunkID,
			chunkID,
			chunkID,
		)
	case 6:
		return fmt.Sprintf("print(chunk%d);\n```\n", chunkID)
	case 7:
		return fmt.Sprintf("> quoted output %d \x1b]52;c;secret-%d\x07 stays inert\n", chunkID, chunkID)
	case 8:
		return fmt.Sprintf(
			"1. ordered item %d with [mail](mailto:ops%d@example.com)\n",
			chunkID,
			chunkID,
		)
	case 9:
		return "\n"
	case 10:
		return fmt.Sprintf("%s\n", longMarkdownParagraph(chunkID))
	default:
		return fmt.Sprintf(
			"[unsafe-%d](javascript:alert(%d)) visible fallback only\n",
			chunkID,
			chunkID,
		)
	}
}

type Sb5StreamingMarkdownModel struct {
	viewport            viewport.Model
	renderer            *glamour.TermRenderer
	width               int
	height              int
	source              string
	document            MarkdownDocumentRecord
	chunkCount          int
	selectedBlockIndex  int
	lastCopiedText      string
	sanitizedChunkCount int
	unsafeLeakCount     int
	lastRenderError     string
	renderedLineCount   int
	renderedByteCount   int
	rendererInitialized bool
}

func NewSb5StreamingMarkdownModel(width int, height int) Sb5StreamingMarkdownModel {
	renderer, err := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(width),
	)
	model := Sb5StreamingMarkdownModel{
		viewport: viewport.New(
			viewport.WithWidth(width),
			viewport.WithHeight(height),
		),
		renderer:            renderer,
		width:               width,
		height:              height,
		document:            parseMarkdownDocument(""),
		rendererInitialized: err == nil,
	}
	if err != nil {
		model.lastRenderError = err.Error()
	}
	return model
}

func (m Sb5StreamingMarkdownModel) Init() tea.Cmd {
	return nil
}

func (m Sb5StreamingMarkdownModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case appendChunkMsg:
		m.appendChunk(msg.RawChunk)
	case selectFinalBlockMsg:
		m.selectFinalBlock()
	case copyBlockMsg:
		m.copySelectedBlock()
	case tea.KeyPressMsg:
		switch msg.String() {
		case "end":
			m.selectFinalBlock()
		case "ctrl+c":
			m.copySelectedBlock()
		case "pgup":
			m.viewport.PageUp()
		case "pgdown":
			m.viewport.PageDown()
		}
	}
	return m, nil
}

func (m Sb5StreamingMarkdownModel) View() tea.View {
	return tea.NewView(m.viewport.View())
}

func (m Sb5StreamingMarkdownModel) Apply(msg tea.Msg) Sb5StreamingMarkdownModel {
	next, _ := m.Update(msg)
	return next.(Sb5StreamingMarkdownModel)
}

func (m Sb5StreamingMarkdownModel) LastCopiedText() string {
	return m.lastCopiedText
}

func (m Sb5StreamingMarkdownModel) StateSnapshot() MarkdownState {
	selectedKind := ""
	if len(m.document.Blocks) > 0 {
		index := clamp(m.selectedBlockIndex, 0, len(m.document.Blocks)-1)
		selectedKind = m.document.Blocks[index].Kind
	}
	return MarkdownState{
		ChunkCount:                     m.chunkCount,
		SourceByteCount:                len([]byte(m.document.Source)),
		BlockCount:                     len(m.document.Blocks),
		HeadingCount:                   m.document.HeadingCount,
		ListItemCount:                  m.document.ListItemCount,
		LinkCount:                      m.document.LinkCount,
		UnsafeLinkCount:                m.document.UnsafeLinkCount,
		CodeBlockCount:                 m.document.CodeBlockCount,
		CodeLineCount:                  m.document.CodeLineCount,
		SelectedBlockIndex:             m.selectedBlockIndex,
		SelectedBlockKind:              selectedKind,
		ScrollY:                        min(m.viewport.YOffset(), max(0, m.renderedLineCount-m.visibleWindowRows())),
		MaxScrollY:                     max(0, m.renderedLineCount-m.visibleWindowRows()),
		VisibleWindowRows:              m.visibleWindowRows(),
		UnsafeArtifactLeakCount:        m.unsafeLeakCount,
		SanitizedBlockCount:            sanitizedBlockCount(m.document.Blocks),
		SanitizedChunkCount:            m.sanitizedChunkCount,
		TruncatedBlockCount:            truncatedBlockCount(m.document.Blocks),
		CopiedByteCount:                len([]byte(m.lastCopiedText)),
		UnsafeLinksHaveVisibleFallback: m.document.UnsafeLinksHaveVisibleFallback,
	}
}

func (m *Sb5StreamingMarkdownModel) appendChunk(rawChunk string) {
	chunk := sanitizeMarkdownChunk(rawChunk)
	if chunk != rawChunk {
		m.sanitizedChunkCount++
	}
	m.unsafeLeakCount += unsafeCountText(chunk)
	m.source += chunk
	m.chunkCount++
	m.document = parseMarkdownDocument(m.source)
	m.syncViewport()
}

func (m *Sb5StreamingMarkdownModel) selectFinalBlock() {
	m.selectedBlockIndex = max(0, len(m.document.Blocks)-1)
	m.viewport.GotoBottom()
}

func (m *Sb5StreamingMarkdownModel) copySelectedBlock() string {
	if len(m.document.Blocks) == 0 {
		m.lastCopiedText = ""
		return m.lastCopiedText
	}
	index := clamp(m.selectedBlockIndex, 0, len(m.document.Blocks)-1)
	m.lastCopiedText = m.document.Blocks[index].SourceText
	m.unsafeLeakCount += unsafeCountText(m.lastCopiedText)
	return m.lastCopiedText
}

func (m *Sb5StreamingMarkdownModel) syncViewport() {
	rendered := m.source
	if m.renderer != nil {
		output, err := m.renderer.Render(m.source)
		if err != nil {
			m.lastRenderError = err.Error()
		} else {
			rendered = output
			m.lastRenderError = ""
		}
	}
	m.unsafeLeakCount += unsafeVisibleTextCount(rendered)
	lines := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if len(lines) == 1 && lines[0] == "" {
		lines = []string{}
	}
	m.renderedLineCount = len(lines)
	m.renderedByteCount = len([]byte(rendered))
	m.viewport.SetContentLines(lines)
}

func (m Sb5StreamingMarkdownModel) visibleWindowRows() int {
	visible := m.viewport.VisibleLineCount()
	if visible <= 0 {
		return max(1, m.height)
	}
	return visible
}

func longMarkdownParagraph(chunkID int) string {
	words := make([]string, 24)
	for offset := range words {
		words[offset] = fmt.Sprintf("word%d", (chunkID+offset)%17)
	}
	return fmt.Sprintf(
		"Long paragraph %d %s with ~~strike~~ and _emphasis_.",
		chunkID,
		strings.Join(words, " "),
	)
}

func markdownChunkCountFor(rowCount int) int {
	scaled := rowCount / 100
	if scaled < 64 {
		return 64
	}
	if scaled > 1024 {
		return 1024
	}
	return scaled
}

func sanitizeMarkdownChunk(raw string) string {
	value := oscPattern.ReplaceAllString(raw, "")
	value = csiPattern.ReplaceAllString(value, "")
	value = secretPattern.ReplaceAllString(value, "[redacted]")
	var cleaned strings.Builder
	for _, character := range value {
		if character == '\r' || character == '\t' || (character < 0x20 && character != '\n') {
			cleaned.WriteRune(' ')
			continue
		}
		cleaned.WriteRune(character)
	}
	return rewriteLinksWithVisibleFallback(cleaned.String())
}

func rewriteLinksWithVisibleFallback(value string) string {
	lines := strings.SplitAfter(value, "\n")
	inCode := false
	var output strings.Builder
	for _, line := range lines {
		stripped := strings.TrimSpace(line)
		if strings.HasPrefix(stripped, "```") {
			inCode = !inCode
			output.WriteString(line)
			continue
		}
		if inCode {
			output.WriteString(line)
			continue
		}
		output.WriteString(linkPattern.ReplaceAllStringFunc(line, func(match string) string {
			parts := linkPattern.FindStringSubmatch(match)
			if len(parts) != 3 {
				return match
			}
			label := parts[1]
			url := parts[2]
			scheme := urlScheme(url)
			if safeSchemes[scheme] {
				return fmt.Sprintf("[%s](%s) (%s)", label, url, url)
			}
			return fmt.Sprintf("[%s](#blocked) (unsafe link: %s)", label, url)
		}))
	}
	return output.String()
}

func parseMarkdownDocument(source string) MarkdownDocumentRecord {
	return parseMarkdownDocumentWithLimit(source, 1_000)
}

func parseMarkdownDocumentWithLimit(source string, maxLineLength int) MarkdownDocumentRecord {
	document := MarkdownDocumentRecord{
		Source:                         source,
		UnsafeLinksHaveVisibleFallback: true,
	}
	inCode := false
	currentCode := make([]string, 0)

	addBlock := func(kind string, text string, sanitized bool) {
		if kind == "blank" {
			return
		}
		truncated := len([]byte(text)) > maxLineLength
		if truncated {
			text = string([]byte(text)[:maxLineLength])
		}
		document.Blocks = append(document.Blocks, MarkdownBlockRecord{
			Index:      len(document.Blocks),
			Kind:       kind,
			SourceText: text,
			Sanitized:  sanitized,
			Truncated:  truncated,
		})
		if kind == "heading" {
			document.HeadingCount++
		}
		if kind == "bullet" || kind == "ordered" {
			document.ListItemCount++
		}
	}

	for _, line := range strings.Split(source, "\n") {
		stripped := strings.TrimSpace(line)
		if strings.HasPrefix(stripped, "```") {
			if inCode {
				addBlock("codeFence", strings.Join(currentCode, "\n"), false)
				currentCode = currentCode[:0]
			} else {
				document.CodeBlockCount++
			}
			inCode = !inCode
			continue
		}
		if inCode {
			document.CodeLineCount++
			currentCode = append(currentCode, line)
			continue
		}

		matches := linkPattern.FindAllStringSubmatch(line, -1)
		for _, match := range matches {
			document.LinkCount++
			url := match[2]
			scheme := urlScheme(url)
			if !safeSchemes[scheme] && url != "#blocked" {
				document.UnsafeLinkCount++
				document.UnsafeLinksHaveVisibleFallback = false
			}
		}
		if strings.Contains(line, "(unsafe link:") {
			document.UnsafeLinkCount += strings.Count(line, "(unsafe link:")
		}

		switch {
		case stripped == "":
			addBlock("blank", "", false)
		case strings.HasPrefix(stripped, "#"):
			addBlock("heading", line, unsafeCountText(line) > 0)
		case strings.HasPrefix(stripped, "- ") || strings.HasPrefix(stripped, "* "):
			addBlock("bullet", line, unsafeCountText(line) > 0)
		case orderedPattern.MatchString(line):
			addBlock("ordered", line, unsafeCountText(line) > 0)
		case strings.HasPrefix(stripped, ">"):
			addBlock("blockquote", line, unsafeCountText(line) > 0)
		case strings.HasPrefix(stripped, "|"):
			addBlock("tableRow", line, unsafeCountText(line) > 0)
		default:
			addBlock("paragraph", line, unsafeCountText(line) > 0)
		}
	}

	if inCode && len(currentCode) > 0 {
		addBlock("codeFence", strings.Join(currentCode, "\n"), false)
	}
	return document
}

func urlScheme(url string) string {
	index := strings.Index(url, ":")
	if index <= 0 {
		return ""
	}
	return strings.ToLower(url[:index])
}

func unsafeCountText(value string) int {
	count := strings.Count(value, "\x1b")
	count += len(secretPattern.FindAllString(value, -1))
	count += strings.Count(value, "\x07")
	count += strings.Count(value, "\r")
	return count
}

func unsafeVisibleTextCount(value string) int {
	value = stripSafeSGR(value)
	value = stripSafeOSC8(value)
	count := len(oscPattern.FindAllString(value, -1))
	count += len(secretPattern.FindAllString(value, -1))
	count += strings.Count(value, "\x07")
	count += strings.Count(value, "\r")
	value = oscPattern.ReplaceAllString(value, "")
	count += strings.Count(value, "\x1b")
	return count
}

func stripSafeSGR(value string) string {
	return sgrPattern.ReplaceAllString(value, "")
}

func stripSafeOSC8(value string) string {
	return osc8Pattern.ReplaceAllString(value, "")
}

func sanitizedBlockCount(blocks []MarkdownBlockRecord) int {
	count := 0
	for _, block := range blocks {
		if block.Sanitized {
			count++
		}
	}
	return count
}

func truncatedBlockCount(blocks []MarkdownBlockRecord) int {
	count := 0
	for _, block := range blocks {
		if block.Truncated {
			count++
		}
	}
	return count
}

func clamp(value int, low int, high int) int {
	return max(low, min(value, high))
}
