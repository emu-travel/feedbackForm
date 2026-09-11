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
}
