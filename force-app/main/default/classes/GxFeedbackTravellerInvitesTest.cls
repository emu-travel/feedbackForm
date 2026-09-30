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

  /** The invitations for one trip: one row per guest who was asked. */
  private static List<Feedback_Invitation__c> invitationsOf(
    String mainContactEmail
  ) {
    return [
      SELECT
        Id,
        Contact__r.Email,
        Traveler__c,
        Secret__c,
        Survey_Link__c,
        Guest_Name__c,
        Sent_On__c,
        Reminder_Sent__c,
        Answered_On__c
      FROM Feedback_Invitation__c
      WHERE Booking__r.MainContact__r.Email = :mainContactEmail
      ORDER BY Contact__r.LastName
    ];
  }

  /**
   * The link a guest was given. The org creates a traveller row of its own for
   * a booking's main contact, so one person can have more than one row on a
   * trip; only the row that was invited carries a secret, because the run asks
   * each contact once.
   */
  private static Feedback_Invitation__c invitedRowFor(
    String bookingKey,
    String guestEmail
  ) {
    for (Feedback_Invitation__c inv : invitationsOf(bookingKey)) {
      if (
        inv.Contact__r.Email == guestEmail && String.isNotBlank(inv.Secret__c)
      ) {
        return inv;
      }
    }
    return null;
  }

  /** How many guests on a booking hold a link of their own. */
  private static Integer invitedCount(String bookingKey) {
    Integer count = 0;
    for (Feedback_Invitation__c inv : invitationsOf(bookingKey)) {
      if (String.isNotBlank(inv.Secret__c)) {
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

    Feedback_Invitation__c anna = invitedRowFor(
      SOLO_TRIP,
      'anna@example.invalid'
    );
    Feedback_Invitation__c bruno = invitedRowFor(
      SOLO_TRIP,
      'bruno@example.invalid'
    );
    Assert.isNotNull(anna, 'Anna has her own link');
    Assert.isNotNull(bruno, 'Bruno has his own link');
    Assert.areNotEqual(
      anna.Secret__c,
      bruno.Secret__c,
      'Two guests never share one link'
    );
  }

  @IsTest
  static void aTravellerWithoutAnEmailIsLeftOut() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    for (Feedback_Invitation__c inv : invitationsOf(SOLO_TRIP)) {
      Assert.areNotEqual(
        'chris@example.invalid',
        inv.Contact__r.Email,
        'Nobody is asked without an address to ask at'
      );
    }
    Assert.areEqual(
      2,
      invitedCount(SOLO_TRIP),
      'Only Anna and Bruno were asked on the solo trip'
    );
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

    Feedback_Invitation__c anna = invitedRowFor(
      SOLO_TRIP,
      'anna@example.invalid'
    );
    Feedback_Invitation__c bruno = invitedRowFor(
      SOLO_TRIP,
      'bruno@example.invalid'
    );

    Test.startTest();
    GxFeedbackService.SubmitResult saved = GxFeedbackService.submit(
      JSON.serialize(
        answerFrom(bookingFor(SOLO_TRIP).BookingNumber__c, anna.Secret__c)
      )
    );
    Test.stopTest();

    Assert.isTrue(saved.ok, 'Anna could answer: ' + saved.message);
    Assert.areEqual(
      'submitted',
      GxFeedbackService.getContext(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          anna.Secret__c
        )
        .message,
      'Her own link is closed'
    );
    Assert.isTrue(
      GxFeedbackService.getContext(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          bruno.Secret__c
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
    for (Feedback_Invitation__c inv : invitationsOf(SOLO_TRIP)) {
      if (String.isNotBlank(inv.Secret__c)) {
        secrets.add(inv.Secret__c);
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
    List<Feedback_Invitation__c> moved = new List<Feedback_Invitation__c>();
    Feedback_Invitation__c answered;
    for (Feedback_Invitation__c inv : invitationsOf(SOLO_TRIP)) {
      if (String.isBlank(inv.Secret__c)) {
        continue;
      }
      if (answered == null) {
        answered = inv;
      }
      moved.add(
        new Feedback_Invitation__c(
          Id = inv.Id,
          Sent_On__c = Datetime.now().addDays(-11)
        )
      );
    }
    update moved;
    GxFeedbackService.submit(
      JSON.serialize(
        answerFrom(bookingFor(SOLO_TRIP).BookingNumber__c, answered.Secret__c)
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

    for (Feedback_Invitation__c inv : invitationsOf(SOLO_TRIP)) {
      if (inv.Id == answered.Id) {
        Assert.isFalse(
          inv.Reminder_Sent__c,
          'The guest who answered is left alone'
        );
        Assert.isNotNull(inv.Answered_On__c, 'Their answer is recorded');
      }
    }
  }

  /**
   * The templates can only merge the booking's link, so the sender swaps in the
   * traveller's. Without it every guest on a trip would be emailed the main
   * contact's link, and the first of them to answer would close it for all.
   */
  @IsTest
  static void eachGuestsEmailCarriesTheirOwnLink() {
    String bookingLink = 'https://example.test/feedback/?b=X&k=BOOKINGSECRET';
    String personLink = 'https://example.test/feedback/?b=X&k=ANNASECRET';
    // A rendered template writes the address into the markup with the
    // ampersand escaped, and leaves it plain in the text beneath. Both have to
    // end up pointing at this guest, which is exactly what swapping the whole
    // address misses.
    String body =
      '<a href="' +
      bookingLink.replace('&', '&amp;') +
      '">Feedback geben</a> oder ' +
      bookingLink;

    String out = GxFeedbackSender.personalise(body, bookingLink, personLink);

    Assert.isFalse(
      out.contains('BOOKINGSECRET'),
      'The booking\'s own link is gone'
    );
    Assert.areEqual(
      2,
      out.countMatches('ANNASECRET'),
      'Both the button and the line beneath it lead to this guest\'s survey'
    );
    Assert.areEqual(
      body,
      GxFeedbackSender.personalise(body, null, personLink),
      'With nothing to swap the email is left as it is'
    );
  }

  /** The link a guest is emailed is the one that opens their survey. */
  @IsTest
  static void theTravellersLinkFieldMatchesTheirSecret() {
    GxFeedbackSettings.useForTest(settings(0));

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    Feedback_Invitation__c anna = invitedRowFor(
      SOLO_TRIP,
      'anna@example.invalid'
    );
    Feedback_Invitation__c fromOrg = [
      SELECT Survey_Link__c, Secret__c
      FROM Feedback_Invitation__c
      WHERE Id = :anna.Id
    ];
    Assert.isTrue(
      fromOrg.Survey_Link__c.endsWith('k=' + fromOrg.Secret__c),
      'The traveller link carries their own secret: ' + fromOrg.Survey_Link__c
    );
    Assert.isTrue(
      GxFeedbackService.getContext(
          bookingFor(SOLO_TRIP).BookingNumber__c,
          fromOrg.Secret__c
        )
        .ok,
      'And that secret opens their survey'
    );
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
  /**
   * Two guests on one booking: the second must not be greeted by the first
   * one's name. The page reads the name from the invitation, never from a
   * Contact, because the public survey may not read contacts at all.
   */
  @IsTest
  static void theSurveyGreetsTheGuestHoldingTheLink() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();

    Booking__c solo = bookingFor(SOLO_TRIP);
    Feedback_Invitation__c bruno = invitedRowFor(
      SOLO_TRIP,
      'bruno@example.invalid'
    );

    Test.startTest();
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      solo.BookingNumber__c,
      bruno.Secret__c
    );
    Test.stopTest();

    Assert.isTrue(c.ok, 'Bruno can open his own link: ' + c.message);
    Assert.isTrue(
      c.guestName != null && c.guestName.contains('Bruno'),
      'The page greets Bruno, not the main contact of the trip: ' + c.guestName
    );
  }

  /**
   * Validity runs from this guest's own invitation. Measured from the booking
   * it would both revive a dead link because somebody else was reminded, and
   * kill a link handed out today on a trip asked a fortnight ago.
   */
  @IsTest
  static void aGuestsLinkExpiresOnTheirOwnClock() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();

    Booking__c solo = bookingFor(SOLO_TRIP);
    Feedback_Invitation__c bruno = invitedRowFor(
      SOLO_TRIP,
      'bruno@example.invalid'
    );
    // Bruno was asked long ago; the trip was asked again today, for Anna.
    update new Feedback_Invitation__c(
      Id = bruno.Id,
      Sent_On__c = Datetime.now().addDays(-400)
    );
    update new Booking__c(Id = solo.Id, Survey_Sent_On__c = Datetime.now());

    Test.startTest();
    GxFeedbackService.Context stale = GxFeedbackService.getContext(
      solo.BookingNumber__c,
      bruno.Secret__c
    );
    update new Feedback_Invitation__c(
      Id = bruno.Id,
      Sent_On__c = Datetime.now()
    );
    update new Booking__c(
      Id = solo.Id,
      Survey_Sent_On__c = Datetime.now().addDays(-400)
    );
    GxFeedbackService.Context fresh = GxFeedbackService.getContext(
      solo.BookingNumber__c,
      bruno.Secret__c
    );
    Test.stopTest();

    Assert.areEqual(
      'expired',
      stale.message,
      'His own link is old, whatever the trip was asked today'
    );
    Assert.isTrue(
      fresh.ok,
      'And asked today it works, however long ago the trip was asked: ' +
      fresh.message
    );
  }

  /**
   * The team adds a guest, or fills in the address the run notice asked for,
   * after the trip was invited. Without a pass of its own that person is never
   * asked: the invitation pass only looks at trips nobody has been asked about.
   */
  @IsTest
  static void aGuestAddedAfterTheInvitationsWentOutIsStillAsked() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();
    Integer asked = invitedCount(SOLO_TRIP);

    Booking__c solo = bookingFor(SOLO_TRIP);
    Contact late = new Contact(
      FirstName = 'Lena',
      LastName = 'Later',
      Email = 'lena@example.invalid'
    );
    insert late;
    insert traveller(solo.Id, late.Id);

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    Assert.areEqual(
      asked + 1,
      invitedCount(SOLO_TRIP),
      'The guest added later is asked, and nobody is asked twice'
    );
    Assert.isNotNull(
      invitedRowFor(SOLO_TRIP, 'lena@example.invalid'),
      'Lena holds a link of her own'
    );
  }

  /** Two travellers, one inbox: the trip writes to that address once. */
  @IsTest
  static void aLatecomerSharingAnInboxIsNotAskedAgain() {
    GxFeedbackSettings.useForTest(settings(0));
    GxFeedbackScheduler.run();
    Integer asked = invitedCount(SOLO_TRIP);

    Booking__c solo = bookingFor(SOLO_TRIP);
    Contact sameInbox = new Contact(
      FirstName = 'Beate',
      LastName = 'Berger',
      Email = 'BRUNO@example.invalid'
    );
    insert sameInbox;
    insert traveller(solo.Id, sameInbox.Id);

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    Assert.areEqual(
      asked,
      invitedCount(SOLO_TRIP),
      'An address this trip already writes to is not written to twice'
    );
  }

  /**
   * A party booking carrying no lines of its own still travelled with the
   * group, so it is asked about the group booking's itinerary rather than
   * refused a survey altogether.
   */
  @IsTest
  static void aPartyWithoutLinesIsAskedAboutTheGroupsItinerary() {
    GxFeedbackSettings.useForTest(settings(0));
    Booking__c party = bookingFor(PARTY_TRIP);
    delete [SELECT Id FROM Reservation__c WHERE Booking__c = :party.Id];

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    Feedback_Invitation__c dora = invitedRowFor(
      PARTY_TRIP,
      'dora@example.invalid'
    );
    Assert.isNotNull(dora, 'A party with no lines of its own is still asked');

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      bookingFor(PARTY_TRIP).BookingNumber__c,
      dora.Secret__c
    );
    Assert.isTrue(c.ok, 'Her survey opens: ' + c.message);
    Assert.areEqual(
      1,
      c.hotels.size(),
      'And asks about the hotel the group booking carries'
    );
  }
  /**
   * One guest stays a night longer and plays a round the others go home before.
   * The org records who was on which service, so only he is asked about it.
   */
  @IsTest
  static void aGuestIsAskedOnlyAboutTheServicesTheyWereOn() {
    GxFeedbackSettings.useForTest(settings(0));
    Booking__c solo = bookingFor(SOLO_TRIP);
    Account course = new Account(
      Name = 'Extra Round Golf',
      Account_Type__c = 'Golfclub',
      BillingCity = 'Faro',
      BillingCountry = 'Portugal'
    );
    insert course;

    TriggerHandler.bypass('ReservationTriggerHandler');
    Reservation__c extra = new Reservation__c(
      Booking__c = solo.Id,
      Travel_Location__c = course.Id,
      AccountType__c = 'Golfclub',
      Pricing__c = 'Leistung',
      Status__c = 'Completed',
      Date_Begin__c = Date.today().addDays(-8),
      Date_End__c = Date.today().addDays(-8),
      AutoAssigneAllTravelers__c = false
    );
    insert extra;
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    // Everyone is on the hotel; only Bruno is on the extra round. One person
    // can hold several traveller rows, so every row of theirs is linked.
    Map<String, List<Id>> rowsOf = new Map<String, List<Id>>();
    for (Traveler__c t : [
      SELECT Id, Traveler__r.Email
      FROM Traveler__c
      WHERE TravelQuote__c = :solo.Id AND Traveler__c != NULL
    ]) {
      if (!rowsOf.containsKey(t.Traveler__r.Email)) {
        rowsOf.put(t.Traveler__r.Email, new List<Id>());
      }
      rowsOf.get(t.Traveler__r.Email).add(t.Id);
    }
    List<Authorized_Traveler__c> onIt = new List<Authorized_Traveler__c>();
    for (Reservation__c line : [
      SELECT Id
      FROM Reservation__c
      WHERE Booking__c = :solo.Id AND Id != :extra.Id
    ]) {
      for (String email : rowsOf.keySet()) {
        for (Id rowId : rowsOf.get(email)) {
          onIt.add(
            new Authorized_Traveler__c(
              TravelItems__c = line.Id,
              Traveler__c = rowId
            )
          );
        }
      }
    }
    for (Id rowId : rowsOf.get('bruno@example.invalid')) {
      onIt.add(
        new Authorized_Traveler__c(
          TravelItems__c = extra.Id,
          Traveler__c = rowId
        )
      );
    }
    delete [
      SELECT Id
      FROM Authorized_Traveler__c
      WHERE TravelItems__c = :extra.Id
    ];
    insert onIt;

    Test.startTest();
    GxFeedbackScheduler.run();
    Test.stopTest();

    String tripNumber = bookingFor(SOLO_TRIP).BookingNumber__c;
    GxFeedbackService.Context hers = GxFeedbackService.getContext(
      tripNumber,
      invitedRowFor(SOLO_TRIP, 'anna@example.invalid').Secret__c
    );
    GxFeedbackService.Context his = GxFeedbackService.getContext(
      tripNumber,
      invitedRowFor(SOLO_TRIP, 'bruno@example.invalid').Secret__c
    );

    Assert.areEqual(
      0,
      hers.golfCourses.size(),
      'Anna went home before that round and is not asked about it'
    );
    Assert.areEqual(1, his.golfCourses.size(), 'Bruno played it, so he is');
    Assert.areEqual(
      1,
      hers.hotels.size(),
      'The hotel they shared is still on her survey'
    );
  }
}
