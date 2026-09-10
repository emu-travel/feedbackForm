/*
 * Sends one guest their feedback invitation, for a named booking.
 *
 * The same invocable the button and the nightly job both call. allowResend is
 * true, so this will re-send to a booking that has already been invited - but
 * it will still refuse a guest who has already answered.
 *
 * Put the booking number below, then:
 *   sf apex run --target-org gx-sandbox --file scripts/apex/send-feedback-invitation.apex
 */
String bookingNumber = 'REPLACE-ME';

Booking__c b = [
  SELECT Id, BookingNumber__c, MainContact__r.Name, MainContact__r.Email
  FROM Booking__c
  WHERE BookingNumber__c = :bookingNumber
  LIMIT 1
];

System.debug(
  '=== Sending ' + b.BookingNumber__c +
  ' to ' + b.MainContact__r.Name + ' <' + b.MainContact__r.Email + '>'
);

GxFeedbackSender.Request req = new GxFeedbackSender.Request();
req.bookingId = b.Id;
req.allowResend = true;

GxFeedbackSender.Result r = GxFeedbackSender.send(
  new List<GxFeedbackSender.Request>{ req }
)[0];

System.debug(r.sent ? 'SENT    ' + r.surveyUrl : 'NOT SENT: ' + r.message);
