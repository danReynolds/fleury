/// Shared completeness accounting: failed measurements stay in the artifact.
class CaptureAttempts {
  CaptureAttempts(this.requested);
  final int requested;
  final runs = <Map<String, Object?>>[];
  bool get complete =>
      runs.length == requested && runs.every((r) => r['status'] == 'complete');
  Map<String, Object?> toJson() => {
        'requestedRuns': requested,
        'successfulRuns': runs.where((r) => r['status'] == 'complete').length,
        'failedRuns': runs.where((r) => r['status'] != 'complete').length,
        'status': complete ? 'complete' : 'incomplete',
        'attempts': runs,
      };
}
