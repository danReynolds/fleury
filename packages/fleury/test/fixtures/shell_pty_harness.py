"""Drives `fleury shell` in a pseudo-terminal that is its controlling terminal.

The shell runs as a session leader on the PTY, the arrangement an interactive
terminal gives it, so the terminal's signal keys act exactly as they do for a
user: while ISIG is on, Ctrl+C is SIGINT to the shell, not a byte. An app
attaches from a session of its own with no terminal, as an IDE run does
(test/fixtures/shell_keys_app.dart), and records what reached it.

usage: shell_pty_harness.py <scenario> <dart> <package-root> <work-dir>

The harness is the terminal emulator too: it keeps the modes the shell's
output sets (TerminalState), and reports a click or a pointer move only when
those modes would make a real terminal report one.

Writes <work-dir>/report.json (the facts a scenario observed; `failure` names
the step that could not complete) and <work-dir>/pty.bin (every byte the
shell wrote to its terminal). Exits 0 whenever a report was written; the Dart
test asserts on the facts.
"""

import fcntl
import json
import os
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time


class StepFailed(Exception):
    pass


class TerminalState:
    """What a real terminal emulator keeps from the bytes written to it: the
    DEC private modes (starting from xterm's defaults, autowrap and a visible
    cursor) and the Kitty keyboard flag stack of each screen. The harness
    stands in for that emulator, so it reports a click or a pointer move only
    while the modes the shell set would make a real terminal report one."""

    TOKEN = re.compile(
        rb'\x1b\[\?([0-9;]+)([hl])|\x1b\[>([0-9]+)u|\x1b\[<([0-9]*)u'
    )

    def __init__(self, output):
        self.modes = {7, 25}
        stacks = {False: [], True: []}
        for match in self.TOKEN.finditer(output):
            dec, op, push, pop = match.groups()
            if dec is not None:
                for mode in dec.split(b';'):
                    if op == b'h':
                        self.modes.add(int(mode))
                    else:
                        self.modes.discard(int(mode))
            elif push is not None:
                stacks[1049 in self.modes].append(int(push))
            else:
                stack = stacks[1049 in self.modes]
                del stack[max(0, len(stack) - int(pop or 1)):]
        self.kitty = list(stacks[1049 in self.modes])
        self.main_kitty = list(stacks[False])

    @property
    def reports_buttons(self):
        return bool(self.modes & {1000, 1002, 1003})

    @property
    def reports_motion(self):
        return 1003 in self.modes

    def describe(self):
        return {'modes': sorted(self.modes), 'kitty': self.kitty,
                'mainKitty': self.main_kitty}


