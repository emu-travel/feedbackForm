/**
 * GxFeedbackTravellerInvitesTest
 *
 * One trip, several guests. Covers what changes when a booking carries
 * travellers rather than a single main contact: a link each, an answer that
 * closes only the person who gave it, a reminder each, and the participant
 * bookings of a group trip being asked through their group.
 */
@IsTest
private class GxFeedbackTravellerInvitesTest {
  // The org writes both Name and BookingNumber__c itself, and a group booking
  // shares its number with every party under it. So these tests find each
  // booking by its main contact, which nothing else touches, and read whatever
  // number the org gave it.
  private static final String SOLO_TRIP = 'anna@example.invalid';
  private static final String GROUP_TRIP = 'paula@example.invalid';
  private static final String PARTY_TRIP = 'dora@example.invalid';

  private static Gx_Feedback_Setting__mdt settings(Decimal reminderDays) {
    return new Gx_Feedback_Setting__mdt(
      Dispatch_Delay_Hours__c = 0,
      Link_Validity_Days__c = 14,
      Reminder_Delay_Days__c = reminderDays,
      Survey_Base_URL__c = 'https://example.test/feedback/',
      Survey_Start_Date__c = Date.today().addYears(-5),
      Max_Trip_Age_Days__c = 3650
    );
  }

