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
 * Every number is counted or averaged in SOQL rather than from loaded rows, so
 * it stays right however many responses a selection covers. Rows are loaded
 * only for what has to be read - follow-ups, next destinations, comments -
 * and each of those is capped, with the cap reported so the page can say so.
 * The page pages through what it receives.
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

  /** Caps on rows sent to the page. The page pages through them 10 at a time. */
  @TestVisible
  private static Integer maxComments = 300;
  @TestVisible
  private static Integer maxFollowUps = 500;
  @TestVisible
  private static Integer maxDestinations = 500;

  /** Newest responses read for their free text (comments, next destinations). */
  private static final Integer MAX_RESPONSES = 2000;

  /**
   * Averages count every rating they cover against the 50,000-row limit per
   * request. Beyond this many in one selection the page asks for narrower
   * dates rather than failing half way. At ~10 ratings per response this is
   * about 4,000 responses in one view.
   */
  @TestVisible
  private static Integer maxRatingsInView = 40000;

  /** The response list is paged on the server, this many rows at a time. */
  @TestVisible
  private static Integer responsePageSize = 10;

  /** SOQL cannot skip further than this, so deeper pages ask for a search. */
  private static final Integer MAX_OFFSET = 2000;

  /** Most responses one export file holds; more asks for narrower dates. */
  @TestVisible
  private static Integer maxExport = 1000;

  /** The designer filter's value for trips with no travel designer set. */
  private static final String NO_DESIGNER = 'none';

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
    /** A User Id, or 'none' for trips without a travel designer. */
    public String designer;
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

    /** Every detractor in the selection; followUps may hold fewer. */
    @AuraEnabled
    public Integer followUpsTotal = 0;
    /** True when there were more comments than were sent. */
    @AuraEnabled
    public Boolean commentsCapped = false;
    /** True when older next-destination wishes were left out. */
    @AuraEnabled
    public Boolean destinationsCapped = false;

    /** How each travel designer's guests rated the trip and our advice. */
    @AuraEnabled
    public List<DesignerRow> designers = new List<DesignerRow>();
  }

  public class DesignerRow {
    /** The designer filter value: a User Id, or 'none'. */
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer responses = 0;
    @AuraEnabled
    public Decimal consultation;
    @AuraEnabled
    public Integer promoters = 0;
    @AuraEnabled
    public Integer detractors = 0;
    @AuraEnabled
    public Decimal nps;
  }

  /** One page of the response list. */
  public class ResponsePage {
    @AuraEnabled
    public List<ListRow> rows = new List<ListRow>();
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public Integer page = 1;
    @AuraEnabled
    public Integer pageSize;
    /** True when a search ran: it covers every response, whatever the filters. */
    @AuraEnabled
    public Boolean searching = false;
    /** True when there are more rows than paging can reach. */
    @AuraEnabled
    public Boolean capped = false;
  }

  /** A spreadsheet of responses, ready to download. */
  public class ExportResult {
    @AuraEnabled
    public String csv;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public Integer rows = 0;
    @AuraEnabled
    public Integer total = 0;
    /** True when the selection held more than one file takes. */
    @AuraEnabled
    public Boolean capped = false;
  }

  /** A guest who was invited and has not answered yet. */
  public class WaitingRow {
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public String designer;
    @AuraEnabled
    public String region;
    @AuraEnabled
    public Date tripEnd;
    /** When they were last asked: the invitation, or the reminder. */
    @AuraEnabled
    public Datetime lastSent;
    @AuraEnabled
    public Boolean reminded = false;
    @AuraEnabled
    public Date reminderDue;
    @AuraEnabled
    public Date expiresOn;
    /** 'waiting', 'reminded' or 'expired'. */
    @AuraEnabled
    public String state;
  }

  public class WaitingPage {
    @AuraEnabled
    public List<WaitingRow> rows = new List<WaitingRow>();
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public Integer page = 1;
    @AuraEnabled
    public Integer pageSize;
  }

  /** A response as a list row: who, which trip, and what stood out. */
  public class ListRow {
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
    public String designer;
    @AuraEnabled
    public String region;
    @AuraEnabled
    public Date tripEnd;
    @AuraEnabled
    public Datetime submittedOn;
    @AuraEnabled
    public Decimal nps;
    @AuraEnabled
    public Decimal overall;
    /** The lowest score anywhere in the answer, and what it was for. */
    @AuraEnabled
    public String lowestLabel;
    @AuraEnabled
    public Decimal lowestScore;
    /** How many things the guest wrote in their own words. */
    @AuraEnabled
    public Integer comments = 0;
    @AuraEnabled
    public String followUpStatus;
    @AuraEnabled
    public Boolean reviewPrompted = false;
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
    public Id responseId;
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

  /** One whole survey answer, in the order the guest filled it in. */
  public class ResponseDetail {
    @AuraEnabled
    public Id responseId;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public Datetime submittedOn;
    @AuraEnabled
    public String language;
    @AuraEnabled
    public String guest;
    @AuraEnabled
    public Id bookingId;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String region;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public Date tripStart;
    @AuraEnabled
    public Date tripEnd;
    @AuraEnabled
    public String designer;

    // Screen 1
    @AuraEnabled
    public Decimal overall;
    @AuraEnabled
    public String overallComment;
    @AuraEnabled
    public Decimal consultation;
    @AuraEnabled
    public String consultationComment;

    // Screens 2-4
    @AuraEnabled
    public List<DetailRating> services = new List<DetailRating>();
    @AuraEnabled
    public List<DetailRating> hotels = new List<DetailRating>();
    @AuraEnabled
    public String generalHotelComment;
    @AuraEnabled
    public List<DetailRating> golf = new List<DetailRating>();
    @AuraEnabled
    public String generalGolfComment;

    // Screen 5
    @AuraEnabled
    public Decimal recommendation;
    @AuraEnabled
    public String npsCategory;
    @AuraEnabled
    public Boolean publicReviewPrompted;
    @AuraEnabled
    public String nextDestination;
    @AuraEnabled
    public String improvementSuggestions;
    @AuraEnabled
    public String generalFeedback;

    // What the team did about it
    @AuraEnabled
    public String followUpStatus;
    @AuraEnabled
    public String followUpNote;
    @AuraEnabled
    public String followUpBy;
    @AuraEnabled
    public Datetime followUpOn;
  }

  public class DetailRating {
    @AuraEnabled
    public String category;
    /** A venue, or for travel services every supplier rated together. */
    @AuraEnabled
    public String name;
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
    @AuraEnabled
    public List<Option> designers = new List<Option>();
  }

  // ------------------------------------------------------------------
  // Entry points

  @AuraEnabled(cacheable=true)
  public static Dashboard getDashboard(String filtersJson) {
    Filters f = parse(filtersJson);
    Dashboard d = new Dashboard();
    guardVolume(f);

    applyKpis(d.kpis, f);
    d.trend = trend(f);
    countInvitations(d.kpis, f);
    applyVenues(d, f);
    d.hotelDetail = hotelDetail(f);
    d.designers = designers(f);

    d.followUps = followUps(f);
    d.followUpsTotal = d.kpis.detractors;

    List<Feedback_Response__c> recent = loadResponses(f);
    applyDestinations(d, recent, d.kpis.responses > recent.size());
    applyComments(d, f, recent);
    return d;
  }

  /**
   * The whole of one guest's answer, laid out screen by screen. `with sharing`
   * decides whether the user may see it at all.
   */
  @AuraEnabled(cacheable=true)
  public static ResponseDetail getResponseDetail(Id responseId) {
    List<Feedback_Response__c> found = [
      SELECT
        Id,
        Name,
        Submitted_On__c,
        Language__c,
        Contact__r.Name,
        Booking__c,
        Booking__r.BookingNumber__c,
        toLabel(Booking__r.Region__c),
        toLabel(Booking__r.DestinationCountry__c),
        Booking__r.Start_Date__c,
        Booking__r.End_Date__c,
        Booking__r.TravelDesigner__r.Name,
        Overall_Experience__c,
        Overall_Experience_Comment__c,
        Consultation_Rating__c,
        Consultation_Comment__c,
        General_Hotel_Comment__c,
        General_Golf_Comment__c,
        Recommendation_NPS__c,
        NPS_Category__c,
        Public_Review_Prompted__c,
        Next_Destination__c,
        Improvement_Suggestions__c,
        General_Feedback__c,
        Follow_Up_Status__c,
        Follow_Up_Note__c,
        Follow_Up_By__r.Name,
        Follow_Up_On__c,
        (
          SELECT
            Category__c,
            Sub_Category__c,
            Item_Name__c,
            Reservation__c,
            Score__c,
            Comment__c
          FROM Feedback_Ratings__r
          ORDER BY CreatedDate, Id
        )
      FROM Feedback_Response__c
      WHERE Id = :responseId
    ];
    if (found.isEmpty()) {
      throw new AuraHandledException(
        'This feedback could not be found, or you do not have access to it.'
      );
    }
    Feedback_Response__c r = found[0];

    ResponseDetail d = new ResponseDetail();
    d.responseId = r.Id;
    d.reference = r.Name;
    d.submittedOn = r.Submitted_On__c;
    d.language = r.Language__c;
    d.guest = r.Contact__r?.Name;
    d.bookingId = r.Booking__c;
    d.bookingNumber = r.Booking__r?.BookingNumber__c;
    d.region = r.Booking__r?.Region__c;
    d.country = r.Booking__r?.DestinationCountry__c;
    d.tripStart = r.Booking__r?.Start_Date__c;
    d.tripEnd = r.Booking__r?.End_Date__c;
    d.designer = r.Booking__r?.TravelDesigner__r?.Name;
    d.overall = r.Overall_Experience__c;
    d.overallComment = r.Overall_Experience_Comment__c;
    d.consultation = r.Consultation_Rating__c;
    d.consultationComment = r.Consultation_Comment__c;
    d.generalHotelComment = r.General_Hotel_Comment__c;
    d.generalGolfComment = r.General_Golf_Comment__c;
    d.recommendation = r.Recommendation_NPS__c;
    d.npsCategory = r.NPS_Category__c;
    d.publicReviewPrompted = r.Public_Review_Prompted__c;
    d.nextDestination = r.Next_Destination__c;
    d.improvementSuggestions = r.Improvement_Suggestions__c;
    d.generalFeedback = r.General_Feedback__c;
    d.followUpStatus = r.Follow_Up_Status__c;
    d.followUpNote = r.Follow_Up_Note__c;
    d.followUpBy = r.Follow_Up_By__r?.Name;
    d.followUpOn = r.Follow_Up_On__c;
    applyDetailRatings(d, r.Feedback_Ratings__r);
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

    Boolean anyWithout = false;
    for (AggregateResult ar : [
      SELECT
        Booking__r.TravelDesigner__c designer,
        Booking__r.TravelDesigner__r.Name name,
        COUNT(Id) n
      FROM Feedback_Response__c
      GROUP BY Booking__r.TravelDesigner__c, Booking__r.TravelDesigner__r.Name
      ORDER BY Booking__r.TravelDesigner__r.Name
    ]) {
      Object designer = ar.get('designer');
      if (designer == null) {
        anyWithout = true;
      } else {
        o.designers.add(
          new Option((String) ar.get('name'), String.valueOf(designer))
        );
      }
    }
    if (anyWithout) {
      o.designers.add(new Option('No travel designer', NO_DESIGNER));
    }
    return o;
  }

  /**
   * Every response, a page at a time: the list the team works from.
   *
   * A search finds a guest by name, email, booking number or FB reference
   * across every response, ignoring the dashboard filters - when a guest is
   * on the phone, the trip date is exactly what nobody wants to guess. The
   * group ('promoters', 'passives', 'detractors', 'open') and the order
   * ('newest', 'lowest') apply either way.
   */
  @AuraEnabled(cacheable=true)
  public static ResponsePage findResponses(
    String filtersJson,
    String search,
    String groupName,
    String sortBy,
    Integer pageNumber
  ) {
    Filters f = parse(filtersJson);
    ResponsePage out = new ResponsePage();
    out.pageSize = responsePageSize;

    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = listClauses(f, search, groupName, binds);
    out.searching = binds.containsKey('term');

    out.total = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Feedback_Response__c' + whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    );
    Integer lastPage = Math.max(
      1,
      Math.ceil((Decimal) out.total / responsePageSize).intValue()
    );
    Integer reachable = MAX_OFFSET / responsePageSize + 1;
    out.capped = lastPage > reachable;
    out.page = Math.min(
      Math.max(pageNumber == null ? 1 : pageNumber, 1),
      Math.min(lastPage, reachable)
    );

    String order = orderOf(sortBy);
    List<Feedback_Response__c> found = (List<Feedback_Response__c>) Database.queryWithBinds(
      'SELECT ' +
        RESPONSE_FIELDS +
        ', Booking__r.TravelDesigner__r.Name, Booking__r.Region__c,' +
        ' Booking__r.End_Date__c, Public_Review_Prompted__c' +
        ' FROM Feedback_Response__c' +
        whereOf(clauses) +
        ' ORDER BY ' +
        order +
        ' LIMIT ' +
        responsePageSize +
        ' OFFSET ' +
        (out.page - 1) * responsePageSize,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    out.rows = listRows(found);
    return out;
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

  private static final String RESPONSE_FIELDS =
    'Id, Name, Overall_Experience__c, Consultation_Rating__c, ' +
    'Recommendation_NPS__c, Next_Destination__c, Improvement_Suggestions__c, ' +
    'Overall_Experience_Comment__c, Consultation_Comment__c, ' +
    'General_Hotel_Comment__c, General_Golf_Comment__c, General_Feedback__c, ' +
    'Follow_Up_Status__c, Follow_Up_Note__c, Follow_Up_On__c, Follow_Up_By__r.Name, ' +
    'Submitted_On__c, Contact__r.Name, Booking__c, Booking__r.BookingNumber__c';

  /** The newest responses, read for their free text. */
  private static List<Feedback_Response__c> loadResponses(Filters f) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    return (List<Feedback_Response__c>) Database.queryWithBinds(
      'SELECT ' +
        RESPONSE_FIELDS +
        ' FROM Feedback_Response__c' +
        whereOf(clauses) +
        ' ORDER BY Submitted_On__c DESC LIMIT ' +
        MAX_RESPONSES,
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  /**
   * Refuses a selection too large to total in one request, with a message the
   * page can show, instead of hitting the row limit part way through.
   */
  private static void guardVolume(Filters f) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses(
      'Feedback_Response__r.Booking__r.',
      f,
      binds
    );
    Integer ratings = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Feedback_Rating__c' + whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    );
    if (ratings > maxRatingsInView) {
      throw new AuraHandledException(
        'This selection covers ' +
          ratings +
          ' ratings, more than the dashboard can total at once. ' +
          'Narrow the dates, or pick a region or country.'
      );
    }
  }

  /**
   * Headline numbers, each counted by the database. COUNT() costs one row
   * whatever it counts, so these stay cheap at any volume.
   */
  private static void applyKpis(Kpis k, Filters f) {
    k.responses = countResponses(f, null, null);
    k.promoters = countResponses(
      f,
      'Recommendation_NPS__c >= :promoterMin',
      new Map<String, Object>{ 'promoterMin' => PROMOTER_MIN }
    );
    k.detractors = countResponses(
      f,
      'Recommendation_NPS__c <= :detractorMax',
      new Map<String, Object>{ 'detractorMax' => DETRACTOR_MAX }
    );
    k.passives = countResponses(
      f,
      'Recommendation_NPS__c > :detractorMax AND Recommendation_NPS__c < :promoterMin',
      new Map<String, Object>{
        'detractorMax' => DETRACTOR_MAX,
        'promoterMin' => PROMOTER_MIN
      }
    );
    k.answeredInvitations = countResponses(
      f,
      'Booking__r.Survey_Sent_On__c != null',
      null
    );
    // Reminders only ever go to guests who had not answered, so any answer
    // on a reminded booking arrived after the reminder.
    k.answeredAfterReminder = countResponses(
      f,
      'Booking__r.Survey_Reminder_Sent__c = true',
      null
    );
    k.openFollowUps = countResponses(
      f,
      'Recommendation_NPS__c <= :detractorMax AND ' +
      '(Follow_Up_Status__c = null OR Follow_Up_Status__c NOT IN :closed)',
      new Map<String, Object>{
        'detractorMax' => DETRACTOR_MAX,
        'closed' => CLOSED_STATUSES
      }
    );
    k.nps = npsOf(k.promoters, k.detractors, k.responses);

    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    AggregateResult avg = ((List<AggregateResult>) Database.queryWithBinds(
      'SELECT AVG(Overall_Experience__c) overall, ' +
        'AVG(Consultation_Rating__c) consult ' +
        'FROM Feedback_Response__c' +
        whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    ))[0];
    k.avgOverall = scaled((Decimal) avg.get('overall'));
    k.avgConsultation = scaled((Decimal) avg.get('consult'));
  }

  private static Integer countResponses(
    Filters f,
    String extra,
    Map<String, Object> extraBinds
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    if (extra != null) {
      clauses.add(extra);
      binds.putAll(extraBinds == null ? new Map<String, Object>() : extraBinds);
    }
    return Database.countQueryWithBinds(
      'SELECT COUNT() FROM Feedback_Response__c' + whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    );
  }

  /** One point per trip month, each bucket counted by the database. */
  private static List<MonthPoint> trend(Filters f) {
    Map<String, MonthPoint> months = new Map<String, MonthPoint>();
    addMonthCounts(months, f, null, null, 'total');
    addMonthCounts(
      months,
      f,
      'Recommendation_NPS__c >= :promoterMin',
      new Map<String, Object>{ 'promoterMin' => PROMOTER_MIN },
      'promoter'
    );
    addMonthCounts(
      months,
      f,
      'Recommendation_NPS__c <= :detractorMax',
      new Map<String, Object>{ 'detractorMax' => DETRACTOR_MAX },
      'detractor'
    );
    addMonthCounts(
      months,
      f,
      'Recommendation_NPS__c > :detractorMax AND Recommendation_NPS__c < :promoterMin',
      new Map<String, Object>{
        'detractorMax' => DETRACTOR_MAX,
        'promoterMin' => PROMOTER_MIN
      },
      'passive'
    );

    List<String> keys = new List<String>(months.keySet());
    keys.sort();
    List<MonthPoint> points = new List<MonthPoint>();
    for (String key : keys) {
      MonthPoint m = months.get(key);
      m.nps = npsOf(m.promoters, m.detractors, m.total);
      points.add(m);
    }
    return points;
  }

  private static void addMonthCounts(
    Map<String, MonthPoint> months,
    Filters f,
    String extra,
    Map<String, Object> extraBinds,
    String bucket
  ) {
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    clauses.add('Booking__r.End_Date__c != null');
    if (extra != null) {
      clauses.add(extra);
      binds.putAll(extraBinds);
    }
    for (
      AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(Booking__r.End_Date__c) y, ' +
          'CALENDAR_MONTH(Booking__r.End_Date__c) m, COUNT(Id) n ' +
          'FROM Feedback_Response__c' +
          whereOf(clauses) +
          ' GROUP BY CALENDAR_YEAR(Booking__r.End_Date__c), ' +
          'CALENDAR_MONTH(Booking__r.End_Date__c)',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      Integer year = (Integer) ar.get('y');
      Integer month = (Integer) ar.get('m');
      String key =
        String.valueOf(year) +
        '-' +
        String.valueOf(month).leftPad(2, '0');
      MonthPoint point = months.get(key);
      if (point == null) {
        point = new MonthPoint();
        point.key = key;
        point.year = year;
        point.month = month;
        months.put(key, point);
      }
      Integer n = (Integer) ar.get('n');
      if (bucket == 'total') {
        point.total = n;
      } else if (bucket == 'promoter') {
        point.promoters = n;
      } else if (bucket == 'detractor') {
        point.detractors = n;
      } else {
        point.passives = n;
      }
    }
  }

  /**
   * Unhappy guests: open cases first (the picklist sorts Open before
   * Contacted and Resolved, and blank first of all), newest first within.
   */
  private static List<ResponseRow> followUps(Filters f) {
    Map<String, Object> binds = new Map<String, Object>{
      'detractorMax' => DETRACTOR_MAX
    };
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    clauses.add('Recommendation_NPS__c <= :detractorMax');
    List<ResponseRow> rows = new List<ResponseRow>();
    for (
      Feedback_Response__c r : (List<Feedback_Response__c>) Database.queryWithBinds(
        'SELECT ' +
          RESPONSE_FIELDS +
          ' FROM Feedback_Response__c' +
          whereOf(clauses) +
          ' ORDER BY Follow_Up_Status__c NULLS FIRST, Submitted_On__c DESC' +
          ' LIMIT ' +
          maxFollowUps,
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      rows.add(toRow(r));
    }
    return rows;
  }

  /**
   * Next-destination wishes, happiest guests first: they are the warmest
   * leads. Long text cannot be filtered in SOQL, so this reads the newest
   * responses and keeps the ones with a wish.
   */
  private static void applyDestinations(
    Dashboard d,
    List<Feedback_Response__c> recent,
    Boolean olderLeftOut
  ) {
    for (Feedback_Response__c r : recent) {
      if (String.isNotBlank(r.Next_Destination__c)) {
        d.nextDestinations.add(toRow(r));
      }
    }
    d.nextDestinations.sort(new ByNpsDescending());
    d.destinationsCapped = olderLeftOut;
    while (d.nextDestinations.size() > maxDestinations) {
      d.nextDestinations.remove(d.nextDestinations.size() - 1);
      d.destinationsCapped = true;
    }
  }

  /**
   * Ratings arranged the way the form asked for them. Travel services are
   * saved once per supplier with the same score, so they are folded back into
   * one line per service; hotel sub-ratings join the hotel they belong to.
   */
  private static void applyDetailRatings(
    ResponseDetail d,
    List<Feedback_Rating__c> ratings
  ) {
    Map<String, DetailRating> services = new Map<String, DetailRating>();
    Map<String, DetailRating> hotels = new Map<String, DetailRating>();
    List<Feedback_Rating__c> subs = new List<Feedback_Rating__c>();

    for (Feedback_Rating__c r : ratings) {
      if (String.isNotBlank(r.Sub_Category__c)) {
        subs.add(r);
        continue;
      }
      DetailRating item = new DetailRating();
      item.category = r.Category__c;
      item.name = r.Item_Name__c;
      item.score = r.Score__c;
      item.comment = r.Comment__c;

      if (SUPPLIER_TYPES.contains(r.Category__c)) {
        DetailRating existing = services.get(r.Category__c);
        if (existing == null) {
          services.put(r.Category__c, item);
        } else {
          existing.name += ', ' + r.Item_Name__c;
          if (String.isBlank(existing.comment)) {
            existing.comment = r.Comment__c;
          }
        }
      } else if (r.Category__c == HOTEL) {
        hotels.put(venueKey(r), item);
        d.hotels.add(item);
      } else if (r.Category__c == GOLF) {
        d.golf.add(item);
      }
    }

    for (
      String type : new List<String>{
        'Airline',
        'TransferCompany',
        'CarRentalCompany'
      }
    ) {
      if (services.containsKey(type)) {
        d.services.add(services.get(type));
      }
    }

    for (Feedback_Rating__c s : subs) {
      DetailRating hotel = hotels.get(venueKey(s));
      if (hotel == null) {
        continue;
      }
      HeatCell c = new HeatCell();
      c.subCategory = s.Sub_Category__c;
      c.average = s.Score__c;
      c.ratings = 1;
      hotel.subScores.add(c);
    }
  }

  private static String venueKey(Feedback_Rating__c r) {
    return r.Reservation__c != null
      ? String.valueOf(r.Reservation__c)
      : r.Item_Name__c;
  }

  /**
   * The same selection as the response list - filters or search, group and
   * order - as a spreadsheet. Semicolon-separated UTF-8, which is what
   * Excel set to German opens straight into columns; the page adds the byte
   * order mark that tells Excel it is UTF-8, so umlauts survive.
   */
  @AuraEnabled
  public static ExportResult exportResponses(
    String filtersJson,
    String search,
    String groupName,
    String sortBy
  ) {
    Filters f = parse(filtersJson);
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = listClauses(f, search, groupName, binds);

    ExportResult out = new ExportResult();
    out.total = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Feedback_Response__c' + whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    );
    out.capped = out.total > maxExport;
    out.fileName =
      'golf-extra-feedback-' +
      Datetime.now().format('yyyy-MM-dd') +
      '.csv';

    List<Feedback_Response__c> responses = (List<Feedback_Response__c>) Database.queryWithBinds(
      'SELECT ' +
        RESPONSE_FIELDS +
        ', Contact__r.Email, Booking__r.TravelDesigner__r.Name, Booking__r.Region__c,' +
        ' toLabel(Booking__r.DestinationCountry__c), Booking__r.Start_Date__c,' +
        ' Booking__r.End_Date__c, Public_Review_Prompted__c' +
        ' FROM Feedback_Response__c' +
        whereOf(clauses) +
        ' ORDER BY ' +
        orderOf(sortBy) +
        ' LIMIT ' +
        maxExport,
      binds,
      AccessLevel.SYSTEM_MODE
    );
    out.rows = responses.size();

    Map<Id, ExportRatings> ratings = new Map<Id, ExportRatings>();
    for (Feedback_Response__c r : responses) {
      ratings.put(r.Id, new ExportRatings());
    }
    Set<Id> ids = ratings.keySet();
    // A query loop, so thousands of ratings never sit in memory at once.
    for (Feedback_Rating__c rating : [
      SELECT
        Feedback_Response__c,
        Category__c,
        Sub_Category__c,
        Item_Name__c,
        Reservation__c,
        Score__c,
        Comment__c
      FROM Feedback_Rating__c
      WHERE Feedback_Response__c IN :ids
      WITH SYSTEM_MODE
      ORDER BY Feedback_Response__c, CreatedDate, Id
    ]) {
      ratings.get(rating.Feedback_Response__c).add(rating);
    }

    List<String> lines = new List<String>{ csvLine(EXPORT_HEADER) };
    for (Feedback_Response__c r : responses) {
      ExportRatings x = ratings.get(r.Id);
      Integer nps = r.Recommendation_NPS__c?.intValue();
      lines.add(
        csvLine(
          new List<String>{
            r.Name,
            r.Submitted_On__c?.format('yyyy-MM-dd HH:mm'),
            r.Contact__r?.Name,
            r.Contact__r?.Email,
            r.Booking__r?.BookingNumber__c,
            r.Booking__r?.Region__c,
            r.Booking__r?.DestinationCountry__c,
            isoDate(r.Booking__r?.Start_Date__c),
            isoDate(r.Booking__r?.End_Date__c),
            r.Booking__r?.TravelDesigner__r?.Name,
            nps == null ? null : String.valueOf(nps),
            npsGroupOf(nps),
            whole(r.Overall_Experience__c),
            r.Overall_Experience_Comment__c,
            whole(r.Consultation_Rating__c),
            r.Consultation_Comment__c,
            x.service('Airline'),
            x.service('TransferCompany'),
            x.service('CarRentalCompany'),
            x.venues(HOTEL),
            r.General_Hotel_Comment__c,
            x.venues(GOLF),
            r.General_Golf_Comment__c,
            r.Next_Destination__c,
            r.Improvement_Suggestions__c,
            r.General_Feedback__c,
            r.Public_Review_Prompted__c == true ? 'Yes' : 'No',
            r.Follow_Up_Status__c,
            r.Follow_Up_Note__c,
            r.Follow_Up_By__r?.Name,
            r.Follow_Up_On__c?.format('yyyy-MM-dd HH:mm')
          }
        )
      );
    }
    out.csv = String.join(lines, '\r\n');
    return out;
  }

  /**
   * Guests who were sent the survey and have not answered, newest first:
   * the people a travel designer might still nudge personally.
   */
  @AuraEnabled(cacheable=true)
  public static WaitingPage findWaiting(
    String filtersJson,
    Integer pageNumber
  ) {
    Filters f = parse(filtersJson);
    WaitingPage out = new WaitingPage();
    out.pageSize = responsePageSize;

    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('', f, binds);
    clauses.add('Survey_Sent_On__c != null');
    clauses.add('Id NOT IN (SELECT Booking__c FROM Feedback_Response__c)');

    out.total = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Booking__c' + whereOf(clauses),
      binds,
      AccessLevel.SYSTEM_MODE
    );
    Integer lastPage = Math.max(
      1,
      Math.ceil((Decimal) out.total / responsePageSize).intValue()
    );
    out.page = Math.min(
      Math.max(pageNumber == null ? 1 : pageNumber, 1),
      Math.min(lastPage, MAX_OFFSET / responsePageSize + 1)
    );

    Decimal validity = GxFeedbackSettings.linkValidityDays();
    Decimal reminderDelay = GxFeedbackSettings.reminderDelayDays();
    for (
      Booking__c b : (List<Booking__c>) Database.queryWithBinds(
        'SELECT Id, BookingNumber__c, MainContact__r.Name, TravelDesigner__r.Name,' +
          ' Region__c, End_Date__c, Survey_Sent_On__c, Survey_Reminder_Sent__c' +
          ' FROM Booking__c' +
          whereOf(clauses) +
          ' ORDER BY Survey_Sent_On__c DESC, Id DESC' +
          ' LIMIT ' +
          responsePageSize +
          ' OFFSET ' +
          (out.page - 1) * responsePageSize,
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      WaitingRow row = new WaitingRow();
      row.bookingId = b.Id;
      row.bookingNumber = b.BookingNumber__c;
      row.guest = b.MainContact__r?.Name;
      row.designer = b.TravelDesigner__r?.Name;
      row.region = b.Region__c;
      row.tripEnd = b.End_Date__c;
      row.lastSent = b.Survey_Sent_On__c;
      row.reminded = b.Survey_Reminder_Sent__c == true;
      Date sentOn = b.Survey_Sent_On__c.date();
      // The link counts from the last time the guest was asked, reminder
      // included - the same rule the survey itself applies.
      if (validity != null && validity > 0) {
        row.expiresOn = sentOn.addDays(validity.intValue());
      }
      if (!row.reminded && reminderDelay != null && reminderDelay > 0) {
        row.reminderDue = sentOn.addDays(reminderDelay.intValue());
      }
      if (row.expiresOn != null && Date.today() > row.expiresOn) {
        row.state = 'expired';
      } else {
        row.state = row.reminded ? 'reminded' : 'waiting';
      }
      out.rows.add(row);
    }
    return out;
  }

  private static final List<String> EXPORT_HEADER = new List<String>{
    'Feedback number',
    'Submitted',
    'Guest',
    'Guest email',
    'Booking',
    'Region',
    'Country',
    'Trip start',
    'Trip end',
    'Travel designer',
    'Would recommend (1-10)',
    'NPS group',
    'Overall trip',
    'Overall comment',
    'Consultation',
    'Consultation comment',
    'Flights',
    'Transfers',
    'Rental car',
    'Hotels',
    'Hotels in general',
    'Golf courses',
    'Golf in general',
    'Next on their wish list',
    'Suggestions',
    'Anything else',
    'Shown review invitation',
    'Follow-up status',
    'Follow-up note',
    'Follow-up by',
    'Follow-up on'
  };

  /** One response's ratings, folded into spreadsheet cells. */
  private class ExportRatings {
    Map<String, List<Feedback_Rating__c>> services = new Map<String, List<Feedback_Rating__c>>();
    Map<String, List<String>> subs = new Map<String, List<String>>();
    Map<String, List<Feedback_Rating__c>> venues = new Map<String, List<Feedback_Rating__c>>();

    void add(Feedback_Rating__c r) {
      if (
        GxFeedbackDashboardController.SUPPLIER_TYPES.contains(r.Category__c)
      ) {
        listFor(services, r.Category__c).add(r);
      } else if (String.isNotBlank(r.Sub_Category__c)) {
        String key = keyOf(r);
        if (!subs.containsKey(key)) {
          subs.put(key, new List<String>());
        }
        subs.get(key)
          .add(
            r.Sub_Category__c +
              ' ' +
              GxFeedbackDashboardController.whole(r.Score__c)
          );
      } else {
        listFor(venues, r.Category__c).add(r);
      }
    }

    /** "Lufthansa, Condor: 7 - Verspätet" - one answer, every supplier. */
    String service(String category) {
      List<Feedback_Rating__c> rows = services.get(category);
      if (rows == null || rows.isEmpty()) {
        return null;
      }
      List<String> names = new List<String>();
      String comment;
      for (Feedback_Rating__c r : rows) {
        names.add(r.Item_Name__c);
        if (String.isBlank(comment)) {
          comment = r.Comment__c;
        }
      }
      return String.join(names, ', ') +
        ': ' +
        GxFeedbackDashboardController.whole(rows[0].Score__c) +
        (String.isBlank(comment) ? '' : ' - ' + comment);
    }

    /** "Conrad: 5 (Room 4, Service 6) - Laut; Pine Cliffs: 9" */
    String venues(String category) {
      List<Feedback_Rating__c> rows = venues.get(category);
      if (rows == null || rows.isEmpty()) {
        return null;
      }
      List<String> parts = new List<String>();
      for (Feedback_Rating__c r : rows) {
        List<String> detail = subs.get(keyOf(r));
        parts.add(
          r.Item_Name__c +
            ': ' +
            GxFeedbackDashboardController.whole(r.Score__c) +
            (detail == null ? '' : ' (' + String.join(detail, ', ') + ')') +
            (String.isBlank(r.Comment__c) ? '' : ' - ' + r.Comment__c)
        );
      }
      return String.join(parts, '; ');
    }

    String keyOf(Feedback_Rating__c r) {
      return r.Reservation__c != null
        ? String.valueOf(r.Reservation__c)
        : r.Category__c + '|' + r.Item_Name__c;
    }

    List<Feedback_Rating__c> listFor(
      Map<String, List<Feedback_Rating__c>> m,
      String key
    ) {
      if (!m.containsKey(key)) {
        m.put(key, new List<Feedback_Rating__c>());
      }
      return m.get(key);
    }
  }

  /**
   * One CSV line, every cell quoted. Guests write some of these cells, so a
   * cell Excel would read as a formula (=, +, -, @) is defused with a leading
   * apostrophe rather than run.
   */
  @TestVisible
  private static String csvLine(List<String> cells) {
    List<String> out = new List<String>();
    for (String cell : cells) {
      String value = cell == null ? '' : cell;
      if (value.length() > 0 && '=+-@\t\r'.contains(value.left(1))) {
        value = '\'' + value;
      }
      out.add('"' + value.replace('"', '""') + '"');
    }
    return String.join(out, ';');
  }

  private static String whole(Decimal value) {
    return value == null ? null : String.valueOf(value.intValue());
  }

  private static String isoDate(Date value) {
    return value == null
      ? null
      : Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0))
          .format('yyyy-MM-dd');
  }

  private static String npsGroupOf(Integer nps) {
    String bucket = bucketFor(nps);
    if (bucket == 'promoter') {
      return 'Promoter';
    }
    if (bucket == 'passive') {
      return 'Passive';
    }
    return bucket == 'detractor' ? 'Detractor' : null;
  }

  /** What a response list covers: a search, or the filters; then a group. */
  private static List<String> listClauses(
    Filters f,
    String search,
    String groupName,
    Map<String, Object> binds
  ) {
    List<String> clauses = new List<String>();
    String term = String.isBlank(search) ? '' : search.trim();
    if (term.length() >= 2) {
      binds.put('term', '%' + escapeLike(term) + '%');
      clauses.add(
        '(Contact__r.LastName LIKE :term OR Contact__r.Name LIKE :term' +
          ' OR Contact__r.Email LIKE :term' +
          ' OR Booking__r.BookingNumber__c LIKE :term OR Name LIKE :term)'
      );
    } else {
      clauses.addAll(bookingClauses('Booking__r.', f, binds));
    }
    String groupClause = groupClause(groupName, binds);
    if (groupClause != null) {
      clauses.add(groupClause);
    }
    return clauses;
  }

  private static String orderOf(String sortBy) {
    return sortBy == 'lowest'
      ? 'Recommendation_NPS__c ASC NULLS LAST, Overall_Experience__c ASC NULLS LAST, Submitted_On__c DESC'
      : 'Submitted_On__c DESC NULLS LAST, Id DESC';
  }

  /** Per designer: responses, their consultation average, and NPS. */
  private static List<DesignerRow> designers(Filters f) {
    Map<String, DesignerRow> byId = new Map<String, DesignerRow>();
    Map<String, Object> binds = new Map<String, Object>();
    List<String> clauses = bookingClauses('Booking__r.', f, binds);
    String groupBy = ' GROUP BY Booking__r.TravelDesigner__c, Booking__r.TravelDesigner__r.Name';

    for (
      AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Booking__r.TravelDesigner__c designer, ' +
          'Booking__r.TravelDesigner__r.Name name, COUNT(Id) n, ' +
          'AVG(Consultation_Rating__c) consult FROM Feedback_Response__c' +
          whereOf(clauses) +
          groupBy,
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      DesignerRow row = new DesignerRow();
      Object designer = ar.get('designer');
      row.id = designer == null ? NO_DESIGNER : String.valueOf(designer);
      row.name = designer == null
        ? 'No travel designer'
        : (String) ar.get('name');
      row.responses = (Integer) ar.get('n');
      row.consultation = scaled((Decimal) ar.get('consult'));
      byId.put(row.id, row);
    }

    for (String bucket : new List<String>{ 'promoter', 'detractor' }) {
      Map<String, Object> bucketBinds = binds.clone();
      List<String> bucketClauses = clauses.clone();
      if (bucket == 'promoter') {
        bucketClauses.add('Recommendation_NPS__c >= :promoterMin');
        bucketBinds.put('promoterMin', PROMOTER_MIN);
      } else {
        bucketClauses.add('Recommendation_NPS__c <= :detractorMax');
        bucketBinds.put('detractorMax', DETRACTOR_MAX);
      }
      for (
        AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
          'SELECT Booking__r.TravelDesigner__c designer, COUNT(Id) n ' +
            'FROM Feedback_Response__c' +
            whereOf(bucketClauses) +
            ' GROUP BY Booking__r.TravelDesigner__c',
          bucketBinds,
          AccessLevel.SYSTEM_MODE
        )
      ) {
        Object designer = ar.get('designer');
        DesignerRow row = byId.get(
          designer == null ? NO_DESIGNER : String.valueOf(designer)
        );
        if (row == null) {
          continue;
        }
        if (bucket == 'promoter') {
          row.promoters = (Integer) ar.get('n');
        } else {
          row.detractors = (Integer) ar.get('n');
        }
      }
    }

    List<DesignerRow> rows = byId.values();
    for (DesignerRow row : rows) {
      row.nps = npsOf(row.promoters, row.detractors, row.responses);
    }
    rows.sort(new ByResponsesDescending());
    return rows;
  }

  private static String groupClause(
    String groupName,
    Map<String, Object> binds
  ) {
    if (groupName == 'promoters') {
      binds.put('promoterMin', PROMOTER_MIN);
      return 'Recommendation_NPS__c >= :promoterMin';
    }
    if (groupName == 'passives') {
      binds.put('promoterMin', PROMOTER_MIN);
      binds.put('detractorMax', DETRACTOR_MAX);
      return 'Recommendation_NPS__c > :detractorMax AND Recommendation_NPS__c < :promoterMin';
    }
    if (groupName == 'detractors') {
      binds.put('detractorMax', DETRACTOR_MAX);
      return 'Recommendation_NPS__c <= :detractorMax';
    }
    if (groupName == 'open') {
      binds.put('detractorMax', DETRACTOR_MAX);
      binds.put('closed', CLOSED_STATUSES);
      return 'Recommendation_NPS__c <= :detractorMax AND ' +
        '(Follow_Up_Status__c = null OR Follow_Up_Status__c NOT IN :closed)';
    }
    return null;
  }

  /**
   * List rows with what stood out in each answer: its lowest score and how
   * much the guest wrote. One query for the page's ratings, not one per row.
   */
  private static List<ListRow> listRows(List<Feedback_Response__c> found) {
    Map<Id, ListRow> byId = new Map<Id, ListRow>();
    List<ListRow> rows = new List<ListRow>();
    for (Feedback_Response__c r : found) {
      ListRow row = new ListRow();
      row.responseId = r.Id;
      row.reference = r.Name;
      row.bookingId = r.Booking__c;
      row.bookingNumber = r.Booking__r?.BookingNumber__c;
      row.guest = r.Contact__r?.Name;
      row.designer = r.Booking__r?.TravelDesigner__r?.Name;
      row.region = r.Booking__r?.Region__c;
      row.tripEnd = r.Booking__r?.End_Date__c;
      row.submittedOn = r.Submitted_On__c;
      row.nps = r.Recommendation_NPS__c;
      row.overall = r.Overall_Experience__c;
      row.followUpStatus = r.Follow_Up_Status__c;
      row.reviewPrompted = r.Public_Review_Prompted__c == true;
      considerLowest(row, 'Overall', r.Overall_Experience__c);
      considerLowest(row, 'Consultation', r.Consultation_Rating__c);
      for (
        String text : new List<String>{
          r.Overall_Experience_Comment__c,
          r.Consultation_Comment__c,
          r.General_Hotel_Comment__c,
          r.General_Golf_Comment__c,
          r.Improvement_Suggestions__c,
          r.General_Feedback__c
        }
      ) {
        if (String.isNotBlank(text)) {
          row.comments++;
        }
      }
      byId.put(r.Id, row);
      rows.add(row);
    }
    if (byId.isEmpty()) {
      return rows;
    }
    Set<Id> ids = byId.keySet();
    for (Feedback_Rating__c rating : [
      SELECT
        Feedback_Response__c,
        Item_Name__c,
        Sub_Category__c,
        Score__c,
        Comment__c
      FROM Feedback_Rating__c
      WHERE Feedback_Response__c IN :ids
      WITH SYSTEM_MODE
      ORDER BY CreatedDate, Id
    ]) {
      ListRow row = byId.get(rating.Feedback_Response__c);
      if (String.isBlank(rating.Sub_Category__c)) {
        considerLowest(row, rating.Item_Name__c, rating.Score__c);
      }
      if (String.isNotBlank(rating.Comment__c)) {
        row.comments++;
      }
    }
    return rows;
  }

  /** Keeps the first lowest score, so ties name the earlier question. */
  private static void considerLowest(ListRow row, String label, Decimal score) {
    if (score == null) {
      return;
    }
    if (row.lowestScore == null || score < row.lowestScore) {
      row.lowestScore = score;
      row.lowestLabel = label;
    }
  }

  /** A search term's own % and _ are matched literally, not as wildcards. */
  private static String escapeLike(String term) {
    return term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }

  private static Decimal scaled(Decimal value) {
    return value == null ? null : value.setScale(1);
  }

  private static String whereOf(List<String> clauses) {
    return clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
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
  private static void applyComments(
    Dashboard d,
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
          'Feedback_Response__c, Feedback_Response__r.Booking__c, ' +
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
      c.responseId = r.Feedback_Response__c;
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
    while (rows.size() > maxComments) {
      rows.remove(rows.size() - 1);
      d.commentsCapped = true;
    }
    d.comments = rows;
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
    c.responseId = r.Id;
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
    if (f.designer == NO_DESIGNER) {
      clauses.add(prefix + 'TravelDesigner__c = null');
    } else if (String.isNotBlank(f.designer)) {
      clauses.add(prefix + 'TravelDesigner__c = :designer');
      binds.put('designer', f.designer);
    }
    return clauses;
  }

  private static Filters parse(String filtersJson) {
    if (String.isBlank(filtersJson)) {
      return new Filters();
    }
    try {
      Filters f = (Filters) JSON.deserialize(filtersJson, Filters.class);
      if (f == null) {
        return new Filters();
      }
      if (String.isNotBlank(f.designer) && f.designer != NO_DESIGNER) {
        f.designer = Id.valueOf(f.designer); // throws on anything else
      }
      return f;
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

  private class ByResponsesDescending implements Comparator<DesignerRow> {
    public Integer compare(DesignerRow a, DesignerRow b) {
      if (a.responses != b.responses) {
        return a.responses > b.responses ? -1 : 1;
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
