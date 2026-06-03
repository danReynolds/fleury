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
)

const (
	schemaVersion     = 1
	peerID            = "bubbletea"
	peerName          = "Bubble Tea + Bubbles"
	bubbleTeaVersion  = "2.0.7"
	bubblesVersion    = "2.1.0"
	peerURL           = "https://pkg.go.dev/charm.land/bubbletea/v2"
	scenarioID        = "SB.4"
	defaultWarmups    = 1
	defaultIterations = 5
	defaultRowCount   = 100_000
	defaultAppend     = 1_000
)

type Options struct {
	WarmupIterations   int
	MeasuredIterations int
	Rows               int
	AppendCount        int
	TerminalColumns    int
	TerminalRows       int
	PrintJSON          bool
	OutputPath         string
}

type Sample struct {
	MountUs                   int64
	FirstRenderUs             int64
	AppendBurstUs             int64
	ScrollbackJumpUs          int64
	ScrollToTailUs            int64
	CopySelectedEntryUs       int64
	FilterQueryUs             int64
	SemanticOrTestQueryUs     int64
	RSSDeltaBytes             int64
	UnsafeArtifactLeakCount   int
	EntryCountAfterAppend     int
	LineCountAfterFilter      int
	FilterMatchCount          int
	SelectedKey               string
	ScrollY                   int
	MaxScrollY                int
	VisibleWindowRows         int
	TailAnchoringCorrect      bool
	CopyTextSanitized         bool
	FilterResultCorrect       bool
	ScrollbackSelectedCorrect bool
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
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
	fmt.Println("Bubble Tea SB.4 LogRegion fixture")
	fmt.Printf("Run: %s\n", artifact["runId"])
	fmt.Printf("Rows: %d\n", options.Rows)
	fmt.Printf("Append: %d\n", options.AppendCount)
	fmt.Printf("Iterations: %d\n", options.MeasuredIterations)
	fmt.Printf("appendBurstUs p95: %v\n", metrics["appendBurstUs"].(map[string]any)["p95"])
	fmt.Printf("filterQueryUs p95: %v\n", metrics["filterQueryUs"].(map[string]any)["p95"])
	fmt.Printf("unsafeArtifactLeakCount: %v\n", metrics["unsafeArtifactLeakCount"])
	if options.OutputPath != "" {
		fmt.Printf("Saved %s\n", options.OutputPath)
	}
}

func runSample(options Options) Sample {
	rssBefore := currentRSSBytes()
	mountStart := time.Now()
	model := NewSb4LogRegionModel(options.Rows, options.TerminalColumns, options.TerminalRows)
	mountUs := elapsedUs(mountStart)

	firstRenderStart := time.Now()
	firstView := model.View().Content
	firstRenderUs := elapsedUs(firstRenderStart)

	appendStart := time.Now()
	model = model.Apply(appendBurstMsg{Count: options.AppendCount})
	appendView := model.View().Content
	appendBurstUs := elapsedUs(appendStart)
	appendState := model.StateSnapshot()

	scrollbackIndex := options.Rows / 2
	scrollbackStart := time.Now()
	model = model.Apply(jumpToScrollbackMsg{SourceIndex: scrollbackIndex})
	scrollbackView := model.View().Content
	scrollbackJumpUs := elapsedUs(scrollbackStart)
	scrollbackState := model.StateSnapshot()

	tailStart := time.Now()
	model = model.Apply(tailMsg{})
	tailView := model.View().Content
	scrollToTailUs := elapsedUs(tailStart)
	tailState := model.StateSnapshot()

	copyStart := time.Now()
	model = model.Apply(copyEntryMsg{})
	copySelectedEntryUs := elapsedUs(copyStart)
	copied := model.LastCopiedText()

	filterStart := time.Now()
	query := appendFilterQuery(options.Rows)
	model = model.Apply(filterQueryMsg{Query: query})
	filterView := model.View().Content
	filterQueryUs := elapsedUs(filterStart)

	queryStart := time.Now()
	state := model.StateSnapshot()
	viewLeakCount := unsafeVisibleTextCount(firstView) +
		unsafeVisibleTextCount(appendView) +
		unsafeVisibleTextCount(scrollbackView) +
		unsafeVisibleTextCount(tailView) +
		unsafeVisibleTextCount(filterView)
	semanticOrTestQueryUs := elapsedUs(queryStart)

	rssAfter := currentRSSBytes()
	expectedLastIndex := options.Rows + options.AppendCount - 1
	expectedLastKey := logKey(expectedLastIndex)
	unsafeLeakCount := state.UnsafeArtifactLeakCount + viewLeakCount

	return Sample{
		MountUs:                 mountUs,
		FirstRenderUs:           firstRenderUs,
		AppendBurstUs:           appendBurstUs,
		ScrollbackJumpUs:        scrollbackJumpUs,
		ScrollToTailUs:          scrollToTailUs,
		CopySelectedEntryUs:     copySelectedEntryUs,
		FilterQueryUs:           filterQueryUs,
		SemanticOrTestQueryUs:   semanticOrTestQueryUs,
		RSSDeltaBytes:           max64(0, rssAfter-rssBefore),
		UnsafeArtifactLeakCount: unsafeLeakCount,
		EntryCountAfterAppend:   appendState.EntryCount,
		LineCountAfterFilter:    state.LineCount,
		FilterMatchCount:        state.DisplayedCount,
		SelectedKey:             state.SelectedKey,
		ScrollY:                 state.ScrollY,
		MaxScrollY:              state.MaxScrollY,
		VisibleWindowRows:       state.VisibleWindowRows,
		TailAnchoringCorrect: appendState.TailAnchored &&
			tailState.TailAnchored &&
			tailState.SelectedKey == expectedLastKey &&
			tailState.LineCount == options.Rows+options.AppendCount,
		CopyTextSanitized: copied == expectedCopiedText(expectedLastIndex) &&
			unsafeCountText(copied) == 0,
		FilterResultCorrect: state.DisplayedCount == options.AppendCount &&
			state.LineCount == options.AppendCount &&
			state.SelectedKey == expectedLastKey,
		ScrollbackSelectedCorrect: scrollbackState.SelectedKey == logKey(scrollbackIndex) &&
			scrollbackState.ScrollY <= scrollbackState.MaxScrollY,
	}
}

