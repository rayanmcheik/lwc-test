public with sharing class CampaignController {
    @AuraEnabled(cacheable=true)
    public static string getCampaigns(){
        try {
            
            List<Campaign> campaigns = [
                SELECT Id, Name, Type, Status, StartDate, EndDate 
                FROM Campaign 
                WHERE IsActive = true OR Status = 'Draft'
                WITH USER_MODE
                ORDER BY StartDate DESC
            ];
            return JSON.serialize(campaigns);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CampaignMember> getLeadMemberships(Id leadId) {
        if (leadId == null) {
            return new List<CampaignMember>();
        }
        
        return [
            SELECT CampaignId 
            FROM CampaignMember 
            WHERE LeadId = :leadId 
            WITH USER_MODE
        ];
    }
}