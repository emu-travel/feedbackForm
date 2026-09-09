/**
 * GxFeedbackSenderTest
 *
 * Covers sending and the nightly selection. Messaging.sendEmail does not
 * actually deliver in a test context, so these assert on what the sender
 * reports and on the state it leaves behind, not on inboxes.
 */
@IsTest
private class GxFeedbackSenderTest {
  private static final String READY = 'TEST-GX-SEND-READY';
  private static final String TOO_SOON = 'TEST-GX-SEND-SOON';

  private static void pinSettings(Decimal delayHours) {
    GxFeedbackSettings.useForTest(
      new Gx_Feedback_Setting__mdt(
        Dispatch_Delay_Hours__c = delayHours,
        Link_Validity_Days__c = 14,
        Survey_Base_URL__c = 'https://example.test/feedback/',
        Sender_Email__c = null
      )
    );
  }

  private static Booking__c newBooking(
    Account customer,
    Opportunity opp,
    Contact guest,
    String bookingNumber,
    Date ended
  ) {
    return new Booking__c(
      Opportunity__c = opp.Id,
      Quote_for__c = customer.Id,
      MainContact__c = guest.Id,
      BookingNumber__c = bookingNumber,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'EG',
      Status__c = 'Completed',
      Start_Date__c = ended.addDays(-7),
      End_Date__c = ended
    );
  }

  @TestSetup
  static void setup() {
    TriggerHandler.bypass('ReservationTriggerHandler');

    Account customer = new Account(Name = 'Sender Customer');
    Account hotel = new Account(
      Name = 'Sender Hotel',
      Account_Type__c = 'Hotel',
      BillingCity = 'Faro',
      BillingCountry = 'Portugal'
    );
    insert new List<Account>{ customer, hotel };

    Contact guest = new Contact(
      LastName = 'Schmidt',
      FirstName = 'Anna',
      Email = 'anna.schmidt@example.test',
      AccountId = customer.Id
    );
    insert guest;

    // See GxFeedbackDispatchTest: updating a Booking fires an org flow that
    // creates an Opportunity when none is linked, and that fails in tests.
    Opportunity opp = new Opportunity(
      Name = 'Sender Test Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = customer.Id
    );
    insert opp;

    List<Booking__c> bookings = new List<Booking__c>{
      newBooking(customer, opp, guest, READY, Date.today().addDays(-5)),
      newBooking(customer, opp, guest, TOO_SOON, Date.today())
    };
    insert bookings;

    List<Reservation__c> lines = new List<Reservation__c>();
    for (Booking__c b : bookings) {
      lines.add(
        new Reservation__c(
          Booking__c = b.Id,
          Travel_Location__c = hotel.Id,
          AccountType__c = 'Hotel',
          Pricing__c = 'Leistung',
          Status__c = 'Completed',
          Date_Begin__c = Date.today().addDays(-12),
          Date_End__c = Date.today().addDays(-5)
        )
      );
    }
    insert lines;

    TriggerHandler.clearBypass('ReservationTriggerHandler');
  }

  private static Booking__c booking(String bookingNumber) {
    return [
      SELECT Id, Status__c, SurveySent__c, Form_Secret__c
      FROM Booking__c
      WHERE BookingNumber__c = :bookingNumber
    ];
  }

  private static List<GxFeedbackSender.Result> send(
    Id bookingId,
    Boolean allowResend
  ) {
    GxFeedbackSender.Request r = new GxFeedbackSender.Request();
    r.bookingId = bookingId;
    r.allowResend = allowResend;
    return GxFeedbackSender.send(new List<GxFeedbackSender.Request>{ r });
  }

  // ------------------------------------------------------------------

  @IsTest
  static void sendingPreparesTheBookingAndReportsSuccess() {
    pinSettings(36);

    Test.startTest();
    List<GxFeedbackSender.Result> out = send(booking(READY).Id, false);
    Test.stopTest();

    Assert.areEqual(1, out.size(), 'One booking in, one result out');
    Assert.isTrue(out[0].sent, 'The invitation went out: ' + out[0].message);
    Assert.isTrue(
      out[0].surveyUrl.contains(READY),
      'The link it sent is the guest own: ' + out[0].surveyUrl
    );

    Booking__c after = booking(READY);
    Assert.areEqual(
      'Feedback',
      after.Status__c,
      'The booking was opened to the guest before the mail left'
    );
    Assert.isTrue(after.SurveySent__c, 'The booking is marked as invited');
    Assert.isNotNull(after.Form_Secret__c, 'A token was minted');
  }

