/**
 * GxFeedbackDashboardControllerTest
 *
 * Five trips, chosen so every number on the dashboard has one right answer
 * that can be worked out by hand:
 *
 *   GXD-1  Algarve   answered  NPS 10  promoter   wants Schottland next
 *   GXD-2  Algarve   answered  NPS 3   detractor  reminded first; complains
 *   GXD-3  Algarve   answered  NPS 8   passive
 *   GXD-4  Mallorca  invited, never answered
 *   GXD-5  Mallorca  answered  NPS 9   promoter   wants Japan next
 *   GXD-6  Algarve   SurveySent__c only, from the old survey - not our invitation
 */
@IsTest
private class GxFeedbackDashboardControllerTest {
  private static final String CONRAD = 'Conrad Algarve';
  private static final String QUINTA = 'Quinta do Vale Golf';
  private static final String LUFTHANSA = 'Lufthansa';
  private static final String FINCA = 'Finca Serena';

  @TestSetup
  static void setup() {
    Account acct = new Account(Name = 'Dashboard Customer');
    insert acct;
    Contact guest = new Contact(
      LastName = 'Gast',
      FirstName = 'Test',
      AccountId = acct.Id
    );
    insert guest;
    Opportunity opp = new Opportunity(
      Name = 'Dashboard Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = acct.Id
    );
    insert opp;

    List<Booking__c> bookings = new List<Booking__c>{
      booking(opp, acct, guest, 'GXD-1', 'Algarve', 'PT', -40, true, false),
      booking(opp, acct, guest, 'GXD-2', 'Algarve', 'PT', -30, true, true),
      booking(opp, acct, guest, 'GXD-3', 'Algarve', 'PT', -20, true, false),
      booking(opp, acct, guest, 'GXD-4', 'Mallorca', 'ES', -10, true, false),
      booking(opp, acct, guest, 'GXD-5', 'Mallorca', 'ES', -5, true, false),
      booking(opp, acct, guest, 'GXD-6', 'Algarve', 'PT', -15, false, false)
    };
    bookings[5].SurveySent__c = true; // the old flow's flag, without our date
    insert bookings;

    Map<String, Id> b = new Map<String, Id>();
    for (Booking__c x : bookings) {
      b.put(x.BookingNumber__c, x.Id);
    }

    List<Feedback_Response__c> responses = new List<Feedback_Response__c>{
      response(b.get('GXD-1'), guest, 9, 10, 10, 'Schottland', null),
      response(b.get('GXD-2'), guest, 5, 6, 3, null, 'Zu laut'),
      response(b.get('GXD-3'), guest, 8, null, 8, null, null),
      response(b.get('GXD-5'), guest, 10, null, 9, 'Japan', null)
    };
    insert responses;

    List<Feedback_Rating__c> ratings = new List<Feedback_Rating__c>();
    // GXD-1
    ratings.add(rating(responses[0], 'Hotel', CONRAD, null, 9, null));
    ratings.addAll(subs(responses[0], CONRAD, 8, 9, 9, 10));
    ratings.add(rating(responses[0], 'Golfclub', QUINTA, null, 10, null));
    ratings.add(rating(responses[0], 'Airline', LUFTHANSA, null, 8, null));
    // GXD-2 - the unhappy one
    ratings.add(rating(responses[1], 'Hotel', CONRAD, null, 5, 'Laut'));
    ratings.addAll(subs(responses[1], CONRAD, 4, 6, 7, 5));
    ratings.add(rating(responses[1], 'Golfclub', QUINTA, null, 8, null));
    ratings.add(
      rating(responses[1], 'Airline', LUFTHANSA, null, 6, 'Verspätet')
    );
    // GXD-3
    ratings.add(rating(responses[2], 'Hotel', CONRAD, null, 7, null));
    ratings.add(rating(responses[2], 'Golfclub', QUINTA, null, 9, null));
    // GXD-5
    ratings.add(rating(responses[3], 'Hotel', FINCA, null, 10, null));
    insert ratings;
  }

