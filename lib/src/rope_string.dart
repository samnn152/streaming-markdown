class RopeString {
  final List<String> _chunks = <String>[];
  final List<int> _prefixCodeUnits = <int>[];
  int _length = 0;
  String? _cache;

  int get length => _length;
  bool get isEmpty => _length == 0;

  void append(String text) {
    if (text.isEmpty) return;
    _chunks.add(text);
    _length += text.length;
    _prefixCodeUnits.add(_length);
    _cache = null;
  }

  void clear() {
    _chunks.clear();
    _prefixCodeUnits.clear();
    _length = 0;
    _cache = '';
  }

  String substring(int start, [int? end]) {
    end ??= _length;
    RangeError.checkValidRange(start, end, _length);
    if (start == end) return '';

    final StringBuffer out = StringBuffer();
    int chunkIndex = _lowerBoundPrefix(start + 1);
    int cursor = start;

    while (cursor < end) {
      final int chunkStart = chunkIndex == 0
          ? 0
          : _prefixCodeUnits[chunkIndex - 1];
      final int chunkEnd = _prefixCodeUnits[chunkIndex];

      final int localStart = cursor - chunkStart;
      final int localEnd = (end < chunkEnd ? end : chunkEnd) - chunkStart;

      out.write(_chunks[chunkIndex].substring(localStart, localEnd));
      cursor += (localEnd - localStart);
      chunkIndex++;
    }

    return out.toString();
  }

  int codeUnitAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    final int chunkIndex = _lowerBoundPrefix(index + 1);
    final int chunkStart = chunkIndex == 0
        ? 0
        : _prefixCodeUnits[chunkIndex - 1];
    return _chunks[chunkIndex].codeUnitAt(index - chunkStart);
  }

  String charAt(int index) => String.fromCharCode(codeUnitAt(index));

  @override
  String toString() {
    return _cache ??= _chunks.join();
  }

  int _lowerBoundPrefix(int target) {
    int left = 0;
    int right = _prefixCodeUnits.length;
    while (left < right) {
      final int mid = (left + right) >> 1;
      if (_prefixCodeUnits[mid] < target) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    return left;
  }
}
