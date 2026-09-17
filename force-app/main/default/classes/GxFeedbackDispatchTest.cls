/**
 * GxFeedbackDispatchTest
 *
 * Covers who gets invited and who does not, and the ordering that matters:
 * the booking must be readable by the guest before the link goes anywhere.
 */
@IsTest
private class GxFeedbackDispatchTest {
  private static final String BOOKING_NUM = 'TEST-GX-DISPATCH';

  /** The survey window wide open, so these tests are about everything else. */
  private static Gx_Feedback_Setting__mdt settings(
    Decimal delayHours,
    String baseUrl
  ) {
    return settings(delayHours, baseUrl, Date.today().addYears(-5), null);
  }

  private static Gx_Feedback_Setting__mdt settings(
    Decimal delayHours,
    String baseUrl,
    Date surveyStart,
    Decimal maxTripAgeDays
  ) {
    return new Gx_Feedback_Setting__mdt(
      Dispatch_Delay_Hours__c = delayHours,
      Link_Validity_Days__c = 14,
      Survey_Base_URL__c = baseUrl,
      Survey_Start_Date__c = surveyStart,
      Max_Trip_Age_Days__c = maxTripAgeDays
    );
  }

  @TestSetup
  static void setup() {
    // See GxFeedbackServiceTest for why the pricing trigger is bypassed.
    TriggerHandler.bypass('ReservationTriggerHandler');

    Account customer = new Account(Name = 'Dispatch Customer');
    Account hotel = new Account(
      Name = 'Dispatch Hotel',
      Account_Type__c = 'Hotel',
      BillingCity = 'Marbella',
      BillingCountry = 'Spain'
    );
    insert new List<Account>{ customer, hotel };

    Contact guest = new Contact(
      LastName = 'von Bern',
      FirstName = 'Maximilian',
      AccountId = customer.Id
    );
    insert guest;

    // Updating a Booking fires the org's "Booking - Update Reservations and
    // Opp Status" flow, which creates an Opportunity when none is linked -
    // and that create fails in a test context. Linking one up front sends
    // the flow down its existing-opportunity path instead.
    Opportunity opp = new Opportunity(
      Name = 'Dispatch Test Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = customer.Id
    );
    insert opp;

    Booking__c b = new Booking__c(
      Opportunity__c = opp.Id,
      Quote_for__c = customer.Id,
      MainContact__c = guest.Id,
      BookingNumber__c = BOOKING_NUM,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'EG',
      // Marked Traveled by the team: the state a trip is in when it is due.
      Status__c = 'Traveled',
      Start_Date__c = Date.today().addDays(-14),
      End_Date__c = Date.today().addDays(-7)
    );
    insert b;

    insert new Reservation__c(
      Booking__c = b.Id,
      Travel_Location__c = hotel.Id,
      AccountType__c = 'Hotel',
      Pricing__c = 'Leistung',
      Status__c = 'Completed',
      Date_Begin__c = Date.today().addDays(-14),
      Date_End__c = Date.today().addDays(-7)
    );

    TriggerHandler.clearBypass('ReservationTriggerHandler');
  }

  private static Booking__c theBooking() {
    return [
      SELECT
        Id,
        Status__c,
        SurveySent__c,
        Form_Secret__c,
        Start_Date__c,
        End_Date__c,
        Survey_Sent_On__c,
        Survey_Reminder_Sent__c,
        Survey_Trip_Start__c,
        Survey_Trip_End__c,
        Survey_Snapshot__c
      FROM Booking__c
      WHERE BookingNumber__c = :BOOKING_NUM
    ];
  }

