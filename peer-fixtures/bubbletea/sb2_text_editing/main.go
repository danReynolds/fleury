package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

const (
	schemaVersion     = 1
	peerID            = "bubbletea"
	peerName          = "Bubble Tea + Bubbles"
	bubbleTeaVersion  = "2.0.7"
	bubblesVersion    = "2.1.0"
	peerURL           = "https://pkg.go.dev/charm.land/bubbles/v2"
	scenarioID        = "SB.2"
	defaultWarmups    = 1
	defaultIterations = 5
	defaultTextChars  = 10_000
	defaultWireSteps  = 8
	defaultWireMs     = 60
)

type Options struct {
	WarmupIterations   int
	MeasuredIterations int
	TextChars          int
	TerminalColumns    int
	TerminalRows       int
	PrintJSON          bool
	OutputPath         string
	Wire               bool
	WireSteps          int
	WireIntervalMs     int
}

type Sample struct {
	MountUs                int64
	FirstRenderUs          int64
	CursorMoveUs           int64
	InsertionDeletionUs    int64
	SelectionUs            int64
	UndoRedoUs             int64
	HistoryNavigationUs    int64
	CompletionAcceptUs     int64
	PasteCompleteUs        int64
	SemanticOrTestQueryUs  int64
	RSSDeltaBytes          int64
	MixedWidthValid        bool
	SelectionUndoCorrect   bool
	RedactedValueStaysSafe bool
	HistoryCorrect         bool
	CompletionCorrect      bool
	PasteCorrect           bool
	EditorLength           int
	EditorLineCount        int
	ComposerValue          string
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if options.Wire {
		if err := runWire(options); err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	for range options.WarmupIterations {
		_ = runSample(options)
	}

	samples := make([]Sample, options.MeasuredIterations)
	for index := range options.MeasuredIterations {
		samples[index] = runSample(options)
	}

	artifact := buildArtifact(options, samples)
	jsonText, err := json.MarshalIndent(artifact, "", "  ")
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if options.OutputPath != "" {
		if err := os.MkdirAll(filepath.Dir(options.OutputPath), 0o755); err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := os.WriteFile(options.OutputPath, append(jsonText, '\n'), 0o644); err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}

	if options.PrintJSON {
		fmt.Println(string(jsonText))
		return
	}

	metrics := artifact["metrics"].(map[string]any)
	fmt.Println("Bubble Tea SB.2 text editing fixture")
	fmt.Printf("Run: %s\n", artifact["runId"])
	fmt.Printf("Text chars: %d\n", options.TextChars)
	fmt.Printf("Iterations: %d\n", options.MeasuredIterations)
	fmt.Printf("cursorMoveUs p95: %v\n", metrics["cursorMoveUs"].(map[string]any)["p95"])
	fmt.Printf("pasteCompleteUs p95: %v\n", metrics["pasteCompleteUs"].(map[string]any)["p95"])
	if options.OutputPath != "" {
		fmt.Printf("Saved %s\n", options.OutputPath)
	}
}

type wireModel struct {
	Sb2TextEditingModel
}

func (m wireModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	next, cmd := m.Sb2TextEditingModel.Update(msg)
	if typed, ok := next.(Sb2TextEditingModel); ok {
		m.Sb2TextEditingModel = typed
	}
	return m, cmd
}

func (m wireModel) View() tea.View {
	view := m.Sb2TextEditingModel.View()
	view.AltScreen = true
	return view
}

func runWire(options Options) error {
	model := wireModel{
		Sb2TextEditingModel: NewSb2TextEditingModel(
			options.TextChars,
			options.TerminalColumns,
			options.TerminalRows,
		),
	}
	program := tea.NewProgram(
		model,
		tea.WithInput(nil),
		tea.WithWindowSize(options.TerminalColumns, options.TerminalRows),
		tea.WithFPS(60),
	)

	go func() {
		interval := time.Duration(options.WireIntervalMs) * time.Millisecond
		time.Sleep(interval)
		for step := 0; step < options.WireSteps; step++ {
			switch step % 8 {
			case 0:
				for range 12 {
					program.Send(tea.KeyPressMsg{Code: tea.KeyLeft})
				}
				for range 6 {
					program.Send(tea.KeyPressMsg{Code: tea.KeyRight})
				}
			case 1:
				program.Send(insertDeleteMsg{})
			case 2:
				program.Send(replaceSelectionMsg{})
			case 3:
				program.Send(undoMsg{})
				program.Send(redoMsg{})
			case 4:
				program.Send(tea.PasteMsg{Content: largePasteText()})
			case 5:
				program.Send(prepareCompletionMsg{})
				program.Send(acceptCompletionMsg{})
			case 6:
				program.Send(historyPreviousMsg{})
				program.Send(historyNextMsg{})
			case 7:
				program.Send(tea.KeyPressMsg{Code: tea.KeyUp})
			}
			time.Sleep(interval)
		}
		program.Quit()
	}()

	_, err := program.Run()
	return err
}

func runSample(options Options) Sample {
	rssBefore := currentRSSBytes()
	mountStart := time.Now()
	model := NewSb2TextEditingModel(options.TextChars, options.TerminalColumns, options.TerminalRows)
	mountUs := elapsedUs(mountStart)

	firstRenderStart := time.Now()
	firstView := model.View().Content
	firstRenderUs := elapsedUs(firstRenderStart)

	cursorStart := time.Now()
	for range 24 {
		model = model.Apply(tea.KeyPressMsg{Code: tea.KeyLeft})
	}
	for range 12 {
		model = model.Apply(tea.KeyPressMsg{Code: tea.KeyRight})
	}
	model = model.Apply(tea.KeyPressMsg{Code: tea.KeyUp})
	model = model.Apply(tea.KeyPressMsg{Code: tea.KeyDown})
	cursorMoveUs := elapsedUs(cursorStart)

	insertStart := time.Now()
	model = model.Apply(insertDeleteMsg{})
	insertionDeletionUs := elapsedUs(insertStart)

	selectionStart := time.Now()
	model = model.Apply(replaceSelectionMsg{})
	selectionUs := elapsedUs(selectionStart)

	undoStart := time.Now()
	model = model.Apply(undoMsg{})
	model = model.Apply(redoMsg{})
	undoRedoUs := elapsedUs(undoStart)

	historyStart := time.Now()
	model = model.Apply(historyPreviousMsg{})
	model = model.Apply(historyPreviousMsg{})
	historyNavigationUs := elapsedUs(historyStart)

	completionStart := time.Now()
	model = model.Apply(prepareCompletionMsg{})
	model = model.Apply(acceptCompletionMsg{})
	completionAcceptUs := elapsedUs(completionStart)

	pasteStart := time.Now()
	model = model.Apply(tea.PasteMsg{Content: largePasteText()})
	pasteCompleteUs := elapsedUs(pasteStart)

	queryStart := time.Now()
	state := model.StateSnapshot()
	viewText := firstView + "\n" + model.View().Content
	semanticOrTestQueryUs := elapsedUs(queryStart)
	rssAfter := currentRSSBytes()

	return Sample{
		MountUs:                mountUs,
		FirstRenderUs:          firstRenderUs,
		CursorMoveUs:           cursorMoveUs,
		InsertionDeletionUs:    insertionDeletionUs,
		SelectionUs:            selectionUs,
		UndoRedoUs:             undoRedoUs,
		HistoryNavigationUs:    historyNavigationUs,
		CompletionAcceptUs:     completionAcceptUs,
		PasteCompleteUs:        pasteCompleteUs,
		SemanticOrTestQueryUs:  semanticOrTestQueryUs,
		RSSDeltaBytes:          max64(0, rssAfter-rssBefore),
		MixedWidthValid:        state.MixedWidthValid,
		SelectionUndoCorrect:   state.SelectionReplacementValid && state.UndoRedoCorrect,
		RedactedValueStaysSafe: !state.SecretRawVisible && !strings.Contains(viewText, secretValue),
		HistoryCorrect:         state.HistoryNavigationCorrect,
		CompletionCorrect:      state.CompletionAccepted,
		PasteCorrect:           state.PasteInserted,
		EditorLength:           state.EditorLength,
		EditorLineCount:        state.EditorLineCount,
		ComposerValue:          state.ComposerValue,
	}
}

func buildArtifact(options Options, samples []Sample) map[string]any {
	capturedAt := time.Now().UTC()
	last := samples[len(samples)-1]
	appLines := sourceLineCount("app.go")
	benchmarkLines := sourceLineCount("main.go")
	testLines := sourceLineCount("app_test.go")

	return map[string]any{
		"schemaVersion": schemaVersion,
		"kind":          "fleuryPeerBenchmarkRun",
		"runId":         fmt.Sprintf("bubbletea-sb2-text-editing-%s", timestampForID(capturedAt)),
		"peerId":        peerID,
		"scenarioId":    scenarioID,
		"capturedAt":    capturedAt.Format(time.RFC3339Nano),
		"source": map[string]any{
			"name":    peerName,
			"version": fmt.Sprintf("Bubble Tea %s / Bubbles %s", bubbleTeaVersion, bubblesVersion),
			"url":     peerURL,
		},
		"environment": map[string]any{
			"machine":                hostname(),
			"operatingSystem":        runtime.GOOS,
			"operatingSystemVersion": osVersion(),
			"runtime": fmt.Sprintf(
				"%s / Bubble Tea %s / Bubbles %s",
				runtime.Version(),
				bubbleTeaVersion,
				bubblesVersion,
			),
			"terminalMode": "bubbletea-textarea-model-harness",
			"terminalSize": map[string]any{
				"columns": options.TerminalColumns,
				"rows":    options.TerminalRows,
			},
		},
		"fixture": map[string]any{
			"workingDirectory": "peer-fixtures/bubbletea/sb2_text_editing",
			"command": []string{
				"go",
				"run",
				".",
				fmt.Sprintf("--warmup=%d", options.WarmupIterations),
				fmt.Sprintf("--iterations=%d", options.MeasuredIterations),
				fmt.Sprintf("--text-chars=%d", options.TextChars),
				"--json",
			},
			"warmupIterations":   options.WarmupIterations,
			"measuredIterations": options.MeasuredIterations,
		},
		"metrics": map[string]any{
			"mountUs":               stats(samples, func(sample Sample) int64 { return sample.MountUs }),
			"firstRenderUs":         stats(samples, func(sample Sample) int64 { return sample.FirstRenderUs }),
			"cursorMoveUs":          stats(samples, func(sample Sample) int64 { return sample.CursorMoveUs }),
			"insertionDeletionUs":   stats(samples, func(sample Sample) int64 { return sample.InsertionDeletionUs }),
			"selectionUs":           stats(samples, func(sample Sample) int64 { return sample.SelectionUs }),
			"undoRedoUs":            stats(samples, func(sample Sample) int64 { return sample.UndoRedoUs }),
			"historyNavigationUs":   stats(samples, func(sample Sample) int64 { return sample.HistoryNavigationUs }),
			"completionAcceptUs":    stats(samples, func(sample Sample) int64 { return sample.CompletionAcceptUs }),
			"pasteCompleteUs":       stats(samples, func(sample Sample) int64 { return sample.PasteCompleteUs }),
			"semanticOrTestQueryUs": stats(samples, func(sample Sample) int64 { return sample.SemanticOrTestQueryUs }),
			"rssDeltaBytes": maxSample(samples, func(sample Sample) int64 {
				return sample.RSSDeltaBytes
			}),
			"lineOfCodeCount":          appLines,
			"benchmarkLineOfCodeCount": benchmarkLines,
			"testLineOfCodeCount":      testLines,
			"textCharsRequested":       options.TextChars,
			"editorLength":             last.EditorLength,
			"editorLineCount":          last.EditorLineCount,
			"composerValue":            last.ComposerValue,
			"adapterOwnedFeatureCount": 3,
		},
		"correctness": []map[string]any{
			{
				"gate": "mixed-width text remains valid",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.MixedWidthValid && sample.PasteCorrect
				}),
				"evidence": "Bubbles textarea retained emoji, CJK, combining text, and the paste marker.",
			},
			{
				"gate": "selection and undo state are correct",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.SelectionUndoCorrect
				}),
				"evidence": "Selection replacement, undo, and redo were fixture-owned adapters over the Bubbles textarea value.",
			},
			{
				"gate": "redacted value stays redacted",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.RedactedValueStaysSafe
				}),
				"evidence": "Password textinput view did not contain the raw secret.",
			},
		},
		"ergonomics": map[string]any{
			"lineOfCodeCount":          appLines,
			"benchmarkLineOfCodeCount": benchmarkLines,
			"testLineOfCodeCount":      testLines,
			"appFile":                  "app.go",
			"benchmarkFile":            "main.go",
			"testFile":                 "app_test.go",
			"peerOwnedTextarea":        true,
			"peerOwnedTextinput":       true,
			"peerOwnedPasteHandling":   true,
			"peerOwnedCompletion":      true,
			"appOwnedSelection":        true,
			"appOwnedUndoRedo":         true,
			"appOwnedHistory":          true,
			"semanticGraphAvailable":   false,
			"testQueryViaAppState":     true,
		},
		"artifacts": []map[string]any{
			{
				"kind": "source",
				"path": "peer-fixtures/bubbletea/sb2_text_editing/app.go",
			},
			{
				"kind": "benchmark",
				"path": "peer-fixtures/bubbletea/sb2_text_editing/main.go",
			},
			{
				"kind": "test",
				"path": "peer-fixtures/bubbletea/sb2_text_editing/app_test.go",
			},
		},
		"notes": []string{
			"This is a Bubble Tea/Bubbles textarea and textinput model harness, not a real-terminal run.",
			"Bubble Tea 2.0.7 supplies the Model/Update/View architecture; Bubbles 2.1.0 supplies textarea cursor/edit/paste behavior, textinput password masking, and textinput suggestions.",
			"Selection replacement, undo/redo, and submission history are app-owned fixture adapters because Bubbles textarea/textinput do not expose Fleury-equivalent primitives for those SB.2 behaviors.",
			"Bubble Tea/Bubbles exposes app/model state for this fixture, not a Fleury-style semantic app graph.",
			"Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
		},
	}
}

