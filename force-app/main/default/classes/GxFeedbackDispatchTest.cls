/**
 * GxFeedbackDispatchTest
 *
 * Covers who gets invited and who does not, and the ordering that matters:
 * the booking must be readable by the guest before the link goes anywhere.
 */
@IsTest
private class GxFeedbackDispatchTest {
  private static final String BOOKING_NUM = 'TEST-GX-DISPATCH';

  private static Gx_Feedback_Setting__mdt settings(
    Decimal delayHours,
    String baseUrl
  ) {
    return new Gx_Feedback_Setting__mdt(
      Dispatch_Delay_Hours__c = delayHours,
      Link_Validity_Days__c = 14,
      Survey_Base_URL__c = baseUrl
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
      Status__c = 'Completed',
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
      SELECT Id, Status__c, SurveySent__c, Form_Secret__c, End_Date__c
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
    // The guest sharing rule keys on this status. If it were set after the
    // email went out, the guest would follow a good link to a booking they
    // cannot read.
    Assert.areEqual(
      'Feedback',
      after.Status__c,
      'The booking is shared to the guest as part of preparing the link'
    );
    Assert.isTrue(after.SurveySent__c, 'The booking is marked as invited');
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
}