  @TestSetup
  static void setup() {
    // See GxFeedbackServiceTest: the org's pricing trigger needs price data
    // these synthetic lines do not carry.
    TriggerHandler.bypass('ReservationTriggerHandler');

    Account customer = new Account(Name = 'Traveller Customer');
    Account hotel = new Account(
      Name = 'Traveller Hotel',
      Account_Type__c = 'Hotel',
      BillingCity = 'Faro',
      BillingCountry = 'Portugal'
    );
    insert new List<Account>{ customer, hotel };

    // Anna is the booking's main contact and travels herself; Bruno travels
    // and has an address; Chris travels with no address at all.
    Contact anna = new Contact(
      FirstName = 'Anna',
      LastName = 'Achter',
      Email = 'anna@example.invalid',
      AccountId = customer.Id
    );
    Contact bruno = new Contact(
      FirstName = 'Bruno',
      LastName = 'Berger',
      Email = 'bruno@example.invalid',
      AccountId = customer.Id
    );
    Contact chris = new Contact(
      FirstName = 'Chris',
      LastName = 'Cramer',
      AccountId = customer.Id
    );
    Contact pro = new Contact(
      FirstName = 'Paula',
      LastName = 'Pro',
      Email = 'paula@example.invalid',
      AccountId = customer.Id
    );
    Contact dora = new Contact(
      FirstName = 'Dora',
      LastName = 'Danz',
      Email = 'dora@example.invalid',
      AccountId = customer.Id
    );
    insert new List<Contact>{ anna, bruno, chris, pro, dora };

    // The org's booking flow creates an Opportunity when none is linked, and
    // that create fails in a test context, so every booking gets one up front.
    Opportunity opp = new Opportunity(
      Name = 'Traveller Test Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = customer.Id
    );
    insert opp;

    Booking__c solo = newBooking(
      'Traveller test - solo',
      customer.Id,
      anna.Id,
      opp.Id
    );
    // The group booking: travelled, and the party under it still at Accepted,
    // which is how the team keeps a group trip.
    Booking__c groupTrip = newBooking(
      'Traveller test - group',
      customer.Id,
      pro.Id,
      opp.Id
    );
    insert new List<Booking__c>{ solo, groupTrip };

    Booking__c participant = newBooking(
      'Traveller test - party',
      customer.Id,
      dora.Id,
      opp.Id
    );
    participant.Status__c = 'Accepted';
    participant.TravelGroup__c = groupTrip.Id;
    insert participant;

    insert new List<Traveler__c>{
      traveller(solo.Id, anna.Id),
      traveller(solo.Id, bruno.Id),
      traveller(solo.Id, chris.Id),
      traveller(participant.Id, dora.Id)
    };

    List<Reservation__c> lines = new List<Reservation__c>();
    for (Id bookingId : new List<Id>{ solo.Id, groupTrip.Id, participant.Id }) {
      lines.add(
        new Reservation__c(
          Booking__c = bookingId,
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
  }

  private static Booking__c newBooking(
    String label,
    Id customerId,
    Id mainContactId,
    Id opportunityId
  ) {
    return new Booking__c(
      Opportunity__c = opportunityId,
      Quote_for__c = customerId,
      MainContact__c = mainContactId,
      Name = label,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'PT',
      Status__c = 'Traveled',
      Start_Date__c = Date.today().addDays(-14),
      End_Date__c = Date.today().addDays(-7)
    );
  }

  private static Traveler__c traveller(Id bookingId, Id contactId) {
    return new Traveler__c(TravelQuote__c = bookingId, Traveler__c = contactId);
  }

  private static Booking__c bookingFor(String mainContactEmail) {
    return [
      SELECT Id, Name, BookingNumber__c, Status__c, SurveySent__c
      FROM Booking__c
      WHERE MainContact__r.Email = :mainContactEmail
      LIMIT 1
    ];
  }

  private static List<Traveler__c> travellersOf(String mainContactEmail) {
    return [
      SELECT
        Id,
        Traveler__r.Email,
        Survey_Secret__c,
        Survey_Sent_On__c,
        Survey_Reminder_Sent__c,
        Survey_Answered_On__c
      FROM Traveler__c
      WHERE TravelQuote__r.MainContact__r.Email = :mainContactEmail
      ORDER BY Traveler__r.LastName
    ];
  }

  /**
   * The link a guest was given. The org creates a traveller row of its own for
   * a booking's main contact, so one person can have more than one row on a
   * trip; only the row that was invited carries a secret, because the run asks
   * each contact once.
   */
  private static Traveler__c invitedRowFor(
    String bookingKey,
    String travellerEmail
  ) {
    for (Traveler__c t : travellersOf(bookingKey)) {
      if (
        t.Traveler__r.Email == travellerEmail &&
        String.isNotBlank(t.Survey_Secret__c)
      ) {
        return t;
      }
    }
    return null;
  }

  /** How many guests on a booking hold a link of their own. */
  private static Integer invitedCount(String bookingKey) {
    Integer count = 0;
    for (Traveler__c t : travellersOf(bookingKey)) {
      if (String.isNotBlank(t.Survey_Secret__c)) {
        count++;
      }
    }
    return count;
  }

  /** How many invitations went out for one booking, by its main contact. */
  private static Integer sentFor(
    List<GxFeedbackSender.Result> out,
    String bookingKey
  ) {
    String wanted = bookingFor(bookingKey).BookingNumber__c;
    Integer count = 0;
    for (GxFeedbackSender.Result r : out) {
      if (r.sent && r.bookingNumber == wanted) {
        count++;
      }
    }
    return count;
  }

  private static Map<String, Object> answerFrom(
    String bookingNumber,
    String secret
  ) {
    return new Map<String, Object>{
      'bookingNumber' => bookingNumber,
      'secret' => secret,
      'language' => 'DE',
      'overallExperience' => 9,
      'recommendation' => 10
    };
  }

  // ------------------------------------------------------------------

  @IsTest
  static void everyTravellerWithAnEmailIsAskedOnTheirOwnLink() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    List<GxFeedbackSender.Result> out = GxFeedbackScheduler.run();
    Test.stopTest();

    Integer sent = 0;
    for (GxFeedbackSender.Result r : out) {
      if (r.sent) {
        sent++;
      }
    }
    // Anna and Bruno on the solo trip, Paula on the group booking and Dora on
    // the participant booking. Chris has no address, so he is not asked.
    Assert.areEqual(4, sent, 'Everyone reachable was asked once: ' + out);

    Traveler__c anna = invitedRowFor(SOLO_TRIP, 'anna@example.invalid');
    Traveler__c bruno = invitedRowFor(SOLO_TRIP, 'bruno@example.invalid');
    Assert.isNotNull(anna, 'Anna has her own link');
    Assert.isNotNull(bruno, 'Bruno has his own link');
    Assert.areNotEqual(
      anna.Survey_Secret__c,
      bruno.Survey_Secret__c,
      'Two guests never share one link'
    );
  }

  @IsTest
  static void aTravellerWithoutAnEmailIsLeftOut() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    for (Traveler__c t : travellersOf(SOLO_TRIP)) {
      if (String.isBlank(t.Traveler__r.Email)) {
        Assert.isNull(
          t.Survey_Sent_On__c,
          'Nobody is asked without an address to ask at'
        );
        Assert.isNull(t.Survey_Secret__c, 'And no link is minted for them');
      }
    }
  }

  @IsTest
  static void theMainContactWhoAlsoTravelsIsAskedOnce() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    List<GxFeedbackSender.Result> out = GxFeedbackScheduler.run();
    Test.stopTest();

    // Anna is both the main contact and a traveller on the solo booking. She
    // is asked as a traveller, so the booking's own link is not used as well.
    Assert.areEqual(
      2,
      sentFor(out, SOLO_TRIP),
      'Anna and Bruno, and Anna only once: ' + out
    );
  }

