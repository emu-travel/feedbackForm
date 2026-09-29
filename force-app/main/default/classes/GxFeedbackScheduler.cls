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

  /**
   * Both passes, in one transaction, invitations first. A booking the org
   * refuses to save does not stop the others (see GxFeedbackDispatch); anyone
   * due who could not be asked is reported by GxFeedbackRunNotice.
   */
  public static List<GxFeedbackSender.Result> run() {
    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();
    requests.addAll(invitations());
    requests.addAll(reminders());

    if (requests.isEmpty()) {
      return new List<GxFeedbackSender.Result>();
    }
    List<GxFeedbackSender.Result> results = GxFeedbackSender.send(requests);
    GxFeedbackRunNotice.sendIfNeeded(requests, results);
    return results;
  }

  /**
   * Bookings worth inviting: a trip that has happened, nobody invited yet, and
   * an end date already behind us. Everything finer - the waiting period,
   * whether there is anything to rate, whether feedback already arrived - is
   * decided per booking by GxFeedbackDispatch.
   */
  private static List<GxFeedbackSender.Request> invitations() {
    Date earliest = earliestTripEnd();
    if (earliest == null) {
      // No survey start date: nobody is invited. See Survey_Start_Date__c.
      return new List<GxFeedbackSender.Request>();
    }
    // A group trip is several bookings: the group booking and one participant
    // booking per party, linked by TravelGroup__c. The team marks the group
    // booking as travelled, so a participant booking qualifies through its
    // group as well as through its own status. Its own end date and waiting
    // period still decide when its guests are asked.
    List<Booking__c> due = [
      SELECT Id, MainContact__c
      FROM Booking__c
      WHERE
        SurveySent__c = FALSE
        AND End_Date__c != NULL
        AND End_Date__c >= :earliest
        AND End_Date__c < TODAY
        AND (Status__c IN ('Traveled', 'Completed')
        OR TravelGroup__r.Status__c IN ('Traveled', 'Completed'))
      ORDER BY End_Date__c
      LIMIT :batchLimit
    ];
    return requestsFor(due, false);
  }

  /**
   * The oldest trip end the programme will invite: the survey start date, or
   * the age cap, whichever is later.
   *
   * Filtered here as well as refused in GxFeedbackDispatch. Without it the
   * query would select the org's whole booking history every night, the
   * dispatch would refuse all of it, and those refusals would fill the batch
   * limit ahead of the guests who should actually be asked. The dispatch stays
   * the authority; this only keeps the batch for trips that can pass.
   */
  @TestVisible
  private static Date earliestTripEnd() {
    Date startDate = GxFeedbackSettings.surveyStartDate();
    if (startDate == null) {
      return null;
    }
    Decimal maxAge = GxFeedbackSettings.maxTripAgeDays();
    if (maxAge == null || maxAge <= 0) {
      return startDate;
    }
    Date ageLimit = Date.today().addDays(-maxAge.intValue());
    return ageLimit > startDate ? ageLimit : startDate;
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
    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();

    // One guest, one reminder. Their own invitation carries when they were
    // asked, whether they have been reminded and whether they have answered, so
    // the silent guests on a trip are reminded and the others are left alone.
    for (Feedback_Invitation__c inv : [
      SELECT Id, Booking__c, Contact__c, Traveler__c
      FROM Feedback_Invitation__c
      WHERE
        Sent_On__c != NULL
        AND Sent_On__c <= :askedBefore
        AND Reminder_Sent__c = FALSE
        AND Answered_On__c = NULL
        AND Contact__c != NULL
      ORDER BY Sent_On__c
      LIMIT :batchLimit
    ]) {
      requests.add(
        requestFor(inv.Booking__c, inv.Traveler__c, inv.Contact__c, true)
      );
    }

    // Trips invited before invitations were kept per person carry no rows, so
    // their main contact is reminded from the booking, exactly as before. New
    // trips never reach this: their guests all have a row of their own.
    for (Booking__c b : [
      SELECT Id, MainContact__c
      FROM Booking__c
      WHERE
        SurveySent__c = TRUE
        AND Survey_Reminder_Sent__c = FALSE
        AND MainContact__c != NULL
        AND Survey_Sent_On__c != NULL
        AND Survey_Sent_On__c <= :askedBefore
        AND Id NOT IN (SELECT Booking__c FROM Feedback_Response__c)
        AND Id NOT IN (SELECT Booking__c FROM Feedback_Invitation__c)
      ORDER BY Survey_Sent_On__c
      LIMIT :batchLimit
    ]) {
      requests.add(requestFor(b.Id, null, b.MainContact__c, true));
    }
    return requests;
  }

  /**
   * One request per person, not per booking: every traveller with an email
   * address, plus the booking's main contact when they are not already one of
   * them. Nobody is asked twice for the same trip, whether they appear as a
   * traveller and as the main contact, or twice with the same address.
   */
  private static List<GxFeedbackSender.Request> requestsFor(
    List<Booking__c> bookings,
    Boolean asReminder
  ) {
    List<GxFeedbackSender.Request> requests = new List<GxFeedbackSender.Request>();
    if (bookings.isEmpty()) {
      return requests;
    }
    Map<Id, Booking__c> byId = new Map<Id, Booking__c>(bookings);

    Map<Id, Set<Id>> contactsAsked = new Map<Id, Set<Id>>();
    Map<Id, Set<String>> addressesAsked = new Map<Id, Set<String>>();
    for (Id bookingId : byId.keySet()) {
      contactsAsked.put(bookingId, new Set<Id>());
      addressesAsked.put(bookingId, new Set<String>());
    }

    for (Traveler__c t : [
      SELECT Id, TravelQuote__c, Traveler__c, Traveler__r.Email
      FROM Traveler__c
      WHERE
        TravelQuote__c IN :byId.keySet()
        AND Traveler__c != NULL
        AND Traveler__r.Email != NULL
      ORDER BY CreatedDate
    ]) {
      String address = t.Traveler__r.Email.trim().toLowerCase();
      if (
        !contactsAsked.get(t.TravelQuote__c).add(t.Traveler__c) ||
        !addressesAsked.get(t.TravelQuote__c).add(address)
      ) {
        continue;
      }
      requests.add(
        requestFor(t.TravelQuote__c, t.Id, t.Traveler__c, asReminder)
      );
    }

    for (Booking__c b : bookings) {
      if (
        b.MainContact__c == null ||
        contactsAsked.get(b.Id).contains(b.MainContact__c)
      ) {
        continue;
      }
      requests.add(requestFor(b.Id, null, b.MainContact__c, asReminder));
    }
    return requests;
  }

  private static GxFeedbackSender.Request requestFor(
    Id bookingId,
    Id travelerId,
    Id contactId,
    Boolean asReminder
  ) {
    GxFeedbackSender.Request r = new GxFeedbackSender.Request();
    r.bookingId = bookingId;
    r.travelerId = travelerId;
    r.contactId = contactId;
    // A reminder is a second send to someone already marked as invited, so it
    // needs the same guard bypass a person clicking Resend needs.
    r.allowResend = asReminder;
    r.markReminder = asReminder;
    return r;
  }
}