func parseArgs(args []string) (Options, error) {
	options := Options{
		WarmupIterations:   defaultWarmups,
		MeasuredIterations: defaultIterations,
		TextChars:          defaultTextChars,
		TerminalColumns:    defaultColumns,
		TerminalRows:       defaultRows,
		WireSteps:          defaultWireSteps,
		WireIntervalMs:     defaultWireMs,
	}
	for _, arg := range args {
		switch {
		case arg == "--wire":
			options.Wire = true
		case arg == "--json":
			options.PrintJSON = true
		case strings.HasPrefix(arg, "--warmup="):
			value, err := positiveOrZeroInt(strings.TrimPrefix(arg, "--warmup="), "warmup")
			if err != nil {
				return Options{}, err
			}
			options.WarmupIterations = value
		case strings.HasPrefix(arg, "--iterations="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--iterations="), "iterations")
			if err != nil {
				return Options{}, err
			}
			options.MeasuredIterations = value
		case strings.HasPrefix(arg, "--text-chars="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--text-chars="), "text-chars")
			if err != nil {
				return Options{}, err
			}
			options.TextChars = value
		case strings.HasPrefix(arg, "--rows="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--rows="), "rows")
			if err != nil {
				return Options{}, err
			}
			options.TextChars = value
		case strings.HasPrefix(arg, "--steps="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--steps="), "steps")
			if err != nil {
				return Options{}, err
			}
			options.WireSteps = value
		case strings.HasPrefix(arg, "--interval-ms="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--interval-ms="), "interval-ms")
			if err != nil {
				return Options{}, err
			}
			options.WireIntervalMs = value
		case strings.HasPrefix(arg, "--size="):
			columns, rows, err := parseSize(strings.TrimPrefix(arg, "--size="))
			if err != nil {
				return Options{}, err
			}
			options.TerminalColumns = columns
			options.TerminalRows = rows
		case strings.HasPrefix(arg, "--output="):
			options.OutputPath = strings.TrimPrefix(arg, "--output=")
		default:
			return Options{}, fmt.Errorf("unknown argument: %s", arg)
		}
	}
	return options, nil
}

func positiveInt(value string, label string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return 0, fmt.Errorf("--%s must be positive", label)
	}
	return parsed, nil
}

func positiveOrZeroInt(value string, label string) (int, error) {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return 0, fmt.Errorf("--%s must be zero or positive", label)
	}
	return parsed, nil
}

func parseSize(value string) (int, int, error) {
	parts := strings.Split(value, "x")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("--size must be COLUMNSxROWS")
	}
	columns, err := positiveInt(parts[0], "size columns")
	if err != nil {
		return 0, 0, err
	}
	rows, err := positiveInt(parts[1], "size rows")
	if err != nil {
		return 0, 0, err
	}
	return columns, rows, nil
}

func elapsedUs(start time.Time) int64 {
	return time.Since(start).Microseconds()
}

func stats(samples []Sample, value func(Sample) int64) map[string]any {
	values := make([]int64, len(samples))
	for index, sample := range samples {
		values[index] = value(sample)
	}
	sort.Slice(values, func(i int, j int) bool {
		return values[i] < values[j]
	})
	if len(values) == 0 {
		return map[string]any{"min": 0, "median": 0, "p95": 0, "p99": 0, "max": 0, "samples": 0}
	}
	return map[string]any{
		"min":     values[0],
		"median":  percentile(values, 0.50),
		"p95":     percentile(values, 0.95),
		"p99":     percentile(values, 0.99),
		"max":     values[len(values)-1],
		"samples": len(values),
	}
}

func percentile(values []int64, fraction float64) int64 {
	if len(values) == 1 {
		return values[0]
	}
	index := int(float64(len(values)-1)*fraction + 0.999999)
	if index >= len(values) {
		index = len(values) - 1
	}
	return values[index]
}

func allSamples(samples []Sample, predicate func(Sample) bool) bool {
	for _, sample := range samples {
		if !predicate(sample) {
			return false
		}
	}
	return true
}

func maxSample(samples []Sample, value func(Sample) int64) int64 {
	var result int64
	for index, sample := range samples {
		next := value(sample)
		if index == 0 || next > result {
			result = next
		}
	}
	return result
}

func currentRSSBytes() int64 {
	output, err := exec.Command("ps", "-o", "rss=", "-p", strconv.Itoa(os.Getpid())).Output()
	if err != nil {
		return 0
	}
	rssKB, err := strconv.ParseInt(strings.TrimSpace(string(output)), 10, 64)
	if err != nil {
		return 0
	}
	return rssKB * 1024
}

func sourceLineCount(path string) int {
	content, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	count := 0
	for _, line := range strings.Split(string(content), "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "//") {
			continue
		}
		count++
	}
	return count
}

func hostname() string {
	name, err := os.Hostname()
	if err != nil || name == "" {
		return "unknown"
	}
	return name
}

func osVersion() string {
	output, err := exec.Command("uname", "-a").Output()
	if err != nil {
		return runtime.GOOS
	}
	return strings.TrimSpace(string(output))
}

func timestampForID(value time.Time) string {
	return value.Format("2006-01-02T15-04-05Z")
}

func max64(a int64, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
