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
	peerName          = "Bubble Tea + Bubbles + Glamour"
	bubbleTeaVersion  = "2.0.7"
	bubblesVersion    = "2.1.0"
	glamourVersion    = "2.0.0"
	peerURL           = "https://pkg.go.dev/charm.land/glamour/v2"
	scenarioID        = "SB.5"
	defaultWarmups    = 1
	defaultIterations = 3
	defaultRowCount   = 10_000
	defaultWireSteps  = 16
	defaultWireMs     = 50
)

type Options struct {
	WarmupIterations   int
	MeasuredIterations int
	Rows               int
	TerminalColumns    int
	TerminalRows       int
	PrintJSON          bool
	OutputPath         string
	Wire               bool
	WireSteps          int
	WireIntervalMs     int
}

type Sample struct {
	TotalJourneyUs                 int64
	ChunkParseUs                   []int64
	ChunkFrameUs                   []int64
	ChunkUpdateUs                  []int64
	FinalRenderUs                  int64
	CopySelectedBlockUs            int64
	SemanticOrTestQueryUs          int64
	RSSDeltaBytes                  int64
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
	UnsafeFrameCount               int
	SanitizedBlockCount            int
	SanitizedChunkCount            int
	TruncatedBlockCount            int
	CopiedByteCount                int
	IncrementalContentCoherent     bool
	UnsafeLinksHaveVisibleFallback bool
	UnsafeFrameFree                bool
	RenderErrorFree                bool
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
	fmt.Println("Bubble Tea SB.5 Streaming Markdown fixture")
	fmt.Printf("Run: %s\n", artifact["runId"])
	fmt.Printf("Rows: %d\n", options.Rows)
	fmt.Printf("Chunks: %v\n", metrics["chunkCount"])
	fmt.Printf("Iterations: %d\n", options.MeasuredIterations)
	fmt.Printf("chunkUpdateUs p95: %v\n", metrics["chunkUpdateUs"].(map[string]any)["p95"])
	fmt.Printf("finalRenderUs p95: %v\n", metrics["finalRenderUs"].(map[string]any)["p95"])
	fmt.Printf("unsafeFrameCount: %v\n", metrics["unsafeFrameCount"])
	if options.OutputPath != "" {
		fmt.Printf("Saved %s\n", options.OutputPath)
	}
}

type wireModel struct {
	Sb5StreamingMarkdownModel
}

func (m wireModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	next, cmd := m.Sb5StreamingMarkdownModel.Update(msg)
	if typed, ok := next.(Sb5StreamingMarkdownModel); ok {
		m.Sb5StreamingMarkdownModel = typed
	}
	return m, cmd
}

func (m wireModel) View() tea.View {
	view := m.Sb5StreamingMarkdownModel.View()
	view.AltScreen = true
	return view
}

