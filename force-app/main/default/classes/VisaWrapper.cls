
global with sharing class VisaWrapper {

    global class VisaCheckInputWrapper {
        global VisaCheckInputWrapper() {}

        @InvocableVariable(required=true label='Opportunity ID')
        global Id opportunityId;
    }

    global class VisaCheckOutputWrapper {
        global VisaCheckOutputWrapper() {}

        @InvocableVariable global Id opportunityId;
        @InvocableVariable global String status;
        @InvocableVariable global String message;
        @InvocableVariable global Id jobId;
    }

    public class VisaRecordWrapper {
        @AuraEnabled public String Passport_c { get; set; }
        @AuraEnabled public String Destination_c { get; set; }
        @AuraEnabled public Boolean Visa_Required_c { get; set; }
        @AuraEnabled public String Visa_Type_c { get; set; }
        @AuraEnabled public String Allowed_Stay_c { get; set; }
        @AuraEnabled public String Notes_c { get; set; }
    }

    public class ExternalQueryResponse {
        public Integer totalSize;
        public Boolean done;
        public String nextRecordsUrl;
        public List<VisaRecordWrapper> records;
    }

    global class VisaValidationResult {
        global VisaValidationResult() {}

        @AuraEnabled global Boolean isAllowed { get; set; }
        @AuraEnabled global Boolean visaRequired { get; set; }
        @AuraEnabled global String blockReason { get; set; }
        @AuraEnabled global String visaStatus { get; set; }
        @AuraEnabled global String requirements { get; set; }
        @AuraEnabled global Boolean passportValid { get; set; }
        @AuraEnabled global Id passportRecordId { get; set; }
        @AuraEnabled global String passportCountry { get; set; }
        @AuraEnabled global Date passportExpiryDate { get; set; }
    }

    public class VisaServiceException extends Exception {}

    public class Snapshot {
        public Opportunity booking;
        public Id passportId;
        public String country;
        public Date expiry;
        public String problem;
        public Boolean missingDestination = false;
        public Set<String> destinations = new Set<String>();
        public List<String> sources = new List<String>();
    }
}

