public with sharing class AccountController {
    public AccountController() {

    }

    @AuraEnabled(cacheable = true)
    public static List<Account> getAccounts(Integer maxRecords){
        List<Account> accounts=[SELECT Id, Name FROM Account ORDER BY CreatedDate DESC LIMIT :maxRecords];
        return this.accounts;
    }
    
}