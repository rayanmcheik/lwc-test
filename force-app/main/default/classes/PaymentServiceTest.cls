@IsTest
public class PaymentServiceTest {

    // =========================================================
    // HELPER
    // =========================================================
    private static Opportunity createOpportunity(
        String name,
        Decimal amount
    ) {
        Opportunity opp = new Opportunity(
            Name = name,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = amount
        );

        insert opp;
        return opp;
    }


    // =========================================================
    // 1. PAID PAYMENT UPDATES TOTAL PAID
    // =========================================================
    @IsTest
    static void testPaidPaymentUpdatesTotalPaid() {

        Opportunity opp =
            createOpportunity('Test Opportunity', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 2000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        Test.startTest();
        insert payment;
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Total_Paid__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            2000,
            updatedOpp.Total_Paid__c
        );
    }


    // =========================================================
    // 2. NON-PAID PAYMENT IS NOT INCLUDED
    // =========================================================
    @IsTest
    static void testNonPaidPaymentNotIncluded() {

        Opportunity opp =
            createOpportunity('Pending Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 3000,
            Status__c = 'Pending'
        );

        Test.startTest();
        insert payment;
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Total_Paid__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            0,
            updatedOpp.Total_Paid__c
        );
    }


    // =========================================================
    // 3. MULTIPLE PAYMENTS AT SAME TIME
    //    IMPORTANT BULK TEST
    // =========================================================
    @IsTest
    static void testMultiplePaymentsBulk() {

        Opportunity opp =
            createOpportunity('Bulk Test', 20000);

        List<Payment__c> payments =
            new List<Payment__c>{
                
                new Payment__c(
                    Opportunity__c = opp.Id,
                    Amount__c = 2000,
                    Status__c = 'Paid',
                    Payment_Date__c = Date.today()
                ),

                new Payment__c(
                    Opportunity__c = opp.Id,
                    Amount__c = 3000,
                    Status__c = 'Paid',
                    Payment_Date__c = Date.today()
                ),

                new Payment__c(
                    Opportunity__c = opp.Id,
                    Amount__c = 4000,
                    Status__c = 'Paid',
                    Payment_Date__c = Date.today()
                )
            };

        Test.startTest();
        insert payments;
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Total_Paid__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            9000,
            updatedOpp.Total_Paid__c
        );
    }


    // =========================================================
    // 4. TOTAL PAID CANNOT EXCEED OPPORTUNITY AMOUNT
    // =========================================================
    @IsTest
    static void testTotalCannotExceedOpportunityAmount() {

        Opportunity opp =
            createOpportunity('Limit Test', 5000);

        Payment__c payment1 = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 4000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        insert payment1;

        Payment__c payment2 = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 2000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(payment2, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Payment should fail because total would exceed Opportunity Amount.'
        );

        Opportunity updatedOpp = [
            SELECT Total_Paid__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            4000,
            updatedOpp.Total_Paid__c
        );
    }


    // =========================================================
    // 5. PAID PAYMENT CANNOT BE DELETED
    // =========================================================
    @IsTest
    static void testPaidPaymentCannotBeDeleted() {

        Opportunity opp =
            createOpportunity('Delete Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 2000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        insert payment;

        Test.startTest();

        Database.DeleteResult result =
            Database.delete(payment, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'A Paid Payment should not be deletable.'
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Payment__c
                WHERE Id = :payment.Id
            ]
        );
    }


    // =========================================================
    // 6. PAYMENT CHANGES OPPORTUNITY
    //    BOTH OLD AND NEW OPPORTUNITIES MUST UPDATE
    // =========================================================
    @IsTest
    static void testPaymentChangesOpportunity() {

        Opportunity opp1 =
            createOpportunity('Opportunity A', 10000);

        Opportunity opp2 =
            createOpportunity('Opportunity B', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp1.Id,
            Amount__c = 3000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        insert payment;

        payment.Opportunity__c = opp2.Id;

        Test.startTest();
        update payment;
        Test.stopTest();

        Map<Id, Opportunity> opportunities =
            new Map<Id, Opportunity>([
                SELECT Id, Total_Paid__c
                FROM Opportunity
                WHERE Id IN :new Set<Id>{opp1.Id, opp2.Id}
            ]);

        System.assertEquals(
            0,
            opportunities.get(opp1.Id).Total_Paid__c,
            'Old Opportunity should become 0.'
        );

        System.assertEquals(
            3000,
            opportunities.get(opp2.Id).Total_Paid__c,
            'New Opportunity should contain the Payment.'
        );
    }


    // =========================================================
    // 7. STATUS CHANGES FROM NON-PAID TO PAID
    // =========================================================
    @IsTest
    static void testStatusChangesToPaid() {

        Opportunity opp =
            createOpportunity('Status Change Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 2500,
            Status__c = 'Pending'
        );

        insert payment;

        payment.Status__c = 'Paid';
        payment.Payment_Date__c = Date.today();

        Test.startTest();
        update payment;
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Total_Paid__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            2500,
            updatedOpp.Total_Paid__c
        );
    }


    // =========================================================
    // 8. VALIDATION RULE: AMOUNT MUST BE > 0
    // =========================================================
    @IsTest
    static void testAmountMustBeGreaterThanZero() {

        Opportunity opp =
            createOpportunity('Amount Validation', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 0,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(payment, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess()
        );
    }


    // =========================================================
    // 9. VALIDATION RULE: PAID REQUIRES PAYMENT DATE
    // =========================================================
    @IsTest
    static void testPaidRequiresPaymentDate() {

        Opportunity opp =
            createOpportunity('Date Required Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 1000,
            Status__c = 'Paid'
        );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(payment, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess()
        );
    }


    // =========================================================
    // 10. VALIDATION RULE: PAYMENT DATE CANNOT BE FUTURE
    // =========================================================
    @IsTest
    static void testPaidDateCannotBeFuture() {

        Opportunity opp =
            createOpportunity('Future Date Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 1000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today().addDays(1)
        );

        Test.startTest();

        Database.SaveResult result =
            Database.insert(payment, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess()
        );
    }


    // =========================================================
    // 11. VALIDATION RULE:
    //     AMOUNT OF PAID PAYMENT CANNOT CHANGE
    // =========================================================
    @IsTest
    static void testPaidAmountCannotChange() {

        Opportunity opp =
            createOpportunity('Amount Change Test', 10000);

        Payment__c payment = new Payment__c(
            Opportunity__c = opp.Id,
            Amount__c = 2000,
            Status__c = 'Paid',
            Payment_Date__c = Date.today()
        );

        insert payment;

        payment.Amount__c = 3000;

        Test.startTest();

        Database.SaveResult result =
            Database.update(payment, false);

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess()
        );
    }
}