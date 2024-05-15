String transformUnixTimestampToGeneralizedHumanFormat(int timestamp) {
  final DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final DateTime now = DateTime.now();

  if (timestampDateTime.year == now.year &&
      timestampDateTime.month == now.month &&
      timestampDateTime.day == now.day) {
    // If date is today, show only time
    return '${timestampDateTime.hour.toString().padLeft(2, '0')}:${timestampDateTime.minute.toString().padLeft(2, '0')}';
  } else {
    // If date is not today, show only date
    return '${timestampDateTime.day.toString().padLeft(2, '0')}.${timestampDateTime.month.toString().padLeft(2, '0')}.${timestampDateTime.year.toString().substring(2)}';
  }
}

String transformUnixTimestampToTimeHumanFormat(int timestamp) {
  final DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${timestampDateTime.hour.toString().padLeft(2, '0')}:${timestampDateTime.minute.toString().padLeft(2, '0')}';
}
