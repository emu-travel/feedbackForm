/**
 * GxFeedbackScheduler
 *
 * Nightly job that invites guests whose trips have finished. The eligibility
 * rules - including the waiting period after the trip - live in
 * GxFeedbackDispatch, so this class only has to decide which bookings are worth
 * looking at.
 *
 * Schedule with, for example:
 *   System.schedule('Golf Extra Feedback', '0 0 7 * * ?', new GxFeedbackScheduler());
 */
public with sharing class GxFeedbackScheduler implements Schedulable {
  /** Kept small: the dispatch layer re-checks everything anyway. */
  @TestVisible
  private static Integer batchLimit = 200;

  public void execute(SchedulableContext context) {
    run();
  }

  /**
   * Bookings worth considering: a trip that has happened, nobody invited yet,
   * and an end date already behind us. Everything finer - the waiting period,
   * whether there is anything to rate, whether feedback already arrived - is
   * decided per booking by GxFeedbackDispatch.
   */
  public static List<GxFeedbackSender.Result> run() {
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

    if (due.isEmpty()) {
      return new List<GxFeedbackSender.Result>();
    }

    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();
    for (Booking__c b : due) {
      GxFeedbackSender.Request r = new GxFeedbackSender.Request();
      r.bookingId = b.Id;
      r.allowResend = false;
      requests.add(r);
    }
    return GxFeedbackSender.send(requests);
  }
}
