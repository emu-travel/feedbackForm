/**
 * GxFeedbackService
 *
 * All logic behind the public post-trip feedback survey.
 * Called by GxFeedbackFormController on behalf of a guest user, hence
 * `without sharing`. Everything the guest can reach goes through here; the
 * guest profile has no object access of its own.
 *
 * Deliberately modelled on ReiseanmeldungService so the two public forms in
 * this org stay recognisably the same shape.
 *
 * The survey is generated per booking: only the hotels, golf courses, flights,
 * transfers and rental cars actually on that booking are asked about.
 */
public without sharing class GxFeedbackService {
  public class FormException extends Exception {
  }

  // ------------------------------------------------------------------
  // Constants

  /** Only travel that was actually delivered is rated. Quote-stage and dead
   *  lines (Calculation, Offered, Accepted, Rejected, Canceled) are excluded. */
  private static final Set<String> RATEABLE_RESERVATION_STATUS = new Set<String>{
    'Booked',
    'Invoiced',
    'Paid',
    'Completed'
  };

  /** Reservation__c.AccountType__c is the populated discriminator on the
   *  itinerary. Type__c looks right but is null on every record - do not use it. */
  private static final String TYPE_HOTEL = 'Hotel';
  private static final String TYPE_GOLF = 'Golfclub';
  private static final String TYPE_FLIGHT = 'Airline';
  private static final String TYPE_TRANSFER = 'TransferCompany';
  private static final String TYPE_RENTAL = 'CarRentalCompany';

  private static final Set<String> RATEABLE_ACCOUNT_TYPE = new Set<String>{
    TYPE_HOTEL,
    TYPE_GOLF,
    TYPE_FLIGHT,
    TYPE_TRANSFER,
    TYPE_RENTAL
  };

  private static final Integer SCORE_MIN = 1;
  private static final Integer SCORE_MAX = 10;
  private static final Integer PROMOTER_THRESHOLD = 9;
  private static final Integer COMMENT_MAX_LEN = 2000;
  private static final Integer ITEM_NAME_MAX_LEN = 255;
  private static final Set<String> LANGUAGES = new Set<String>{ 'DE', 'EN' };

  private static final Set<String> HOTEL_SUB_CATEGORIES = new Set<String>{
    'Room',
    'Service',
    'Catering',
    'Cleanliness'
  };

  // ------------------------------------------------------------------
  // DTOs - what crosses the wire to/from the LWC

  public class Context {
    @AuraEnabled
    public Boolean ok = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String bookingNumber;
    @AuraEnabled
    public String guestName;
    @AuraEnabled
    public String destination;
    @AuraEnabled
    public String region;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public String designerName;
    @AuraEnabled
    public String language;

    /** Drive the survey's screen skipping. */
    @AuraEnabled
    public Boolean hasFlight = false;
    @AuraEnabled
    public Boolean hasTransfers = false;
    @AuraEnabled
    public Boolean hasRentalCar = false;
    @AuraEnabled
    public Boolean hasHotels = false;
    @AuraEnabled
    public Boolean hasGolf = false;

    /** One card per distinct venue. */
    @AuraEnabled
    public List<RateableItem> hotels = new List<RateableItem>();
    @AuraEnabled
    public List<RateableItem> golfCourses = new List<RateableItem>();

    /** Public review links for the promoter thank-you screen, from custom metadata. */
    @AuraEnabled
    public String trustpilotUrl;
    @AuraEnabled
    public String googleMapsUrl;

    /** Shown as context on the single flight / transfer / rental car ratings. */
    @AuraEnabled
    public List<String> flightSuppliers = new List<String>();
    @AuraEnabled
    public List<String> transferSuppliers = new List<String>();
    @AuraEnabled
    public List<String> rentalSuppliers = new List<String>();
  }

  public class RateableItem {
    @AuraEnabled
    public String reservationId;
    @AuraEnabled
    public String name;
    /** Room type for hotels, service description for everything else. */
    @AuraEnabled
    public String detail;
    /** "Almancil, Portugal" - shown under the hotel name on its card. */
    @AuraEnabled
    public String location;
    /** Nights for hotels; null where it does not apply. */
    @AuraEnabled
    public Decimal nights;
    @AuraEnabled
    public String teeTime;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
  }

  public class SubmitResult {
    @AuraEnabled
    public Boolean ok = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String reference;
    /** True when the recommendation score earns the Trustpilot / Google invitation. */
    @AuraEnabled
    public Boolean showPublicReview = false;
  }

  // Inbound payload - plain classes, deserialized from JSON

  public class Payload {
    public String bookingNumber;
    public String secret;
    public String language;
    public Integer overallExperience;
    public String overallExperienceComment;
    public Integer consultation;
    public String consultationComment;
    public RatingInput flight;
    public RatingInput transfer;
    public RatingInput rentalCar;
    public List<ItemRatingInput> hotels;
    public List<ItemRatingInput> golfCourses;
    public Integer recommendation;
    public String nextDestination;
    public String positiveMoment;
    public String improvementSuggestions;
    public String generalFeedback;
    public String generalHotelComment;
    public String generalGolfComment;
    public Integer sustainabilityImportance;
  }

  public class RatingInput {
    public Integer score;
    public String comment;
  }

  public class ItemRatingInput {
    public String reservationId;
    public String itemName;
    public Integer score;
    public String comment;
    public Map<String, Integer> sub;
  }

  // ------------------------------------------------------------------
  // getContext

  public static Context getContext(String bookingNumber, String secret) {
    Context c = new Context();

    if (String.isBlank(bookingNumber) || String.isBlank(secret)) {
      c.message = 'invalid';
      return c;
    }

    Booking__c b = resolveBooking(bookingNumber, secret);
    if (b == null) {
      c.message = 'invalid';
      return c;
    }

    if (hasExistingResponse(b.Id)) {
      c.message = 'submitted';
      return c;
    }

    c.bookingNumber = b.BookingNumber__c;
    c.guestName = buildGuestName(b);
    c.destination = b.DestinationCountry__c;
    c.region = b.Region__c;
    c.startDate = formatDate(b.Start_Date__c);
    c.endDate = formatDate(b.End_Date__c);
    c.designerName = String.isNotBlank(b.Form_Designer_Name__c)
      ? b.Form_Designer_Name__c
      : (b.TravelDesigner__r != null ? b.TravelDesigner__r.Name : null);
    c.language = 'DE';

    Gx_Feedback_Setting__mdt cfg = reviewLinks();
    if (cfg != null) {
      c.trustpilotUrl = cfg.Trustpilot_URL__c;
      c.googleMapsUrl = cfg.Google_Maps_URL__c;
    }

    applyItinerary(c, loadRateableReservations(b.Id));

    // A booking with nothing rateable gets no survey rather than an empty one.
    if (
      !c.hasFlight &&
      !c.hasTransfers &&
      !c.hasRentalCar &&
      !c.hasHotels &&
      !c.hasGolf
    ) {
      c.message = 'empty';
      return c;
    }

    c.ok = true;
    return c;
  }

  /**
   * Splits the itinerary into what the survey asks about.
   * Repeat rows for the same venue collapse into one card - a real booking
   * carries the same hotel on four rows, one per room. Distinct venues never
   * collapse, so three hotels stay three cards.
   */
  private static void applyItinerary(Context c, List<Reservation__c> rows) {
    Set<String> seenHotels = new Set<String>();
    Set<String> seenGolf = new Set<String>();
    Set<String> seenFlight = new Set<String>();
    Set<String> seenTransfer = new Set<String>();
    Set<String> seenRental = new Set<String>();

    for (Reservation__c r : rows) {
      String venueKey = venueKeyFor(r);
      String venueName = venueNameFor(r);

      if (r.AccountType__c == TYPE_HOTEL) {
        if (seenHotels.add(venueKey)) {
          c.hotels.add(toItem(r, venueName));
        }
      } else if (r.AccountType__c == TYPE_GOLF) {
        if (seenGolf.add(venueKey)) {
          c.golfCourses.add(toItem(r, venueName));
        }
      } else if (r.AccountType__c == TYPE_FLIGHT) {
        if (seenFlight.add(venueKey)) {
          c.flightSuppliers.add(venueName);
        }
      } else if (r.AccountType__c == TYPE_TRANSFER) {
        if (seenTransfer.add(venueKey)) {
          c.transferSuppliers.add(venueName);
        }
      } else if (r.AccountType__c == TYPE_RENTAL) {
        if (seenRental.add(venueKey)) {
          c.rentalSuppliers.add(venueName);
        }
      }
    }

    c.hasHotels = !c.hotels.isEmpty();
    c.hasGolf = !c.golfCourses.isEmpty();
    c.hasFlight = !c.flightSuppliers.isEmpty();
    c.hasTransfers = !c.transferSuppliers.isEmpty();
    c.hasRentalCar = !c.rentalSuppliers.isEmpty();
  }

  private static RateableItem toItem(Reservation__c r, String venueName) {
    RateableItem i = new RateableItem();
    i.reservationId = r.Id;
    i.name = venueName;
    i.detail = r.Service__r != null ? r.Service__r.Name : null;
    i.location = venueLocationFor(r);
    i.nights = r.Duration__c;
    i.teeTime = r.TeeTime__c;
    i.startDate = formatDate(r.Date_Begin__c);
    i.endDate = formatDate(r.Date_End__c);
    return i;
  }

  /** Group by the venue Account; fall back to the service name, then the row itself. */
  private static String venueKeyFor(Reservation__c r) {
    if (r.Travel_Location__c != null) {
      return String.valueOf(r.Travel_Location__c);
    }
    if (r.Service__r != null && String.isNotBlank(r.Service__r.Name)) {
      return 'svc:' + r.Service__r.Name;
    }
    return 'res:' + r.Id;
  }

  private static String venueNameFor(Reservation__c r) {
    if (
      r.Travel_Location__r != null &&
      String.isNotBlank(r.Travel_Location__r.Name)
    ) {
      return r.Travel_Location__r.Name;
    }
    if (r.Service__r != null && String.isNotBlank(r.Service__r.Name)) {
      return r.Service__r.Name;
    }
    return r.Name;
  }

  // ------------------------------------------------------------------
  // submit

  public static SubmitResult submit(String payloadJson) {
    SubmitResult res = new SubmitResult();

    Payload p;
    try {
      p = (Payload) JSON.deserialize(payloadJson, Payload.class);
    } catch (Exception e) {
      res.message = 'Die Übermittlung konnte nicht gelesen werden.';
      return res;
    }
    if (
      p == null ||
      String.isBlank(p.bookingNumber) ||
      String.isBlank(p.secret)
    ) {
      res.message = 'Dieser Link ist ungültig oder abgelaufen.';
      return res;
    }

    Booking__c b = resolveBooking(p.bookingNumber, p.secret);
    if (b == null) {
      res.message = 'Dieser Link ist ungültig oder abgelaufen.';
      return res;
    }

    // One response per booking. This is a stronger constraint than the
    // per-hour rate limit the Reiseanmeldung form needs, because that form
    // legitimately accepts repeat submissions and this one does not.
    if (hasExistingResponse(b.Id)) {
      res.message = 'Für diese Reise haben wir Ihr Feedback bereits erhalten. Vielen Dank!';
      return res;
    }

    String problem = validate(p);
    if (problem != null) {
      res.message = problem;
      return res;
    }

    // Only reservations actually on this booking may be referenced, so a
    // tampered payload cannot attach feedback to someone else's trip.
    Map<Id, Reservation__c> allowed = new Map<Id, Reservation__c>(
      loadRateableReservations(b.Id)
    );

    Savepoint sp = Database.setSavepoint();
    try {
      Feedback_Response__c resp = buildResponse(p, b);
      insert resp;

      List<Feedback_Rating__c> ratings = buildRatings(p, resp.Id, allowed);
      if (!ratings.isEmpty()) {
        insert ratings;
      }

      res.ok = true;
      res.reference = [
        SELECT Name
        FROM Feedback_Response__c
        WHERE Id = :resp.Id
      ]
      .Name;
      res.showPublicReview = p.recommendation >= PROMOTER_THRESHOLD;
      return res;
    } catch (Exception e) {
      Database.rollback(sp);
      res.ok = false;
      res.message = 'Ihr Feedback konnte nicht gespeichert werden. Bitte versuchen Sie es später erneut.';
      return res;
    }
  }

  private static Feedback_Response__c buildResponse(Payload p, Booking__c b) {
    return new Feedback_Response__c(
      Booking__c = b.Id,
      Contact__c = b.MainContact__c,
      Language__c = LANGUAGES.contains(p.language) ? p.language : 'DE',
      Overall_Experience__c = p.overallExperience,
      Overall_Experience_Comment__c = clean(p.overallExperienceComment),
      Consultation_Rating__c = p.consultation,
      Consultation_Comment__c = clean(p.consultationComment),
      Recommendation_NPS__c = p.recommendation,
      Next_Destination__c = clean(p.nextDestination),
      Positive_Moment__c = clean(p.positiveMoment),
      Improvement_Suggestions__c = clean(p.improvementSuggestions),
      General_Feedback__c = clean(p.generalFeedback),
      General_Hotel_Comment__c = clean(p.generalHotelComment),
      General_Golf_Comment__c = clean(p.generalGolfComment),
      Sustainability_Importance__c = p.sustainabilityImportance,
      Public_Review_Prompted__c = p.recommendation >= PROMOTER_THRESHOLD,
      Submitted_On__c = Datetime.now()
    );
  }

  private static List<Feedback_Rating__c> buildRatings(
    Payload p,
    Id responseId,
    Map<Id, Reservation__c> allowed
  ) {
    List<Feedback_Rating__c> out = new List<Feedback_Rating__c>();

    addSingle(out, responseId, TYPE_FLIGHT, 'Flug', p.flight);
    addSingle(out, responseId, TYPE_TRANSFER, 'Transfer', p.transfer);
    addSingle(out, responseId, TYPE_RENTAL, 'Mietwagen', p.rentalCar);

    addItems(out, responseId, TYPE_HOTEL, p.hotels, allowed, true);
    addItems(out, responseId, TYPE_GOLF, p.golfCourses, allowed, false);

    return out;
  }

  private static void addSingle(
    List<Feedback_Rating__c> out,
    Id responseId,
    String category,
    String label,
    RatingInput input
  ) {
    if (input == null || !isValidScore(input.score)) {
      return;
    }
    out.add(
      new Feedback_Rating__c(
        Feedback_Response__c = responseId,
        Category__c = category,
        Item_Name__c = label,
        Score__c = input.score,
        Comment__c = clean(input.comment)
      )
    );
  }

  private static void addItems(
    List<Feedback_Rating__c> out,
    Id responseId,
    String category,
    List<ItemRatingInput> items,
    Map<Id, Reservation__c> allowed,
    Boolean withSubRatings
  ) {
    if (items == null) {
      return;
    }
    for (ItemRatingInput item : items) {
      if (item == null || !isValidScore(item.score)) {
        continue;
      }

      Id reservationId = resolveReservationId(item.reservationId, allowed);
      String itemName = resolveItemName(item, reservationId, allowed);

      out.add(
        new Feedback_Rating__c(
          Feedback_Response__c = responseId,
          Reservation__c = reservationId,
          Category__c = category,
          Item_Name__c = itemName,
          Score__c = item.score,
          Comment__c = clean(item.comment)
        )
      );

      if (!withSubRatings || item.sub == null) {
        continue;
      }
      for (String key : item.sub.keySet()) {
        if (
          !HOTEL_SUB_CATEGORIES.contains(key) ||
          !isValidScore(item.sub.get(key))
        ) {
          continue;
        }
        out.add(
          new Feedback_Rating__c(
            Feedback_Response__c = responseId,
            Reservation__c = reservationId,
            Category__c = category,
            Sub_Category__c = key,
            Item_Name__c = itemName,
            Score__c = item.sub.get(key)
          )
        );
      }
    }
  }

  /** Null unless the id is a reservation on this very booking. */
  private static Id resolveReservationId(
    String raw,
    Map<Id, Reservation__c> allowed
  ) {
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      Id candidate = Id.valueOf(raw);
      return allowed.containsKey(candidate) ? candidate : null;
    } catch (Exception e) {
      return null;
    }
  }

  /** Prefer the server's own name for the venue; only fall back to the client's. */
  private static String resolveItemName(
    ItemRatingInput item,
    Id reservationId,
    Map<Id, Reservation__c> allowed
  ) {
    if (reservationId != null) {
      return truncate(
        venueNameFor(allowed.get(reservationId)),
        ITEM_NAME_MAX_LEN
      );
    }
    return truncate(stripTags(item.itemName), ITEM_NAME_MAX_LEN);
  }

  // ------------------------------------------------------------------
  // Validation

  private static String validate(Payload p) {
    if (!isValidScore(p.overallExperience)) {
      return 'Bitte bewerten Sie Ihren Gesamteindruck.';
    }
    if (!isValidScore(p.recommendation)) {
      return 'Bitte beantworten Sie die Weiterempfehlungsfrage.';
    }
    if (p.consultation != null && !isValidScore(p.consultation)) {
      return 'Ungültige Bewertung.';
    }
    if (
      p.sustainabilityImportance != null &&
      !isValidScore(p.sustainabilityImportance)
    ) {
      return 'Ungültige Bewertung.';
    }
    return null;
  }

  private static Boolean isValidScore(Integer score) {
    return score != null && score >= SCORE_MIN && score <= SCORE_MAX;
  }

  // ------------------------------------------------------------------
  // Shared helpers

  private static Booking__c resolveBooking(
    String bookingNumber,
    String secret
  ) {
    List<Booking__c> found = [
      SELECT
        Id,
        BookingNumber__c,
        MainContact__c,
        MainContactName__c,
        Start_Date__c,
        End_Date__c,
        toLabel(DestinationCountry__c),
        toLabel(Region__c),
        TravelDesigner__r.Name,
        Form_Designer_Name__c
      FROM Booking__c
      WHERE BookingNumber__c = :bookingNumber AND Form_Secret__c = :secret
      LIMIT 2
    ];
    return found.size() == 1 ? found[0] : null;
  }

  private static List<Reservation__c> loadRateableReservations(Id bookingId) {
    return [
      SELECT
        Id,
        Name,
        AccountType__c,
        Status__c,
        TeeTime__c,
        Duration__c,
        Date_Begin__c,
        Date_End__c,
        Travel_Location__c,
        Travel_Location__r.Name,
        Travel_Location__r.BillingCity,
        Travel_Location__r.BillingCountry,
        Service__r.Name
      FROM Reservation__c
      WHERE
        Booking__c = :bookingId
        AND Status__c IN :RATEABLE_RESERVATION_STATUS
        AND AccountType__c IN :RATEABLE_ACCOUNT_TYPE
      ORDER BY Date_Begin__c NULLS LAST, Name
    ];
  }

  private static Boolean hasExistingResponse(Id bookingId) {
    return [
        SELECT COUNT()
        FROM Feedback_Response__c
        WHERE Booking__c = :bookingId
      ] > 0;
  }

  private static String buildGuestName(Booking__c b) {
    return String.isNotBlank(b.MainContactName__c)
      ? b.MainContactName__c
      : null;
  }

  /** City and country of the venue, e.g. "Almancil, Portugal". */
  private static String venueLocationFor(Reservation__c r) {
    if (r.Travel_Location__r == null) {
      return null;
    }
    List<String> parts = new List<String>();
    if (String.isNotBlank(r.Travel_Location__r.BillingCity)) {
      parts.add(r.Travel_Location__r.BillingCity);
    }
    if (String.isNotBlank(r.Travel_Location__r.BillingCountry)) {
      parts.add(r.Travel_Location__r.BillingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  /** Review links live in custom metadata so marketing can change them without a deploy. */
  private static Gx_Feedback_Setting__mdt reviewLinks() {
    List<Gx_Feedback_Setting__mdt> rows = [
      SELECT Trustpilot_URL__c, Google_Maps_URL__c
      FROM Gx_Feedback_Setting__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static String formatDate(Date d) {
    return d == null ? null : String.valueOf(d);
  }

  /** Guest free text: drop markup, then cap at the field length. */
  private static String clean(String raw) {
    return truncate(stripTags(raw), COMMENT_MAX_LEN);
  }

  private static String stripTags(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.stripHtmlTags().trim();
  }

  private static String truncate(String raw, Integer max) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.length() > max ? raw.left(max) : raw;
  }
}