func buildArtifact(options Options, samples []Sample) map[string]any {
	capturedAt := time.Now().UTC()
	last := samples[len(samples)-1]
	unsafeLeakCount := 0
	for _, sample := range samples {
		unsafeLeakCount = max(unsafeLeakCount, sample.UnsafeArtifactLeakCount)
	}
	appLines := sourceLineCount("app.go")
	benchmarkLines := sourceLineCount("main.go")
	testLines := sourceLineCount("app_test.go")

	return map[string]any{
		"schemaVersion": schemaVersion,
		"kind":          "fleuryPeerBenchmarkRun",
		"runId":         fmt.Sprintf("bubbletea-sb4-log-region-%s", timestampForID(capturedAt)),
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
			"terminalMode": "bubbletea-viewport-model-harness",
			"terminalSize": map[string]any{
				"columns": options.TerminalColumns,
				"rows":    options.TerminalRows,
			},
		},
		"fixture": map[string]any{
			"workingDirectory": "peer-fixtures/bubbletea/sb4_log_region",
			"command": []string{
				"go",
				"run",
				".",
				fmt.Sprintf("--warmup=%d", options.WarmupIterations),
				fmt.Sprintf("--iterations=%d", options.MeasuredIterations),
				fmt.Sprintf("--rows=%d", options.Rows),
				fmt.Sprintf("--append=%d", options.AppendCount),
				"--json",
			},
			"warmupIterations":   options.WarmupIterations,
			"measuredIterations": options.MeasuredIterations,
		},
		"metrics": map[string]any{
			"mountUs":                 stats(samples, func(sample Sample) int64 { return sample.MountUs }),
			"firstRenderUs":           stats(samples, func(sample Sample) int64 { return sample.FirstRenderUs }),
			"appendBurstUs":           stats(samples, func(sample Sample) int64 { return sample.AppendBurstUs }),
			"scrollbackJumpUs":        stats(samples, func(sample Sample) int64 { return sample.ScrollbackJumpUs }),
			"scrollToTailUs":          stats(samples, func(sample Sample) int64 { return sample.ScrollToTailUs }),
			"copySelectedEntryUs":     stats(samples, func(sample Sample) int64 { return sample.CopySelectedEntryUs }),
			"filterQueryUs":           stats(samples, func(sample Sample) int64 { return sample.FilterQueryUs }),
			"semanticOrTestQueryUs":   stats(samples, func(sample Sample) int64 { return sample.SemanticOrTestQueryUs }),
			"unsafeArtifactLeakCount": unsafeLeakCount,
			"rssDeltaBytes": maxSample(samples, func(sample Sample) int64 {
				return sample.RSSDeltaBytes
			}),
			"lineOfCodeCount":          appLines,
			"benchmarkLineOfCodeCount": benchmarkLines,
			"testLineOfCodeCount":      testLines,
			"entryCountAfterAppend":    last.EntryCountAfterAppend,
			"appendCount":              options.AppendCount,
			"lineCountAfterFilter":     last.LineCountAfterFilter,
			"filterMatchCount":         last.FilterMatchCount,
			"selectedKey":              last.SelectedKey,
			"finalScrollY":             last.ScrollY,
			"finalMaxScrollY":          last.MaxScrollY,
			"visibleWindowRowEstimate": last.VisibleWindowRows,
		},
		"correctness": []map[string]any{
			{
				"gate": "tail anchoring is correct",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.TailAnchoringCorrect
				}),
				"evidence": fmt.Sprintf(
					"After append and explicit tail scroll, the Bubbles viewport stayed anchored at %s.",
					logKey(options.Rows+options.AppendCount-1),
				),
			},
			{
				"gate": "copy text is sanitized",
				"pass": allSamples(samples, func(sample Sample) bool {
					return sample.CopyTextSanitized
				}),
				"evidence": "Selected-entry copy matched the generated sanitized log line and contained no escape, secret, or newline artifacts.",
			},
			{
				"gate":     "unsafe output leak count is zero",
				"pass":     unsafeLeakCount == 0,
				"evidence": "Fixture-owned sanitizer removed ANSI/OSC/control payloads before Bubbles viewport ingestion.",
			},
		},
		"ergonomics": map[string]any{
			"lineOfCodeCount":                 appLines,
			"benchmarkLineOfCodeCount":        benchmarkLines,
			"testLineOfCodeCount":             testLines,
			"appFile":                         "app.go",
			"benchmarkFile":                   "main.go",
			"testFile":                        "app_test.go",
			"peerOwnedViewportWidget":         true,
			"appOwnedSanitization":            true,
			"appOwnedFiltering":               true,
			"appOwnedSelectedEntryCopy":       true,
			"semanticGraphAvailable":          false,
			"testQueryViaAppStateAndViewport": true,
		},
		"artifacts": []map[string]any{
			{
				"kind": "source",
				"path": "peer-fixtures/bubbletea/sb4_log_region/app.go",
			},
			{
				"kind": "benchmark",
				"path": "peer-fixtures/bubbletea/sb4_log_region/main.go",
			},
			{
				"kind": "test",
				"path": "peer-fixtures/bubbletea/sb4_log_region/app_test.go",
			},
		},
		"notes": []string{
			"This is a Bubble Tea/Bubbles viewport model harness, not a real-terminal run.",
			"Bubble Tea 2.0.7 supplies the Model/Update/View architecture, and Bubbles 2.1.0 supplies viewport content and scrolling primitives.",
			"Sanitization/redaction, filtering, selected-entry state, and copy/export are app-owned fixture code because Bubbles viewport does not provide Fleury-equivalent primitives for those SB.4 behaviors.",
			"Bubble Tea/Bubbles exposes app/model state for this fixture, not a Fleury-style semantic app graph.",
			"Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
		},
	}
}

func parseArgs(args []string) (Options, error) {
	options := Options{
		WarmupIterations:   defaultWarmups,
		MeasuredIterations: defaultIterations,
		Rows:               defaultRowCount,
		AppendCount:        defaultAppend,
		TerminalColumns:    defaultColumns,
		TerminalRows:       defaultRows,
	}
	for _, arg := range args {
		switch {
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
		case strings.HasPrefix(arg, "--rows="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--rows="), "rows")
			if err != nil {
				return Options{}, err
			}
			options.Rows = value
		case strings.HasPrefix(arg, "--append="):
			value, err := positiveInt(strings.TrimPrefix(arg, "--append="), "append")
			if err != nil {
				return Options{}, err
			}
			options.AppendCount = value
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

func unsafeVisibleTextCount(value string) int {
	count := strings.Count(value, "\x1b")
	count += len(secretPattern.FindAllString(value, -1))
	count += strings.Count(value, "\x07")
	count += strings.Count(value, "\r")
	return count
}

func max64(a int64, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