class Harness:
    def __init__(self, dart, package_root, work_dir):
        self.dart = dart
        self.package_root = package_root
        self.work_dir = work_dir
        self.output = bytearray()
        self.trace = []
        self.report = {'trace': self.trace, 'apps': []}
        self.master = None
        self.slave_name = None
        self.shell_pid = None
        self.shell_status = None
        self.apps = []

    # -- the shell and its terminal -------------------------------------

    def start_shell(self):
        master, slave = os.openpty()
        self.slave_name = os.ttyname(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith('FLEURY_') and key not in ('TMUX', 'STY')
        }
        env['TERM'] = 'xterm-256color'
        argv = [self.dart, f'{self.package_root}/bin/fleury.dart', 'shell']
        pid = os.fork()
        if pid == 0:
            try:
                os.close(master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                for fd in (0, 1, 2):
                    os.dup2(slave, fd)
                if slave > 2:
                    os.close(slave)
                os.chdir(self.work_dir)
                os.execve(self.dart, argv, env)
            finally:
                os._exit(127)
        os.close(slave)
        self.master = master
        self.shell_pid = pid
        self.note('shell started')

    def note(self, event):
        self.trace.append(event)

    def pump(self, timeout):
        """Reads whatever the shell wrote within [timeout] seconds."""
        if self.master is None:
            time.sleep(timeout)
            return
        ready, _, _ = select.select([self.master], [], [], timeout)
        if not ready:
            return
        try:
            chunk = os.read(self.master, 65536)
        except OSError:
            chunk = b''  # EIO: every slave descriptor closed
        if chunk:
            self.output.extend(chunk)
        else:
            time.sleep(timeout)

    def shell_exit(self):
        """The shell's exit code (negative: killed by that signal), or None."""
        if self.shell_status is None:
            pid, status = os.waitpid(self.shell_pid, os.WNOHANG)
            if pid == self.shell_pid:
                self.shell_status = os.waitstatus_to_exitcode(status)
                self.report['shellExit'] = self.shell_status
                self.note(f'shell exited {self.shell_status}')
        return self.shell_status

    def wait_until(self, check, timeout, what):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if check():
                return
            self.pump(0.02)
        raise StepFailed(f'timed out waiting for {what}')

    def expect_output(self, marker, timeout, what, start=0):
        """Waits for [marker] in the terminal output past offset [start]."""
        found = []

        def seen():
            index = self.output.find(marker, start)
            if index >= 0:
                found.append(index)
                return True
            if self.shell_exit() is not None:
                raise StepFailed(
                    f'the shell exited {self.shell_status} while waiting for {what}'
                )
            return False

        self.wait_until(seen, timeout, what)
        self.note(f'saw {what}')
        return found[0] + len(marker)

    def expect_shell_alive(self, when):
        self.pump(0.2)
        if self.shell_exit() is not None:
            raise StepFailed(f'the shell exited {self.shell_status} {when}')

    def expect_shell_exit(self, timeout, what):
        self.wait_until(lambda: self.shell_exit() is not None, timeout, what)

    def write(self, data, what):
        os.write(self.master, data)
        self.note(f'typed {what}')

    def termios(self, label):
        """Snapshots the terminal's full termios through its slave device."""
        fd = os.open(self.slave_name, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            attrs = termios.tcgetattr(fd)
        finally:
            os.close(fd)
        if sys.platform == 'darwin':
            # Darwin sets PENDIN when canonical mode returns with input pending:
            # kernel-managed retype state, not an application mode.
            attrs[3] &= ~termios.PENDIN
        iflag, oflag, _, lflag = attrs[0:4]
        self.report.setdefault('termios', {})[label] = {
            'ISIG': bool(lflag & termios.ISIG),
            'ICANON': bool(lflag & termios.ICANON),
            'ECHO': bool(lflag & termios.ECHO),
            'IEXTEN': bool(lflag & termios.IEXTEN),
            'IXON': bool(iflag & termios.IXON),
            'ICRNL': bool(iflag & termios.ICRNL),
            'OPOST': bool(oflag & termios.OPOST),
        }
        return attrs

    def expect_restored(self, idle, label):
        restored = self.termios(label)
        self.report.setdefault('restoredExactly', {})[label] = restored == idle

    def hang_up(self):
        """Closes the terminal the way a closed window does: master first."""
        os.close(self.master)
        self.master = None
        self.note('closed the terminal')

    def drain(self):
        """Reads everything the shell has written so far."""
        while self.master is not None:
            ready, _, _ = select.select([self.master], [], [], 0.1)
            if not ready:
                return
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                return  # EIO: every slave descriptor closed
            if not chunk:
                return
            self.output.extend(chunk)

    def terminal_state(self, label):
        """Records the emulated terminal's state under [label], once it has
        everything the shell wrote."""
        self.drain()
        state = TerminalState(bytes(self.output))
        self.report.setdefault('terminal', {})[label] = state.describe()
        return state

    def click(self, col, row, what):
        """A left click at 1-based ([col], [row]), as the terminal reports it:
        a press and a release in SGR encoding, while button tracking is on.
        With tracking off a real terminal keeps the click for its own text
        selection, so nothing reaches the shell."""
        state = TerminalState(bytes(self.output))
        if not state.reports_buttons:
            self.note(f'{what}: not reported, mouse tracking is off')
            return
        if 1006 not in state.modes:
            raise StepFailed(f'{what}: mouse tracking is on without SGR (1006)')
        self.write(
            f'\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m'.encode(), what
        )

    def move(self, col, row, what):
        """The pointer moving onto 1-based ([col], [row]) with no button held,
        as the terminal reports it: only while any-motion tracking (1003) is
        on."""
        state = TerminalState(bytes(self.output))
        if not state.reports_motion:
            self.note(f'{what}: not reported, motion tracking is off')
            return
        if 1006 not in state.modes:
            raise StepFailed(f'{what}: motion tracking is on without SGR (1006)')
        self.write(f'\x1b[<35;{col};{row}M'.encode(), what)

    def fake_app(self, answer, what):
        """Attaches a peer that is not this build's app: it connects to the
        shell's socket, reads the shell's INIT, sends [answer] (an INIT
        payload, or None to hang up without one, as an app built before
        shell protocol 2 does on reading an INIT with no `v`), and closes
        once the shell has hung up on it."""
        path = open(os.path.join(self.work_dir, '.fleury', 'handle')).read()
        peer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            peer.connect(path.strip())
            self.note(f'{what} connected')
            header = self._receive(peer, 5, f'the INIT {what} was sent')
            if header[0] != 0x01:
                raise StepFailed(f'{what} got frame 0x{header[0]:02x}, not INIT')
            length = struct.unpack('>I', header[1:5])[0]
            payload = self._receive(peer, length, f'the INIT {what} was sent')
            self.report.setdefault('shellInit', payload.decode())
            if answer is not None:
                body = answer.encode()
                peer.sendall(b'\x01' + struct.pack('>I', len(body)) + body)
                self.note(f'{what} answered')
                # Stay until the shell hangs up, as an app that is told goodbye.
                self._receive(peer, None, f'the shell to hang up on {what}')
        finally:
            peer.close()
            self.note(f'{what} closed')

    def _receive(self, peer, count, what, timeout=30):
        """Reads [count] bytes from [peer], or until it closes when [count]
        is None, pumping the terminal meanwhile so the shell never blocks on
        a write nobody reads."""
        data = b''
        deadline = time.monotonic() + timeout
        while count is None or len(data) < count:
            if time.monotonic() > deadline:
                raise StepFailed(f'timed out waiting for {what}')
            watched = [peer] if self.master is None else [peer, self.master]
            ready, _, _ = select.select(watched, [], [], 0.05)
            if self.master is not None and self.master in ready:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError:
                    chunk = b''
                self.output.extend(chunk)
            if peer in ready:
                want = 4096 if count is None else count - len(data)
                try:
                    chunk = peer.recv(want)
                except ConnectionResetError:
                    chunk = b''
                if not chunk:
                    if count is None:
                        return data
                    raise StepFailed(f'the shell closed the socket before {what}')
                data += chunk
        return data

    # -- apps ------------------------------------------------------------

    def start_app(self, extra_args=()):
        index = len(self.apps)
        result = os.path.join(self.work_dir, f'app{index}.jsonl')
        log = open(os.path.join(self.work_dir, f'app{index}.log'), 'wb')
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith('FLEURY_')
        }
        app = subprocess.Popen(
            [
                self.dart,
                f'{self.package_root}/test/fixtures/shell_keys_app.dart',
                f'--result={result}',
                *extra_args,
            ],
            cwd=self.work_dir,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            start_new_session=True,
        )
        record = {'result': result, 'exit': None}
        self.report['apps'].append(record)
        self.apps.append((app, record, log))
        self.note(f'app {index} started')
        return index

    def app_records(self, index):
        path = self.apps[index][1]['result']
        if not os.path.exists(path):
            return []
        with open(path) as file:
            return [json.loads(line) for line in file if line.strip()]

    def expect_app_record(self, index, entry, timeout, what):
        def seen():
            if entry in self.app_records(index):
                return True
            if self.shell_exit() is not None:
                raise StepFailed(
                    f'the shell exited {self.shell_status} while waiting for {what}'
                )
            return False

        self.wait_until(seen, timeout, what)
        self.note(f'app {index} recorded {what}')

    def app_exit(self, index):
        app, record, _ = self.apps[index]
        code = app.poll()
        if code is not None and record['exit'] is None:
            record['exit'] = code
            self.note(f'app {index} exited {code}')
        return code

    def expect_app_exit(self, index, timeout, what):
        self.wait_until(lambda: self.app_exit(index) is not None, timeout, what)

    def expect_running(self, index, when):
        """Neither the shell nor app [index] has stopped or exited."""
        self.pump(0.5)
        for name, pid in (('shell', self.shell_pid), ('app', self.apps[index][0].pid)):
            waited, status = os.waitpid(pid, os.WNOHANG | os.WUNTRACED)
            if waited == pid:
                state = 'stopped' if os.WIFSTOPPED(status) else 'exited'
                raise StepFailed(f'the {name} {state} {when}')

    def kill_app(self, index):
        app = self.apps[index][0]
        app.kill()
        app.wait()
        self.app_exit(index)
        self.note(f'app {index} killed')

    # -- teardown --------------------------------------------------------

    def close(self):
        for index, (app, record, log) in enumerate(self.apps):
            if app.poll() is None:
                app.kill()
                app.wait()
            self.app_exit(index)
            record['records'] = self.app_records(index)
            log.close()
        if self.shell_pid is not None and self.shell_exit() is None:
            os.kill(self.shell_pid, signal.SIGKILL)
            os.waitpid(self.shell_pid, 0)
            self.note('shell killed at teardown')
        # Collect what the shell wrote on its way out.
        for _ in range(10):
            if self.master is None:
                break
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if not ready:
                break
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                break
            if not chunk:
                break
            self.output.extend(chunk)
        if self.master is not None:
            os.close(self.master)
            self.master = None


WAITING = b'Waiting for the next run'


def attach(h, index, start=0, args=()):
    """Starts app [index] with [args] and waits for its first frame past
    [start]."""
    h.start_app(args)
    return h.expect_output(
        b'SHELL-KEYS-READY', 60, f'app {index} first frame', start
    )


def scenario_keys(h):
    """Every key reaches the app, the terminal comes back exactly after each
    run, and the shell serves the next run until Ctrl+C quits it idle."""
    h.start_shell()
    ready = h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    # Typed while no app is attached: addressed to no app, so none gets it.
    h.write(b'stale\r', 'stale + Enter while idle')
    offset = attach(h, 0, ready)
    h.termios('attached')
    h.terminal_state('attached')
    h.write(b'x', 'x')
    h.expect_app_record(0, {'text': 'x'}, 15, 'the typed x')
    h.write(b'\x1a', 'Ctrl+Z')
    h.expect_app_record(0, {'text': ''}, 15, "Ctrl+Z's undo")
    h.expect_shell_alive('after Ctrl+Z')
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(0, 15, 'app 0 to end on its unhandled Ctrl+C')
    offset = h.expect_output(WAITING, 15, 'the shell to wait for the next run', offset)
    h.expect_restored(idle, 'afterSession')
    h.terminal_state('afterSession')

    # The next run attaches to the same shell.
    offset = attach(h, 1, offset)
    h.write(b'y', 'y')
    h.expect_app_record(1, {'text': 'y'}, 15, 'the typed y')
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(1, 15, 'app 1 to end on its unhandled Ctrl+C')
    h.expect_output(WAITING, 15, 'the shell to wait again', offset)

    # With no app attached, Ctrl+C is the terminal's interrupt again.
    h.write(b'\x03', 'Ctrl+C while idle')
    h.expect_shell_exit(15, 'the idle shell to quit on Ctrl+C')
    h.expect_restored(idle, 'afterShell')
    h.terminal_state('afterShell')


def scenario_unhandled_ctrl_z(h):
    """A Ctrl+Z the app leaves unhandled stays an ordinary key: the app runs
    in the IDE, not as a job of the shell's terminal, so nothing stops."""
    h.start_shell()
    h.expect_output(b'fleury shell ready', 60, 'shell ready')
    h.start_app(['--no-field'])
    h.expect_output(b'SHELL-KEYS-NO-FIELD', 60, 'app 0 first frame')
    h.write(b'\x1a', 'Ctrl+Z')
    h.expect_app_record(0, {'key': 'z', 'ctrl': True}, 15, 'the unhandled Ctrl+Z')
    h.expect_running(0, 'after the unhandled Ctrl+Z')
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(0, 15, 'app 0 to end on its unhandled Ctrl+C')


def scenario_sigterm(h):
    """SIGTERM while an app is attached restores the terminal, the app's
    mouse tracking included, then exits."""
    h.start_shell()
    h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    attach(h, 0, args=['--mouse-motion'])
    h.terminal_state('attached')
    os.kill(h.shell_pid, signal.SIGTERM)
    h.note('sent SIGTERM')
    h.expect_shell_exit(15, 'the shell to exit on SIGTERM')
    h.expect_restored(idle, 'afterShell')
    h.terminal_state('afterShell')
    h.expect_app_exit(0, 15, 'app 0 to end with the shell')


def scenario_app_killed(h):
    """An app that dies without a goodbye still hands the terminal back,
    its mouse tracking off again, and the shell waits for the next run."""
    h.start_shell()
    h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    offset = attach(h, 0, args=['--mouse-motion'])
    h.terminal_state('attached')
    h.kill_app(0)
    h.expect_output(b'the app disconnected', 15, 'the disconnect status', offset)
    h.expect_shell_alive('after its app was killed')
    h.expect_restored(idle, 'afterSession')
    h.terminal_state('afterSession')
    os.kill(h.shell_pid, signal.SIGINT)
    h.note('sent SIGINT')
    h.expect_shell_exit(15, 'the shell to quit on SIGINT')


def scenario_hangup(h):
    """Closing the terminal while attached ends the shell and the app."""
    h.start_shell()
    h.expect_output(b'fleury shell ready', 60, 'shell ready')
    attach(h, 0)
    h.hang_up()
    h.expect_shell_exit(15, 'the shell to exit on hangup')
    h.expect_app_exit(0, 15, 'app 0 to end with the shell')


def scenario_mouse(h, flag):
    """An app whose mode asks for the mouse: the shell turns tracking on in
    its terminal, a click the terminal then reports presses the app's button
    (and with motion, moving onto a region hovers it), and when the app exits
    the terminal's modes and termios come back exactly."""
    h.start_shell()
    ready = h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    h.start_app([flag])
    offset = h.expect_output(b'SHELL-KEYS-READY', 60, 'app 0 first frame', ready)
    h.termios('attached')
    h.terminal_state('attached')
    if flag == '--mouse-motion':
        h.move(5, 2, 'the pointer onto the hover region')
        h.expect_app_record(0, {'hover': 'enter'}, 15, 'the hover')
    h.click(5, 1, 'a click on the button')
    h.expect_app_record(0, {'pressed': 'button'}, 15, 'the click')
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(0, 15, 'app 0 to end on its unhandled Ctrl+C')
    h.expect_output(WAITING, 15, 'the shell to wait for the next run', offset)
    h.expect_restored(idle, 'afterSession')
    h.terminal_state('afterSession')
    os.kill(h.shell_pid, signal.SIGINT)
    h.note('sent SIGINT')
    h.expect_shell_exit(15, 'the shell to quit on SIGINT')
    h.expect_restored(idle, 'afterShell')
    h.terminal_state('afterShell')


def scenario_no_input_reporting(h):
    """An app that reads no mouse, no pastes, no focus changes, and legacy
    keys gets a terminal that reports none of them: a click stays the
    terminal's, and a typed key arrives as a plain byte."""
    h.start_shell()
    ready = h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    h.start_app(['--no-input-reporting'])
    offset = h.expect_output(b'SHELL-KEYS-READY', 60, 'app 0 first frame', ready)
    h.terminal_state('attached')
    h.click(5, 1, 'a click')
    h.write(b'x', 'x')
    h.expect_app_record(0, {'text': 'x'}, 15, 'the typed x')
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(0, 15, 'app 0 to end on its unhandled Ctrl+C')
    h.expect_output(WAITING, 15, 'the shell to wait for the next run', offset)
    h.expect_restored(idle, 'afterSession')
    h.terminal_state('afterSession')


def scenario_mismatched_apps(h):
    """Peers that do not speak this shell's protocol are turned away with a
    message that says why, the terminal comes back, and the shell serves the
    next run: an app that hangs up on the INIT without answering, then one
    from a newer Fleury (it answers at shell protocol 3)."""
    h.start_shell()
    ready = h.expect_output(b'fleury shell ready', 60, 'shell ready')
    idle = h.termios('idle')
    h.terminal_state('idle')
    h.fake_app(None, 'an app that hangs up without answering')
    offset = h.expect_output(WAITING, 15, 'the shell to turn it away', ready)
    h.expect_restored(idle, 'afterSilentApp')
    h.terminal_state('afterSilentApp')
    h.fake_app(
        'cols=80,rows=24,color=truecolor,glyph=unicode,image=halfBlock,'
        'tmux=0,mouse=1,motion=0,paste=1,focus=1,'
        'keyboardProtocol=lifecycle,shell=3',
        'an app at shell protocol 3',
    )
    offset = h.expect_output(WAITING, 15, 'the shell to turn it away', offset)
    h.expect_restored(idle, 'afterNewApp')
    h.terminal_state('afterNewApp')
    # The next run, this build's app, attaches as usual.
    offset = attach(h, 0, offset)
    h.write(b'\x03', 'Ctrl+C')
    h.expect_app_exit(0, 15, 'app 0 to end on its unhandled Ctrl+C')
    h.expect_output(WAITING, 15, 'the shell to wait again', offset)


SCENARIOS = {
    'keys': scenario_keys,
    'unhandled-ctrl-z': scenario_unhandled_ctrl_z,
    'sigterm': scenario_sigterm,
    'app-killed': scenario_app_killed,
    'hangup': scenario_hangup,
    'mouse': lambda h: scenario_mouse(h, '--mouse'),
    'mouse-motion': lambda h: scenario_mouse(h, '--mouse-motion'),
    'no-input-reporting': scenario_no_input_reporting,
    'mismatched-apps': scenario_mismatched_apps,
}


def main():
    scenario, dart, package_root, work_dir = sys.argv[1:5]
    h = Harness(dart, package_root, work_dir)
    h.report['scenario'] = scenario
    h.report['failure'] = None
    try:
        SCENARIOS[scenario](h)
    except StepFailed as error:
        h.report['failure'] = str(error)
    except Exception as error:  # a harness bug: report it the same way
        h.report['failure'] = f'harness error: {error!r}'
    finally:
        h.close()
        h.report['shellExit'] = h.shell_status
        with open(os.path.join(work_dir, 'pty.bin'), 'wb') as file:
            file.write(bytes(h.output))
        with open(os.path.join(work_dir, 'report.json'), 'w') as file:
            json.dump(h.report, file, indent=2)


if __name__ == '__main__':
    main()