  private static Booking__c booking(
    Opportunity opp,
    Account acct,
    Contact guest,
    String num,
    String region,
    String country,
    Integer endOffset,
    Boolean invited,
    Boolean reminded
  ) {
    return new Booking__c(
      Opportunity__c = opp.Id,
      Quote_for__c = acct.Id,
      MainContact__c = guest.Id,
      BookingNumber__c = num,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = country,
      Region__c = region,
      Status__c = 'Feedback',
      Start_Date__c = Date.today().addDays(endOffset - 7),
      End_Date__c = Date.today().addDays(endOffset),
      SurveySent__c = invited,
      Survey_Sent_On__c = invited
        ? Datetime.now().addDays(endOffset + 2)
        : null,
      Survey_Reminder_Sent__c = reminded
    );
  }

  private static Feedback_Response__c response(
    Id bookingId,
    Contact guest,
    Integer overall,
    Integer consultation,
    Integer nps,
    String nextDestination,
    String suggestion
  ) {
    return new Feedback_Response__c(
      Booking__c = bookingId,
      Contact__c = guest.Id,
      Overall_Experience__c = overall,
      Consultation_Rating__c = consultation,
      Recommendation_NPS__c = nps,
      Next_Destination__c = nextDestination,
      Improvement_Suggestions__c = suggestion,
      Submitted_On__c = Datetime.now()
    );
  }

  private static Feedback_Rating__c rating(
    Feedback_Response__c r,
    String category,
    String item,
    String sub,
    Integer score,
    String comment
  ) {
    return new Feedback_Rating__c(
      Feedback_Response__c = r.Id,
      Category__c = category,
      Item_Name__c = item,
      Sub_Category__c = sub,
      Score__c = score,
      Comment__c = comment
    );
  }

  private static List<Feedback_Rating__c> subs(
    Feedback_Response__c r,
    String hotel,
    Integer room,
    Integer service,
    Integer catering,
    Integer cleanliness
  ) {
    return new List<Feedback_Rating__c>{
      rating(r, 'Hotel', hotel, 'Room', room, null),
      rating(r, 'Hotel', hotel, 'Service', service, null),
      rating(r, 'Hotel', hotel, 'Catering', catering, null),
      rating(r, 'Hotel', hotel, 'Cleanliness', cleanliness, null)
    };
  }

  private static GxFeedbackDashboardController.Dashboard load(
    Map<String, Object> filters
  ) {
    return GxFeedbackDashboardController.getDashboard(
      filters == null ? null : JSON.serialize(filters)
    );
  }

