/**
 * GxFeedbackDispatch
 *
 * Prepares a booking for its post-trip feedback invitation: mints the token,
 * opens the booking to the guest, and returns the link for the email to send.
 *
 * Invocable rather than a Flow full of elements, for three reasons. It can be
 * called from anywhere - a scheduled Flow, the existing Send Survey button, a
 * record-triggered Flow or Apex - so how surveys are triggered stays a business
 * decision rather than a dependency of this code. The ordering below is
 * enforced here rather than in a sequence of Flow elements someone can reorder.
 * And it is testable.
 *
 * ORDERING MATTERS. The guest sharing rule shares bookings whose Status__c is
 * 'Feedback'. If the email went out before that status were set, the guest would
 * follow a valid link to a booking they cannot read and be told the link is
 * invalid. The status and the secret are therefore committed before any link is
 * handed back to the caller.
 */
public with sharing class GxFeedbackDispatch {
  /** Statuses meaning the trip happened and feedback is fair to ask for. */
  private static final Set<String> ELIGIBLE_BOOKING_STATUS = new Set<String>{
    'Completed',
    'Paid',
    'Invoiced',
    'Feedback'
  };

  private static final String STATUS_FEEDBACK = 'Feedback';

  /** 24 random bytes, base64url encoded - 32 characters, ~192 bits. */
  private static final Integer SECRET_KEY_BITS = 192;

  public class Request {
    @InvocableVariable(
      label='Booking Id'
      description='The booking to prepare a feedback invitation for.'
      required=true
    )
    public Id bookingId;

    @InvocableVariable(
      label='Allow Resend'
      description='Set when a person is deliberately re-sending. Bypasses the already-invited guard, but never the guard on feedback that has already been given.'
    )
    public Boolean allowResend = false;

    @InvocableVariable(
      label='Mark As Reminder'
      description='Set by the reminder pass. Records that this guest has now been reminded, so they are only ever reminded once.'
    )
    public Boolean markReminder = false;
  }

  public class Result {
    @InvocableVariable(label='Ready To Send')
    public Boolean ok = false;

    @InvocableVariable(
      label='Survey URL'
      description='The tokenised link to put in the email. Empty when the booking was skipped.'
    )
    public String surveyUrl;

    @InvocableVariable(label='Booking Number')
    public String bookingNumber;

    @InvocableVariable(
      label='Recipient Contact Id'
      description='Who the invitation should go to.'
    )
    public Id recipientContactId;

    @InvocableVariable(
      label='Skipped Reason'
      description='Why this booking was not prepared. Empty when it was.'
    )
    public String skippedReason;
  }

  @InvocableMethod(
    label='Prepare Golf Extra Feedback Invitation'
    description='Mints the survey token, opens the booking to the guest user and returns the link to email. Skips bookings that are not ready, with a reason.'
    category='Golf Extra Feedback'
  )
  public static List<Result> prepare(List<Request> requests) {
    List<Result> results = new List<Result>();
    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> bookingIds = new Set<Id>();
    for (Request r : requests) {
      if (r != null && r.bookingId != null) {
        bookingIds.add(r.bookingId);
      }
    }

    Map<Id, Booking__c> bookings = new Map<Id, Booking__c>(
      [
        SELECT
          Id,
          BookingNumber__c,
          Status__c,
          End_Date__c,
          Start_Date__c,
          MainContact__c,
          Form_Secret__c,
          SurveySent__c,
          Survey_Sent_On__c,
          Survey_Reminder_Sent__c
        FROM Booking__c
        WHERE Id IN :bookingIds
      ]
    );

    // Bookings that already carry feedback are never invited twice.
    Set<Id> answered = new Set<Id>();
    for (Feedback_Response__c f : [
      SELECT Booking__c
      FROM Feedback_Response__c
      WHERE Booking__c IN :bookingIds
    ]) {
      answered.add(f.Booking__c);
    }

    // An invitation to a survey with no questions in it is worse than no
    // invitation, so every booking is checked against the same rules the survey
    // itself applies. Asked once for the whole batch: checking each booking on
    // its own costs two queries apiece, which a nightly run cannot afford.
    Set<Id> rateable = GxFeedbackService.bookingsWithRateableItems(bookingIds);

    Map<Id, Booking__c> toUpdate = new Map<Id, Booking__c>();

    for (Request r : requests) {
      Result out = new Result();
      Booking__c b = r == null ||
        r.bookingId == null
        ? null
        : bookings.get(r.bookingId);

      Boolean resending = r != null && r.allowResend == true;
      String problem = ineligibleReason(b, answered, rateable, resending);
      if (problem != null) {
        out.skippedReason = problem;
        results.add(out);
        continue;
      }

      if (String.isBlank(b.Form_Secret__c)) {
        b.Form_Secret__c = newSecret();
      }
      b.Status__c = STATUS_FEEDBACK;
      b.SurveySent__c = true;
      // Moves forward on every send, reminder included, because the survey's
      // expiry counts from the last time the guest was actually asked.
      b.Survey_Sent_On__c = Datetime.now();
      if (r.markReminder == true) {
        // Set before the reminder leaves, so a failed send is not retried.
        // With a guest's inbox at stake, under-reminding is the safer failure.
        b.Survey_Reminder_Sent__c = true;
      }
      toUpdate.put(b.Id, b);

      out.ok = true;
      out.bookingNumber = b.BookingNumber__c;
      out.recipientContactId = b.MainContact__c;
      out.surveyUrl = buildUrl(b);
      results.add(out);
    }

    if (!toUpdate.isEmpty()) {
      // Committed before the caller sends anything, so the guest can read
      // the booking by the time the link reaches them.
      update toUpdate.values();
    }

    return results;
  }

  /** Null when the booking is ready; otherwise why it was skipped. */
  private static String ineligibleReason(
    Booking__c b,
    Set<Id> answered,
    Set<Id> rateable,
    Boolean allowResend
  ) {
    if (b == null) {
      return 'Booking not found';
    }
    if (String.isBlank(b.BookingNumber__c)) {
      return 'Booking has no booking number';
    }
    if (b.MainContact__c == null) {
      return 'Booking has no main contact to invite';
    }
    if (answered.contains(b.Id)) {
      return 'Feedback already received';
    }
    if (b.SurveySent__c == true && allowResend != true) {
      return 'Invitation already sent';
    }
    if (!ELIGIBLE_BOOKING_STATUS.contains(b.Status__c)) {
      return 'Trip is not complete (status ' + b.Status__c + ')';
    }
    // The window decides who enters the programme. A guest we have already
    // invited is inside it, so reminders and resends are not re-judged here.
    if (b.Survey_Sent_On__c == null) {
      String outside = outsideSurveyWindow(b);
      if (outside != null) {
        return outside;
      }
    }
    if (!waitingPeriodPassed(b)) {
      return 'Waiting period after the trip has not passed yet';
    }
    if (!rateable.contains(b.Id)) {
      return 'Nothing on this itinerary can be rated';
    }
    return null;
  }

  /**
   * Null when the trip may be surveyed; otherwise why not.
   *
   * Without this, the first nightly run in an org would invite every guest in
   * its booking history - every finished trip has an end date in the past,
   * the waiting period long since over. Two guards, and either is enough to
   * refuse:
   *
   * - Survey_Start_Date__c: nothing that ended before the programme started.
   *   Blank refuses everything, because a missing setting must not quietly
   *   become "no limit".
   * - Max_Trip_Age_Days__c: nothing older than a few weeks, whatever the start
   *   date says. If the start date is set wrong or the job is paused and later
   *   resumed, this bounds the damage to recent trips.
   */
  @TestVisible
  private static String outsideSurveyWindow(Booking__c b) {
    Date startDate = GxFeedbackSettings.surveyStartDate();
    if (startDate == null) {
      return 'No survey start date is configured, so no trip is invited';
    }
    Date tripEnd = b.End_Date__c != null ? b.End_Date__c : b.Start_Date__c;
    if (tripEnd == null) {
      return 'Trip has no dates to check against the survey start date';
    }
    if (tripEnd < startDate) {
      return 'Trip ended before the survey started (' +
        startDate.format() +
        ')';
    }
    Decimal maxAge = GxFeedbackSettings.maxTripAgeDays();
    if (
      maxAge != null &&
      maxAge > 0 &&
      tripEnd.daysBetween(Date.today()) > maxAge.intValue()
    ) {
      return 'Trip ended more than ' + maxAge.intValue() + ' days ago';
    }
    return null;
  }

  /**
   * Guests are given room to get home before being asked to reflect. The delay
   * runs from the start of the trip's end date, so a 36 hour setting reaches
   * the guest a day and a half after the trip finishes.
   */
  @TestVisible
  private static Boolean waitingPeriodPassed(Booking__c b) {
    Decimal hours = GxFeedbackSettings.dispatchDelayHours();
    if (hours == null || hours <= 0) {
      return true;
    }
    Date reference = b.End_Date__c != null ? b.End_Date__c : b.Start_Date__c;
    if (reference == null) {
      // Nothing to measure from: do not hold the invitation forever.
      return true;
    }
    Datetime tripEnd = Datetime.newInstance(
      reference,
      Time.newInstance(0, 0, 0, 0)
    );
    return Datetime.now() >= tripEnd.addMinutes((hours * 60).intValue());
  }

  private static String buildUrl(Booking__c b) {
    String base = GxFeedbackSettings.surveyBaseUrl();
    if (String.isBlank(base)) {
      return null;
    }
    if (!base.endsWith('/') && !base.endsWith('=')) {
      base += '/';
    }
    return base +
      '?b=' +
      EncodingUtil.urlEncode(b.BookingNumber__c, 'UTF-8') +
      '&k=' +
      EncodingUtil.urlEncode(b.Form_Secret__c, 'UTF-8');
  }

  /**
   * Cryptographically random, and URL safe so it survives an email client
   * rewriting the link. Matches the ~120 bit standard of the secrets the
   * Reiseanmeldung process already mints.
   */
  @TestVisible
  private static String newSecret() {
    return EncodingUtil.base64Encode(Crypto.generateAesKey(SECRET_KEY_BITS))
      .replace('+', '-')
      .replace('/', '_')
      .replace('=', '');
  }
}
