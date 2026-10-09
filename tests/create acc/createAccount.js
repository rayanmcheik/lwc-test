import { LightningElement, wire } from 'lwc';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

export default class createAccount extends LightningElement {

    accountName;
    maxRecords;
    accounts;
    errors;

    handleInputChange(event){
        this.maxRecords = event.target.value;
    }

   // @wire(getAccounts, {maxRecords: "$maxRecords"}) accounts;
    @wire(getAccounts, {maxRecords:"$maxRecords"}) wiredAccounts({data,errors}){
        if (data) {
            this.accounts = data; this.errors = undefined;
        }else if (errors)
        {
            this.accounts = undefined; this.errors = errors;
        }
    }
}