  private static GxFeedbackDashboardController.Venue find(
    List<GxFeedbackDashboardController.Venue> venues,
    String name
  ) {
    for (GxFeedbackDashboardController.Venue v : venues) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // KPIs

  @IsTest
  static void headlineNumbersAreRight() {
    GxFeedbackDashboardController.Kpis k = load(null).kpis;

    Assert.areEqual(4, k.responses, 'Four trips answered');
    Assert.areEqual(2, k.promoters, 'NPS 10 and 9');
    Assert.areEqual(1, k.passives, 'NPS 8');
    Assert.areEqual(1, k.detractors, 'NPS 3');
    Assert.areEqual(8.0, k.avgOverall, '(9 + 5 + 8 + 10) / 4');
    Assert.areEqual(
      8.0,
      k.avgConsultation,
      'Only two guests rated it: (10 + 6) / 2'
    );
  }

  @IsTest
  static void npsIsPromotersMinusDetractorsNotAnAverage() {
    // 2 promoters, 1 detractor, 4 responses: (2 - 1) / 4 = 25.
    // The average recommendation score is 7.5, which is not NPS at all.
    Assert.areEqual(25, load(null).kpis.nps);
  }

  @IsTest
  static void responseRateCountsOnlyOurOwnInvitations() {
    GxFeedbackDashboardController.Kpis k = load(null).kpis;

    // GXD-6 carries the old flow's SurveySent__c but was never sent this
    // survey. Counting it would drag the rate down for no real reason.
    Assert.areEqual(5, k.invited, 'Five bookings carry Survey_Sent_On__c');
    Assert.areEqual(4, k.answeredInvitations, 'Four of them answered');
    Assert.areEqual(80, k.responseRate, '4 of 5');
  }

  @IsTest
  static void theReminderIsMeasurable() {
    GxFeedbackDashboardController.Kpis k = load(null).kpis;
    Assert.areEqual(1, k.reminded, 'One guest was reminded');
    Assert.areEqual(1, k.answeredAfterReminder, 'And answered because of it');
  }

  // ------------------------------------------------------------------
  // Venues

  @IsTest
  static void venueAveragesLeaveSubRatingsOut() {
    GxFeedbackDashboardController.Venue conrad = find(
      load(null).hotels,
      CONRAD
    );

    // Overall scores 9, 5, 7 -> 7.0. Mixing in the eight sub-ratings would
    // give 7.2 and mean nothing.
    Assert.areEqual(7.0, conrad.average, 'Overall scores only');
    Assert.areEqual(3, conrad.ratings, 'Three guests rated it');
  }

  @IsTest
  static void aVenueWithTooFewRatingsIsListedButNotRanked() {
    List<GxFeedbackDashboardController.Venue> hotels = load(null).hotels;

    Assert.areEqual(
      CONRAD,
      hotels[0].name,
      'Conrad at 7.0 from three guests ranks above Finca at 10.0 from one'
    );
    Assert.isTrue(hotels[0].ranked, 'Three ratings is enough');
    Assert.areEqual(FINCA, hotels[1].name, 'Finca is still shown');
    Assert.isFalse(hotels[1].ranked, 'But one rating is not enough to rank');
  }

  @IsTest
  static void suppliersAreRankedByName() {
    GxFeedbackDashboardController.Venue lh = find(
      load(null).suppliers,
      LUFTHANSA
    );
    Assert.isNotNull(lh, 'Airlines appear under their own name');
    Assert.areEqual(7.0, lh.average, '(8 + 6) / 2');
    Assert.isFalse(lh.ranked, 'Two ratings is below the ranking minimum');
  }

  @IsTest
  static void theHotelDetailGridAlwaysHasFourColumnsInOrder() {
    List<GxFeedbackDashboardController.HeatRow> rows = load(null).hotelDetail;

    Assert.areEqual(1, rows.size(), 'Only Conrad has sub-ratings');
    List<GxFeedbackDashboardController.HeatCell> cells = rows[0].cells;
    Assert.areEqual('Room', cells[0].subCategory, 'Fixed order');
    Assert.areEqual('Cleanliness', cells[3].subCategory, 'Fixed order');
    Assert.areEqual(6.0, cells[0].average, 'Room (8 + 4) / 2');
    Assert.areEqual(7.5, cells[1].average, 'Service (9 + 6) / 2');
    Assert.areEqual(8.0, cells[2].average, 'Catering (9 + 7) / 2');
    Assert.areEqual(7.5, cells[3].average, 'Cleanliness (10 + 5) / 2');
  }

  // ------------------------------------------------------------------
  // Filters

  @IsTest
  static void aRegionFilterNarrowsEverything() {
    GxFeedbackDashboardController.Dashboard d = load(
      new Map<String, Object>{ 'region' => 'Mallorca' }
    );
    Assert.areEqual(1, d.kpis.responses, 'Only GXD-5 answered in Mallorca');
    Assert.areEqual(2, d.kpis.invited, 'GXD-4 and GXD-5 were invited');
    Assert.areEqual(50, d.kpis.responseRate, '1 of 2');
    Assert.areEqual(1, d.hotels.size(), 'Only Finca');
    Assert.areEqual(FINCA, d.hotels[0].name, 'Only Finca');
  }

  @IsTest
  static void aDateFilterWorksOnTheTripEndDate() {
    GxFeedbackDashboardController.Dashboard d = load(
      new Map<String, Object>{ 'fromDate' => Date.today().addDays(-25) }
    );
    Assert.areEqual(2, d.kpis.responses, 'GXD-3 and GXD-5 ended in the window');
    Assert.areEqual(3, d.kpis.invited, 'GXD-3, GXD-4 and GXD-5');
  }

  @IsTest
  static void aCategoryFilterNarrowsTheVenuesButNotTheTrip() {
    GxFeedbackDashboardController.Dashboard d = load(
      new Map<String, Object>{ 'category' => 'Golfclub' }
    );
    Assert.areEqual(
      4,
      d.kpis.responses,
      'NPS is about the whole trip, not the golf'
    );
    Assert.isTrue(d.hotels.isEmpty(), 'No hotels when looking at golf');
    Assert.isTrue(d.hotelDetail.isEmpty(), 'Nor hotel detail');
    Assert.areEqual(QUINTA, d.golf[0].name, 'The golf is there');
  }

  @IsTest
  static void aTravelTypeFilterAppliesToo() {
    Assert.areEqual(
      0,
      load(new Map<String, Object>{ 'travelType' => 'NONE' }).kpis.responses,
      'A travel type no trip has returns nothing'
    );
  }

  @IsTest
  static void unreadableFiltersAreReportedNotIgnored() {
    try {
      GxFeedbackDashboardController.getDashboard('{not json');
      Assert.fail('A broken filter must not silently show unfiltered data');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage(), 'It says why');
    }
  }

