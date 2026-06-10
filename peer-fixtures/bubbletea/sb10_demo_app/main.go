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
	rows     int
	steps    int
	interval time.Duration
	step     int
	screen   string
	events   []string
}

func main() {
	options, err := parseArgs(os.Args[1:])
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if _, err := tea.NewProgram(model{
		rows:     options.rows,
		steps:    options.steps,
		interval: time.Duration(options.intervalMs) * time.Millisecond,
		screen:   "home",
		events:   []string{"boot demo app"},
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
		screens := []string{"home", "search", "task", "logs", "diagnostics"}
		m.screen = screens[m.step%len(screens)]
		m.events = append(m.events, fmt.Sprintf("step=%d screen=%s rows=%d", m.step, m.screen, m.rows))
		if len(m.events) > 12 {
			m.events = m.events[len(m.events)-12:]
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
	var b strings.Builder
	fmt.Fprintf(&b, "SB.10 demo app screen=%s step=%d\n\n", m.screen, m.step)
	fmt.Fprintf(&b, "nav: home search task  command: %-14s status: %s\n\n", commandName(m.screen), status(m.step))
	fmt.Fprintf(&b, "results visible=%d selected=%d\n\n", (m.step*17)%m.rows, m.step%9)
	for _, event := range m.events {
		fmt.Fprintln(&b, event)
	}
	return b.String()
}

func commandName(screen string) string {
	switch screen {
	case "home":
		return "open-palette"
	case "search":
		return "rank-results"
	case "task":
		return "run-process"
	case "logs":
		return "copy-log"
	default:
		return "diagnose"
	}
}

func status(step int) string {
	return []string{"idle", "running", "complete", "warning"}[step%4]
}

func parseArgs(args []string) (options, error) {
	result := options{rows: 1000, steps: 10, intervalMs: 50}
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
