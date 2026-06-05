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
	rows        int
	steps       int
	interval    time.Duration
	step        int
	query       string
	paletteOpen bool
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if _, err := tea.NewProgram(model{
		rows:        options.rows,
		steps:       options.steps,
		interval:    time.Duration(options.intervalMs) * time.Millisecond,
		query:       "open",
		paletteOpen: true,
	}).Run(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func (m model) Init() tea.Cmd {
	return m.nextTick()
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		if m.step >= m.steps {
			return m, tea.Quit
		}
		m.paletteOpen = m.step%3 != 2
		m.query = []string{"open", "run", "diag", "copy"}[m.step%4]
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
	var b strings.Builder
	fmt.Fprintf(&b, "SB.8 overlay churn step=%d open=%v query=%s\n\n", m.step, m.paletteOpen, m.query)
	for index := 0; index < 9; index++ {
		fmt.Fprintf(&b, "screen row %d focus=%v command=cmd-%d\n", index, index == m.step%9, (m.step+index)%m.rows)
	}
	if m.paletteOpen {
		fmt.Fprintf(&b, "\n+%s+\n", strings.Repeat("-", 54))
		fmt.Fprintf(&b, "| Command Palette query=%-26s |\n", m.query)
		for index := 0; index < 6; index++ {
			commandIndex := (m.step*7 + index) % m.rows
			fmt.Fprintf(&b, "| cmd-%04d %s action-%-31d |\n", commandIndex, m.query, index)
		}
		fmt.Fprintf(&b, "+%s+\n", strings.Repeat("-", 54))
	}
	return b.String()
}

func parseArgs(args []string) (options, error) {
	result := options{rows: 500, steps: 12, intervalMs: 40}
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
