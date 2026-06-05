package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
)

type options struct {
	rows       int
	steps      int
	intervalMs int
}

type tickMsg struct{}

type model struct {
	steps    int
	interval time.Duration
	step     int
	lines    []string
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	lines := make([]string, 16)
	for index := range lines {
		lines[index] = lineFor(index)
	}
	if _, err := tea.NewProgram(model{
		steps:    options.steps,
		interval: time.Duration(options.intervalMs) * time.Millisecond,
		lines:    lines,
	}).Run(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func (m model) Init() tea.Cmd { return m.nextTick() }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		if m.step >= m.steps {
			return m, tea.Quit
		}
		for index := 0; index < 4; index++ {
			m.lines = append(m.lines, lineFor(len(m.lines)))
		}
		if len(m.lines) > 24 {
			m.lines = m.lines[len(m.lines)-24:]
		}
		m.step++
		if m.step >= m.steps {
			return m, tea.Quit
		}
		return m, m.nextTick()
	}
	return m, nil
}

func (m model) View() tea.View {
	view := tea.NewView(render(m))
	view.AltScreen = true
	return view
}

func (m model) nextTick() tea.Cmd {
	return tea.Tick(m.interval, func(time.Time) tea.Msg { return tickMsg{} })
}

func render(m model) string {
	return fmt.Sprintf("SB.9 subprocess output step=%d total=%d\n\n%s", m.step, len(m.lines), strings.Join(m.lines, "\n"))
}

func lineFor(index int) string {
	unsafe := ""
	if index%5 == 0 {
		unsafe = fmt.Sprintf(" secret-%d", index)
	}
	return fmt.Sprintf("proc[%d] stdout shard=%d status=%d message=\"streamed output %d\"%s", index, index%17, index%3, index, unsafe)
}

func parseArgs(args []string) (options, error) {
	result := options{rows: 400, steps: 10, intervalMs: 35}
	for _, arg := range args {
		switch {
		case arg == "--wire" || strings.HasPrefix(arg, "--size="):
			continue
		case strings.HasPrefix(arg, "--rows="):
			result.rows = mustPositive(arg, "--rows=")
		case strings.HasPrefix(arg, "--steps="):
			result.steps = mustPositive(arg, "--steps=")
		case strings.HasPrefix(arg, "--interval-ms="):
			result.intervalMs = mustPositive(arg, "--interval-ms=")
		default:
			return result, fmt.Errorf("unknown argument: %s", arg)
		}
	}
	return result, nil
}

func mustPositive(arg string, prefix string) int {
	value, err := strconv.Atoi(strings.TrimPrefix(arg, prefix))
	if err != nil || value <= 0 {
		panic(fmt.Sprintf("%s expects a positive integer", prefix))
	}
	return value
}