func runWire(options Options) error {
	model := wireModel{
		Sb5StreamingMarkdownModel: NewSb5StreamingMarkdownModel(
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
		fixture := MarkdownFixture{Seed: 1}
		chunkCount := markdownChunkCountFor(options.Rows)
		interval := time.Duration(options.WireIntervalMs) * time.Millisecond
		time.Sleep(interval)
		emitted := 0
		for step := 0; step < options.WireSteps && emitted < chunkCount; step++ {
			remaining := chunkCount - emitted
			remainingSteps := options.WireSteps - step
			count := remaining / remainingSteps
			if count <= 0 {
				count = 1
			}
			for i := 0; i < count && emitted < chunkCount; i++ {
				program.Send(appendChunkMsg{RawChunk: fixture.Chunk(emitted)})
				emitted++
			}
			time.Sleep(interval)
		}
		program.Send(selectFinalBlockMsg{})
		time.Sleep(interval)
		program.Quit()
	}()

	_, err := program.Run()
	return err
}

func runSample(options Options) Sample {
	model := NewSb5StreamingMarkdownModel(options.TerminalColumns, options.TerminalRows)
	fixture := MarkdownFixture{Seed: 1}
	chunkCount := markdownChunkCountFor(options.Rows)
	chunkParseUs := make([]int64, 0, chunkCount)
	chunkFrameUs := make([]int64, 0, chunkCount)
	chunkUpdateUs := make([]int64, 0, chunkCount)
	metadataSource := ""
	unsafeFrameCount := 0
	rssBefore := currentRSSBytes()
	totalStart := time.Now()

	for index := range chunkCount {
		rawChunk := fixture.Chunk(index)
		updateStart := time.Now()

		parseStart := time.Now()
		sanitized := sanitizeMarkdownChunk(rawChunk)
		metadataSource += sanitized
		parseMarkdownDocument(metadataSource)
		parseUs := elapsedUs(parseStart)

		model = model.Apply(appendChunkMsg{RawChunk: rawChunk})

		frameStart := time.Now()
		frame := model.View().Content
		frameUs := elapsedUs(frameStart)
		if unsafeVisibleTextCount(frame) > 0 || unsafeCountText(model.source) > 0 {
			unsafeFrameCount++
		}

		chunkParseUs = append(chunkParseUs, parseUs)
		chunkFrameUs = append(chunkFrameUs, frameUs)
		chunkUpdateUs = append(chunkUpdateUs, elapsedUs(updateStart))
	}

	model = model.Apply(selectFinalBlockMsg{})
	finalStart := time.Now()
	finalFrame := model.View().Content
	finalRenderUs := elapsedUs(finalStart)
	if unsafeVisibleTextCount(finalFrame) > 0 {
		unsafeFrameCount++
	}

	copyStart := time.Now()
	model = model.Apply(copyBlockMsg{})
	copySelectedBlockUs := elapsedUs(copyStart)
	copied := model.LastCopiedText()

	queryStart := time.Now()
	state := model.StateSnapshot()
	semanticOrTestQueryUs := elapsedUs(queryStart)

	rssAfter := currentRSSBytes()
	copiedSafe := unsafeCountText(copied) == 0
	sourceSafe := unsafeCountText(model.source) == 0
	contentCoherent := state.ChunkCount == chunkCount &&
		state.BlockCount > 0 &&
		state.HeadingCount > 0 &&
		state.ListItemCount > 0 &&
		state.LinkCount > 0 &&
		state.UnsafeLinkCount > 0 &&
		state.CodeBlockCount > 0 &&
		state.CodeLineCount > 0 &&
		state.SelectedBlockIndex == state.BlockCount-1 &&
		state.CopiedByteCount > 0 &&
		state.SanitizedChunkCount > 0
	unsafeFrameCount += state.UnsafeArtifactLeakCount

	return Sample{
		TotalJourneyUs:                 elapsedUs(totalStart),
		ChunkParseUs:                   chunkParseUs,
		ChunkFrameUs:                   chunkFrameUs,
		ChunkUpdateUs:                  chunkUpdateUs,
		FinalRenderUs:                  finalRenderUs,
		CopySelectedBlockUs:            copySelectedBlockUs,
		SemanticOrTestQueryUs:          semanticOrTestQueryUs,
		RSSDeltaBytes:                  max64(0, rssAfter-rssBefore),
		ChunkCount:                     state.ChunkCount,
		SourceByteCount:                state.SourceByteCount,
		BlockCount:                     state.BlockCount,
		HeadingCount:                   state.HeadingCount,
		ListItemCount:                  state.ListItemCount,
		LinkCount:                      state.LinkCount,
		UnsafeLinkCount:                state.UnsafeLinkCount,
		CodeBlockCount:                 state.CodeBlockCount,
		CodeLineCount:                  state.CodeLineCount,
		SelectedBlockIndex:             state.SelectedBlockIndex,
		SelectedBlockKind:              state.SelectedBlockKind,
		UnsafeFrameCount:               unsafeFrameCount,
		SanitizedBlockCount:            state.SanitizedBlockCount,
		SanitizedChunkCount:            state.SanitizedChunkCount,
		TruncatedBlockCount:            state.TruncatedBlockCount,
		CopiedByteCount:                state.CopiedByteCount,
		IncrementalContentCoherent:     contentCoherent,
		UnsafeLinksHaveVisibleFallback: state.UnsafeLinksHaveVisibleFallback,
		UnsafeFrameFree:                unsafeFrameCount == 0 && copiedSafe && sourceSafe,
		RenderErrorFree:                model.lastRenderError == "" && model.rendererInitialized,
	}
}

func buildArtifact(options Options, samples []Sample) map[string]any {
	capturedAt := time.Now().UTC()
	last := samples[len(samples)-1]
	unsafeFrameCount := 0
	for _, sample := range samples {
		unsafeFrameCount = max(unsafeFrameCount, sample.UnsafeFrameCount)
	}
	appLines := sourceLineCount("app.go")
	benchmarkLines := sourceLineCount("main.go")
	testLines := sourceLineCount("app_test.go")

	return map[string]any{
		"schemaVersion": schemaVersion,
		"kind":          "fleuryPeerBenchmarkRun",
		"runId":         fmt.Sprintf("bubbletea-sb5-streaming-markdown-%s", timestampForID(capturedAt)),
		"peerId":        peerID,
		"scenarioId":    scenarioID,
		"capturedAt":    capturedAt.Format(time.RFC3339Nano),
		"source": map[string]any{
			"name": "Bubble Tea + Bubbles + Glamour",
			"version": fmt.Sprintf(
				"Bubble Tea %s / Bubbles %s / Glamour %s",
				bubbleTeaVersion,
				bubblesVersion,
				glamourVersion,
			),
			"url": peerURL,
		},
		"environment": map[string]any{
			"machine":                hostname(),
			"operatingSystem":        runtime.GOOS,
			"operatingSystemVersion": osVersion(),
			"runtime": fmt.Sprintf(
				"%s / Bubble Tea %s / Bubbles %s / Glamour %s",
				runtime.Version(),
				bubbleTeaVersion,
				bubblesVersion,
				glamourVersion,
			),
			"terminalMode": "bubbletea-glamour-viewport-model-harness",
			"terminalSize": map[string]any{
				"columns": options.TerminalColumns,
				"rows":    options.TerminalRows,
			},
		},
		"fixture": map[string]any{
			"workingDirectory": "peer-fixtures/bubbletea/sb5_streaming_markdown",
			"command": []string{
				"go",
				"run",
				".",
				fmt.Sprintf("--warmup=%d", options.WarmupIterations),
				fmt.Sprintf("--iterations=%d", options.MeasuredIterations),
				fmt.Sprintf("--rows=%d", options.Rows),
				"--json",
			},
			"warmupIterations":   options.WarmupIterations,
			"measuredIterations": options.MeasuredIterations,
		},
		"metrics": map[string]any{
			"journeyUs":                stats(samples, func(sample Sample) int64 { return sample.TotalJourneyUs }),
			"chunkParseUs":             flattenedStats(samples, func(sample Sample) []int64 { return sample.ChunkParseUs }),
			"chunkFrameUs":             flattenedStats(samples, func(sample Sample) []int64 { return sample.ChunkFrameUs }),
			"chunkUpdateUs":            flattenedStats(samples, func(sample Sample) []int64 { return sample.ChunkUpdateUs }),
			"finalRenderUs":            stats(samples, func(sample Sample) int64 { return sample.FinalRenderUs }),
			"selectedBlockCopyUs":      stats(samples, func(sample Sample) int64 { return sample.CopySelectedBlockUs }),
			"semanticOrTestQueryUs":    stats(samples, func(sample Sample) int64 { return sample.SemanticOrTestQueryUs }),
			"unsafeFrameCount":         unsafeFrameCount,
			"rssDeltaBytes":            maxSample(samples, func(sample Sample) int64 { return sample.RSSDeltaBytes }),
			"lineOfCodeCount":          appLines,
			"benchmarkLineOfCodeCount": benchmarkLines,
			"testLineOfCodeCount":      testLines,
			"chunkCount":               last.ChunkCount,
			"sourceByteCount":          last.SourceByteCount,
			"blockCount":               last.BlockCount,
			"headingCount":             last.HeadingCount,
			"listItemCount":            last.ListItemCount,
			"linkCount":                last.LinkCount,
			"unsafeLinkCount":          last.UnsafeLinkCount,
			"codeBlockCount":           last.CodeBlockCount,
			"codeLineCount":            last.CodeLineCount,
			"selectedBlockIndex":       last.SelectedBlockIndex,
			"selectedBlockKind":        last.SelectedBlockKind,
			"sanitizedBlockCount":      last.SanitizedBlockCount,
			"sanitizedChunkCount":      last.SanitizedChunkCount,
			"truncatedBlockCount":      last.TruncatedBlockCount,
			"copiedByteCount":          last.CopiedByteCount,
		},
		"correctness": []map[string]any{
			{
				"gate": "incremental content remains coherent",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.IncrementalContentCoherent && sample.RenderErrorFree
				}),
				"evidence": "The streamed document retained headings, lists, links, unsafe-link fallback metadata, code fences, selected final block, and non-empty copy text.",
			},
			{
				"gate": "unsafe links have visible fallback",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.UnsafeLinksHaveVisibleFallback
				}),
				"evidence": "Fixture-owned link policy rewrote unsafe links to a blocked href while preserving the original URL in visible text.",
			},
			{
				"gate": "unsafe frame count is zero",
				"pass": unsafeFrameCount == 0 && allSamples(samples, func(sample Sample) bool {
					return sample.UnsafeFrameFree
				}),
				"evidence": "Fixture-owned sanitizer removed OSC/CSI/control payloads and redacted secret-shaped text before Glamour rendering and Bubbles viewport ingestion.",
			},
		},
		"ergonomics": map[string]any{
			"lineOfCodeCount":                 appLines,
			"benchmarkLineOfCodeCount":        benchmarkLines,
			"testLineOfCodeCount":             testLines,
			"appFile":                         "app.go",
			"benchmarkFile":                   "main.go",
			"testFile":                        "app_test.go",
			"peerOwnedModelUpdateView":        true,
			"peerOwnedViewportWidget":         true,
			"ecosystemOwnedMarkdownRenderer":  true,
			"peerOwnedIncrementalMarkdown":    false,
			"appOwnedSanitization":            true,
			"appOwnedLinkPolicy":              true,
			"appOwnedSelectedBlockCopy":       true,
			"appOwnedMarkdownMetadata":        true,
			"semanticGraphAvailable":          false,
			"testQueryViaAppStateAndViewport": true,
		},
		"artifacts": []map[string]any{
			{
				"kind": "source",
				"path": "peer-fixtures/bubbletea/sb5_streaming_markdown/app.go",
			},
			{
				"kind": "benchmark",
				"path": "peer-fixtures/bubbletea/sb5_streaming_markdown/main.go",
			},
			{
				"kind": "test",
				"path": "peer-fixtures/bubbletea/sb5_streaming_markdown/app_test.go",
			},
		},
		"notes": []string{
			"This is a Bubble Tea/Bubbles/Glamour model harness, not a real-terminal run.",
			"Bubble Tea 2.0.7 supplies the Model/Update/View architecture, Bubbles 2.1.0 supplies viewport content and scrolling primitives, and Glamour 2.0.0 supplies full-document terminal Markdown rendering.",
			"Sanitization/redaction, visible URL fallback for unsafe links, selected-block copy, and markdown metadata/test query state are fixture-owned app code.",
			"The fixture re-renders the full Markdown document after each append because Bubble Tea/Bubbles/Glamour do not provide a built-in incremental Markdown stream widget matching Fleury SB.5.",
			"Bubble Tea/Bubbles exposes app/model state for this fixture, not a Fleury-style semantic app graph.",
			"chunkParseUs is fixture metadata parsing around the streamed source; Glamour rendering work is included in chunkUpdateUs.",
			"Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
		},
	}
}

func parseArgs(args []string) (Options, error) {
	options := Options{
		WarmupIterations:   defaultWarmups,
		MeasuredIterations: defaultIterations,
		Rows:               defaultRowCount,
		TerminalColumns:    defaultColumns,
		TerminalRows:       defaultRows,
		WireSteps:          defaultWireSteps,
		WireIntervalMs:     defaultWireMs,
	}
	for _, arg := range args {
		switch {
		case arg == "--json":
			options.PrintJSON = true
		case arg == "--wire":
			options.Wire = true
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
		case strings.HasPrefix(arg, "--rows="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--rows="), "rows")
			if err != nil {
				return Options{}, err
			}
			options.Rows = value
		case strings.HasPrefix(arg, "--size="):
			columns, rows, err := parseSize(strings.TrimPrefix(arg, "--size="))
			if err != nil {
				return Options{}, err
			}
			options.TerminalColumns = columns
			options.TerminalRows = rows
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
	return statsFromValues(values)
}

func flattenedStats(samples []Sample, value func(Sample) []int64) map[string]any {
	values := make([]int64, 0)
	for _, sample := range samples {
		values = append(values, value(sample)...)
	}
	return statsFromValues(values)
}

func statsFromValues(values []int64) map[string]any {
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
