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
	steps      int
	intervalMs int
}

type tickMsg struct{}

type model struct {
	steps    int
	interval time.Duration
	count    int
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if _, err := tea.NewProgram(model{
		steps:    options.steps,
		interval: time.Duration(options.intervalMs) * time.Millisecond,
	}).Run(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func (m model) Init() tea.Cmd { return m.nextTick() }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg.(type) {
	case tickMsg:
		if m.count >= m.steps {
			return m, tea.Quit
		}
		m.count++
		if m.count >= m.steps {
			return m, tea.Quit
		}
		return m, m.nextTick()
	}
	return m, nil
}

func (m model) View() tea.View {
	view := tea.NewView(fmt.Sprintf("Count: %d\n", m.count))
	view.AltScreen = true
	return view
}

func (m model) nextTick() tea.Cmd {
	return tea.Tick(m.interval, func(time.Time) tea.Msg { return tickMsg{} })
}

func parseArgs(args []string) (options, error) {
	result := options{steps: 1, intervalMs: 60}
	for _, arg := range args {
		switch {
		case arg == "--wire" || strings.HasPrefix(arg, "--rows=") || strings.HasPrefix(arg, "--size="):
			continue
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
