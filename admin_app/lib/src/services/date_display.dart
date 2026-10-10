String transactionDateTime(DateTime? value) {
  if (value == null) return '—';
  final date = value.toLocal();
  const months = [
    'Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.',
    'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour < 12 ? 'am' : 'pm';
  return '${months[date.month - 1]} ${date.day}, ${date.year} $hour:$minute$period';
}
