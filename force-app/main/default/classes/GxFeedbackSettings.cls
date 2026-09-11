/**
 * GxFeedbackSettings
 *
 * Single reader for Gx_Feedback_Setting__mdt, so the survey and its dispatch
 * cannot drift apart on what the configuration says.
 *
 * Read through getInstance rather than SOQL: a guest user cannot query a custom
 * metadata type at all - SOQL reports it as an unsupported sObject - and
 * getInstance costs nothing against the query limits either.
 */
public with sharing class GxFeedbackSettings {
  private static final String RECORD = 'Default';
  private static Gx_Feedback_Setting__mdt cached;

  @TestVisible
  private static Gx_Feedback_Setting__mdt config() {
    if (cached == null) {
      Gx_Feedback_Setting__mdt found = Gx_Feedback_Setting__mdt.getInstance(
        RECORD
      );
      cached = found == null ? new Gx_Feedback_Setting__mdt() : found;
    }
    return cached;
  }

  /** Lets a test pin the configuration instead of depending on the deployed record. */
  @TestVisible
  private static void useForTest(Gx_Feedback_Setting__mdt stub) {
    cached = stub;
  }

  public static String trustpilotUrl() {
    return config().Trustpilot_URL__c;
  }

  public static String googleMapsUrl() {
    return config().Google_Maps_URL__c;
  }

  /** Days a feedback link keeps working, from the moment the guest was last asked. */
  public static Decimal linkValidityDays() {
    return config().Link_Validity_Days__c;
  }

  /** Hours to wait after a trip ends before inviting the guest. */
  public static Decimal dispatchDelayHours() {
    return config().Dispatch_Delay_Hours__c;
  }

  /**
   * Days to wait after inviting a guest before reminding them. Blank or zero
   * switches reminders off.
   */
  public static Decimal reminderDelayDays() {
    return config().Reminder_Delay_Days__c;
  }

  /**
   * Trips that ended before this are never invited. Null means no trip is,
   * by design - see Survey_Start_Date__c.
   */
  public static Date surveyStartDate() {
    return config().Survey_Start_Date__c;
  }

  /** Trips older than this many days are never invited. Blank or zero: no cap. */
  public static Decimal maxTripAgeDays() {
    return config().Max_Trip_Age_Days__c;
  }

  /** Public address of the survey page. Differs per environment. */
  public static String surveyBaseUrl() {
    return config().Survey_Base_URL__c;
  }

  /** Org-wide address the invitation is sent from. */
  public static String senderEmail() {
    return config().Sender_Email__c;
  }
}
