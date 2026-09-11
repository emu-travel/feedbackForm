/**
 * GxFeedbackServiceTest
 *
 * Covers the public feedback form's service layer: token handling, the
 * per-booking survey shape (including venue de-duplication), validation,
 * and the tamper cases that matter because this runs for guest users.
 */
@IsTest
private class GxFeedbackServiceTest {
  private static final String SECRET = 'sekret-abc-123';
  private static final String BOOKING_NUM = 'TEST-GX-0001';

  // ------------------------------------------------------------------
  // Fixtures

  /**
   * Venue accounts must carry Account_Type__c: Reservation__c.Travel_Location__c
   * has a dependent lookup filter that matches it against AccountType__c.
   */
  private static Account newAccount(String name, String accountType) {
    return new Account(
      Name = name,
      Account_Type__c = accountType,
      BillingCity = 'Almancil',
      BillingCountry = 'Portugal'
    );
  }

  private static Booking__c newBooking(
    Account customer,
    String bookingNumber,
    String secret
  ) {
    return new Booking__c(
      Quote_for__c = customer.Id,
      BookingNumber__c = bookingNumber,
      Form_Secret__c = secret,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'EG',
      Status__c = 'Completed',
      Start_Date__c = Date.today().addDays(-20),
      End_Date__c = Date.today().addDays(-10)
    );
  }

  private static Reservation__c newReservation(
    Id bookingId,
    Account venue,
    String accountType,
    String status
  ) {
    return new Reservation__c(
      Booking__c = bookingId,
      Travel_Location__c = venue.Id,
      AccountType__c = accountType,
      Pricing__c = 'Leistung',
      Status__c = status,
      // Both dates are required: the org's ReservationTrigger runs
      // ReservationPricingService, which needs a date range to price the line.
      // Duration__c is a formula (Date_End__c - Date_Begin__c), so the nights
      // shown on the hotel card come from this six-day range.
      Date_Begin__c = Date.today().addDays(-18),
      Date_End__c = Date.today().addDays(-12)
    );
  }

  /**
   * A rich booking: three hotels where one appears twice (the real data has a
   * hotel repeated once per room), two golf courses, and one each of flight,
   * transfer and rental car - plus two lines that must never be rated.
   */
  /**
   * The org prices every Reservation__c through ReservationTriggerHandler, which
   * needs a fully configured Service__c and season/rate graph behind it. These
   * tests are about the feedback survey, not the pricing engine, so the handler
   * is bypassed while fixtures are built.
   */
  @TestSetup
  static void setup() {
    TriggerHandler.bypass('ReservationTriggerHandler');

    Account customer = newAccount('Test Customer GmbH', null);
    insert customer;

    List<Account> venues = new List<Account>{
      newAccount('Hotel Alpha', 'Hotel'),
      newAccount('Hotel Beta', 'Hotel'),
      newAccount('Golf Club One', 'Golfclub'),
      newAccount('Golf Club Two', 'Golfclub'),
      newAccount('Test Airline', 'Airline'),
      newAccount('Test Transfers', 'TransferCompany'),
      newAccount('Test Rentals', 'CarRentalCompany'),
      newAccount('Test Insurer', 'Insurance'),
      newAccount('Golf Club Three', 'Golfclub'),
      newAccount('Golf Club Four', 'Golfclub')
    };
    insert venues;

    Booking__c b = newBooking(customer, BOOKING_NUM, SECRET);
    insert b;

    insert new List<Reservation__c>{
      // Hotel Alpha twice - must collapse to one card
      newReservation(b.Id, venues[0], 'Hotel', 'Completed'),
      newReservation(b.Id, venues[0], 'Hotel', 'Paid'),
      newReservation(b.Id, venues[1], 'Hotel', 'Booked'),
      newReservation(b.Id, venues[2], 'Golfclub', 'Completed'),
      newReservation(b.Id, venues[3], 'Golfclub', 'Invoiced'),
      newReservation(b.Id, venues[4], 'Airline', 'Completed'),
      newReservation(b.Id, venues[5], 'TransferCompany', 'Completed'),
      newReservation(b.Id, venues[6], 'CarRentalCompany', 'Completed'),
      // Same club as venues[2], still at quote stage - must collapse, not duplicate
      newReservation(b.Id, venues[2], 'Golfclub', 'Calculation'),
      // A course the guest played whose line was never advanced past quote stage.
      // On a delivered booking this must still be rated.
      newReservation(b.Id, venues[8], 'Golfclub', 'Calculation'),
      // Genuinely cancelled - never rated, whatever the booking says
      newReservation(b.Id, venues[9], 'Golfclub', 'Canceled'),
      // Delivered but not a rateable category
      newReservation(b.Id, venues[7], 'Insurance', 'Completed')
    };

    TriggerHandler.clearBypass('ReservationTriggerHandler');
  }

