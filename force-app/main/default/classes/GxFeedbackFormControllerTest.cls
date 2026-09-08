/**
 * GxFeedbackFormControllerTest
 *
 * The controller is a thin wrapper, so this covers the pass-through and,
 * importantly, the catch paths: a public form must degrade to a neutral
 * message rather than surfacing an exception to an anonymous visitor.
 */
@IsTest
private class GxFeedbackFormControllerTest {
  private static final String SECRET = 'ctrl-secret-1';
  private static final String BOOKING_NUM = 'TEST-GX-CTRL';

  @TestSetup
  static void setup() {
    // See GxFeedbackServiceTest.setup for why the pricing trigger is bypassed.
    TriggerHandler.bypass('ReservationTriggerHandler');

    Account customer = new Account(Name = 'Controller Customer');
    insert customer;

    // Account_Type__c must match the reservation's AccountType__c for the lookup filter.
    Account hotel = new Account(
      Name = 'Controller Hotel',
      Account_Type__c = 'Hotel'
    );
    insert hotel;

    Booking__c b = new Booking__c(
      Quote_for__c = customer.Id,
      BookingNumber__c = BOOKING_NUM,
      Form_Secret__c = SECRET,
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'EG',
      Status__c = 'Completed',
      Start_Date__c = Date.today().addDays(-15),
      End_Date__c = Date.today().addDays(-8)
    );
    insert b;

    insert new Reservation__c(
      Booking__c = b.Id,
      Travel_Location__c = hotel.Id,
      AccountType__c = 'Hotel',
      Pricing__c = 'Leistung',
      Status__c = 'Completed',
      Date_Begin__c = Date.today().addDays(-14),
      Date_End__c = Date.today().addDays(-9)
    );

    TriggerHandler.clearBypass('ReservationTriggerHandler');
  }

  @IsTest
  static void getContextPassesThroughToTheService() {
    GxFeedbackService.Context c = GxFeedbackFormController.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isTrue(c.ok, 'A valid link opens the survey through the controller');
    Assert.areEqual(
      1,
      c.hotels.size(),
      'The booked hotel is offered for rating'
    );
  }

  @IsTest
  static void submitPassesThroughToTheService() {
    String payload = JSON.serialize(
      new Map<String, Object>{
        'bookingNumber' => BOOKING_NUM,
        'secret' => SECRET,
        'overallExperience' => 10,
        'recommendation' => 10
      }
    );

    GxFeedbackService.SubmitResult r = GxFeedbackFormController.submit(payload);

    Assert.isTrue(r.ok, 'A valid submission succeeds through the controller');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Feedback_Response__c],
      'The response is written'
    );
  }

  @IsTest
  static void getContextHidesUnexpectedFailures() {
    GxFeedbackFormController.throwForTest = true;

    GxFeedbackService.Context c = GxFeedbackFormController.getContext(
      BOOKING_NUM,
      SECRET
    );

    Assert.isFalse(c.ok, 'An unexpected failure never reports success');
    Assert.areEqual(
      'invalid',
      c.message,
      'The visitor sees a neutral message, not an exception'
    );
  }

  @IsTest
  static void submitHidesUnexpectedFailures() {
    GxFeedbackFormController.throwForTest = true;

    GxFeedbackService.SubmitResult r = GxFeedbackFormController.submit('{}');

    Assert.isFalse(r.ok, 'An unexpected failure never reports success');
    Assert.isTrue(
      r.message.contains('konnte nicht verarbeitet werden'),
      'The visitor sees a neutral German message'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Feedback_Response__c],
      'Nothing is written when the call fails'
    );
  }
}
