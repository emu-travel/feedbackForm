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

  /**
   * Whether a trip actually happened is decided by the booking, not by its
   * individual lines. Reservation statuses are not reliably advanced when a trip
   * completes - a real booking sits in Feedback with its green fee still at
   * Calculation - and on a golf product, silently dropping the golf is worse
   * than the alternative.
   */
  private static final Set<String> DELIVERED_BOOKING_STATUS = new Set<String>{
    'Feedback',
    'Completed',
    'Paid',
    'Invoiced'
  };

  /** Never rated, whatever the booking says: the guest did not receive these. */
  private static final Set<String> EXCLUDED_RESERVATION_STATUS = new Set<String>{
    'Rejected',
    'Canceled'
  };

  /** Used only when the booking itself does not yet say the trip was delivered. */
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
    public String improvementSuggestions;
    public String generalFeedback;
    public String generalHotelComment;
    public String generalGolfComment;
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

    if (isExpired(b)) {
      c.message = 'expired';
      return c;
    }

    c.bookingNumber = b.BookingNumber__c;
    c.guestName = buildGuestName(b);
    c.destination = b.DestinationCountry__c;
    c.region = b.Region__c;
    c.startDate = formatDate(b.Start_Date__c);
    c.endDate = formatDate(b.End_Date__c);
    // Deliberately no TravelDesigner__r.Name traversal: guest users have heavily
    // restricted access to User, and Form_Designer_Name__c exists on Booking__c
    // precisely so a public form never has to reach across to it.
    c.designerName = b.Form_Designer_Name__c;
    c.language = 'DE';

    c.trustpilotUrl = GxFeedbackSettings.trustpilotUrl();
    c.googleMapsUrl = GxFeedbackSettings.googleMapsUrl();

    applyItinerary(c, loadRateableReservations(b));

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
    if (isExpired(b)) {
      res.message = 'Der Link zu dieser Umfrage ist leider abgelaufen.';
      return res;
    }

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
      loadRateableReservations(b)
    );

    Savepoint sp = Database.setSavepoint();
    try {
      Feedback_Response__c resp = buildResponse(p, b);
      // System mode, deliberately. Feedback_Response__c is a detail of
      // Booking__c, and inserting a detail record requires EDIT access to its
      // master. A guest user can only ever hold Read Only on a booking - that
      // is the hard ceiling on what a guest sharing rule can grant - so in user
      // mode this insert always fails with
      // INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY, and `without sharing`
      // does not lift it because guest record access is enforced beneath it.
      //
      // What actually guards this write is above, not here: the booking is
      // resolved by its secret, the link must not have expired, feedback must
      // not already exist, the payload is validated, and every reservation id
      // is checked against the ones on this booking. The guest's own record
      // access was never the control.
      Database.insert(resp, true, AccessLevel.SYSTEM_MODE);

      List<Feedback_Rating__c> ratings = buildRatings(p, resp.Id, allowed);
      if (!ratings.isEmpty()) {
        Database.insert(ratings, true, AccessLevel.SYSTEM_MODE);
      }

      res.ok = true;
      res.reference = [
        SELECT Name
        FROM Feedback_Response__c
        WHERE Id = :resp.Id
      ]
      .Name;
      res.showPublicReview = p.recommendation >= PROMOTER_THRESHOLD;
      // An unhappy guest reaches their travel designer at once. Published
      // after commit, so the email goes out only once this answer is saved.
      GxDetractorAlert.raise(resp.Id, p.recommendation);
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
      Improvement_Suggestions__c = clean(p.improvementSuggestions),
      General_Feedback__c = clean(p.generalFeedback),
      General_Hotel_Comment__c = clean(p.generalHotelComment),
      General_Golf_Comment__c = clean(p.generalGolfComment),
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

    addSuppliers(out, responseId, TYPE_FLIGHT, 'Flug', p.flight, allowed);
    addSuppliers(
      out,
      responseId,
      TYPE_TRANSFER,
      'Transfer',
      p.transfer,
      allowed
    );
    addSuppliers(
      out,
      responseId,
      TYPE_RENTAL,
      'Mietwagen',
      p.rentalCar,
      allowed
    );

    addItems(out, responseId, TYPE_HOTEL, p.hotels, allowed, true);
    addItems(out, responseId, TYPE_GOLF, p.golfCourses, allowed, false);

    return out;
  }

  /**
   * One flight, transfer or rental-car answer, saved against every supplier
   * the guest was shown for it.
   *
   * The survey asks a single question per mode - "how were the flights" - but
   * a trip can carry Lufthansa out and Condor back. Storing the answer under
   * a generic "Flug" made every airline indistinguishable in reporting, so it
   * is recorded once per supplier instead, each row linked to its reservation.
   * The guest rated the flights as a whole, so each airline on the trip gets
   * that same score. Dashboards count distinct responses, not rows, so this
   * does not inflate any total.
   *
   * Suppliers are de-duplicated exactly as the survey de-duplicates them for
   * display, so what is saved matches what the guest saw. If none can be found
   * the answer is kept under the generic label rather than dropped.
   */
  private static void addSuppliers(
    List<Feedback_Rating__c> out,
    Id responseId,
    String category,
    String fallbackLabel,
    RatingInput input,
    Map<Id, Reservation__c> allowed
  ) {
    if (input == null || !isValidScore(input.score)) {
      return;
    }
    String comment = clean(input.comment);

    Set<String> seen = new Set<String>();
    Integer added = 0;
    for (Reservation__c r : allowed.values()) {
      if (r.AccountType__c != category || !seen.add(venueKeyFor(r))) {
        continue;
      }
      out.add(
        new Feedback_Rating__c(
          Feedback_Response__c = responseId,
          Reservation__c = r.Id,
          Category__c = category,
          Item_Name__c = venueNameFor(r),
          Score__c = input.score,
          Comment__c = comment
        )
      );
      added++;
    }

    if (added > 0) {
      return;
    }
    out.add(
      new Feedback_Rating__c(
        Feedback_Response__c = responseId,
        Category__c = category,
        Item_Name__c = fallbackLabel,
        Score__c = input.score,
        Comment__c = comment
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
        Status__c,
        Start_Date__c,
        End_Date__c,
        toLabel(DestinationCountry__c),
        toLabel(Region__c),
        Form_Designer_Name__c,
        Survey_Sent_On__c
      FROM Booking__c
      WHERE BookingNumber__c = :bookingNumber AND Form_Secret__c = :secret
      LIMIT 2
    ];
    return found.size() == 1 ? found[0] : null;
  }

  /**
   * What the survey would ask this booking about. Dispatch uses it to avoid
   * inviting a guest to a survey with no questions in it.
   */
  public static List<Reservation__c> rateableItemsFor(Id bookingId) {
    List<Booking__c> found = [
      SELECT Id, Status__c
      FROM Booking__c
      WHERE Id = :bookingId
      LIMIT 1
    ];
    return found.isEmpty()
      ? new List<Reservation__c>()
      : loadRateableReservations(found[0]);
  }

  /**
   * Which of these bookings the survey would have something to ask about, in
   * two queries however many bookings are passed in. Dispatch uses it to keep a
   * nightly batch inside the SOQL limit; rateableItemsFor above is the
   * single-booking form for the survey itself.
   */
  public static Set<Id> bookingsWithRateableItems(Set<Id> bookingIds) {
    Set<Id> withItems = new Set<Id>();
    if (bookingIds == null || bookingIds.isEmpty()) {
      return withItems;
    }
    Map<Id, Booking__c> bookings = new Map<Id, Booking__c>(
      [SELECT Id, Status__c FROM Booking__c WHERE Id IN :bookingIds]
    );
    Map<Id, List<Reservation__c>> rateable = loadRateableReservations(bookings);
    for (Id bookingId : rateable.keySet()) {
      if (!rateable.get(bookingId).isEmpty()) {
        withItems.add(bookingId);
      }
    }
    return withItems;
  }

  /**
   * On a delivered booking every line is rated except the ones the guest never
   * received. On a booking that is not yet delivered we fall back to the strict
   * line-level check, so a trip still being quoted cannot be surveyed by mistake.
   */
  private static List<Reservation__c> loadRateableReservations(Booking__c b) {
    List<Reservation__c> found = loadRateableReservations(
        new Map<Id, Booking__c>{ b.Id => b }
      )
      .get(b.Id);
    return found == null ? new List<Reservation__c>() : found;
  }

  /**
   * The bulk form, and the only place the rateability rules are actually
   * expressed - the single-booking version above delegates here.
   *
   * Bulk because dispatch asks about a whole nightly batch: at two queries per
   * booking a 200 booking run would exhaust the SOQL limit before it reached
   * the fiftieth guest, and nothing in a one-booking test would ever show it.
   */
  private static Map<Id, List<Reservation__c>> loadRateableReservations(
    Map<Id, Booking__c> bookings
  ) {
    Map<Id, List<Reservation__c>> byBooking = new Map<Id, List<Reservation__c>>();
    if (bookings == null || bookings.isEmpty()) {
      return byBooking;
    }
    for (Id bookingId : bookings.keySet()) {
      byBooking.put(bookingId, new List<Reservation__c>());
    }

    // Booking__c and AccountType__c carry no field permissions of their own
    // (master-detail and a required picklist), so selecting them here does not
    // widen what the guest permission set has to grant.
    for (Reservation__c r : [
      SELECT
        Id,
        Name,
        Booking__c,
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
        Booking__c IN :bookings.keySet()
        AND Status__c NOT IN :EXCLUDED_RESERVATION_STATUS
        AND AccountType__c IN :RATEABLE_ACCOUNT_TYPE
      ORDER BY Date_Begin__c NULLS LAST, Name
    ]) {
      Booking__c b = bookings.get(r.Booking__c);
      if (b == null) {
        continue;
      }
      // On a delivered booking every line is rated except the ones the guest
      // never received. On a booking that is not yet delivered we fall back to
      // the strict line-level check, so a trip still being quoted cannot be
      // surveyed by mistake.
      Boolean rateable =
        DELIVERED_BOOKING_STATUS.contains(b.Status__c) ||
        RATEABLE_RESERVATION_STATUS.contains(r.Status__c);
      if (rateable) {
        byBooking.get(r.Booking__c).add(r);
      }
    }
    return byBooking;
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

  /**
   * A feedback link stops working a configurable number of days after the guest
   * was last asked for feedback, so a forwarded email or a shared browser does
   * not expose someone's itinerary indefinitely.
   *
   * Counted from the invitation rather than from the trip, because a guest who
   * is reminded on day ten would otherwise be handed a link with days left on
   * it - which defeats the point of reminding them. A reminder moves
   * Survey_Sent_On__c forward, so it also renews the window.
   *
   * Dates the survey can measure from, in order: when we last asked, then the
   * trip end, then the trip start. The trip dates are the fallback for bookings
   * invited before Survey_Sent_On__c existed. A booking carrying none of the
   * three is not expired - the secret remains the gate. Blank or zero validity
   * disables expiry entirely.
   */
  @TestVisible
  private static Boolean isExpired(Booking__c b) {
    Decimal validityDays = GxFeedbackSettings.linkValidityDays();
    if (validityDays == null || validityDays <= 0) {
      return false;
    }
    Date reference = b.Survey_Sent_On__c != null
      ? b.Survey_Sent_On__c.date()
      : (b.End_Date__c != null ? b.End_Date__c : b.Start_Date__c);
    if (reference == null) {
      return false;
    }
    return reference.daysBetween(Date.today()) > validityDays.intValue();
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
