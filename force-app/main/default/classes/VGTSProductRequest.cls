public class VGTSProductRequest {

    @AuraEnabled
    @InvocableVariable(
        label='Destination'
        required=true
    )
    public String destination;

    @AuraEnabled
    @InvocableVariable(
        label='Customer Email'
        required=true
    )
    public String customerEmail;
}

