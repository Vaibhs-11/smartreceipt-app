abstract class NotificationsService {
  Future<void> scheduleExpiryReminder(String receiptId, DateTime when);
}

class NotificationsServiceStub implements NotificationsService {
  @override
  Future<void> scheduleExpiryReminder(String receiptId, DateTime when) async {
    // no-op in stub
  }
}


