// Own only the browser handoff. Compilation and accepted checkpoints belong
// to the editor; application reassembly belongs to MountedApp in Fleury.
export class Preview {
  constructor(container, { onError = () => {}, timeoutMs = 15000, frameUrl = '/frame.html' } = {}) {
    this.container = container;
    this.frameUrl = frameUrl;
    this.onError = onError;
    this.timeoutMs = timeoutMs;
    this.frame = null;
    this.pending = null;
    this.sequence = 0;
    this.canReload = false;
    this.disposed = false;
    this.receive = event => this.onMessage(event);
    window.addEventListener('message', this.receive);
  }

  get hasFrame() { return this.frame !== null; }

  apply(program, { reload = false } = {}) {
    if (this.disposed) return Promise.reject(new Error('Preview is disposed.'));
    if (this.pending) return Promise.reject(new Error('An update is already pending.'));
    if (reload && !this.canReload) return Promise.reject(new Error('Restart the preview before reloading again.'));
    const id = ++this.sequence;
    this.canReload = false;
    return new Promise((resolve, reject) => {
      this.pending = { id, mode: reload ? 'reload' : 'run', program, resolve, reject, sent: false,
        timer: setTimeout(() => this.fail(new Error('The preview did not finish updating. Restart to try again.')), this.timeoutMs) };
      try {
        if (reload) this.send();
        else {
          const frame = document.createElement('iframe');
          frame.title = 'Running Fleury app';
          frame.setAttribute('sandbox', 'allow-scripts');
          frame.src = this.frameUrl;
          this.frame = frame;
          this.container.replaceChildren(frame);
        }
      } catch (error) { this.fail(error); }
    });
  }

  send() {
    const operation = this.pending;
    if (!operation || operation.sent) return;
    operation.sent = true;
    // Never send the editor source or compiler checkpoint into user code.
    this.frame.contentWindow.postMessage({ sender: 'fleury-editor', id: operation.id,
      mode: operation.mode, javascript: operation.program.javascript,
      libraries: operation.program.libraries }, '*');
  }

  onMessage(event) {
    if (this.disposed || !this.frame || event.source !== this.frame.contentWindow || event.data?.sender !== 'fleury-pad') return;
    const { type, id, message } = event.data;
    if (type === 'size') {
      // A frame sized to a docs example's grid asks for room to show all of it.
      const { width, height } = event.data;
      if (Number.isFinite(width) && Number.isFinite(height)) {
        this.frame.style.width = `${width + 2}px`;
        this.frame.style.height = `${height + 2}px`;
      }
      return;
    }
    const operation = this.pending;
    if (type === 'ready') {
      if (operation?.mode === 'run') this.send();
      return;
    }
    if (type === 'error' && id === 0 && operation?.mode === 'run' && !operation.sent) {
      this.fail(new Error(message || 'Could not load the preview runtime.'));
      return;
    }
    if (id !== this.sequence) return;
    if (type === 'error') {
      if (operation) this.fail(new Error(message || 'The app failed to update.'));
      else if (this.canReload) {
        this.canReload = false;
        this.onError(new Error(message || 'The app failed.'));
      }
      return;
    }
    if (!operation?.sent || type !== (operation.mode === 'reload' ? 'reloaded' : 'running')) return;
    clearTimeout(operation.timer);
    this.pending = null;
    this.canReload = true;
    operation.resolve();
  }

  fail(error) {
    this.canReload = false;
    const operation = this.pending;
    this.pending = null;
    if (!operation) return;
    clearTimeout(operation.timer);
    operation.reject(error);
  }

  dispose() {
    this.disposed = true;
    window.removeEventListener('message', this.receive);
    this.fail(new Error('Preview was closed.'));
    this.frame?.remove();
    this.frame = null;
  }
}
