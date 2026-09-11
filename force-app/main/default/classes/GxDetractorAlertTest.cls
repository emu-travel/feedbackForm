/**
 * GxDetractorAlertTest
 *
 * One unhappy guest (recommendation 3) on a trip whose travel designer is the
 * running user. Settings are pinned per test, and whether the org counts as a
 * sandbox is set explicitly, because who gets the email depends on both.
 */
@IsTest
private class GxDetractorAlertTest {
  private static final String TEAM = 'team@example.com';

  @TestSetup
  static void setup() {
    Account acct = new Account(Name = 'Alert Customer');
    insert acct;
    Contact guest = new Contact(
      FirstName = 'Greta',
      LastName = 'Gast',
      Email = 'greta@example.com',
      Phone = '+49 40 123456',
      AccountId = acct.Id
    );
    insert guest;
    Opportunity opp = new Opportunity(
      Name = 'Alert Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = acct.Id
    );
    insert opp;
    Booking__c b = new Booking__c(
      Opportunity__c = opp.Id,
      Quote_for__c = acct.Id,
      MainContact__c = guest.Id,
      BookingNumber__c = 'GXA-1',
      Travel_Type__c = 'FIT',
      DestinationCountry__c = 'PT',
      Region__c = 'Algarve',
      Status__c = 'Feedback',
      Start_Date__c = Date.today().addDays(-10),
      End_Date__c = Date.today().addDays(-3)
    );
    insert b;
    b.TravelDesigner__c = UserInfo.getUserId();
    Database.update(b, AccessLevel.SYSTEM_MODE);

    Feedback_Response__c r = new Feedback_Response__c(
      Booking__c = b.Id,
      Contact__c = guest.Id,
      Overall_Experience__c = 5,
      Consultation_Rating__c = 8,
      Recommendation_NPS__c = 3,
      Improvement_Suggestions__c = 'Das Zimmer war zu laut.',
      Submitted_On__c = Datetime.now()
    );
    insert r;
    insert new List<Feedback_Rating__c>{
      new Feedback_Rating__c(
        Feedback_Response__c = r.Id,
        Category__c = 'Hotel',
        Item_Name__c = 'Conrad Algarve',
        Score__c = 4,
        Comment__c = '<b>Laut</b>'
      ),
      new Feedback_Rating__c(
        Feedback_Response__c = r.Id,
        Category__c = 'Hotel',
        Item_Name__c = 'Conrad Algarve',
        Sub_Category__c = 'Room',
        Score__c = 3
      ),
      new Feedback_Rating__c(
        Feedback_Response__c = r.Id,
        Category__c = 'Golfclub',
        Item_Name__c = 'Quinta do Lago',
        Score__c = 9
      )
    };
  }

  private static Id responseId() {
    return [SELECT Id FROM Feedback_Response__c LIMIT 1].Id;
  }

  private static void settings(Boolean alertsOn, String copy) {
    GxFeedbackSettings.useForTest(
      new Gx_Feedback_Setting__mdt(
        Detractor_Alerts_On__c = alertsOn,
        Alert_Copy_Email__c = copy
      )
    );
  }

  /** Raises the alert as the survey would, and lets the event trigger run. */
  private static void alert(Integer recommendation) {
    Test.startTest();
    GxDetractorAlert.raise(responseId(), recommendation);
    Test.stopTest();
  }

  @IsTest
  static void anUnhappyGuestReachesTheirDesignerWithTheTeamCopied() {
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    alert(3);

    Assert.areEqual(1, GxDetractorAlert.sent.size(), 'One alert');
    Messaging.SingleEmailMessage mail = GxDetractorAlert.sent[0];
    Assert.areEqual(
      new List<String>{ UserInfo.getUserEmail() },
      mail.getToAddresses(),
      'To the travel designer'
    );
    Assert.areEqual(
      new List<String>{ TEAM },
      mail.getCcAddresses(),
      'with the team copied'
    );
    Assert.isTrue(
      mail.getSubject().contains('Greta Gast') &&
        mail.getSubject().contains('3/10') &&
        mail.getSubject().contains('GXA-1'),
      'The subject says who, how unhappy, and which trip: ' + mail.getSubject()
    );
    String body = mail.getHtmlBody();
    Assert.isTrue(body.contains('Conrad Algarve: 4'), 'What stood out');
    Assert.isTrue(body.contains('Room: 3'), 'down to the room');
    Assert.isFalse(body.contains('Quinta do Lago: 9'), 'but not the good bits');
    Assert.isTrue(body.contains('Das Zimmer war zu laut.'), 'In their words');
    Assert.isTrue(body.contains('+49 40 123456'), 'and how to reach them');
    Assert.isTrue(
      body.contains('/lightning/r/Feedback_Response__c/'),
      'with a link to the full response'
    );
  }

  @IsTest
  static void whatTheGuestWroteCannotInjectMarkup() {
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    alert(3);

    String body = GxDetractorAlert.sent[0].getHtmlBody();
    Assert.isFalse(body.contains('<b>Laut</b>'), 'Guest text is escaped');
    Assert.isTrue(body.contains('&lt;b&gt;Laut&lt;/b&gt;'), 'and still shown');
  }

  @IsTest
  static void aSandboxNeverEmailsTheDesigner() {
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = true;

    alert(3);

    Messaging.SingleEmailMessage mail = GxDetractorAlert.sent[0];
    Assert.areEqual(
      new List<String>{ TEAM },
      mail.getToAddresses(),
      'Only the team address, whoever the designer is'
    );
    Assert.isNull(mail.getCcAddresses(), 'and nobody else');
    Assert.isTrue(mail.getSubject().startsWith('[Sandbox]'), 'marked as such');
  }

  @IsTest
  static void aSandboxWithNoTeamAddressSendsNothing() {
    settings(true, null);
    GxDetractorAlert.sandboxOverride = true;

    alert(3);

    Assert.areEqual(0, GxDetractorAlert.sent.size(), 'Nobody to tell safely');
  }

  @IsTest
  static void aTripWithNoDesignerGoesToTheTeam() {
    Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
    b.TravelDesigner__c = null;
    Database.update(b, AccessLevel.SYSTEM_MODE);
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    alert(3);

    Assert.areEqual(
      new List<String>{ TEAM },
      GxDetractorAlert.sent[0].getToAddresses(),
      'Someone always hears about it'
    );
  }

  @IsTest
  static void aPassiveOrPromoterRaisesNothing() {
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    alert(7);

    Assert.isTrue(GxDetractorAlert.raised.isEmpty(), 'Only 6 and below');
    Assert.areEqual(0, GxDetractorAlert.sent.size(), 'and nothing is sent');
  }

  @IsTest
  static void alertsCanBeSwitchedOff() {
    settings(false, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    alert(2);

    Assert.isTrue(GxDetractorAlert.raised.isEmpty(), 'Nothing raised');
    Assert.areEqual(0, GxDetractorAlert.sent.size(), 'nothing sent');
  }

  @IsTest
  static void aMalformedEventIsIgnored() {
    settings(true, TEAM);
    GxDetractorAlert.sandboxOverride = false;

    GxDetractorAlert.send(
      new List<Gx_Detractor_Alert__e>{
        new Gx_Detractor_Alert__e(Response_Id__c = 'not-an-id')
      }
    );

    Assert.areEqual(0, GxDetractorAlert.sent.size(), 'No alert, no error');
  }
}