  /** Carries every field isExpired measures from, so expiry tests can use it. */
  private static Booking__c theBooking() {
    return [
      SELECT Id, BookingNumber__c, Survey_Sent_On__c, Start_Date__c, End_Date__c
      FROM Booking__c
      WHERE BookingNumber__c = :BOOKING_NUM
    ];
  }

  // ------------------------------------------------------------------
  // getContext

  @IsTest
  static void getContextBuildsSurveyFromTheItinerary() {
    Test.startTest();
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );
    Test.stopTest();

    Assert.isTrue(
      c.ok,
      'A valid booking number and secret should open the survey'
    );
    Assert.areEqual(
      BOOKING_NUM,
      c.bookingNumber,
      'Booking number should be echoed back'
    );

    Assert.areEqual(
      2,
      c.hotels.size(),
      'Hotel Alpha appears twice and must collapse to one card'
    );
    Assert.areEqual(
      3,
      c.golfCourses.size(),
      'A delivered booking rates every course except the cancelled one'
    );
    Assert.areEqual(1, c.flightSuppliers.size(), 'One airline was booked');
    Assert.areEqual(
      1,
      c.transferSuppliers.size(),
      'One transfer company was booked'
    );
    Assert.areEqual(
      1,
      c.rentalSuppliers.size(),
      'One rental company was booked'
    );

    Assert.isTrue(
      c.hasHotels &&
        c.hasGolf &&
        c.hasFlight &&
        c.hasTransfers &&
        c.hasRentalCar,
      'Every booked service should switch its screen on'
    );