  @IsTest
  static void aTripInsideItsWaitingPeriodIsNotEmailed() {
    pinSettings(36);

    List<GxFeedbackSender.Result> out = send(booking(TOO_SOON).Id, false);

    Assert.isFalse(out[0].sent, 'A guest who just got home is left alone');
    Assert.isTrue(
      out[0].message.contains('Waiting period'),
      'And is told why: ' + out[0].message
    );
    Assert.isNull(
      booking(TOO_SOON).Form_Secret__c,
      'Nothing is minted for a booking that is not ready'
    );
  }

  @IsTest
  static void aSecondSendIsRefusedUnlessItIsADeliberateResend() {
    pinSettings(0);
    Id id = booking(READY).Id;
    send(id, false);

    List<GxFeedbackSender.Result> repeat = send(id, false);
    Assert.isFalse(repeat[0].sent, 'The nightly job never invites twice');
    Assert.isTrue(
      repeat[0].message.contains('already sent'),
      repeat[0].message
    );

    List<GxFeedbackSender.Result> resend = send(id, true);
    Assert.isTrue(
      resend[0].sent,
      'A person choosing to resend can: ' + resend[0].message
    );
  }

  @IsTest
  static void aResendStillWillNotChaseSomeoneWhoAlreadyAnswered() {
    pinSettings(0);
    Booking__c b = booking(READY);
    insert new Feedback_Response__c(
      Booking__c = b.Id,
      Overall_Experience__c = 10,
      Recommendation_NPS__c = 10
    );

    List<GxFeedbackSender.Result> out = send(b.Id, true);

    Assert.isFalse(out[0].sent, 'Answered guests are never chased');
    Assert.isTrue(out[0].message.contains('already received'), out[0].message);
  }

  @IsTest
  static void withoutABaseUrlNothingIsSent() {
    GxFeedbackSettings.useForTest(
      new Gx_Feedback_Setting__mdt(
        Dispatch_Delay_Hours__c = 0,
        Link_Validity_Days__c = 14,
        Survey_Base_URL__c = null
      )
    );

    List<GxFeedbackSender.Result> out = send(booking(READY).Id, false);

    Assert.isFalse(out[0].sent, 'An unconfigured environment sends nothing');
    Assert.isTrue(out[0].message.contains('base URL'), out[0].message);
  }

  @IsTest
  static void noRequestsIsNotAnError() {
    Assert.areEqual(
      0,
      GxFeedbackSender.send(new List<GxFeedbackSender.Request>()).size(),
      'An empty run does nothing quietly'
    );
    Assert.areEqual(0, GxFeedbackSender.send(null).size(), 'Null is tolerated');
  }

  // ------------------------------------------------------------------
  // The nightly job

  @IsTest
  static void theNightlyJobPicksUpFinishedTripsAndSkipsTheRest() {
    pinSettings(36);

    Test.startTest();
    List<GxFeedbackSender.Result> out = GxFeedbackScheduler.run();
    Test.stopTest();

    // Only the trip that ended five days ago qualifies; the one that ended
    // today is filtered out by End_Date__c < TODAY.
    Assert.areEqual(1, out.size(), 'Only finished trips are considered');
    Assert.isTrue(out[0].sent, 'And it was invited: ' + out[0].message);

    Assert.isTrue(
      booking(READY).SurveySent__c,
      'The finished trip was invited'
    );
    Assert.isFalse(
      booking(TOO_SOON).SurveySent__c,
      'The trip that ended today was not'
    );
  }

  @IsTest
  static void theNightlyJobNeverInvitesTheSameBookingTwice() {
    pinSettings(36);
    GxFeedbackScheduler.run();

    List<GxFeedbackSender.Result> second = GxFeedbackScheduler.run();

    Assert.areEqual(
      0,
      second.size(),
      'Once invited, a booking drops out of the nightly query entirely'
    );
  }

  @IsTest
  static void theJobCanBeScheduled() {
    pinSettings(36);

    Test.startTest();
    String jobId = System.schedule(
      'Golf Extra Feedback Test',
      '0 0 7 * * ?',
      new GxFeedbackScheduler()
    );
    Test.stopTest();

    Assert.isNotNull(jobId, 'The job schedules without error');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId],
      'And is registered'
    );
  }
}
