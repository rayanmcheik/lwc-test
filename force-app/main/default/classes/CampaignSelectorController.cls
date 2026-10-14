public with sharing class CampaignSelectorController {

    @AuraEnabled(cacheable=true)
    public static List<Campaign> getCampaigns() {

        return [
            SELECT Id,
                   Name,
                   Type,
                   Status,
                   StartDate,
                   EndDate,
                   IsActive
            FROM Campaign
            WHERE IsActive = TRUE
            AND Status IN ('Planned', 'In Progress')
            ORDER BY StartDate ASC NULLS LAST
        ];
    }
//dfweffffffffffffffffwwwwwwwwwwwww
    @AuraEnabled(cacheable=true)
    public static List<Id> getEnrolledCampaignIds(Id leadId) {

        List<Id> campaignIds = new List<Id>();

        if (leadId == null) {
            return campaignIds;
        }

        for (CampaignMember cm : [
            SELECT CampaignId
            FROM CampaignMember
            WHERE LeadId = :leadId
        ]) {
            campaignIds.add(cm.CampaignId);
        }
        return campaignIds;
    }

    public class AssignmentRequest {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public String selectedIds;
    }

    public class AssignmentResult {
        @InvocableVariable
        public Integer createdCount;
    }

    @InvocableMethod(label='Assign Lead to Campaigns')
    public static List<AssignmentResult> assignLeadToCampaigns(
        List<AssignmentRequest> requests
    ) {

        List<AssignmentResult> results =
            new List<AssignmentResult>();

        for (AssignmentRequest request : requests) {
            AssignmentResult result = new AssignmentResult();
            result.createdCount = 0;

            if (
                request == null ||
                request.leadId == null ||
                String.isBlank(request.selectedIds)
            ) {
                results.add(result);
                continue;
            }

            Set<Id> campaignIds = new Set<Id>();

            for (String campaignIdString : request.selectedIds.split(',')
            ) {

                if (!String.isBlank(campaignIdString)) {
                    campaignIds.add((Id) campaignIdString.trim());
                }
            }

            Set<Id> alreadyEnrolled = new Set<Id>();

            for (CampaignMember cm : [
                SELECT CampaignId
                FROM CampaignMember
                WHERE LeadId = :request.leadId
                AND CampaignId IN :campaignIds
            ]) {
                alreadyEnrolled.add(
                    cm.CampaignId
                );
            }

            List<CampaignMember> membersToCreate = new List<CampaignMember>();

            for (Id campaignId : campaignIds) {
                if (!alreadyEnrolled.contains(campaignId)) {
                    membersToCreate.add(
                        new CampaignMember(LeadId = request.leadId, CampaignId = campaignId)
                    );
                }
            }

            if (!membersToCreate.isEmpty()) {
                insert membersToCreate;
                result.createdCount = membersToCreate.size();
            }
            results.add(result);
        }

        return results;
    }
}