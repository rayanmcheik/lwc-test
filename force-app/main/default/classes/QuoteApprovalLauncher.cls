
public with sharing class QuoteApprovalLauncher {

    @AuraEnabled
    public static String launchApproval(Id recordId) {

        if (recordId == null ||
            recordId.getSObjectType() != Quote.SObjectType) {

            throw new AuraHandledException(
                'Please provide a valid Quote ID.'
            );
        }

        try {
            Map<String, Object> inputs =
                new Map<String, Object>();

            inputs.put('recordId', recordId);

            Flow.Interview launcher =
                Flow.Interview.createInterview(
                    'VGTS_Submit_Discount_Request',
                    inputs
                );

            launcher.start();

            return 'Approval request submitted successfully.';

        } catch (Exception e) {

            throw new AuraHandledException(
                'Approval submission failedd: ' +
                e.getMessage()
            );
        }
    }
}