  @IsTest
  static void onlyValuesThatOccurAreOfferedAsFilters() {
    GxFeedbackDashboardController.FilterOptions o = GxFeedbackDashboardController.getFilterOptions();

    Set<String> regions = new Set<String>();
    for (GxFeedbackDashboardController.Option x : o.regions) {
      regions.add(x.value);
    }
    Assert.isTrue(
      regions.contains('Algarve') && regions.contains('Mallorca'),
      'Both surveyed regions are offered: ' + regions
    );
    Assert.areEqual(2, regions.size(), 'And no region nobody has been to');
  }

  // ------------------------------------------------------------------
  // Follow-up, next destinations, comments

  @IsTest
  static void detractorsAreListedForFollowUp() {
    GxFeedbackDashboardController.Dashboard d = load(null);
    Assert.areEqual(1, d.followUps.size(), 'The one detractor');
    Assert.areEqual('GXD-2', d.followUps[0].bookingNumber, 'GXD-2');
    Assert.areEqual('Zu laut', d.followUps[0].comment, 'With what they said');
    Assert.areEqual(1, d.kpis.openFollowUps, 'And counted as open work');
  }

  @IsTest
  static void followingUpRecordsWhoAndWhenAndClosesTheCase() {
    Id responseId = load(null).followUps[0].responseId;

    GxFeedbackDashboardController.updateFollowUp(
      responseId,
      'Contacted',
      '  Angerufen  '
    );

    Feedback_Response__c r = [
      SELECT
        Follow_Up_Status__c,
        Follow_Up_Note__c,
        Follow_Up_By__c,
        Follow_Up_On__c
      FROM Feedback_Response__c
      WHERE Id = :responseId
    ];
    Assert.areEqual('Contacted', r.Follow_Up_Status__c, 'Status saved');
    Assert.areEqual('Angerufen', r.Follow_Up_Note__c, 'Note saved, trimmed');
    Assert.areEqual(
      UserInfo.getUserId(),
      r.Follow_Up_By__c,
      'Who, set server-side'
    );
    Assert.isNotNull(r.Follow_Up_On__c, 'When, set server-side');
    Assert.areEqual(0, load(null).kpis.openFollowUps, 'No longer open');
    Assert.areEqual(
      1,
      load(null).followUps.size(),
      'But still listed, with its status'
    );
  }

