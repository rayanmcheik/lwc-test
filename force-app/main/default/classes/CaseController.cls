public with sharing class CaseController {

    @AuraEnabled(cacheable=true)
    public static List<Case> getCases(String caseNumber) {

        if (String.isBlank(caseNumber)) {
            return [
                SELECT Id, CaseNumber, Subject, Description, Status
                FROM Case
                ORDER BY CreatedDate DESC
                LIMIT 500
            ];
        }

        String searchValue = '%' + caseNumber.trim() + '%';

        return [
            SELECT Id, CaseNumber, Subject, Description, Status
            FROM Case
            WHERE CaseNumber LIKE :searchValue
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static Id createCase(String subject, String description) {

        if (String.isBlank(subject)) {
            throw new AuraHandledException(
                'Case subject is required.'
            );
        }

        Case newCase = new Case(
            Subject = subject.trim(),
            Description = description,
            Status = 'New'
        );

        insert newCase;

        return newCase.Id;
    }
}