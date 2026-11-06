public with sharing class BookingConfirmationGuard {
    public static void validateConfirmation(List<Opportunity> newRows, Map<Id,Opportunity> oldMap) {
        Set<Id> bookingIds = new Set<Id>();
        for (Opportunity booking : newRows) {
            Opportunity oldBooking = oldMap.get(booking.Id);
            if (booking.Booking_Status__c == 'Confirmed' && oldBooking.Booking_Status__c != 'Confirmed') {
                bookingIds.add(booking.Id);
            }
        }
        if (bookingIds.isEmpty()) return;

        Set<Id> hasAirTicket = new Set<Id>();
        for (OpportunityLineItem line : [
            SELECT OpportunityId, PricebookEntry.Product2.Package_Type__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :bookingIds AND Booking_Service__c = true
        ]) {
            String t = String.valueOf(line.PricebookEntry.Product2.Package_Type__c == null ? '' : line.PricebookEntry.Product2.Package_Type__c).toLowerCase();
            if (t.contains('air') || t.contains('flight') || t.contains('ticket')) hasAirTicket.add(line.OpportunityId);
        }
        Set<Id> acceptedQuotes = new Set<Id>();
        for (Quote q : [SELECT OpportunityId FROM Quote WHERE OpportunityId IN :bookingIds AND Status = 'Accepted']) acceptedQuotes.add(q.OpportunityId);

        Map<Id,List<Visa_Checklist__c>> checklistByBooking = new Map<Id,List<Visa_Checklist__c>>();
        for (Visa_Checklist__c c : [
            SELECT Id, Booking__c, Visa_Required__c, Status__c,
                   Visa_Grant_Received__c, Visa_Expiry_Date__c
            FROM Visa_Checklist__c
            WHERE Booking__c IN :bookingIds AND Is_Active__c = true
        ]) {
            if (!checklistByBooking.containsKey(c.Booking__c)) checklistByBooking.put(c.Booking__c,new List<Visa_Checklist__c>());
            checklistByBooking.get(c.Booking__c).add(c);
        }
        Map<Id,List<Passport__c>> passportByContact = new Map<Id,List<Passport__c>>();
        Set<Id> contacts = new Set<Id>();
        for (Opportunity b : [SELECT Id, Traveler__c FROM Opportunity WHERE Id IN :bookingIds]) if (b.Traveler__c != null) contacts.add(b.Traveler__c);
        for (Passport__c p : [SELECT Id, Contact__c, Passport_Expiry_Date__c FROM Passport__c WHERE Contact__c IN :contacts AND Primary_Passport__c = true]) {
            if (!passportByContact.containsKey(p.Contact__c)) passportByContact.put(p.Contact__c,new List<Passport__c>());
            passportByContact.get(p.Contact__c).add(p);
        }
        Map<Id,Opportunity> fullBookings = new Map<Id,Opportunity>([
            SELECT Id, Traveler__c, Return_Date__c, Visa_Status__c
            FROM Opportunity WHERE Id IN :bookingIds
        ]);
        for (Opportunity booking : newRows) {
            if (!bookingIds.contains(booking.Id)) continue;
            if (!hasAirTicket.contains(booking.Id)) { booking.addError('Cannot confirm: save at least one Air Ticket.'); continue; }
            if (!acceptedQuotes.contains(booking.Id)) { booking.addError('Cannot confirm: the Quote must be Accepted.'); continue; }
            Opportunity full = fullBookings.get(booking.Id);
            if (full.Traveler__c == null || full.Return_Date__c == null) { booking.addError('Cannot confirm: Traveler and Return Date are required.'); continue; }
            if (full.Visa_Status__c != 'Visa Free' && full.Visa_Status__c != 'Visa Required') { booking.addError('Cannot confirm: Visa verification is not complete.'); continue; }
            List<Passport__c> passports = passportByContact.get(full.Traveler__c);
            if (passports == null || passports.size() != 1) { booking.addError('Cannot confirm: exactly one primary Passport is required.'); continue; }
            Date minimumExpiry = full.Return_Date__c.addMonths(6);
            if (passports[0].Passport_Expiry_Date__c == null || passports[0].Passport_Expiry_Date__c < minimumExpiry) { booking.addError('Cannot confirm: Passport must be valid for six months after Return Date. Confirm this policy for each destination before production.'); continue; }
            List<Visa_Checklist__c> rows = checklistByBooking.get(booking.Id);
            if (rows == null || rows.isEmpty()) { booking.addError('Cannot confirm: active Visa Checklist records are missing.'); continue; }
            Boolean complete = true;
            for (Visa_Checklist__c c : rows) {
                if (c.Visa_Required__c == true) {
                    if (c.Status__c != 'Approved' || c.Visa_Grant_Received__c != true || c.Visa_Expiry_Date__c == null || c.Visa_Expiry_Date__c < full.Return_Date__c) complete = false;
                } else if (c.Status__c != 'Not Required') complete = false;
            }
            if (!complete) booking.addError('Cannot confirm: complete all active destination Visa Checklists first.');
        }
    }
}
