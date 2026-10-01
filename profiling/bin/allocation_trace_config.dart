// Keep gate commands and their qualification tests on the same VM settings.
// At the default 1 ms sample period, this reserves roughly 128,000 slots for
// class-registration traffic, warmup, and the measured allocation window. The
// VM default is sized for CPU samples and can fill before allocation work starts.
// Preserve the prefix: the two window guards must still reject any truncation.
const allocationTraceVmFlags = <String>[
  '--deterministic',
  '--profiler',
  '--max-profile-depth=2',
  '--sample-buffer-duration=128',
  '--profile-startup',
  '--enable-vm-service=0',
  '--disable-service-auth-codes',
];
