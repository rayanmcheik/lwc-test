trigger CertificationAttemptTrigger on Certification_Attempt__c (before insert, after insert, after update) 
{
    switch on Trigger.OperationType {

        when BEFORE_INSERT {
            CertificationAttemptTriggerHandler.validateCertificationAttempt(Trigger.new);
        }
        when AFTER_UPDATE, AFTER_INSERT {
            CertificationAttemptTriggerHandler.grantInstructorSharingAccess(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
            CertificationAttemptTriggerHandler.createCertificationHeld(Trigger.new, Trigger.oldMap);
        }
    }
}