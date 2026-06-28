/// Returns a fixed 50 MB estimate for native platforms.
/// Real memory monitoring is done by the Flutter framework.
Future<int> getMemoryInfo() async {
  return 50 * 1024 * 1024;
}
