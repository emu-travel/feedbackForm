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
 * ORDERING MATTERS. The guest sharing rule shares bookings whose SurveySent__c is
 * true. If the email went out before that flag were set, the guest would follow a
 * valid link to a booking they cannot read and be told the link is invalid. The
 * flag and the secret are therefore committed before any link is handed back to
 * the caller.
 *
 * STATUS. The path reads Traveled -> Completed -> Feedback. The team marks a trip
 * Traveled by hand; sending the invitation moves it on to Completed; the guest's
 * answer moves it to Feedback (GxFeedbackService.submit). A booking someone
 * already marked Completed is still invited and stays at Completed.
 */
public with sharing class GxFeedbackDispatch {
  /**
   * Statuses meaning the trip happened and feedback is fair to ask for: Traveled,
   * as agreed with the team on 2026-09-16, plus Completed for a trip someone moved
   * on by hand. Paid and Invoiced come before Traveled on the path and are not
   * enough on their own; Feedback means the guest has already answered.
   */
  private static final Set<String> ELIGIBLE_BOOKING_STATUS = new Set<String>{
    'Traveled',
    'Completed'
  };

  private static final String STATUS_TRAVELED = 'Traveled';
  private static final String STATUS_COMPLETED = 'Completed';

  /** The size of Booking__c.Survey_Snapshot__c. */
  private static final Integer SNAPSHOT_MAX_LENGTH = 131072;

  /** 24 random bytes, base64url encoded - 32 characters, ~192 bits. */
  private static final Integer SECRET_KEY_BITS = 192;

  /** Bookings a test wants refused by the save, as a rule or flow in the org would. */
  @TestVisible
  private static Set<Id> refuseSaveForTest = new Set<Id>();

  /**
   * For tests: a refused booking also sinks every booking saved alongside it,
   * which is what a fault in a record-triggered flow does.
   */
  @TestVisible
  private static Boolean refusalSinksTheBatchForTest = false;

  /**
   * What one more save must leave free in the run. Measured in staging on
   * 2026-09-17: one booking moving to Completed costs about 6 queries, 6 DML
   * statements and under a second of CPU, most of it in the org's booking flow.
   */
  private static final Integer SPARE_QUERIES = 20;
  private static final Integer SPARE_DML_STATEMENTS = 15;
  private static final Integer SPARE_CPU_MS = 5000;

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

    @InvocableVariable(
      label='Traveler Id'
      description='The traveller row this invitation comes from, when it comes from one. Kept on the invitation so the team can see who on the trip was asked.'
    )
    public Id travelerId;

    @InvocableVariable(
      label='Contact Id'
      description='The person to ask. Empty means the booking\'s main contact, which is how a one-off send from the booking works.'
    )
    public Id contactId;
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
      label='Traveler Id'
      description='The traveller this invitation belongs to. Empty when it went to the booking\'s main contact.'
    )
    public Id travelerId;

    @InvocableVariable(
      label='Booking Id'
      description='The trip this invitation is about.'
    )
    public Id bookingId;

    @InvocableVariable(
      label='Skipped Reason'
      description='Why this booking was not prepared. Empty when it was.'
    )
    public String skippedReason;

    @InvocableVariable(
      label='Could Not Be Saved'
      description='The booking was due but the org refused to save it. Nothing was changed on it, so it is tried again next time.'
    )
    public Boolean saveFailed = false;
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

    // One invited person, one link, on a row of their own: their secret, their
    // sent and reminded dates, their answer. So several guests on one trip are
    // asked, reminded and closed independently of each other.
    Map<String, Feedback_Invitation__c> invitations = new Map<String, Feedback_Invitation__c>();
    for (Feedback_Invitation__c inv : [
      SELECT
        Id,
        Booking__c,
        Contact__c,
        Traveler__c,
        Secret__c,
        Sent_On__c,
        Reminder_Sent__c,
        Answered_On__c
      FROM Feedback_Invitation__c
      WHERE Booking__c IN :bookingIds
    ]) {
      invitations.put(personKey(inv.Booking__c, inv.Contact__c), inv);
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
          Opportunity__c,
          Form_Secret__c,
          SurveySent__c,
          Survey_Sent_On__c,
          Survey_Reminder_Sent__c,
          Survey_Trip_Start__c,
          Survey_Trip_End__c,
          Survey_Snapshot__c,
          TravelGroup__c,
          TravelGroup__r.Status__c
        FROM Booking__c
        WHERE Id IN :bookingIds
      ]
    );

    // Nobody is asked twice. Per person, because several people can be asked
    // about the same trip: an answer closes that person's invitation, not
    // everyone else's. A response from before answers were attributed carries
    // no contact; it still closes the booking's main-contact invitation.
    Set<Id> answeredBookings = new Set<Id>();
    Set<String> answeredByPerson = new Set<String>();
    for (Feedback_Response__c f : [
      SELECT Booking__c, Contact__c
      FROM Feedback_Response__c
      WHERE Booking__c IN :bookingIds
    ]) {
      if (f.Contact__c == null) {
        answeredBookings.add(f.Booking__c);
      } else {
        answeredByPerson.add(personKey(f.Booking__c, f.Contact__c));
      }
    }

    // An invitation to a survey with no questions in it is worse than no
    // invitation, so every booking is checked against the same rules the survey
    // itself applies. Asked once for the whole batch: checking each booking on
    // its own costs two queries apiece, which a nightly run cannot afford.
    // The same pass builds the list saved with a first invitation.
    Map<Id, String> snapshots = GxFeedbackService.surveySnapshots(bookingIds);
    Set<Id> rateable = new Set<Id>(snapshots.keySet());
    for (Booking__c saved : bookings.values()) {
      // A guest already asked keeps the list they were sent, whatever the
      // booking's lines look like now, so a reminder or resend still goes out.
      if (String.isNotBlank(saved.Survey_Snapshot__c)) {
        rateable.add(saved.Id);
      }
    }

    Map<Id, Booking__c> toUpdate = new Map<Id, Booking__c>();
    List<Feedback_Invitation__c> invitationsToSave = new List<Feedback_Invitation__c>();
    List<Result> resultOfInvitation = new List<Result>();
    List<Id> bookingOfInvitation = new List<Id>();
    Map<Id, List<Result>> readyByBooking = new Map<Id, List<Result>>();

    for (Request r : requests) {
      Result out = new Result();
      Booking__c b = r == null ||
        r.bookingId == null
        ? null
        : bookings.get(r.bookingId);
      // Who is being asked: the person named on the request, or the booking's
      // main contact when nobody is named.
      Id person = r == null ? null : r.contactId;
      if (person == null && b != null) {
        person = b.MainContact__c;
      }
      Feedback_Invitation__c inv = b == null ||
        person == null
        ? null
        : invitations.get(personKey(b.Id, person));

      Boolean resending = r != null && r.allowResend == true;
      String problem = ineligibleReason(
        b,
        person,
        inv,
        answeredBookings,
        answeredByPerson,
        rateable,
        resending
      );
      if (problem != null) {
        out.skippedReason = problem;
        results.add(out);
        continue;
      }

      // The booking keeps a secret of its own: the email template merges the
      // booking's link, and the sender swaps in this person's. A blank one
      // would leave nothing to swap.
      if (String.isBlank(b.Form_Secret__c)) {
        b.Form_Secret__c = newSecret();
      }
      // This person's own invitation: minted the first time they are asked,
      // and moved forward when they are reminded or sent to again.
      if (inv == null) {
        inv = new Feedback_Invitation__c(
          Booking__c = b.Id,
          Contact__c = person,
          Traveler__c = r.travelerId
        );
        invitations.put(personKey(b.Id, person), inv);
      }
      if (String.isBlank(inv.Secret__c)) {
        inv.Secret__c = newSecret();
      }
      if (inv.Traveler__c == null && r.travelerId != null) {
        inv.Traveler__c = r.travelerId;
      }
      inv.Sent_On__c = Datetime.now();
      if (r.markReminder == true) {
        // Set before the reminder leaves, so a failed send is not retried.
        // With a guest's inbox at stake, under-reminding is the safer failure.
        inv.Reminder_Sent__c = true;
      }
      // The trip as it was when the guest was first asked. Reminders, resends
      // and later edits to the booking leave it alone, so the dashboard and
      // the survey keep to the trip this invitation was about.
      // What the guest will rate, saved with the first invitation and never
      // rebuilt: later changes to the booking do not reach a survey already
      // sent. Built from the lines as they were before this invitation moves
      // the status on, so automation reacting to that change cannot alter it.
      // A list too long for the field is not saved; that survey is then read
      // from the booking instead.
      if (
        String.isBlank(b.Survey_Snapshot__c) &&
        snapshots.containsKey(b.Id) &&
        snapshots.get(b.Id).length() <= SNAPSHOT_MAX_LENGTH
      ) {
        b.Survey_Snapshot__c = snapshots.get(b.Id);
      }
      if (b.Survey_Trip_End__c == null) {
        b.Survey_Trip_Start__c = b.Start_Date__c;
        b.Survey_Trip_End__c = b.End_Date__c != null
          ? b.End_Date__c
          : b.Start_Date__c;
      }
      // Sending is what moves a traveled trip on to Completed. A booking already
      // at Completed stays there; it reaches Feedback only when the guest answers.
      if (b.Status__c == STATUS_TRAVELED) {
        b.Status__c = STATUS_COMPLETED;
      }
      b.SurveySent__c = true;
      // Moves forward on every send, reminder included, because the survey's
      // expiry counts from the last time the guest was actually asked. On a
      // trip with several travellers this records the trip's last invitation;
      // each traveller's own dates live on their Traveler__c row.
      b.Survey_Sent_On__c = Datetime.now();
      if (r.markReminder == true) {
        b.Survey_Reminder_Sent__c = true;
      }
      toUpdate.put(b.Id, b);
      invitationsToSave.add(inv);
      resultOfInvitation.add(out);
      bookingOfInvitation.add(b.Id);
      if (!readyByBooking.containsKey(b.Id)) {
        readyByBooking.put(b.Id, new List<Result>());
      }
      readyByBooking.get(b.Id).add(out);

      out.ok = true;
      out.bookingId = b.Id;
      out.bookingNumber = b.BookingNumber__c;
      out.recipientContactId = person;
      out.travelerId = inv.Traveler__c;
      out.surveyUrl = buildUrl(b, inv.Secret__c);
      results.add(out);
    }

    if (!toUpdate.isEmpty()) {
      // Committed before the caller sends anything, so the guest can read
      // the booking by the time the link reaches them.
      //
      // One booking the org refuses must not hold back every other guest due
      // that night. A refused booking is left exactly as it was - not marked
      // sent, no list saved - so it comes up again on the next run, and it gets
      // no email, because its link would lead nowhere.
      Map<Id, String> refused = new Map<Id, String>();
      saveSeparatingRefusals(toUpdate.values(), refused);

      for (Id bookingId : refused.keySet()) {
        String reason =
          'The booking could not be saved: ' + refused.get(bookingId);
        for (Result out : readyByBooking.get(bookingId)) {
          out.ok = false;
          out.saveFailed = true;
          out.surveyUrl = null;
          out.recipientContactId = null;
          out.skippedReason = reason;
        }
      }
    }

    // The guests' own invitations, saved after their trip and only for the
    // trips that saved: a guest whose booking the org refused keeps no link and
    // no sent date, so the next run asks them again, while everyone else on the
    // trip still goes out tonight.
    if (!invitationsToSave.isEmpty()) {
      List<Feedback_Invitation__c> rows = new List<Feedback_Invitation__c>();
      List<Result> rowResults = new List<Result>();
      for (Integer i = 0; i < invitationsToSave.size(); i++) {
        if (resultOfInvitation[i].ok) {
          rows.add(invitationsToSave[i]);
          rowResults.add(resultOfInvitation[i]);
        }
      }
      if (!rows.isEmpty()) {
        List<Database.UpsertResult> saved = Database.upsert(rows, false);
        for (Integer i = 0; i < rows.size(); i++) {
          if (saved[i].isSuccess()) {
            continue;
          }
          rowResults[i].ok = false;
          rowResults[i].saveFailed = true;
          rowResults[i].surveyUrl = null;
          rowResults[i].recipientContactId = null;
          rowResults[i].skippedReason =
            'The invitation could not be saved: ' +
            (saved[i].getErrors().isEmpty()
              ? 'no reason given'
              : saved[i].getErrors()[0].getMessage().stripHtmlTags());
        }
      }
    }

    return results;
  }

  /**
   * Saves the bookings together, and narrows down any refusal to the bookings
   * that caused it. A fault in a record-triggered flow - the org's booking flow
   * runs when a booking moves to Completed - fails every booking saved in the
   * same batch, not only the one it choked on. So when several are refused
   * together they are split in half and each half saved again, until each
   * refusal belongs to a booking on its own: one bad booking among thirty costs
   * about ten extra saves. Stops splitting before the run could hit a governor
   * limit; bookings it could not separate stay untouched until the next run.
   */
  private static void saveSeparatingRefusals(
    List<Booking__c> rows,
    Map<Id, String> refused
  ) {
    List<Database.SaveResult> saved = save(rows);
    List<Booking__c> failed = new List<Booking__c>();
    for (Integer i = 0; i < saved.size(); i++) {
      if (saved[i].isSuccess()) {
        refused.remove(rows[i].Id);
      } else {
        failed.add(rows[i]);
        refused.put(rows[i].Id, firstError(saved[i]));
      }
    }
    if (failed.size() < 2) {
      return;
    }
    if (!roomForAnotherSave()) {
      for (Booking__c b : failed) {
        refused.put(
          b.Id,
          refused.get(b.Id) +
          ' (refused together with other bookings and not tried on its own this run)'
        );
      }
      return;
    }
    Integer half = failed.size() / 2;
    List<Booking__c> first = new List<Booking__c>();
    List<Booking__c> second = new List<Booking__c>();
    for (Integer i = 0; i < failed.size(); i++) {
      (i < half ? first : second).add(failed[i]);
    }
    saveSeparatingRefusals(first, refused);
    if (roomForAnotherSave()) {
      saveSeparatingRefusals(second, refused);
    } else {
      for (Booking__c b : second) {
        refused.put(
          b.Id,
          refused.get(b.Id) +
          ' (refused together with other bookings and not tried on its own this run)'
        );
      }
    }
  }

  private static List<Database.SaveResult> save(List<Booking__c> rows) {
    // Test support only: a lookup pointing at the wrong kind of record makes
    // the save refuse a booking, the way a rule or flow in the org would.
    Boolean sinkAll = false;
    if (refusalSinksTheBatchForTest && rows.size() > 1) {
      for (Booking__c b : rows) {
        sinkAll = sinkAll || refuseSaveForTest.contains(b.Id);
      }
    }
    Map<Id, Id> opportunities = new Map<Id, Id>();
    for (Booking__c b : rows) {
      if (sinkAll || refuseSaveForTest.contains(b.Id)) {
        opportunities.put(b.Id, b.Opportunity__c);
        b.Opportunity__c = b.Id;
      }
    }
    List<Database.SaveResult> saved = Database.update(rows, false);
    for (Booking__c b : rows) {
      if (opportunities.containsKey(b.Id)) {
        b.Opportunity__c = opportunities.get(b.Id);
      }
    }
    return saved;
  }

  private static Boolean roomForAnotherSave() {
    return Limits.getQueries() + SPARE_QUERIES <= Limits.getLimitQueries() &&
      Limits.getDmlStatements() + SPARE_DML_STATEMENTS <=
      Limits.getLimitDmlStatements() &&
      Limits.getCpuTime() + SPARE_CPU_MS <= Limits.getLimitCpuTime();
  }

  private static String firstError(Database.SaveResult result) {
    List<Database.Error> errors = result.getErrors();
    return errors.isEmpty()
      ? 'no reason given'
      : errors[0].getMessage().stripHtmlTags();
  }

  /** Booking id and contact id together, so one person's answer is one key. */
  private static String personKey(Id bookingId, Id contactId) {
    return String.valueOf(bookingId) + ':' + String.valueOf(contactId);
  }

  /**
   * Null when this person on this booking is ready; otherwise why they were
   * skipped. The trip's own guards (status, window, waiting period, something
   * to rate) apply to everyone on it; the guards on having been asked and
   * having answered apply to the one person being prepared.
   */
  private static String ineligibleReason(
    Booking__c b,
    Id person,
    Feedback_Invitation__c inv,
    Set<Id> answeredBookings,
    Set<String> answeredByPerson,
    Set<Id> rateable,
    Boolean allowResend
  ) {
    if (b == null) {
      return 'Booking not found';
    }
    if (String.isBlank(b.BookingNumber__c)) {
      return 'Booking has no booking number';
    }
    if (person == null) {
      return 'Booking has no main contact to invite';
    }
    // A guest who answered is finished, whichever way the answer was stored: on
    // their own invitation, or - for a response saved before answers carried a
    // contact - on the booking itself, which closes its main contact.
    if (
      answeredByPerson.contains(personKey(b.Id, person)) ||
      (inv != null &&
      inv.Answered_On__c != null) ||
      (person == b.MainContact__c && answeredBookings.contains(b.Id))
    ) {
      return 'Feedback already received';
    }
    // Asked already: their own invitation says so. A trip invited before this
    // ran carries no invitation rows, so its main contact is judged by the
    // booking, which is what marked them as asked at the time.
    Boolean alreadyAsked = inv != null
      ? inv.Sent_On__c != null
      : (person == b.MainContact__c && b.SurveySent__c == true);
    if (alreadyAsked && allowResend != true) {
      return 'Invitation already sent';
    }
    // A participant booking under a group trip counts as travelled when its
    // group booking does: the team marks the group, not every party under it.
    Boolean groupTraveled =
      b.TravelGroup__c != null &&
      b.TravelGroup__r != null &&
      ELIGIBLE_BOOKING_STATUS.contains(b.TravelGroup__r.Status__c);
    // Status decides who enters the programme, so it is judged once per trip.
    // A trip already invited has passed it: its status may since have moved to
    // Feedback because one guest answered, and that must not stop the guests
    // beside them being asked or reminded.
    if (
      b.SurveySent__c != true &&
      !ELIGIBLE_BOOKING_STATUS.contains(b.Status__c) &&
      !groupTraveled
    ) {
      return 'Trip is not marked Traveled yet (status ' + b.Status__c + ')';
    }
    // The window decides who enters the programme. A guest we have already
    // invited is inside it, so reminders and resends are not re-judged here.
    // A trip already invited is inside the programme, whether this person has
    // their own invitation row or the trip was invited before rows existed.
    Boolean insideProgramme =
      (inv != null && inv.Sent_On__c != null) || b.Survey_Sent_On__c != null;
    if (!insideProgramme) {
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

  /**
   * The booking number is in the link for people reading it, not for finding
   * anything: a group booking and every participant booking under it share one
   * number. The secret alone identifies the person and their trip.
   */
  private static String buildUrl(Booking__c b, String secret) {
    String base = GxFeedbackSettings.surveyBaseUrl();
    if (String.isBlank(base) || String.isBlank(secret)) {
      return null;
    }
    if (!base.endsWith('/') && !base.endsWith('=')) {
      base += '/';
    }
    return base +
      '?b=' +
      EncodingUtil.urlEncode(b.BookingNumber__c, 'UTF-8') +
      '&k=' +
      EncodingUtil.urlEncode(secret, 'UTF-8');
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
