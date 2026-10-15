public with sharing class CustomerOnboardingController {

    // Load existing onboarding information
    @AuraEnabled(cacheable=true)
    public static OnboardingData getOnboardingData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        OnboardingData data = new OnboardingData();

        data.account = [
            SELECT Id, Rating, Type, Website,
                   AnnualRevenue, Description
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email,
                   Phone, Role__c, Is_Primary__c
            FROM Contact
            WHERE AccountId = :accountId
            AND Is_Primary__c = true
            LIMIT 2
        ];

        if (contacts.size() > 1) {
            throw new AuraHandledException(
                'Multiple primary contacts found for this Account.'
            );
        }

        if (!contacts.isEmpty()) {
            data.primaryContact = contacts[0];
        }

        data.addresses = [
            SELECT Id, Account__c, Address_Type__c,
                   Street__c, City__c, State__c,
                   Postal_Code__c, Country__c,
                   Is_Default__c
            FROM Customer_Address__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate
        ];

        return data;
    }

    // Save Steps 1, 2 and 3 together
    @AuraEnabled
    public static void saveOnboarding(
        Id accountId,
        Account accountData,
        Contact contactData,
        List<Customer_Address__c> addresses
    ) {
        if (accountId == null || accountData == null ||
            contactData == null || addresses == null) {
            throw new AuraHandledException(
                'Required onboarding information is missing.'
            );
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // Step 1: Update Account
            Account acc = new Account(
                Id = accountId,
                Rating = accountData.Rating,
                Type = accountData.Type,
                Website = accountData.Website,
                AnnualRevenue = accountData.AnnualRevenue,
                Description = accountData.Description
            );
            update acc;

            // Step 2: Create or update Primary Contact
            List<Contact> existing = [
                SELECT Id
                FROM Contact
                WHERE AccountId = :accountId
                AND Is_Primary__c = true
                LIMIT 2
                FOR UPDATE
            ];

            if (existing.size() > 1) {
                throw new AuraHandledException(
                    'Multiple primary contacts found.'
                );
            }

            if (String.isBlank(contactData.LastName) ||
                String.isBlank(contactData.Email)) {
                throw new AuraHandledException(
                    'Last Name and Email are required.'
                );
            }

            Contact primary = new Contact(
                AccountId = accountId,
                FirstName = contactData.FirstName,
                LastName = contactData.LastName,
                Email = contactData.Email,
                Phone = contactData.Phone,
                Role__c = contactData.Role__c,
                Is_Primary__c = true
            );

            if (!existing.isEmpty()) {
                primary.Id = existing[0].Id;
            }

            upsert primary;

            // Step 3: Create or update addresses
            List<Customer_Address__c> toSave =
                new List<Customer_Address__c>();

            Set<Id> addressIds = new Set<Id>();

            for (Customer_Address__c address : addresses) {
                if (address.Id != null) {
                    if (!addressIds.add(address.Id)) {
                        throw new AuraHandledException(
                            'Duplicate address record in request.'
                        );
                    }
                }

                toSave.add(new Customer_Address__c(
                    Id = address.Id,
                    Account__c = accountId,
                    Address_Type__c = address.Address_Type__c,
                    Street__c = address.Street__c,
                    City__c = address.City__c,
                    State__c = address.State__c,
                    Postal_Code__c = address.Postal_Code__c,
                    Country__c = address.Country__c,
                    Is_Default__c = address.Is_Default__c
                ));
            }

            // Ensure existing addresses belong to this Account
            if (!addressIds.isEmpty()) {
                Set<Id> validIds = new Set<Id>();

                for (Customer_Address__c a : [
                    SELECT Id
                    FROM Customer_Address__c
                    WHERE Id IN :addressIds
                    AND Account__c = :accountId
                ]) {
                    validIds.add(a.Id);
                }

                if (validIds.size() != addressIds.size()) {
                    throw new AuraHandledException(
                        'An address does not belong to this Account.'
                    );
                }
            }

            if (!toSave.isEmpty()) {
                upsert toSave;
            }

        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(
                'Onboarding save failed: ' + e.getMessage()
            );
        }
    }

    // Data returned to the LWC
    public class OnboardingData {
        @AuraEnabled public Account account { get; set; }
        @AuraEnabled public Contact primaryContact { get; set; }
        @AuraEnabled public List<Customer_Address__c> addresses { get; set; }
    }
}