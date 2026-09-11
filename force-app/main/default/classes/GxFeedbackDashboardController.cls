/**
 * GxFeedbackDashboardController
 *
 * Everything the feedback dashboard shows, computed server-side in one call.
 *
 * `with sharing`, so a user sees feedback only for bookings they can see.
 * Queries run in system mode for field access: the dashboard is gated by the
 * Golf_Extra_Feedback_Admin permission set, which is where access to guest
 * comments and names is actually decided.
 *
 * Venue scores are aggregated in SOQL rather than loaded row by row, because
 * ratings multiply - a dozen per response - and the dashboard has to keep
 * working at thousands of responses. Responses themselves are one per trip
 * and are loaded as rows.
 *
 * Every filter narrows the bookings, and every number follows from the
 * bookings. The one exception is category, which only narrows the venue
 * sections: NPS and response rate are about the whole trip, not one part of it.
 */
public with sharing class GxFeedbackDashboardController {
  /**
   * Below this many ratings a venue is listed but not ranked. One guest's 10
   * would otherwise beat forty guests averaging 9.4 - and at launch almost
   * every venue has one or two ratings.
   */
  @TestVisible
  private static final Integer MIN_RATINGS = 3;

  private static final Integer PROMOTER_MIN = 9;
  private static final Integer DETRACTOR_MAX = 6;

  /** A comment box only opens at 8 or below, so this bounds the search. */
  private static final Integer COMMENT_SCORE_MAX = 8;

  private static final Integer MAX_COMMENTS = 60;
  private static final Integer MAX_RESPONSES = 2000;

  private static final String HOTEL = 'Hotel';
  private static final String GOLF = 'Golfclub';
  private static final Set<String> SUPPLIER_TYPES = new Set<String>{
    'Airline',
    'TransferCompany',
    'CarRentalCompany'
  };
  private static final List<String> SUB_CATEGORIES = new List<String>{
    'Room',
    'Service',
    'Catering',
    'Cleanliness'
  };

  private static final Set<String> FOLLOW_UP_STATUSES = new Set<String>{
    'Open',
    'Contacted',
    'Resolved'
  };
  private static final Set<String> CLOSED_STATUSES = new Set<String>{
    'Contacted',
    'Resolved'
  };

  // ------------------------------------------------------------------
  // Shapes returned to the component

  public class Filters {
    public Date fromDate;
    public Date toDate;
    public String region;
    public String country;
    public String travelType;
    public String category;
  }

  public class Dashboard {
    @AuraEnabled
    public Kpis kpis = new Kpis();
    @AuraEnabled
    public List<MonthPoint> trend = new List<MonthPoint>();
    @AuraEnabled
    public List<Venue> hotels = new List<Venue>();
    @AuraEnabled
    public List<Venue> golf = new List<Venue>();
    @AuraEnabled
    public List<Venue> suppliers = new List<Venue>();
    @AuraEnabled
    public List<HeatRow> hotelDetail = new List<HeatRow>();
    @AuraEnabled
    public List<ResponseRow> followUps = new List<ResponseRow>();
    @AuraEnabled
    public List<ResponseRow> nextDestinations = new List<ResponseRow>();
    @AuraEnabled
    public List<CommentRow> comments = new List<CommentRow>();
    @AuraEnabled
    public Integer minRatings = MIN_RATINGS;
  }

  public class Kpis {
    @AuraEnabled
    public Integer responses = 0;
    @AuraEnabled
    public Integer invited = 0;
    @AuraEnabled
    public Integer answeredInvitations = 0;
    @AuraEnabled
    public Decimal responseRate;
    @AuraEnabled
    public Integer promoters = 0;
    @AuraEnabled
    public Integer passives = 0;
    @AuraEnabled
    public Integer detractors = 0;
    @AuraEnabled
    public Decimal nps;
    @AuraEnabled
    public Decimal avgOverall;
    @AuraEnabled
    public Decimal avgConsultation;
    @AuraEnabled
    public Integer reminded = 0;
    @AuraEnabled
    public Integer answeredAfterReminder = 0;
    @AuraEnabled
    public Integer openFollowUps = 0;
  }

  public class MonthPoint {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public Integer promoters = 0;
    @AuraEnabled
    public Integer passives = 0;
    @AuraEnabled
    public Integer detractors = 0;
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public Decimal nps;
  }

  public class Venue {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Decimal average;
    @AuraEnabled
    public Integer ratings;
    @AuraEnabled
    public Boolean ranked;
  }

  public class HeatRow {
    @AuraEnabled
    public String hotel;
    @AuraEnabled
    public List<HeatCell> cells = new List<HeatCell>();
  }

  public class HeatCell {
    @AuraEnabled
    public String subCategory;
    @AuraEnabled
    public Decimal average;
    @AuraEnabled
    public Integer ratings = 0;
  }

  public class ResponseRow {
    @AuraEnabled
    public Id responseId;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public Decimal nps;
    @AuraEnabled
    public Decimal overall;
    @AuraEnabled
    public String comment;
    @AuraEnabled
    public String nextDestination;
    @AuraEnabled
    public String followUpStatus;
    @AuraEnabled
    public String followUpNote;
    @AuraEnabled
    public String followUpBy;
    @AuraEnabled
    public Datetime followUpOn;
    @AuraEnabled
    public Datetime submittedOn;
  }

  public class CommentRow {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String text;
    @AuraEnabled
    public String about;
    @AuraEnabled
    public Decimal score;
    /**
     * What `score` is: 'score' for a 1-10 rating of the thing commented on,
     * 'nps' where the only number to hand is the guest's recommendation
     * answer. They look alike and mean different things, so the page labels
     * and colours them differently.
     */
    @AuraEnabled
    public String scoreKind;
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public Datetime submittedOn;
  }

  public class VenueRating {
    @AuraEnabled
    public Id responseId;
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public Datetime submittedOn;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public String comment;
    @AuraEnabled
    public List<HeatCell> subScores = new List<HeatCell>();
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class FilterOptions {
    @AuraEnabled
    public List<Option> regions = new List<Option>();
    @AuraEnabled
    public List<Option> countries = new List<Option>();
    @AuraEnabled
    public List<Option> travelTypes = new List<Option>();
  }

  // ------------------------------------------------------------------
  // Entry points

  @AuraEnabled(cacheable=true)
  public static Dashboard getDashboard(String filtersJson) {
    Filters f = parse(filtersJson);
    Dashboard d = new Dashboard();

    List<Feedback_Response__c> responses = loadResponses(f);
    applyResponses(d, responses);
    countInvitations(d.kpis, f);
    applyVenues(d, f);
    d.hotelDetail = hotelDetail(f);
    d.comments = comments(f, responses);
    return d;
  }

  /** Every rating a venue received, grouped by the guest who gave it. */
  @AuraEnabled(cacheable=true)
  public static List<VenueRating> getVenueDetail(
    String filtersJson,
    String category,
    String itemName
  ) {
    Filters f = parse(filtersJson);
    Map<String, Object> binds = new Map<String, Object>{
      'category' => category,
      'itemName' => itemName
    };
    List<String> clauses = new List<String>{
      'Category__c = :category',
      'Item_Name__c = :itemName'
    };
    clauses.addAll(
      bookingClauses('Feedback_Response__r.Booking__r.', f, binds)
    );

    Map<Id, VenueRating> byResponse = new Map<Id, VenueRating>();
    for (
      Feedback_Rating__c r : (List<Feedback_Rating__c>) Database.queryWithBinds(
        'SELECT Score__c, Sub_Category__c, Comment__c, Feedback_Response__c, ' +
          'Feedback_Response__r.Booking__c, ' +
          'Feedback_Response__r.Booking__r.BookingNumber__c, ' +
          'Feedback_Response__r.Contact__r.Name, ' +
          'Feedback_Response__r.Submitted_On__c ' +
          'FROM Feedback_Rating__c WHERE ' +
          String.join(clauses, ' AND ') +
          ' ORDER BY Feedback_Response__r.Submitted_On__c DESC LIMIT 500',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      VenueRating v = byResponse.get(r.Feedback_Response__c);
      if (v == null) {
        v = new VenueRating();
        v.responseId = r.Feedback_Response__c;
        v.bookingId = r.Feedback_Response__r.Booking__c;
        v.bookingNumber = r.Feedback_Response__r.Booking__r.BookingNumber__c;
        v.guest = r.Feedback_Response__r.Contact__r?.Name;
        v.submittedOn = r.Feedback_Response__r.Submitted_On__c;
        byResponse.put(r.Feedback_Response__c, v);
      }
      if (String.isBlank(r.Sub_Category__c)) {
        v.score = r.Score__c;
        v.comment = r.Comment__c;
      } else {
        HeatCell c = new HeatCell();
        c.subCategory = r.Sub_Category__c;
        c.average = r.Score__c;
        c.ratings = 1;
        v.subScores.add(c);
      }
    }
    return byResponse.values();
  }

  /** Only the values that actually occur on surveyed trips - no dead options. */
  @AuraEnabled(cacheable=true)
  public static FilterOptions getFilterOptions() {
    Set<String> regions = new Set<String>();
    Set<String> countries = new Set<String>();
    Set<String> types = new Set<String>();
    for (AggregateResult ar : [
      SELECT
        Booking__r.Region__c region,
        Booking__r.DestinationCountry__c country,
        Booking__r.Travel_Type__c travelType,
        COUNT(Id) n
      FROM Feedback_Response__c
      GROUP BY
        Booking__r.Region__c,
        Booking__r.DestinationCountry__c,
        Booking__r.Travel_Type__c
    ]) {
      addIfPresent(regions, ar.get('region'));
      addIfPresent(countries, ar.get('country'));
      addIfPresent(types, ar.get('travelType'));
    }

    FilterOptions o = new FilterOptions();
    o.regions = labelled(Booking__c.Region__c, regions);
    o.countries = labelled(Booking__c.DestinationCountry__c, countries);
    o.travelTypes = labelled(Booking__c.Travel_Type__c, types);
    return o;
  }

  /**
   * Records what the team did about an unhappy guest, and who did it. Who and
   * when are set here rather than trusted from the page.
   */
  @AuraEnabled
  public static void updateFollowUp(Id responseId, String status, String note) {
    if (responseId == null) {
      throw new AuraHandledException('No feedback response was given.');
    }
    if (String.isNotBlank(status) && !FOLLOW_UP_STATUSES.contains(status)) {
      throw new AuraHandledException('Unknown follow-up status: ' + status);
    }
    // System mode for field access, like every query in this class: whether a
    // user may follow up is decided by the permission set that grants this
    // controller, and Follow_Up_By__c / Follow_Up_On__c are deliberately not
    // editable by hand. Record access still follows `with sharing`.
    Database.update(
      new Feedback_Response__c(
        Id = responseId,
        Follow_Up_Status__c = String.isBlank(status) ? null : status,
        Follow_Up_Note__c = String.isBlank(note)
          ? null
          : note.trim().left(2000),
        Follow_Up_By__c = UserInfo.getUserId(),
        Follow_Up_On__c = Datetime.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  // ------------------------------------------------------------------
  // Responses: KPIs, trend, follow-ups, next destinations

  private static List<Feedback_Response__c> loadResponses(Filters f) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    return (List<Feedback_Response__c>) Database.queryWithBinds(
      'SELECT Id, Name, Overall_Experience__c, Consultation_Rating__c, ' +
        'Recommendation_NPS__c, Next_Destination__c, Improvement_Suggestions__c, ' +
        'Overall_Experience_Comment__c, Consultation_Comment__c, ' +
        'General_Hotel_Comment__c, General_Golf_Comment__c, General_Feedback__c, ' +
        'Follow_Up_Status__c, Follow_Up_Note__c, Follow_Up_On__c, Follow_Up_By__r.Name, ' +
        'Submitted_On__c, Contact__r.Name, Booking__c, Booking__r.BookingNumber__c, ' +
        'Booking__r.End_Date__c, Booking__r.Survey_Sent_On__c, ' +
        'Booking__r.Survey_Reminder_Sent__c ' +
        'FROM Feedback_Response__c' +
        (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
        ' ORDER BY Submitted_On__c DESC LIMIT ' +
        MAX_RESPONSES,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void applyResponses(
    Dashboard d,
    List<Feedback_Response__c> responses
  ) {
    Kpis k = d.kpis;
    Map<String, MonthPoint> months = new Map<String, MonthPoint>();
    Decimal overallSum = 0, consultSum = 0;
    Integer overallN = 0, consultN = 0;

    for (Feedback_Response__c r : responses) {
      k.responses++;
      Integer score = r.Recommendation_NPS__c == null
        ? null
        : r.Recommendation_NPS__c.intValue();
      String bucket = bucketFor(score);
      if (bucket == 'promoter') {
        k.promoters++;
      } else if (bucket == 'passive') {
        k.passives++;
      } else if (bucket == 'detractor') {
        k.detractors++;
      }

      if (r.Overall_Experience__c != null) {
        overallSum += r.Overall_Experience__c;
        overallN++;
      }
      if (r.Consultation_Rating__c != null) {
        consultSum += r.Consultation_Rating__c;
        consultN++;
      }
      if (r.Booking__r?.Survey_Sent_On__c != null) {
        k.answeredInvitations++;
      }
      // Reminders only ever go to guests who had not answered, so any answer
      // on a reminded booking arrived after the reminder.
      if (r.Booking__r?.Survey_Reminder_Sent__c == true) {
        k.answeredAfterReminder++;
      }

      addToMonth(months, r, bucket);

      if (
        bucket == 'detractor' &&
        !CLOSED_STATUSES.contains(r.Follow_Up_Status__c)
      ) {
        k.openFollowUps++;
      }
      if (bucket == 'detractor') {
        d.followUps.add(toRow(r));
      }
      if (String.isNotBlank(r.Next_Destination__c)) {
        d.nextDestinations.add(toRow(r));
      }
    }

    k.nps = npsOf(k.promoters, k.detractors, k.responses);
    k.avgOverall = overallN == 0 ? null : (overallSum / overallN).setScale(1);
    k.avgConsultation = consultN == 0
      ? null
      : (consultSum / consultN).setScale(1);

    List<String> keys = new List<String>(months.keySet());
    keys.sort();
    for (String key : keys) {
      MonthPoint m = months.get(key);
      m.nps = npsOf(m.promoters, m.detractors, m.total);
      d.trend.add(m);
    }

    // Promoters first: they are the warmest leads for a next trip.
    d.nextDestinations.sort(new ByNpsDescending());
  }

  private static void addToMonth(
    Map<String, MonthPoint> months,
    Feedback_Response__c r,
    String bucket
  ) {
    Date tripEnd = r.Booking__r?.End_Date__c;
    if (tripEnd == null) {
      return;
    }
    String key =
      String.valueOf(tripEnd.year()) +
      '-' +
      String.valueOf(tripEnd.month()).leftPad(2, '0');
    MonthPoint m = months.get(key);
    if (m == null) {
      m = new MonthPoint();
      m.key = key;
      m.year = tripEnd.year();
      m.month = tripEnd.month();
      months.put(key, m);
    }
    m.total++;
    if (bucket == 'promoter') {
      m.promoters++;
    } else if (bucket == 'passive') {
      m.passives++;
    } else if (bucket == 'detractor') {
      m.detractors++;
    }
  }

  /**
   * Invitations are counted from Survey_Sent_On__c, not SurveySent__c. The
   * latter predates this project and was set by the old survey flow too, so it
   * would count guests who were never sent this survey and drag the response
   * rate down for reasons that have nothing to do with it.
   */
  private static void countInvitations(Kpis k, Filters f) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('', f, binds);

    List<String> invited = clauses.clone();
    invited.add('Survey_Sent_On__c != null');
    k.invited = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Booking__c WHERE ' + String.join(invited, ' AND '),
      binds,
      AccessLevel.SYSTEM_MODE
    );

    List<String> reminded = clauses.clone();
    reminded.add('Survey_Reminder_Sent__c = true');
    k.reminded = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Booking__c WHERE ' + String.join(reminded, ' AND '),
      binds,
      AccessLevel.SYSTEM_MODE
    );

    k.responseRate = k.invited == 0
      ? null
      : Math.min(
          (Decimal) 100,
          (Decimal.valueOf(k.answeredInvitations) / k.invited * 100).setScale(0)
        );
  }

  // ------------------------------------------------------------------
  // Venues

  /**
   * Overall venue scores only. Sub-ratings are excluded here, or a hotel's
   * overall score would be averaged together with its room and catering
   * scores - which is exactly the mistake the report builder invites.
   */
  private static void applyVenues(Dashboard d, Filters f) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = new List<String>{ 'Sub_Category__c = null' };
    clauses.addAll(
      bookingClauses('Feedback_Response__r.Booking__r.', f, binds)
    );
    if (String.isNotBlank(f.category)) {
      clauses.add('Category__c = :category');
      binds.put('category', f.category);
    }

    for (
      AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Category__c category, Item_Name__c item, ' +
          'AVG(Score__c) average, COUNT(Id) n ' +
          'FROM Feedback_Rating__c WHERE ' +
          String.join(clauses, ' AND ') +
          ' GROUP BY Category__c, Item_Name__c',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      Venue v = new Venue();
      v.category = (String) ar.get('category');
      v.name = (String) ar.get('item');
      v.average = ((Decimal) ar.get('average')).setScale(1);
      v.ratings = (Integer) ar.get('n');
      v.ranked = v.ratings >= MIN_RATINGS;

      if (v.category == HOTEL) {
        d.hotels.add(v);
      } else if (v.category == GOLF) {
        d.golf.add(v);
      } else if (SUPPLIER_TYPES.contains(v.category)) {
        d.suppliers.add(v);
      }
    }
    d.hotels.sort(new ByRankThenScore());
    d.golf.sort(new ByRankThenScore());
    d.suppliers.sort(new ByRankThenScore());
  }

  private static List<HeatRow> hotelDetail(Filters f) {
    if (String.isNotBlank(f.category) && f.category != HOTEL) {
      return new List<HeatRow>();
    }
    Map<String, Object> binds = new Map<String, Object>{ 'hotel' => HOTEL };
    List<String> clauses = new List<String>{
      'Category__c = :hotel',
      'Sub_Category__c != null'
    };
    clauses.addAll(
      bookingClauses('Feedback_Response__r.Booking__r.', f, binds)
    );

    Map<String, Map<String, HeatCell>> byHotel = new Map<String, Map<String, HeatCell>>();
    for (
      AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Item_Name__c item, Sub_Category__c sub, ' +
          'AVG(Score__c) average, COUNT(Id) n ' +
          'FROM Feedback_Rating__c WHERE ' +
          String.join(clauses, ' AND ') +
          ' GROUP BY Item_Name__c, Sub_Category__c',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      String hotel = (String) ar.get('item');
      if (!byHotel.containsKey(hotel)) {
        byHotel.put(hotel, new Map<String, HeatCell>());
      }
      HeatCell c = new HeatCell();
      c.subCategory = (String) ar.get('sub');
      c.average = ((Decimal) ar.get('average')).setScale(1);
      c.ratings = (Integer) ar.get('n');
      byHotel.get(hotel).put(c.subCategory, c);
    }

    List<String> hotels = new List<String>(byHotel.keySet());
    hotels.sort();
    List<HeatRow> rows = new List<HeatRow>();
    for (String hotel : hotels) {
      HeatRow row = new HeatRow();
      row.hotel = hotel;
      // Always four cells in a fixed order, so the grid lines up even where a
      // hotel is missing a sub-category.
      for (String sub : SUB_CATEGORIES) {
        HeatCell c = byHotel.get(hotel).get(sub);
        if (c == null) {
          c = new HeatCell();
          c.subCategory = sub;
        }
        row.cells.add(c);
      }
      rows.add(row);
    }
    return rows;
  }

  // ------------------------------------------------------------------
  // Comments

  /**
   * The words behind the scores, newest first, from both places they live:
   * the free-text fields on each response, and the comment on each individual
   * rating. Long text fields cannot be filtered in SOQL, so blanks are dropped
   * here; ratings are narrowed to 8 and below first, since a comment box only
   * opens at those scores.
   */
  private static List<CommentRow> comments(
    Filters f,
    List<Feedback_Response__c> responses
  ) {
    List<CommentRow> rows = new List<CommentRow>();

    if (String.isBlank(f.category)) {
      for (Feedback_Response__c r : responses) {
        addComment(
          rows,
          r,
          r.Overall_Experience_Comment__c,
          'Overall experience',
          r.Overall_Experience__c,
          'overall'
        );
        addComment(
          rows,
          r,
          r.Consultation_Comment__c,
          'Consultation',
          r.Consultation_Rating__c,
          'consult'
        );
        addComment(
          rows,
          r,
          r.General_Hotel_Comment__c,
          'Hotels in general',
          null,
          'hotels'
        );
        addComment(
          rows,
          r,
          r.General_Golf_Comment__c,
          'Golf in general',
          null,
          'golf'
        );
        addComment(
          rows,
          r,
          r.Improvement_Suggestions__c,
          'Suggestions',
          r.Recommendation_NPS__c,
          'suggest'
        );
        addComment(rows, r, r.General_Feedback__c, 'Other', null, 'other');
      }
    }

    Map<String, Object> binds = new Map<String, Object>{
      'scoreMax' => COMMENT_SCORE_MAX
    };
    List<String> clauses = new List<String>{ 'Score__c <= :scoreMax' };
    clauses.addAll(
      bookingClauses('Feedback_Response__r.Booking__r.', f, binds)
    );
    if (String.isNotBlank(f.category)) {
      clauses.add('Category__c = :category');
      binds.put('category', f.category);
    }
    for (
      Feedback_Rating__c r : (List<Feedback_Rating__c>) Database.queryWithBinds(
        'SELECT Id, Item_Name__c, Sub_Category__c, Score__c, Comment__c, ' +
          'Feedback_Response__r.Booking__c, ' +
          'Feedback_Response__r.Booking__r.BookingNumber__c, ' +
          'Feedback_Response__r.Contact__r.Name, ' +
          'Feedback_Response__r.Submitted_On__c ' +
          'FROM Feedback_Rating__c WHERE ' +
          String.join(clauses, ' AND ') +
          ' ORDER BY Feedback_Response__r.Submitted_On__c DESC LIMIT 500',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      if (String.isBlank(r.Comment__c)) {
        continue;
      }
      CommentRow c = new CommentRow();
      c.key = r.Id;
      c.text = r.Comment__c;
      c.about = String.isBlank(r.Sub_Category__c)
        ? r.Item_Name__c
        : r.Item_Name__c + ' · ' + r.Sub_Category__c;
      c.score = r.Score__c;
      c.scoreKind = 'score';
      c.bookingId = r.Feedback_Response__r.Booking__c;
      c.bookingNumber = r.Feedback_Response__r.Booking__r.BookingNumber__c;
      c.guest = r.Feedback_Response__r.Contact__r?.Name;
      c.submittedOn = r.Feedback_Response__r.Submitted_On__c;
      rows.add(c);
    }

    rows.sort(new ByNewest());
    while (rows.size() > MAX_COMMENTS) {
      rows.remove(rows.size() - 1);
    }
    return rows;
  }

  private static void addComment(
    List<CommentRow> rows,
    Feedback_Response__c r,
    String text,
    String about,
    Decimal score,
    String suffix
  ) {
    if (String.isBlank(text)) {
      return;
    }
    CommentRow c = new CommentRow();
    c.key = r.Id + '-' + suffix;
    c.text = text;
    c.about = about;
    c.score = score;
    // Suggestions sit on the closing screen beside the recommendation
    // question, so the number beside them is an NPS answer, not a rating.
    c.scoreKind = score == null
      ? null
      : (suffix == 'suggest' ? 'nps' : 'score');
    c.bookingId = r.Booking__c;
    c.bookingNumber = r.Booking__r?.BookingNumber__c;
    c.guest = r.Contact__r?.Name;
    c.submittedOn = r.Submitted_On__c;
    rows.add(c);
  }

  // ------------------------------------------------------------------
  // Helpers

  /**
   * The same booking filter, spelled for whichever object the query starts
   * from. `prefix` is the path to Booking__c: empty from Booking__c itself,
   * 'Booking__r.' from a response, two hops from a rating.
   */
  @TestVisible
  private static List<String> bookingClauses(
    String prefix,
    Filters f,
    Map<String, Object> binds
  ) {
    List<String> clauses = new List<String>();
    if (f.fromDate != null) {
      clauses.add(prefix + 'End_Date__c >= :fromDate');
      binds.put('fromDate', f.fromDate);
    }
    if (f.toDate != null) {
      clauses.add(prefix + 'End_Date__c <= :toDate');
      binds.put('toDate', f.toDate);
    }
    if (String.isNotBlank(f.region)) {
      clauses.add(prefix + 'Region__c = :region');
      binds.put('region', f.region);
    }
    if (String.isNotBlank(f.country)) {
      clauses.add(prefix + 'DestinationCountry__c = :country');
      binds.put('country', f.country);
    }
    if (String.isNotBlank(f.travelType)) {
      clauses.add(prefix + 'Travel_Type__c = :travelType');
      binds.put('travelType', f.travelType);
    }
    return clauses;
  }

  private static Filters parse(String filtersJson) {
    if (String.isBlank(filtersJson)) {
      return new Filters();
    }
    try {
      Filters f = (Filters) JSON.deserialize(filtersJson, Filters.class);
      return f == null ? new Filters() : f;
    } catch (Exception e) {
      throw new AuraHandledException(
        'The dashboard filters could not be read.'
      );
    }
  }

  @TestVisible
  private static String bucketFor(Integer score) {
    if (score == null) {
      return null;
    }
    if (score >= PROMOTER_MIN) {
      return 'promoter';
    }
    return score <= DETRACTOR_MAX ? 'detractor' : 'passive';
  }

  /** Percentage of promoters minus percentage of detractors. Not an average. */
  @TestVisible
  private static Decimal npsOf(
    Integer promoters,
    Integer detractors,
    Integer total
  ) {
    if (total == null || total == 0) {
      return null;
    }
    return (Decimal.valueOf(promoters - detractors) / total * 100).setScale(0);
  }

  private static ResponseRow toRow(Feedback_Response__c r) {
    ResponseRow row = new ResponseRow();
    row.responseId = r.Id;
    row.reference = r.Name;
    row.bookingId = r.Booking__c;
    row.bookingNumber = r.Booking__r?.BookingNumber__c;
    row.guest = r.Contact__r?.Name;
    row.nps = r.Recommendation_NPS__c;
    row.overall = r.Overall_Experience__c;
    row.comment = firstNonBlank(
      new List<String>{
        r.Improvement_Suggestions__c,
        r.Overall_Experience_Comment__c,
        r.Consultation_Comment__c,
        r.General_Feedback__c
      }
    );
    row.nextDestination = r.Next_Destination__c;
    row.followUpStatus = r.Follow_Up_Status__c;
    row.followUpNote = r.Follow_Up_Note__c;
    row.followUpBy = r.Follow_Up_By__r?.Name;
    row.followUpOn = r.Follow_Up_On__c;
    row.submittedOn = r.Submitted_On__c;
    return row;
  }

  private static String firstNonBlank(List<String> values) {
    for (String v : values) {
      if (String.isNotBlank(v)) {
        return v;
      }
    }
    return null;
  }

  private static void addIfPresent(Set<String> target, Object value) {
    if (value != null && String.isNotBlank(String.valueOf(value))) {
      target.add(String.valueOf(value));
    }
  }

  private static List<Option> labelled(
    Schema.SObjectField field,
    Set<String> present
  ) {
    List<Option> out = new List<Option>();
    for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
      if (present.contains(e.getValue())) {
        out.add(new Option(e.getLabel(), e.getValue()));
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Orderings

  private class ByRankThenScore implements Comparator<Venue> {
    public Integer compare(Venue a, Venue b) {
      if (a.ranked != b.ranked) {
        return a.ranked ? -1 : 1;
      }
      if (a.average != b.average) {
        return a.average > b.average ? -1 : 1;
      }
      if (a.ratings != b.ratings) {
        return a.ratings > b.ratings ? -1 : 1;
      }
      return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
    }
  }

  private class ByNpsDescending implements Comparator<ResponseRow> {
    public Integer compare(ResponseRow a, ResponseRow b) {
      Decimal x = a.nps == null ? -1 : a.nps;
      Decimal y = b.nps == null ? -1 : b.nps;
      return x == y ? 0 : (x > y ? -1 : 1);
    }
  }

  private class ByNewest implements Comparator<CommentRow> {
    public Integer compare(CommentRow a, CommentRow b) {
      if (a.submittedOn == b.submittedOn) {
        return 0;
      }
      if (a.submittedOn == null) {
        return 1;
      }
      if (b.submittedOn == null) {
        return -1;
      }
      return a.submittedOn > b.submittedOn ? -1 : 1;
    }
  }
}
