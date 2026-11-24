trigger VGTSQuoteSyncProductTrigger
on OpportunityLineItem (after insert, after update) {

    VGTSQuoteSyncProductHandler.restoreBookingServiceFlag(
        Trigger.new
    );
}

