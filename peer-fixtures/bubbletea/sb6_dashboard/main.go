package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

const (
	defaultRows       = 100000
	defaultSteps      = 120
	defaultIntervalMs = 16
	defaultCols       = 120
	defaultPtyRows    = 32
)

type options struct {
	rows       int
	steps      int
	intervalMs int
	cols       int
	ptyRows    int
	wire       bool
}

type tickMsg struct{}

type dashboardModel struct {
	rows     int
	steps    int
	interval time.Duration
	cols     int
	ptyRows  int
	step     int
	history  []int
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	model := newDashboardModel(options)
	if _, err := tea.NewProgram(model).Run(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func newDashboardModel(options options) dashboardModel {
	history := make([]int, 48)
	for index := range history {
		history[index] = 40 + index%17
	}
	return dashboardModel{
		rows:     options.rows,
		steps:    options.steps,
		interval: time.Duration(options.intervalMs) * time.Millisecond,
		cols:     options.cols,
		ptyRows:  options.ptyRows,
		history:  history,
	}
}

func (m dashboardModel) Init() tea.Cmd {
	return m.nextTick()
}

func (m dashboardModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		if m.step >= m.steps {
			return m, tea.Quit
		}
		m.step++
		copy(m.history, m.history[1:])
		m.history[len(m.history)-1] = 20 + (m.step*13)%80
		if m.step >= m.steps {
			return m, tea.Quit
		}
		return m, m.nextTick()
	}
	return m, nil
}

func (m dashboardModel) View() tea.View {
	view := tea.NewView(renderDashboard(m))
	view.AltScreen = true
	return view
}

func (m dashboardModel) nextTick() tea.Cmd {
	return tea.Tick(m.interval, func(time.Time) tea.Msg { return tickMsg{} })
}

func renderDashboard(m dashboardModel) string {
	var b strings.Builder
	cpu := (m.step * 17) % 100
	mem := (m.step*29 + 15) % 100
	disk := (m.step*7 + 30) % 100
	completed := min(m.rows, m.step*max(1, m.rows/80))
	fmt.Fprintf(&b, "SB.6 dashboard tick=%d rows=%d active=%d\n\n", m.step, m.rows, 20+(m.step*7)%900)
	fmt.Fprintf(&b, "CPU %-36s %3d%%\n", bar(cpu, 32), cpu)
	fmt.Fprintf(&b, "MEM %-36s %3d%%\n", bar(mem, 32), mem)
	fmt.Fprintf(&b, "IO  %-36s %3d%%\n\n", bar(disk, 32), disk)
	fmt.Fprintf(&b, "build queue %6d / %d\n", completed, m.rows)
	fmt.Fprintf(&b, "%s\n\n", bar(percent(completed, m.rows), 76))
	fmt.Fprintf(&b, "spark %s\n\n", spark(m.history, 76))
	for i := 0; i < 14 && i+10 < m.ptyRows; i++ {
		id := (m.step*10 + i) % max(1, m.rows)
		statuses := []string{"queued", "running", "passed", "failed", "blocked"}
		fmt.Fprintf(&b, "RUN-%06d %-7s shard=%02d owner=worker-%02d latency=%dms\n",
			id, statuses[(id+m.step)%len(statuses)], id%31, id%17, 20+id%900)
	}
	return b.String()
}

func bar(value int, width int) string {
	value = max(0, min(100, value))
	filled := value * width / 100
	return strings.Repeat("#", filled) + strings.Repeat(".", max(0, width-filled))
}

func spark(values []int, width int) string {
	levels := "._-~=+*#"
	start := max(0, len(values)-width)
	var b strings.Builder
	for _, value := range values[start:] {
		index := max(0, min(len(levels)-1, value*(len(levels)-1)/100))
		b.WriteByte(levels[index])
	}
	return b.String()
}

func percent(value int, total int) int {
	if total <= 0 {
		return 0
	}
	return value * 100 / total
}

func parseArgs(args []string) (options, error) {
	result := options{
		rows:       defaultRows,
		steps:      defaultSteps,
		intervalMs: defaultIntervalMs,
		cols:       defaultCols,
		ptyRows:    defaultPtyRows,
	}
	for _, arg := range args {
		switch {
		case arg == "--wire":
			result.wire = true
		case strings.HasPrefix(arg, "--rows="):
			result.rows = mustPositive(arg, "--rows=")
		case strings.HasPrefix(arg, "--steps="):
			result.steps = mustPositive(arg, "--steps=")
		case strings.HasPrefix(arg, "--interval-ms="):
			result.intervalMs = mustPositive(arg, "--interval-ms=")
		case strings.HasPrefix(arg, "--size="):
			cols, rows, err := parseSize(strings.TrimPrefix(arg, "--size="))
			if err != nil {
				return result, err
			}
			result.cols = cols
			result.ptyRows = rows
		case arg == "-h" || arg == "--help":
			return result, fmt.Errorf("usage: sb6_dashboard --wire [--rows=N] [--steps=N] [--interval-ms=N] [--size=COLSxROWS]")
		default:
			return result, fmt.Errorf("unknown argument: %s", arg)
		}
	}
	return result, nil
}

func parseSize(value string) (int, int, error) {
	parts := strings.Split(value, "x")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("--size must be COLSxROWS")
	}
	cols, err := strconv.Atoi(parts[0])
	if err != nil || cols <= 0 {
		return 0, 0, fmt.Errorf("--size columns must be positive")
	}
	rows, err := strconv.Atoi(parts[1])
	if err != nil || rows <= 0 {
		return 0, 0, fmt.Errorf("--size rows must be positive")
	}
	return cols, rows, nil
}

func mustPositive(arg string, prefix string) int {
	value, err := strconv.Atoi(strings.TrimPrefix(arg, prefix))
	if err != nil || value <= 0 {
		panic(fmt.Sprintf("%s expects a positive integer", prefix))
	}
	return value
}