  @IsTest
  static void aParticipantIsAskedThroughTheGroupBookingsStatus() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    Assert.areEqual(
      1,
      invitedCount(PARTY_TRIP),
      'Dora is asked once on the party, and only her'
    );
    Assert.isNotNull(
      invitedRowFor(PARTY_TRIP, 'dora@example.invalid'),
      'A party still at Accepted is asked because its group trip travelled'
    );
  }

  @IsTest
  static void oneAnswerClosesOnlyThatGuestsLink() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();

    Traveler__c anna = invitedRowFor(SOLO_TRIP, 'anna@example.invalid');
    Traveler__c bruno = invitedRowFor(SOLO_TRIP, 'bruno@example.invalid');

    Test.startTest();
    GxFeedbackService.SubmitResult saved = GxFeedbackService.submit(
      JSON.serialize(
        answerFrom(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          anna.Survey_Secret__c
        )
      )
    );
    Test.stopTest();

    Assert.isTrue(saved.ok, 'Anna could answer: ' + saved.message);
    Assert.areEqual(
      'submitted',
      GxFeedbackService.getContext(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          anna.Survey_Secret__c
        )
        .message,
      'Her own link is closed'
    );
    Assert.isTrue(
      GxFeedbackService.getContext(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          bruno.Survey_Secret__c
        )
        .ok,
      'Bruno can still answer for himself'
    );

    Feedback_Response__c response = [
      SELECT Contact__r.FirstName
      FROM Feedback_Response__c
      WHERE Booking__r.MainContact__r.Email = :SOLO_TRIP
    ];
    Assert.areEqual(
      'Anna',
      response.Contact__r.FirstName,
      'The answer is stored against the guest who gave it'
    );
  }

  @IsTest
  static void bothGuestsOnOneTripCanAnswer() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();

    List<String> secrets = new List<String>();
    for (Traveler__c t : travellersOf(SOLO_TRIP)) {
      if (String.isNotBlank(t.Survey_Secret__c)) {
        secrets.add(t.Survey_Secret__c);
      }
    }
    Assert.areEqual(2, secrets.size(), 'Two links were minted');

    Test.startTest();
    for (String secret : secrets) {
      GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
        JSON.serialize(
          answerFrom(bookingFor(SOLO_TRIP).BookingNumber__c, secret)
        )
      );
      Assert.isTrue(r.ok, 'Each guest answers for themselves: ' + r.message);
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM Feedback_Response__c
        WHERE Booking__r.MainContact__r.Email = :SOLO_TRIP
      ],
      'One trip, two answers'
    );
  }

  @IsTest
  static void eachGuestIsRemindedOnTheirOwn() {
    GxFeedbackSettings.useForTest(settings(10));
    GxFeedbackScheduler.run();

    // One guest answers; the other is moved back in time so a reminder is due.
    List<Traveler__c> solo = travellersOf(SOLO_TRIP);
    List<Traveler__c> moved = new List<Traveler__c>();
    Traveler__c answered;
    for (Traveler__c t : solo) {
      if (String.isBlank(t.Survey_Secret__c)) {
        continue;
      }
      if (answered == null) {
        answered = t;
      }
      moved.add(
        new Traveler__c(
          Id = t.Id,
          Survey_Sent_On__c = Datetime.now().addDays(-11)
        )
      );
    }
    update moved;
    GxFeedbackService.submit(
      JSON.serialize(
        answerFrom(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          answered.Survey_Secret__c
        )
      )
    );

    Test.startTest();
    List<GxFeedbackSender.Result> out = GxFeedbackScheduler.run();
    Test.stopTest();

    Integer reminders = 0;
    String soloNumber = bookingFor(SOLO_TRIP).BookingNumber__c;
    for (GxFeedbackSender.Result r : out) {
      if (r.sent && r.reminder == true && r.bookingNumber == soloNumber) {
        reminders++;
      }
    }
    Assert.areEqual(
      1,
      reminders,
      'Only the guest who stayed silent is reminded: ' + out
    );

    for (Traveler__c t : travellersOf(SOLO_TRIP)) {
      if (t.Id == answered.Id) {
        Assert.isFalse(
          t.Survey_Reminder_Sent__c,
          'The guest who answered is left alone'
        );
        Assert.isNotNull(t.Survey_Answered_On__c, 'Their answer is recorded');
      }
    }
  }

  @IsTest
  static void aSecondNightDoesNotAskTheSameGuestsAgain() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();

    Test.startTest();
    List<GxFeedbackSender.Result> second = GxFeedbackScheduler.run();
    Test.stopTest();

    for (GxFeedbackSender.Result r : second) {
      Assert.isFalse(r.sent, 'Nobody is invited twice: ' + r.message);
    }
  }
}