  @IsTest
  static void anUnknownFollowUpStatusIsRefused() {
    Id responseId = load(null).followUps[0].responseId;
    try {
      GxFeedbackDashboardController.updateFollowUp(
        responseId,
        'Forgotten',
        null
      );
      Assert.fail('Only Open, Contacted and Resolved are allowed');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage(), 'It says why');
    }
  }

  @IsTest
  static void nextDestinationsListPromotersFirst() {
    List<GxFeedbackDashboardController.ResponseRow> rows = load(null)
      .nextDestinations;
    Assert.areEqual(2, rows.size(), 'Two guests said where they want to go');
    Assert.areEqual('Schottland', rows[0].nextDestination, 'NPS 10 first');
    Assert.areEqual('Japan', rows[1].nextDestination, 'Then NPS 9');
  }

  @IsTest
  static void commentsComeFromResponsesAndRatingsAndSkipBlanks() {
    Set<String> texts = new Set<String>();
    for (GxFeedbackDashboardController.CommentRow c : load(null).comments) {
      texts.add(c.text);
    }
    Assert.isTrue(texts.contains('Zu laut'), 'From the response');
    Assert.isTrue(texts.contains('Laut'), 'From a hotel rating');
    Assert.isTrue(texts.contains('Verspätet'), 'From an airline rating');
    Assert.areEqual(3, texts.size(), 'And nothing blank');
  }

  @IsTest
  static void aVenueDrillsDownToEachGuest() {
    List<GxFeedbackDashboardController.VenueRating> rows = GxFeedbackDashboardController.getVenueDetail(
      null,
      'Hotel',
      CONRAD
    );

    Assert.areEqual(3, rows.size(), 'One row per guest who rated Conrad');
    Integer withBreakdown = 0;
    for (GxFeedbackDashboardController.VenueRating r : rows) {
      Assert.isNotNull(r.score, 'Each has an overall score');
      if (r.subScores.size() == 4) {
        withBreakdown++;
      }
    }
    Assert.areEqual(2, withBreakdown, 'Two guests opened the detail panel');
  }

  // ------------------------------------------------------------------
  // Empty and helpers

  @IsTest
  static void anEmptySelectionIsQuietNotBroken() {
    GxFeedbackDashboardController.Dashboard d = load(
      new Map<String, Object>{ 'region' => 'Nowhere' }
    );
    Assert.areEqual(0, d.kpis.responses, 'Nothing answered');
    Assert.isNull(d.kpis.nps, 'No NPS rather than a misleading zero');
    Assert.isNull(d.kpis.responseRate, 'No rate rather than divide-by-zero');
    Assert.isTrue(d.hotels.isEmpty() && d.trend.isEmpty(), 'Nothing to chart');
  }

  @IsTest
  static void bucketBoundariesMatchTheNpsDefinition() {
    Assert.areEqual('promoter', GxFeedbackDashboardController.bucketFor(9));
    Assert.areEqual('passive', GxFeedbackDashboardController.bucketFor(8));
    Assert.areEqual('passive', GxFeedbackDashboardController.bucketFor(7));
    Assert.areEqual('detractor', GxFeedbackDashboardController.bucketFor(6));
    Assert.isNull(GxFeedbackDashboardController.bucketFor(null));
  }

  @IsTest
  static void theTrendGroupsByTripMonth() {
    Integer total = 0;
    for (GxFeedbackDashboardController.MonthPoint m : load(null).trend) {
      total += m.total;
      Assert.areEqual(
        m.promoters + m.passives + m.detractors,
        m.total,
        'Every response lands in exactly one bucket'
      );
    }
    Assert.areEqual(4, total, 'All four responses are in the trend');
  }

  // ------------------------------------------------------------------
  // Volume

  @IsTest
  static void listsWithinTheirCapsSayNothingWasLeftOut() {
    GxFeedbackDashboardController.Dashboard d = load(null);
    Assert.isFalse(d.commentsCapped, 'Every comment was sent');
    Assert.isFalse(d.destinationsCapped, 'Every wish was sent');
    Assert.areEqual(
      d.kpis.detractors,
      d.followUpsTotal,
      'The follow-up total is every detractor in the selection'
    );
  }

  @IsTest
  static void listsBeyondTheirCapsAreCutAndSaySo() {
    GxFeedbackDashboardController.maxComments = 1;
    GxFeedbackDashboardController.maxDestinations = 1;

    GxFeedbackDashboardController.Dashboard d = load(null);

    Assert.areEqual(1, d.comments.size(), 'Comments stop at the cap');
    Assert.isTrue(d.commentsCapped, 'and the page is told more exist');
    Assert.areEqual(1, d.nextDestinations.size(), 'Wishes stop at the cap');
    Assert.areEqual(
      'Schottland',
      d.nextDestinations[0].nextDestination,
      'The happiest guest is the one kept'
    );
    Assert.isTrue(d.destinationsCapped, 'and the page is told more exist');
  }

  @IsTest
  static void aSelectionTooLargeToTotalIsRefusedRatherThanHalfDone() {
    GxFeedbackDashboardController.maxRatingsInView = 5;
    try {
      load(null);
      Assert.fail('Too many ratings to total must be refused up front');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage(), 'It says what to do instead');
    }
  }

  @IsTest
  static void openCasesComeBeforeHandledOnes() {
    Feedback_Response__c handled = [
      SELECT Id
      FROM Feedback_Response__c
      WHERE Booking__r.BookingNumber__c = 'GXD-1'
    ];
    handled.Recommendation_NPS__c = 2;
    handled.Follow_Up_Status__c = 'Resolved';
    // The follow-up fields are only ever written in system mode, as the
    // controller does; a plain update is refused them.
    Database.update(handled, AccessLevel.SYSTEM_MODE);

    List<GxFeedbackDashboardController.ResponseRow> rows = load(null).followUps;

    Assert.areEqual(2, rows.size(), 'Both detractors are listed');
    Assert.areEqual('GXD-2', rows[0].bookingNumber, 'The open case first');
    Assert.areEqual('GXD-1', rows[1].bookingNumber, 'The resolved one after');
  }

  @IsTest
  static void everyCommentKnowsWhichResponseItCameFrom() {
    for (GxFeedbackDashboardController.CommentRow c : load(null).comments) {
      Assert.isNotNull(c.responseId, c.text + ' can open its full response');
    }
  }

  // ------------------------------------------------------------------
  // Full response

  private static Id responseOf(String bookingNumber) {
    return [
      SELECT Id
      FROM Feedback_Response__c
      WHERE Booking__r.BookingNumber__c = :bookingNumber
    ]
    .Id;
  }

  @IsTest
  static void aResponseOpensInFullScreenByScreen() {
    GxFeedbackDashboardController.ResponseDetail d = GxFeedbackDashboardController.getResponseDetail(
      responseOf('GXD-2')
    );

    Assert.areEqual('GXD-2', d.bookingNumber, 'Its booking');
    Assert.areEqual(5, d.overall, 'Screen 1: overall');
    Assert.areEqual(6, d.consultation, 'Screen 1: consultation');
    Assert.areEqual(3, d.recommendation, 'Screen 5: recommendation');
    Assert.areEqual('Detractor', d.npsCategory, 'and what that makes them');
    Assert.areEqual('Zu laut', d.improvementSuggestions, 'Screen 5: words');

    Assert.areEqual(1, d.services.size(), 'Screen 2: the flight');
    Assert.areEqual('Airline', d.services[0].category, 'is the airline');
    Assert.areEqual('Verspätet', d.services[0].comment, 'with its comment');

    Assert.areEqual(1, d.hotels.size(), 'Screen 3: one hotel');
    Assert.areEqual(CONRAD, d.hotels[0].name, 'by name');
    Assert.areEqual(5, d.hotels[0].score, 'with its score');
    Assert.areEqual('Laut', d.hotels[0].comment, 'and comment');
    Assert.areEqual(
      4,
      d.hotels[0].subScores.size(),
      'and its four detail ratings underneath'
    );

    Assert.areEqual(1, d.golf.size(), 'Screen 4: one course');
    Assert.areEqual(QUINTA, d.golf[0].name, 'by name');
  }

  @IsTest
  static void aServiceSavedPerSupplierReadsAsTheOneAnswerItWas() {
    Id responseId = responseOf('GXD-1');
    insert new Feedback_Rating__c(
      Feedback_Response__c = responseId,
      Category__c = 'Airline',
      Item_Name__c = 'Condor',
      Score__c = 8
    );

    GxFeedbackDashboardController.ResponseDetail d = GxFeedbackDashboardController.getResponseDetail(
      responseId
    );

    Assert.areEqual(1, d.services.size(), 'One flight question, one line');
    Assert.areEqual(
      LUFTHANSA + ', Condor',
      d.services[0].name,
      'naming every airline it covered'
    );
  }

  @IsTest
  static void aResponseThatIsGoneIsReportedNotBlank() {
    Id responseId = responseOf('GXD-3');
    delete new Feedback_Response__c(Id = responseId);
    try {
      GxFeedbackDashboardController.getResponseDetail(responseId);
      Assert.fail('A missing response must be reported');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage(), 'It says why');
    }
  }

  // ------------------------------------------------------------------
  // Finding responses

  private static GxFeedbackDashboardController.ResponsePage find(
    Map<String, Object> filters,
    String search,
    String groupName,
    String sortBy,
    Integer page
  ) {
    return GxFeedbackDashboardController.findResponses(
      filters == null ? null : JSON.serialize(filters),
      search,
      groupName,
      sortBy,
      page
    );
  }

  @IsTest
  static void everyResponseIsListedNewestFirst() {
    GxFeedbackDashboardController.ResponsePage p = find(
      null,
      null,
      null,
      null,
      1
    );
    Assert.areEqual(4, p.total, 'All four answers');
    Assert.areEqual(4, p.rows.size(), 'on one page');
    Assert.isFalse(p.searching, 'No search ran');
  }

  @IsTest
  static void aBookingNumberFindsItsResponse() {
    GxFeedbackDashboardController.ResponsePage p = find(
      null,
      'gxd-2',
      null,
      null,
      1
    );
    Assert.areEqual(1, p.total, 'Found regardless of case');
    Assert.areEqual('GXD-2', p.rows[0].bookingNumber, 'The right one');
    Assert.isTrue(p.searching, 'and the page knows a search ran');
  }

  @IsTest
  static void aLastNameFindsTheGuestWhateverTheDates() {
    // The date filter would exclude every trip; a search ignores it, because
    // nobody on the phone with a guest should have to guess the trip date.
    GxFeedbackDashboardController.ResponsePage p = find(
      new Map<String, Object>{
        'fromDate' => String.valueOf(Date.today().addYears(5))
      },
      'Gast',
      null,
      null,
      1
    );
    Assert.areEqual(4, p.total, 'Every answer from Test Gast');
  }

  @IsTest
  static void aFeedbackReferenceFindsItsResponse() {
    String reference = [
      SELECT Name
      FROM Feedback_Response__c
      WHERE Booking__r.BookingNumber__c = 'GXD-5'
    ]
    .Name;
    Assert.areEqual(1, find(null, reference, null, null, 1).total);
  }

  @IsTest
  static void aSearchTermIsMatchedLiterallyNotAsAWildcard() {
    Assert.areEqual(
      0,
      find(null, '%%', null, null, 1).total,
      'Percent signs are text, not match-everything'
    );
    Assert.isFalse(
      find(null, 'G', null, null, 1).searching,
      'One letter is not a search yet'
    );
  }

  @IsTest
  static void theListNarrowsToOneGroupOfGuests() {
    Assert.areEqual(2, find(null, null, 'promoters', null, 1).total);
    Assert.areEqual(1, find(null, null, 'passives', null, 1).total);
    Assert.areEqual(1, find(null, null, 'detractors', null, 1).total);
    Assert.areEqual(1, find(null, null, 'open', null, 1).total);
  }

  @IsTest
  static void lowestFirstPutsTheUnhappiestGuestOnTop() {
    List<GxFeedbackDashboardController.ListRow> rows = find(
        null,
        null,
        null,
        'lowest',
        1
      )
      .rows;
    Assert.areEqual('GXD-2', rows[0].bookingNumber, 'NPS 3 first');
    Assert.areEqual('GXD-1', rows[3].bookingNumber, 'NPS 10 last');
  }

  @IsTest
  static void eachRowSaysWhatStoodOut() {
    GxFeedbackDashboardController.ListRow row = find(
        null,
        'GXD-2',
        null,
        null,
        1
      )
      .rows[0];
    Assert.areEqual(5, row.lowestScore, 'The lowest score in the answer');
    Assert.areEqual('Overall', row.lowestLabel, 'the first question to hit it');
    Assert.areEqual(3, row.comments, 'A suggestion plus two rating comments');
  }

  @IsTest
  static void theListPagesOnTheServer() {
    GxFeedbackDashboardController.responsePageSize = 3;

    GxFeedbackDashboardController.ResponsePage second = find(
      null,
      null,
      null,
      null,
      2
    );
    Assert.areEqual(4, second.total, 'The total covers every page');
    Assert.areEqual(1, second.rows.size(), 'Page two holds the fourth');
    Assert.areEqual(2, second.page, 'on page two');

    Assert.areEqual(
      2,
      find(null, null, null, null, 99).page,
      'A page past the end lands on the last page'
    );
  }

  // ------------------------------------------------------------------
  // Travel designers

  /**
   * Gives one booking the running user as travel designer and clears it on
   * the rest. Set explicitly on every booking, because the org fills the
   * field in by itself when a booking is created.
   */
  private static void assignDesignerTo(String bookingNumber) {
    List<Booking__c> all = [SELECT Id, BookingNumber__c FROM Booking__c];
    for (Booking__c b : all) {
      b.TravelDesigner__c = b.BookingNumber__c == bookingNumber
        ? UserInfo.getUserId()
        : null;
    }
    Database.update(all, AccessLevel.SYSTEM_MODE);
  }

  @IsTest
  static void eachTravelDesignerHasTheirOwnNumbers() {
    assignDesignerTo('GXD-1');

    List<GxFeedbackDashboardController.DesignerRow> rows = load(null).designers;
    Assert.areEqual(2, rows.size(), 'One designer, and the unassigned rest');
    Assert.areEqual('none', rows[0].id, 'Three trips without a designer');
    Assert.areEqual(3, rows[0].responses, 'come first, with the most answers');
    Assert.areEqual(
      String.valueOf(UserInfo.getUserId()),
      rows[1].id,
      'then the designer'
    );
    Assert.areEqual(10, rows[1].consultation, 'with the consultation score');
    Assert.areEqual(100, rows[1].nps, 'and the NPS of their one promoter');

    GxFeedbackDashboardController.Dashboard mine = load(
      new Map<String, Object>{ 'designer' => UserInfo.getUserId() }
    );
    Assert.areEqual(1, mine.kpis.responses, 'The filter narrows everything');

    GxFeedbackDashboardController.Dashboard unassigned = load(
      new Map<String, Object>{ 'designer' => 'none' }
    );
    Assert.areEqual(3, unassigned.kpis.responses, 'and can find the gaps');

    Assert.isTrue(
      GxFeedbackDashboardController.getFilterOptions().designers.size() >= 2,
      'Both are offered as filters'
    );
  }

  @IsTest
  static void anUnreadableDesignerIsRefused() {
    try {
      load(new Map<String, Object>{ 'designer' => 'not-an-id' });
      Assert.fail('A made-up designer must not silently show everything');
    } catch (AuraHandledException e) {
      Assert.isNotNull(e.getMessage(), 'It says why');
    }
  }

  @IsTest
  static void aFullResponseNamesItsTravelDesigner() {
    assignDesignerTo('GXD-1');
    Assert.areEqual(
      UserInfo.getName(),
      GxFeedbackDashboardController.getResponseDetail(responseOf('GXD-1'))
        .designer
    );
  }
}