  private static List<GxFeedbackDispatch.Result> run(Id bookingId) {
    GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
    req.bookingId = bookingId;
    return GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ req }
    );
  }

  // ------------------------------------------------------------------

  @IsTest
  static void prepareMintsATokenAndReturnsALink() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );

    Test.startTest();
    List<GxFeedbackDispatch.Result> out = run(theBooking().Id);
    Test.stopTest();

    Assert.areEqual(1, out.size(), 'One booking in, one result out');
    GxFeedbackDispatch.Result r = out[0];
    Assert.isTrue(
      r.ok,
      'A completed trip past its waiting period is ready: ' + r.skippedReason
    );
    Assert.areEqual(
      BOOKING_NUM,
      r.bookingNumber,
      'The booking number comes back'
    );
    Assert.isNotNull(r.recipientContactId, 'The email needs a recipient');

    Booking__c after = theBooking();
    Assert.isNotNull(after.Form_Secret__c, 'A token was minted');
    Assert.isTrue(
      after.Form_Secret__c.length() >= 20,
      'The token carries real entropy'
    );
    Assert.isTrue(
      r.surveyUrl.contains('b=' + BOOKING_NUM) &&
      r.surveyUrl.contains('k=' + after.Form_Secret__c),
      'The link carries both halves of the credential: ' + r.surveyUrl
    );
  }

  @IsTest
  static void bookingIsOpenedToTheGuestBeforeTheLinkIsHandedOut() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );

    run(theBooking().Id);

    Booking__c after = theBooking();
    // The guest sharing rule keys on this flag. If it were set after the
    // email went out, the guest would follow a good link to a booking they
    // cannot read.
    Assert.isTrue(
      after.SurveySent__c,
      'The booking is shared to the guest as part of preparing the link'
    );
    Assert.areEqual(
      'Completed',
      after.Status__c,
      'Sending moves a traveled trip on to Completed, not yet to Feedback'
    );
  }

  @IsTest
  static void aTripSomeoneAlreadyMarkedCompletedIsInvitedAndStaysCompleted() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    update new Booking__c(Id = theBooking().Id, Status__c = 'Completed');

    GxFeedbackDispatch.Result r = run(theBooking().Id)[0];

    Assert.isTrue(
      r.ok,
      'A trip moved on by hand is still invited: ' + r.skippedReason
    );
    Assert.areEqual(
      'Completed',
      theBooking().Status__c,
      'It stays at Completed until the guest answers'
    );
  }

  @IsTest
  static void aPaidTripIsNotInvitedUntilSomeoneMarksItTraveled() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    update new Booking__c(Id = theBooking().Id, Status__c = 'Paid');

    GxFeedbackDispatch.Result r = run(theBooking().Id)[0];

    Assert.isFalse(r.ok, 'Paid alone does not say the trip happened');
    Assert.isTrue(
      r.skippedReason.contains('Traveled'),
      'The reason names what is missing: ' + r.skippedReason
    );
    Booking__c after = theBooking();
    Assert.isFalse(after.SurveySent__c, 'Nothing is marked as sent');
    Assert.areEqual('Paid', after.Status__c, 'The status is left alone');
  }

  @IsTest
  static void theTripIsRememberedAsItWasWhenTheGuestWasFirstAsked() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    Booking__c before = theBooking();
    run(before.Id);

    Booking__c sent = theBooking();
    Assert.areEqual(
      before.Start_Date__c,
      sent.Survey_Trip_Start__c,
      'The trip start is saved with the invitation'
    );
    Assert.areEqual(
      before.End_Date__c,
      sent.Survey_Trip_End__c,
      'The trip end is saved with the invitation'
    );

    // The booking changes afterwards and the invitation goes out again: the
    // saved trip stays the one the guest was first asked about.
    update new Booking__c(
      Id = sent.Id,
      Start_Date__c = Date.today().addDays(-30),
      End_Date__c = Date.today().addDays(-25)
    );
    GxFeedbackDispatch.Request resend = new GxFeedbackDispatch.Request();
    resend.bookingId = sent.Id;
    resend.allowResend = true;
    GxFeedbackDispatch.Result r = GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ resend }
    )[0];

    Assert.isTrue(r.ok, 'The resend goes out: ' + r.skippedReason);
    Booking__c after = theBooking();
    Assert.areEqual(
      before.End_Date__c,
      after.Survey_Trip_End__c,
      'A resend does not move the saved trip end'
    );
    Assert.areEqual(
      before.Start_Date__c,
      after.Survey_Trip_Start__c,
      'Nor its start'
    );
  }

  @IsTest
  static void whatTheGuestRatesIsSavedWithTheFirstInvitation() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    run(theBooking().Id);

    Booking__c sent = theBooking();
    Assert.isNotNull(
      sent.Survey_Snapshot__c,
      'The survey list is saved with the invitation'
    );
    List<Reservation__c> saved = (List<Reservation__c>) JSON.deserialize(
      sent.Survey_Snapshot__c,
      List<Reservation__c>.class
    );
    Assert.areEqual(1, saved.size(), 'The one hotel line on the trip');
    Assert.areEqual(
      'Dispatch Hotel',
      saved[0].Travel_Location__r.Name,
      'Saved with the name the guest will see'
    );
  }

  @IsTest
  static void aResendKeepsTheListFromTheFirstInvitation() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    run(theBooking().Id);
    String first = theBooking().Survey_Snapshot__c;

    // A hotel is added to the trip after the invitation went out.
    TriggerHandler.bypass('ReservationTriggerHandler');
    Account later = new Account(
      Name = 'Later Hotel',
      Account_Type__c = 'Hotel',
      BillingCity = 'Faro',
      BillingCountry = 'Portugal'
    );
    insert later;
    insert new Reservation__c(
      Booking__c = theBooking().Id,
      Travel_Location__c = later.Id,
      AccountType__c = 'Hotel',
      Pricing__c = 'Leistung',
      Status__c = 'Completed',
      Date_Begin__c = Date.today().addDays(-10),
      Date_End__c = Date.today().addDays(-8)
    );
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    GxFeedbackDispatch.Request reminder = new GxFeedbackDispatch.Request();
    reminder.bookingId = theBooking().Id;
    reminder.allowResend = true;
    reminder.markReminder = true;
    GxFeedbackDispatch.Result r = GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ reminder }
    )[0];

    Assert.isTrue(r.ok, 'The reminder goes out: ' + r.skippedReason);
    Assert.areEqual(
      first,
      theBooking().Survey_Snapshot__c,
      'The saved list is not rebuilt, so the later hotel is not in it'
    );
  }

  @IsTest
  static void preparingRecordsWhenTheGuestWasAsked() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );

    run(theBooking().Id);

    Booking__c after = theBooking();
    Assert.isNotNull(
      after.Survey_Sent_On__c,
      'The reminder pass and the link expiry both count from this'
    );
    Assert.isFalse(
      after.Survey_Reminder_Sent__c,
      'A first invitation is not a reminder'
    );
  }

  @IsTest
  static void markingAReminderIsWhatStopsASecondOne() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );

    GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
    req.bookingId = theBooking().Id;
    req.allowResend = true;
    req.markReminder = true;
    List<GxFeedbackDispatch.Result> out = GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ req }
    );

    Assert.isTrue(
      out[0].ok,
      'The reminder is prepared: ' + out[0].skippedReason
    );
    Assert.isTrue(
      theBooking().Survey_Reminder_Sent__c,
      'Recorded in the same committed update as the token, before any email'
    );
  }

  @IsTest
  static void anExistingTokenIsReusedRatherThanRotated() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    b.Form_Secret__c = 'already-minted-secret-value';
    update b;

    run(b.Id);

    Assert.areEqual(
      'already-minted-secret-value',
      theBooking().Form_Secret__c,
      'Re-preparing must not invalidate a link already in a guest inbox'
    );
  }

  @IsTest
  static void tokensAreUnique() {
    Set<String> seen = new Set<String>();
    for (Integer i = 0; i < 25; i++) {
      seen.add(GxFeedbackDispatch.newSecret());
    }
    Assert.areEqual(25, seen.size(), 'Every minted token is different');
  }

  // ------------------------------------------------------------------
  // Who gets skipped

  @IsTest
  static void tripStillInsideItsWaitingPeriodIsNotInvited() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    b.End_Date__c = Date.today(); // ended today, 36 hours have not passed
    update b;

    List<GxFeedbackDispatch.Result> out = run(b.Id);

    Assert.isFalse(out[0].ok, 'A guest who just got home is left alone');
    Assert.isTrue(
      out[0].skippedReason.contains('Waiting period'),
      'The reason says so: ' + out[0].skippedReason
    );
    Assert.isNull(theBooking().Form_Secret__c, 'No token is minted for a skip');
  }

  // ------------------------------------------------------------------
  // The survey window: the guard against inviting the whole booking history

  @IsTest
  static void aTripThatEndedBeforeTheSurveyStartedIsNotInvited() {
    // The fixture trip ended a week ago; the programme started three days ago.
    GxFeedbackSettings.useForTest(
      settings(
        0,
        'https://example.test/feedback/',
        Date.today().addDays(-3),
        null
      )
    );

    List<GxFeedbackDispatch.Result> out = run(theBooking().Id);

    Assert.isFalse(out[0].ok, 'A trip from before launch is never invited');
    Assert.isTrue(
      out[0].skippedReason.contains('before the survey started'),
      out[0].skippedReason
    );
    Assert.isNull(theBooking().Form_Secret__c, 'Nothing is minted for it');
  }

  @IsTest
  static void aTripEndingOnTheStartDateIsInvited() {
    GxFeedbackSettings.useForTest(
      settings(
        0,
        'https://example.test/feedback/',
        theBooking().End_Date__c,
        null
      )
    );
    Assert.isTrue(
      run(theBooking().Id)[0].ok,
      'The start date itself is inside the window'
    );
  }

  @IsTest
  static void withNoStartDateNobodyIsInvited() {
    // A missing setting must fail safe: blank is not "no limit".
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/', null, null)
    );

    List<GxFeedbackDispatch.Result> out = run(theBooking().Id);

    Assert.isFalse(out[0].ok, 'Nobody is invited until a start date is set');
    Assert.isTrue(
      out[0].skippedReason.contains('No survey start date'),
      out[0].skippedReason
    );
  }

  @IsTest
  static void aTripOlderThanTheAgeCapIsNotInvitedWhateverTheStartDate() {
    // Start date wide open - as if someone left it too early - but the trip
    // ended a week ago and the cap is five days.
    GxFeedbackSettings.useForTest(
      settings(
        0,
        'https://example.test/feedback/',
        Date.today().addYears(-5),
        5
      )
    );

    List<GxFeedbackDispatch.Result> out = run(theBooking().Id);

    Assert.isFalse(out[0].ok, 'The backstop holds even with a bad start date');
    Assert.isTrue(
      out[0].skippedReason.contains('more than 5 days ago'),
      out[0].skippedReason
    );
  }

  @IsTest
  static void theWindowDoesNotStopAReminder() {
    // Invited while inside the window; by reminder time the start date has
    // moved past the trip. The guest is already in the programme.
    Booking__c b = theBooking();
    b.Survey_Sent_On__c = Datetime.now().addDays(-11);
    b.SurveySent__c = true;
    update b;
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/', Date.today(), 1)
    );

    GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
    req.bookingId = b.Id;
    req.allowResend = true;
    req.markReminder = true;
    List<GxFeedbackDispatch.Result> out = GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ req }
    );

    Assert.isTrue(
      out[0].ok,
      'Reminders are not re-judged: ' + out[0].skippedReason
    );
  }

  @IsTest
  static void aZeroDelaySendsImmediately() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    b.End_Date__c = Date.today();
    update b;

    Assert.isTrue(run(b.Id)[0].ok, 'A zero delay disables the waiting period');
  }

  @IsTest
  static void aBookingWithNoContactCannotBeInvited() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    b.MainContact__c = null;
    update b;

    List<GxFeedbackDispatch.Result> out = run(b.Id);

    Assert.isFalse(out[0].ok, 'There is nobody to email');
    Assert.isTrue(
      out[0].skippedReason.contains('main contact'),
      out[0].skippedReason
    );
  }

  @IsTest
  static void anAlreadyInvitedBookingIsNotInvitedTwice() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    run(b.Id);

    List<GxFeedbackDispatch.Result> second = run(b.Id);

    Assert.isFalse(second[0].ok, 'A second run does not re-invite');
    Assert.isTrue(
      second[0].skippedReason.contains('already sent'),
      second[0].skippedReason
    );
  }

  @IsTest
  static void aBookingThatAlreadyHasFeedbackIsSkipped() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    insert new Feedback_Response__c(
      Booking__c = b.Id,
      Overall_Experience__c = 9,
      Recommendation_NPS__c = 9
    );

    List<GxFeedbackDispatch.Result> out = run(b.Id);

    Assert.isFalse(
      out[0].ok,
      'A guest who already answered is not asked again'
    );
    Assert.isTrue(
      out[0].skippedReason.contains('already received'),
      out[0].skippedReason
    );
  }

  @IsTest
  static void anItineraryWithNothingToRateIsSkipped() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );
    Booking__c b = theBooking();
    delete [SELECT Id FROM Reservation__c WHERE Booking__c = :b.Id];

    List<GxFeedbackDispatch.Result> out = run(b.Id);

    Assert.isFalse(
      out[0].ok,
      'An invitation to an empty survey is worse than none'
    );
    Assert.isTrue(out[0].skippedReason.contains('rated'), out[0].skippedReason);
  }

  @IsTest
  static void anUnknownBookingIsReportedNotThrown() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );

    List<GxFeedbackDispatch.Result> out = run(
      [SELECT Id FROM Booking__c WHERE BookingNumber__c = :BOOKING_NUM].Id
    );
    Assert.areEqual(1, out.size(), 'sanity');

    GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
    req.bookingId = null;
    List<GxFeedbackDispatch.Result> empty = GxFeedbackDispatch.prepare(
      new List<GxFeedbackDispatch.Request>{ req }
    );
    Assert.isFalse(empty[0].ok, 'A missing id is reported, not thrown');
  }

  /**
   * The nightly job hands dispatch a whole batch at once. This is the test that
   * was missing when the rateability check ran per booking: at two queries each
   * it exhausted the SOQL limit somewhere around the fiftieth guest, and every
   * existing test passed because none of them prepared more than two bookings.
   */
  @IsTest
  static void awholeBatchCostsTheSameFewQueriesAsOneBooking() {
    GxFeedbackSettings.useForTest(
      settings(0, 'https://example.test/feedback/')
    );

    TriggerHandler.bypass('ReservationTriggerHandler');
    Account customer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dispatch Customer'
      LIMIT 1
    ];
    Account hotel = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dispatch Hotel'
      LIMIT 1
    ];
    Contact guest = [SELECT Id FROM Contact LIMIT 1];
    Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

    List<Booking__c> batch = new List<Booking__c>();
    for (Integer i = 0; i < 60; i++) {
      batch.add(
        new Booking__c(
          Opportunity__c = opp.Id,
          Quote_for__c = customer.Id,
          MainContact__c = guest.Id,
          BookingNumber__c = 'TEST-GX-BULK-' + i,
          Travel_Type__c = 'FIT',
          DestinationCountry__c = 'EG',
          Status__c = 'Completed',
          Start_Date__c = Date.today().addDays(-14),
          End_Date__c = Date.today().addDays(-7)
        )
      );
    }
    insert batch;

    List<Reservation__c> lines = new List<Reservation__c>();
    for (Booking__c b : batch) {
      lines.add(
        new Reservation__c(
          Booking__c = b.Id,
          Travel_Location__c = hotel.Id,
          AccountType__c = 'Hotel',
          Pricing__c = 'Leistung',
          Status__c = 'Completed',
          Date_Begin__c = Date.today().addDays(-14),
          Date_End__c = Date.today().addDays(-7)
        )
      );
    }
    insert lines;
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    List<GxFeedbackDispatch.Request> requests = new List<GxFeedbackDispatch.Request>();
    for (Booking__c b : batch) {
      GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
      req.bookingId = b.Id;
      requests.add(req);
    }

    Test.startTest();
    Integer before = Limits.getQueries();
    List<GxFeedbackDispatch.Result> out = GxFeedbackDispatch.prepare(requests);
    Integer used = Limits.getQueries() - before;
    Test.stopTest();

    Assert.areEqual(60, out.size(), 'Every booking comes back');
    for (GxFeedbackDispatch.Result r : out) {
      Assert.isTrue(r.ok, 'All 60 are ready: ' + r.skippedReason);
    }
    Assert.isTrue(
      used <= 10,
      'Preparing 60 bookings must not scale with the batch. Queries used: ' +
      used
    );
  }

  @IsTest
  static void noRequestsIsNotAnError() {
    Assert.areEqual(
      0,
      GxFeedbackDispatch.prepare(new List<GxFeedbackDispatch.Request>()).size(),
      'An empty run does nothing quietly'
    );
    Assert.areEqual(
      0,
      GxFeedbackDispatch.prepare(null).size(),
      'Null is tolerated'
    );
  }

  @IsTest
  static void withoutABaseUrlThereIsNoLinkToSend() {
    GxFeedbackSettings.useForTest(settings(0, null));

    List<GxFeedbackDispatch.Result> out = run(theBooking().Id);

    Assert.isNull(
      out[0].surveyUrl,
      'An unconfigured environment yields no link rather than a broken one'
    );
  }

  // ------------------------------------------------------------------
  // One refused booking among several

  /** A second trip, due exactly like the first. */
  private static Booking__c anotherDueBooking(String bookingNumber) {
    Booking__c first = [
      SELECT Opportunity__c, Quote_for__c, MainContact__c
      FROM Booking__c
      WHERE BookingNumber__c = :BOOKING_NUM
    ];
    Booking__c b = new Booking__c(
      Opportunity__c = first.Opportunity__c,
      Quote_for__c = first.Quote_for__c,
      MainContact__c = first.MainContact__c,
      BookingNumber__c = bookingNumber,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'EG',
      Status__c = 'Traveled',
      Start_Date__c = Date.today().addDays(-14),
      End_Date__c = Date.today().addDays(-7)
    );
    insert b;
    TriggerHandler.bypass('ReservationTriggerHandler');
    insert new Reservation__c(
      Booking__c = b.Id,
      Travel_Location__c = [
        SELECT Id
        FROM Account
        WHERE Name = 'Dispatch Hotel'
      ]
      .Id,
      AccountType__c = 'Hotel',
      Pricing__c = 'Leistung',
      Status__c = 'Completed',
      Date_Begin__c = Date.today().addDays(-14),
      Date_End__c = Date.today().addDays(-7)
    );
    TriggerHandler.clearBypass('ReservationTriggerHandler');
    return b;
  }

  private static List<GxFeedbackDispatch.Result> runBoth(Id first, Id second) {
    List<GxFeedbackDispatch.Request> requests = new List<GxFeedbackDispatch.Request>();
    for (Id bookingId : new List<Id>{ first, second }) {
      GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
      req.bookingId = bookingId;
      requests.add(req);
    }
    return GxFeedbackDispatch.prepare(requests);
  }

  @IsTest
  static void aBookingTheOrgRefusesDoesNotHoldBackTheOthers() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    Booking__c other = anotherDueBooking('TEST-GX-DISPATCH-2');
    Id refused = theBooking().Id;
    GxFeedbackDispatch.refuseSaveForTest.add(refused);

    Test.startTest();
    List<GxFeedbackDispatch.Result> out = runBoth(refused, other.Id);
    Test.stopTest();

    Assert.isFalse(out[0].ok, 'The refused booking is not ready to send');
    Assert.isTrue(out[0].saveFailed, 'And says it could not be saved');
    Assert.isTrue(
      out[0].skippedReason.startsWith('The booking could not be saved'),
      'With the reason: ' + out[0].skippedReason
    );
    Assert.isNull(out[0].surveyUrl, 'No link for a booking that was not saved');
    Assert.isTrue(
      out[1].ok,
      'The other booking still goes: ' + out[1].skippedReason
    );
    Assert.isFalse(out[1].saveFailed, 'And was saved');

    Booking__c untouched = theBooking();
    Assert.isFalse(
      untouched.SurveySent__c,
      'The refused booking is not marked as invited'
    );
    Assert.isNull(untouched.Form_Secret__c, 'Has no link');
    Assert.isTrue(
      String.isBlank(untouched.Survey_Snapshot__c),
      'Has no saved list'
    );
    Assert.isNull(untouched.Survey_Trip_End__c, 'Has no saved trip dates');
    Assert.areEqual('Traveled', untouched.Status__c, 'And keeps its status');

    Booking__c invited = [
      SELECT SurveySent__c, Status__c, Survey_Snapshot__c
      FROM Booking__c
      WHERE Id = :other.Id
    ];
    Assert.isTrue(invited.SurveySent__c, 'The other booking is invited');
    Assert.areEqual(
      'Completed',
      invited.Status__c,
      'And moved on to Completed'
    );
    Assert.isTrue(
      String.isNotBlank(invited.Survey_Snapshot__c),
      'With its list saved'
    );
  }

  @IsTest
  static void aFlowFaultThatSinksTheWholeBatchStillOnlyRefusesTheBookingThatCausedIt() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    Booking__c second = anotherDueBooking('TEST-GX-DISPATCH-2');
    Booking__c third = anotherDueBooking('TEST-GX-DISPATCH-3');
    Id bad = theBooking().Id;
    GxFeedbackDispatch.refuseSaveForTest.add(bad);
    GxFeedbackDispatch.refusalSinksTheBatchForTest = true;

    List<GxFeedbackDispatch.Request> requests = new List<GxFeedbackDispatch.Request>();
    for (Id bookingId : new List<Id>{ second.Id, bad, third.Id }) {
      GxFeedbackDispatch.Request req = new GxFeedbackDispatch.Request();
      req.bookingId = bookingId;
      requests.add(req);
    }

    Test.startTest();
    List<GxFeedbackDispatch.Result> out = GxFeedbackDispatch.prepare(requests);
    Test.stopTest();

    Assert.isTrue(
      out[0].ok,
      'Saved on its own after the batch failed: ' + out[0].skippedReason
    );
    Assert.isFalse(out[1].ok, 'The booking that caused it stays refused');
    Assert.isTrue(out[1].saveFailed, 'And is reported as not saved');
    Assert.isTrue(
      out[2].ok,
      'Saved on its own after the batch failed: ' + out[2].skippedReason
    );

    Map<Id, Booking__c> after = new Map<Id, Booking__c>(
      [
        SELECT Id, SurveySent__c, Opportunity__c
        FROM Booking__c
        WHERE Id IN :new List<Id>{ second.Id, bad, third.Id }
      ]
    );
    Assert.isTrue(
      after.get(second.Id).SurveySent__c,
      'The second booking is invited'
    );
    Assert.isTrue(
      after.get(third.Id).SurveySent__c,
      'The third booking is invited'
    );
    Assert.isFalse(after.get(bad).SurveySent__c, 'The bad booking is not');
    Assert.isNotNull(
      after.get(second.Id).Opportunity__c,
      'Retrying keeps everything else on the booking as it was'
    );
  }

  @IsTest
  static void aRefusedBookingIsReadyAgainOnceItCanBeSaved() {
    GxFeedbackSettings.useForTest(
      settings(36, 'https://example.test/feedback/')
    );
    Id bookingId = theBooking().Id;
    GxFeedbackDispatch.refuseSaveForTest.add(bookingId);
    Assert.isFalse(run(bookingId)[0].ok, 'Refused the first time');

    GxFeedbackDispatch.refuseSaveForTest.clear();
    List<GxFeedbackDispatch.Result> again = run(bookingId);

    Assert.isTrue(
      again[0].ok,
      'Ready once it saves: ' + again[0].skippedReason
    );
    Assert.isTrue(theBooking().SurveySent__c, 'And marked as invited');
  }
}
