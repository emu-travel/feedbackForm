/**
 * GxFeedbackScheduler
 *
 * Nightly job that does two things: invites guests whose trips have finished,
 * and reminds the ones who were invited and never answered.
 *
 * Both passes only decide which bookings are worth looking at. Whether any
 * given booking may actually be written to and emailed is GxFeedbackDispatch's
 * decision, every time - so the queries here can stay coarse without the two
 * ever disagreeing.
 *
 * Schedule with, for example:
 *   System.schedule('Golf Extra Feedback', '0 0 7 * * ?', new GxFeedbackScheduler());
 */
public with sharing class GxFeedbackScheduler implements Schedulable {
  /** Per pass, not in total. The dispatch layer re-checks everything anyway. */
  @TestVisible
  private static Integer batchLimit = 200;

  public void execute(SchedulableContext context) {
    run();
  }

  /** Both passes, in one transaction, invitations first. */
  public static List<GxFeedbackSender.Result> run() {
    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();
    requests.addAll(invitations());
    requests.addAll(reminders());

    if (requests.isEmpty()) {
      return new List<GxFeedbackSender.Result>();
    }
    return GxFeedbackSender.send(requests);
  }

  /**
   * Bookings worth inviting: a trip that has happened, nobody invited yet, and
   * an end date already behind us. Everything finer - the waiting period,
   * whether there is anything to rate, whether feedback already arrived - is
   * decided per booking by GxFeedbackDispatch.
   */
  private static List<GxFeedbackSender.Request> invitations() {
    List<Booking__c> due = [
      SELECT Id
      FROM Booking__c
      WHERE
        SurveySent__c = FALSE
        AND MainContact__c != NULL
        AND End_Date__c != NULL
        AND End_Date__c < TODAY
        AND Status__c IN ('Completed', 'Paid', 'Invoiced', 'Feedback')
      ORDER BY End_Date__c
      LIMIT :batchLimit
    ];
    return requestsFor(due, false);
  }

  /**
   * Guests invited a while ago who have not answered. One reminder each, ever,
   * tracked by Survey_Reminder_Sent__c.
   *
   * The bookings that already carry feedback are excluded here as well as in
   * the dispatch. That is not belt and braces: without it, every guest who has
   * answered would be selected again every night, forever, and would eventually
   * crowd the guests who still need reminding out of the batch limit. The
   * dispatch guard remains the authority on whether a reminder may go.
   *
   * Nothing invited before Survey_Sent_On__c existed can be selected, because
   * the field is blank on those bookings - so switching reminders on does not
   * mail a backlog of old trips.
   */
  private static List<GxFeedbackSender.Request> reminders() {
    Decimal delayDays = GxFeedbackSettings.reminderDelayDays();
    if (delayDays == null || delayDays <= 0) {
      return new List<GxFeedbackSender.Request>();
    }

    Datetime askedBefore = Datetime.now().addDays(-delayDays.intValue());
    List<Booking__c> due = [
      SELECT Id
      FROM Booking__c
      WHERE
        SurveySent__c = TRUE
        AND Survey_Reminder_Sent__c = FALSE
        AND MainContact__c != NULL
        AND Survey_Sent_On__c != NULL
        AND Survey_Sent_On__c <= :askedBefore
        AND Id NOT IN (SELECT Booking__c FROM Feedback_Response__c)
      ORDER BY Survey_Sent_On__c
      LIMIT :batchLimit
    ];
    return requestsFor(due, true);
  }

  private static List<GxFeedbackSender.Request> requestsFor(
    List<Booking__c> bookings,
    Boolean asReminder
  ) {
    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();
    for (Booking__c b : bookings) {
      GxFeedbackSender.Request r = new GxFeedbackSender.Request();
      r.bookingId = b.Id;
      // A reminder is a second send to a booking already marked as invited, so
      // it needs the same guard bypass a person clicking Resend needs.
      r.allowResend = asReminder;
      r.markReminder = asReminder;
      requests.add(r);
    }
    return requests;
  }
}