    Set<String> hotelNames = new Set<String>();
    for (GxFeedbackService.RateableItem i : c.hotels) {
      hotelNames.add(i.name);
    }
    Assert.isTrue(
      hotelNames.contains('Hotel Alpha') && hotelNames.contains('Hotel Beta'),
      'Distinct hotels must not be collapsed into each other'
    );
  }

  @IsTest
  static void deliveredBookingRatesACourseWhoseLineStalledAtQuoteStage() {
    // Booking status is Completed, so the trip happened. A green fee left at
    // Calculation is a data-entry gap, not a service the guest did not receive.
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Set<String> played = new Set<String>();
    for (GxFeedbackService.RateableItem i : c.golfCourses) {
      played.add(i.name);
    }
    Assert.isTrue(
      played.contains('Golf Club Three'),
      'A course on a delivered trip is rated even if its line was never advanced'
    );
  }

  @IsTest
  static void cancelledLinesAreNeverRated() {
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    for (GxFeedbackService.RateableItem i : c.golfCourses) {
      Assert.areNotEqual(
        'Golf Club Four',
        i.name,
        'A cancelled line is never rated, however the booking is set'
      );
    }
  }

  @IsTest
  static void bookingStillBeingQuotedFallsBackToTheStrictLineCheck() {
    // Built rather than mutated: changing Status__c on an existing booking fires
    // the org's "Booking - Update Reservations and Opp Status" flow, which cannot
    // complete in a test context.
    Account customer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Customer GmbH'
      LIMIT 1
    ];
    Account played = [
      SELECT Id
      FROM Account
      WHERE Name = 'Golf Club One'
      LIMIT 1
    ];
    Account quoted = [
      SELECT Id
      FROM Account
      WHERE Name = 'Golf Club Three'
      LIMIT 1
    ];

    Booking__c quoting = newBooking(customer, 'TEST-GX-QUOTE', 'quote-secret');
    quoting.Status__c = 'Offered';
    insert quoting;

    TriggerHandler.bypass('ReservationTriggerHandler');
    insert new List<Reservation__c>{
      newReservation(quoting.Id, played, 'Golfclub', 'Booked'),
      newReservation(quoting.Id, quoted, 'Golfclub', 'Calculation')
    };
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      'TEST-GX-QUOTE',
      'quote-secret'
    );

    Assert.areEqual(
      1,
      c.golfCourses.size(),
      'A trip that has not been delivered surveys only properly booked lines'
    );
    Assert.areEqual(
      'Golf Club One',
      c.golfCourses[0].name,
      'The quote-stage course is left out until the trip is delivered'
    );
  }

  @IsTest
  static void getContextRejectsBadCredentials() {
    Assert.areEqual(
      'invalid',
      GxFeedbackService.getContext(null, null).message,
      'Blank input is rejected'
    );
    Assert.areEqual(
      'invalid',
      GxFeedbackService.getContext(BOOKING_NUM, 'wrong').message,
      'A wrong secret is rejected'
    );
    Assert.areEqual(
      'invalid',
      GxFeedbackService.getContext('NOPE', SECRET).message,
      'An unknown booking number is rejected'
    );
    Assert.isFalse(
      GxFeedbackService.getContext(BOOKING_NUM, 'wrong').ok,
      'A rejected context is never ok'
    );
  }

  @IsTest
  static void getContextReportsAnEmptyItinerary() {
    Account customer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Customer GmbH'
      LIMIT 1
    ];
    Booking__c bare = newBooking(customer, 'TEST-GX-EMPTY', 'empty-secret');
    insert bare;

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      'TEST-GX-EMPTY',
      'empty-secret'
    );

    Assert.isFalse(
      c.ok,
      'A booking with nothing rateable does not open a survey'
    );
    Assert.areEqual(
      'empty',
      c.message,
      'The caller is told the itinerary is empty'
    );
  }

  @IsTest
  static void getContextClosesAfterSubmission() {
    insert new Feedback_Response__c(
      Booking__c = theBooking().Id,
      Overall_Experience__c = 9,
      Recommendation_NPS__c = 9
    );

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isFalse(c.ok, 'A booking that already has feedback does not reopen');
    Assert.areEqual(
      'submitted',
      c.message,
      'The caller is told feedback already arrived'
    );
  }

  // ------------------------------------------------------------------
  // submit

  private static Map<String, Object> basePayload() {
    return new Map<String, Object>{
      'bookingNumber' => BOOKING_NUM,
      'secret' => SECRET,
      'language' => 'DE',
      'overallExperience' => 9,
      'recommendation' => 10
    };
  }

  /**
   * Flight, transfer and rental answers used to be stored under a generic
   * "Flug", "Transfer" or "Mietwagen", which made every supplier
   * indistinguishable in reporting. Each is now saved against the supplier the
   * guest was shown, linked to its reservation.
   */
  @IsTest
  static void mobilityScoresAreStoredAgainstTheSupplier() {
    Map<String, Object> payload = basePayload();
    payload.put(
      'flight',
      new Map<String, Object>{ 'score' => 7, 'comment' => 'Verspätet' }
    );
    payload.put('transfer', new Map<String, Object>{ 'score' => 10 });
    payload.put('rentalCar', new Map<String, Object>{ 'score' => 9 });

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );
    Assert.isTrue(r.ok, 'Submission saved: ' + r.message);

    Map<String, Feedback_Rating__c> byCategory = new Map<String, Feedback_Rating__c>();
    for (Feedback_Rating__c row : [
      SELECT Category__c, Item_Name__c, Score__c, Comment__c, Reservation__c
      FROM Feedback_Rating__c
      WHERE Category__c IN ('Airline', 'TransferCompany', 'CarRentalCompany')
    ]) {
      byCategory.put(row.Category__c, row);
    }

    Assert.areEqual(
      'Test Airline',
      byCategory.get('Airline').Item_Name__c,
      'The airline is named, not filed under a generic "Flug"'
    );
    Assert.isNotNull(
      byCategory.get('Airline').Reservation__c,
      'And linked to the reservation it came from'
    );
    Assert.areEqual(
      7,
      byCategory.get('Airline').Score__c,
      'With the guest score'
    );
    Assert.areEqual(
      'Verspätet',
      byCategory.get('Airline').Comment__c,
      'And their comment'
    );
    Assert.areEqual(
      'Test Transfers',
      byCategory.get('TransferCompany').Item_Name__c,
      'Transfer companies likewise'
    );
    Assert.areEqual(
      'Test Rentals',
      byCategory.get('CarRentalCompany').Item_Name__c,
      'And rental firms'
    );
  }

  @IsTest
  static void aTripWithTwoAirlinesRatesBoth() {
    // Outbound with one airline, back with another: the guest answers one
    // flight question, and both airlines should carry that answer.
    TriggerHandler.bypass('ReservationTriggerHandler');
    Account second = newAccount('Second Airline', 'Airline');
    insert second;
    insert newReservation(theBooking().Id, second, 'Airline', 'Completed');
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    Map<String, Object> payload = basePayload();
    payload.put('flight', new Map<String, Object>{ 'score' => 6 });
    GxFeedbackService.submit(JSON.serialize(payload));

    List<Feedback_Rating__c> flights = [
      SELECT Item_Name__c, Score__c
      FROM Feedback_Rating__c
      WHERE Category__c = 'Airline'
      ORDER BY Item_Name__c
    ];
    Assert.areEqual(2, flights.size(), 'One row per airline on the trip');
    Assert.areEqual(
      'Second Airline',
      flights[0].Item_Name__c,
      'The second airline is rated'
    );
    Assert.areEqual(
      'Test Airline',
      flights[1].Item_Name__c,
      'And so is the first'
    );
    Assert.areEqual(6, flights[0].Score__c, 'Each carrying the same answer');
    Assert.areEqual(6, flights[1].Score__c, 'Each carrying the same answer');
  }

  @IsTest
  static void theSameAirlineTwiceIsRatedOnce() {
    // Out and back with the same carrier is still one airline.
    TriggerHandler.bypass('ReservationTriggerHandler');
    Account airline = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Airline'
      LIMIT 1
    ];
    insert newReservation(theBooking().Id, airline, 'Airline', 'Completed');
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    Map<String, Object> payload = basePayload();
    payload.put('flight', new Map<String, Object>{ 'score' => 8 });
    GxFeedbackService.submit(JSON.serialize(payload));

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Feedback_Rating__c WHERE Category__c = 'Airline'],
      'Two reservations with one airline is one airline to rate'
    );
  }

  @IsTest
  static void submitStoresResponseAndRatings() {
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Map<String, Object> payload = basePayload();
    payload.put('consultation', 8);
    payload.put('consultationComment', 'Etwas langsam.');
    payload.put(
      'flight',
      new Map<String, Object>{ 'score' => 7, 'comment' => 'Verspätet' }
    );
    payload.put('transfer', new Map<String, Object>{ 'score' => 10 });
    payload.put('rentalCar', new Map<String, Object>{ 'score' => 9 });
    payload.put('improvementSuggestions', 'Weiter so!');
    payload.put(
      'hotels',
      new List<Object>{
        new Map<String, Object>{
          'reservationId' => c.hotels[0].reservationId,
          'itemName' => c.hotels[0].name,
          'score' => 6,
          'comment' => 'Zimmer war laut',
          'sub' => new Map<String, Object>{
            'Room' => 5,
            'Service' => 8,
            'Catering' => 7,
            'Cleanliness' => 9
          }
        }
      }
    );
    payload.put(
      'golfCourses',
      new List<Object>{
        new Map<String, Object>{
          'reservationId' => c.golfCourses[0].reservationId,
          'itemName' => c.golfCourses[0].name,
          'score' => 10
        }
      }
    );

    Test.startTest();
    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );
    Test.stopTest();

    Assert.isTrue(r.ok, 'A complete payload should be accepted');
    Assert.isTrue(
      r.showPublicReview,
      'A recommendation of 10 earns the public review prompt'
    );
    Assert.isNotNull(r.reference, 'The guest gets a reference number back');

    Feedback_Response__c saved = [
      SELECT
        Id,
        Overall_Experience__c,
        Recommendation_NPS__c,
        NPS_Category__c,
        Consultation_Rating__c,
        Public_Review_Prompted__c,
        Submitted_On__c,
        Language__c
      FROM Feedback_Response__c
      WHERE Booking__c = :theBooking().Id
    ];
    Assert.areEqual(9, saved.Overall_Experience__c, 'Overall score is stored');
    Assert.areEqual(
      'Promoter',
      saved.NPS_Category__c,
      'A 10 classifies as a Promoter'
    );
    Assert.isTrue(
      saved.Public_Review_Prompted__c,
      'The review prompt is recorded'
    );
    Assert.isNotNull(
      saved.Submitted_On__c,
      'Submission time is stamped server-side'
    );

    List<Feedback_Rating__c> ratings = [
      SELECT
        Category__c,
        Sub_Category__c,
        Item_Name__c,
        Score__c,
        Reservation__c
      FROM Feedback_Rating__c
      WHERE Feedback_Response__c = :saved.Id
    ];
    // flight + transfer + rentalCar + hotel + 4 hotel sub-ratings + golf course
    Assert.areEqual(
      9,
      ratings.size(),
      'Every scored item becomes its own rating row'
    );

    Integer subRatings = 0;
    for (Feedback_Rating__c r2 : ratings) {
      if (r2.Sub_Category__c != null) {
        subRatings++;
        Assert.areEqual(
          'Hotel',
          r2.Category__c,
          'Sub-ratings belong to the hotel'
        );
        Assert.areNotEqual(
          null,
          r2.Reservation__c,
          'Sub-ratings keep the reservation link'
        );
      }
    }
    Assert.areEqual(4, subRatings, 'All four hotel sub-categories are stored');
  }

  @IsTest
  static void submitWithLowRecommendationSkipsPublicReview() {
    Map<String, Object> payload = basePayload();
    payload.put('recommendation', 6);

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );

    Assert.isTrue(r.ok, 'A detractor response is still accepted');
    Assert.isFalse(
      r.showPublicReview,
      'A score of 6 must not trigger the review invitation'
    );

    Feedback_Response__c saved = [
      SELECT NPS_Category__c, Public_Review_Prompted__c
      FROM Feedback_Response__c
      LIMIT 1
    ];
    Assert.areEqual(
      'Detractor',
      saved.NPS_Category__c,
      'A 6 classifies as a Detractor'
    );
    Assert.isFalse(
      saved.Public_Review_Prompted__c,
      'No review prompt is recorded'
    );
  }

  @IsTest
  static void submitAcceptsARecommendationOfZero() {
    Map<String, Object> payload = basePayload();
    payload.put('recommendation', 0);

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );

    Assert.isTrue(r.ok, 'NPS runs 0-10, so 0 is a real answer');
    Feedback_Response__c saved = [
      SELECT Recommendation_NPS__c, NPS_Category__c
      FROM Feedback_Response__c
      LIMIT 1
    ];
    Assert.areEqual(0, saved.Recommendation_NPS__c, 'Stored as 0, not blank');
    Assert.areEqual('Detractor', saved.NPS_Category__c, 'A 0 is a Detractor');
  }

  @IsTest
  static void submitRejectsSecondResponseForTheSameBooking() {
    GxFeedbackService.submit(JSON.serialize(basePayload()));

    GxFeedbackService.SubmitResult second = GxFeedbackService.submit(
      JSON.serialize(basePayload())
    );

    Assert.isFalse(second.ok, 'A booking accepts feedback only once');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Feedback_Response__c],
      'The second attempt creates nothing'
    );
  }

  @IsTest
  static void submitRejectsBadCredentialsAndMalformedInput() {
    Assert.isFalse(
      GxFeedbackService.submit('not json at all').ok,
      'Unparseable JSON is rejected'
    );
    Assert.isFalse(
      GxFeedbackService.submit(
          JSON.serialize(
            new Map<String, Object>{
              'bookingNumber' => BOOKING_NUM,
              'secret' => 'wrong',
              'overallExperience' => 9,
              'recommendation' => 9
            }
          )
        )
        .ok,
      'A wrong secret is rejected'
    );
    Assert.isFalse(
      GxFeedbackService.submit(
          JSON.serialize(new Map<String, Object>{ 'overallExperience' => 9 })
        )
        .ok,
      'A payload with no credentials is rejected'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Feedback_Response__c],
      'No rejected attempt writes anything'
    );
  }

  @IsTest
  static void submitEnforcesRequiredAndRangedScores() {
    Map<String, Object> noOverall = basePayload();
    noOverall.remove('overallExperience');
    Assert.isFalse(
      GxFeedbackService.submit(JSON.serialize(noOverall)).ok,
      'The overall score is required'
    );

    Map<String, Object> outOfRange = basePayload();
    outOfRange.put('overallExperience', 11);
    Assert.isFalse(
      GxFeedbackService.submit(JSON.serialize(outOfRange)).ok,
      'A score above 10 is rejected rather than stored'
    );

    Map<String, Object> noRecommendation = basePayload();
    noRecommendation.remove('recommendation');
    Assert.isFalse(
      GxFeedbackService.submit(JSON.serialize(noRecommendation)).ok,
      'The recommendation score is required'
    );

    Map<String, Object> negative = basePayload();
    negative.put('recommendation', -1);
    Assert.isFalse(
      GxFeedbackService.submit(JSON.serialize(negative)).ok,
      'A recommendation below 0 is rejected'
    );

    Map<String, Object> zeroOverall = basePayload();
    zeroOverall.put('overallExperience', 0);
    Assert.isFalse(
      GxFeedbackService.submit(JSON.serialize(zeroOverall)).ok,
      'Only the recommendation scale starts at 0; the ratings start at 1'
    );

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Feedback_Response__c],
      'No invalid submission is stored'
    );
  }

  @IsTest
  static void submitIgnoresOutOfRangeItemScores() {
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Map<String, Object> payload = basePayload();
    payload.put(
      'hotels',
      new List<Object>{
        new Map<String, Object>{
          'reservationId' => c.hotels[0].reservationId,
          'itemName' => c.hotels[0].name,
          'score' => 99,
          'sub' => new Map<String, Object>{ 'Room' => 42, 'Bogus' => 5 }
        }
      }
    );

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );

    Assert.isTrue(r.ok, 'The response is still saved');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Feedback_Rating__c],
      'An impossible item score is dropped rather than stored'
    );
  }

  @IsTest
  static void submitIgnoresAReservationFromAnotherBooking() {
    Account customer = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Customer GmbH'
      LIMIT 1
    ];
    Account venue = [SELECT Id FROM Account WHERE Name = 'Hotel Alpha' LIMIT 1];
    Booking__c other = newBooking(customer, 'TEST-GX-OTHER', 'other-secret');
    insert other;

    TriggerHandler.bypass('ReservationTriggerHandler');
    Reservation__c foreign = newReservation(
      other.Id,
      venue,
      'Hotel',
      'Completed'
    );
    insert foreign;
    TriggerHandler.clearBypass('ReservationTriggerHandler');

    Map<String, Object> payload = basePayload();
    payload.put(
      'hotels',
      new List<Object>{
        new Map<String, Object>{
          'reservationId' => foreign.Id,
          'itemName' => 'Injected Hotel',
          'score' => 10
        }
      }
    );

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(payload)
    );

    Assert.isTrue(r.ok, 'The rest of the submission still succeeds');
    Feedback_Rating__c rating = [
      SELECT Reservation__c, Item_Name__c
      FROM Feedback_Rating__c
      LIMIT 1
    ];
    Assert.areEqual(
      null,
      rating.Reservation__c,
      'A reservation from another booking must never be linked'
    );
    Assert.areEqual(
      'Injected Hotel',
      rating.Item_Name__c,
      'Without a trusted reservation the name falls back to the client value'
    );
  }

  @IsTest
  static void submitStripsMarkupFromGuestText() {
    Map<String, Object> payload = basePayload();
    payload.put(
      'improvementSuggestions',
      '<script>alert(1)</script>Bitte mehr Golf'
    );

    GxFeedbackService.submit(JSON.serialize(payload));

    Feedback_Response__c saved = [
      SELECT Improvement_Suggestions__c
      FROM Feedback_Response__c
      LIMIT 1
    ];
    Assert.isFalse(
      saved.Improvement_Suggestions__c.contains('<script>'),
      'Markup is stripped from guest free text'
    );
    Assert.isTrue(
      saved.Improvement_Suggestions__c.contains('Bitte mehr Golf'),
      'The guest\'s actual words survive'
    );
  }

  @IsTest
  static void submitCapsOverlongText() {
    Map<String, Object> payload = basePayload();
    payload.put('generalFeedback', 'x'.repeat(3000));

    GxFeedbackService.submit(JSON.serialize(payload));

    Feedback_Response__c saved = [
      SELECT General_Feedback__c
      FROM Feedback_Response__c
      LIMIT 1
    ];
    Assert.areEqual(
      2000,
      saved.General_Feedback__c.length(),
      'Text longer than the field is truncated, not rejected'
    );
  }

  @IsTest
  static void getContextCarriesTheHotelCardDetail() {
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    GxFeedbackService.RateableItem hotel = c.hotels[0];
    Assert.areEqual(
      'Almancil, Portugal',
      hotel.location,
      'The hotel card shows city and country under the name'
    );
    Assert.areEqual(
      6,
      hotel.nights,
      'The hotel card shows the number of nights'
    );
    Assert.isNotNull(
      hotel.startDate,
      'The stay dates are available to the card'
    );
  }

  @IsTest
  static void getContextExposesTheReviewLinks() {
    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isNotNull(
      c.trustpilotUrl,
      'The promoter screen needs the Trustpilot link from custom metadata'
    );
    Assert.isNotNull(
      c.googleMapsUrl,
      'The promoter screen needs the Google link'
    );
  }

  @IsTest
  static void submitStoresTheScreenClosingComments() {
    Map<String, Object> payload = basePayload();
    payload.put('generalHotelComment', 'Beide Hotels waren hervorragend.');
    payload.put('generalGolfComment', 'Die Plaetze waren in Top-Zustand.');

    GxFeedbackService.submit(JSON.serialize(payload));

    Feedback_Response__c saved = [
      SELECT General_Hotel_Comment__c, General_Golf_Comment__c
      FROM Feedback_Response__c
      LIMIT 1
    ];
    Assert.areEqual(
      'Beide Hotels waren hervorragend.',
      saved.General_Hotel_Comment__c,
      'Screen 3 closing remarks are stored'
    );
    Assert.areEqual(
      'Die Plaetze waren in Top-Zustand.',
      saved.General_Golf_Comment__c,
      'Screen 4 closing remarks are stored'
    );
  }

  // ------------------------------------------------------------------
  // Link expiry

  private static void setTripEnd(Date ended) {
    Booking__c b = theBooking();
    b.Start_Date__c = ended.addDays(-7);
    b.End_Date__c = ended;
    update b;
  }

  @IsTest
  static void expiredLinkRefusesToOpenTheSurvey() {
    setTripEnd(Date.today().addDays(-400));

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isFalse(c.ok, 'A long-past trip does not open a survey');
    Assert.areEqual(
      'expired',
      c.message,
      'The caller is told the link expired'
    );
    Assert.isTrue(c.hotels.isEmpty(), 'An expired link discloses no itinerary');
    Assert.areEqual(
      null,
      c.bookingNumber,
      'An expired link echoes nothing back'
    );
  }

  @IsTest
  static void expiredLinkRefusesToSubmit() {
    setTripEnd(Date.today().addDays(-400));

    GxFeedbackService.SubmitResult r = GxFeedbackService.submit(
      JSON.serialize(basePayload())
    );

    Assert.isFalse(r.ok, 'A stale link cannot write feedback');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Feedback_Response__c],
      'Nothing is stored for an expired link'
    );
  }

  @IsTest
  static void linkStillWorksInsideTheWindow() {
    setTripEnd(Date.today().addDays(-3));

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isTrue(
      c.ok,
      'A trip inside the configured validity window is still open for feedback'
    );
  }

  @IsTest
  static void bookingWithoutDatesNeverExpires() {
    Booking__c b = theBooking();
    b.Start_Date__c = null;
    b.End_Date__c = null;
    update b;

    Assert.isFalse(
      GxFeedbackService.isExpired(b),
      'With no date to measure from the secret stays the only gate'
    );
  }

  @IsTest
  static void expiryFallsBackToTheStartDateWhenThereIsNoEnd() {
    Booking__c b = theBooking();
    b.End_Date__c = null;
    b.Start_Date__c = Date.today().addDays(-400);
    update b;

    Assert.isTrue(
      GxFeedbackService.isExpired(b),
      'A trip that started long ago is expired even without an end date'
    );
  }

  /**
   * The reason validity is counted from the invitation rather than the trip: a
   * guest reminded on day ten has to get a working link, not the tail of one.
   */
  @IsTest
  static void theWindowRunsFromWhenTheGuestWasLastAsked() {
    setTripEnd(Date.today().addDays(-400));
    Booking__c b = theBooking();
    b.Survey_Sent_On__c = Datetime.now().addDays(-2);
    update b;

    GxFeedbackService.Context c = GxFeedbackService.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isTrue(
      c.ok,
      'Asked two days ago, the guest can answer - however old the trip is: ' +
      c.message
    );
  }

  @IsTest
  static void anOldInvitationExpiresEvenOnARecentTrip() {
    setTripEnd(Date.today().addDays(-1));
    Booking__c b = theBooking();
    b.Survey_Sent_On__c = Datetime.now().addDays(-400);
    update b;

    Assert.isTrue(
      GxFeedbackService.isExpired(theBooking()),
      'Once asked, the clock is the invitation - not the trip dates'
    );
  }

  @IsTest
  static void theTripDatesRemainTheFallbackForOlderBookings() {
    setTripEnd(Date.today().addDays(-3));
    Booking__c b = theBooking();

    Assert.isNull(
      b.Survey_Sent_On__c,
      'This booking predates the field, as every booking invited before it did'
    );
    Assert.isFalse(
      GxFeedbackService.isExpired(b),
      'And is still measured from its trip end'
    );
  }
}
