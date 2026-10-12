import { LightningElement, api, wire } from 'lwc';
import getRelatedContacts from
    '@salesforce/apex/AccountContactController.getRelatedContacts';

export default class ShowRelatedContacts extends LightningElement {
    @api recordId;
    showPopup = false;
    contacts = [];
    columns = [
        { label: 'First Name', fieldName: 'FirstName' },
        { label: 'Last Name', fieldName: 'LastName' },
        { label: 'Email', fieldName: 'Email', type: 'email' },
        { label: 'Phone', fieldName: 'Phone', type: 'phone' }
    ];
    @wire(getRelatedContacts, { accountId: '$recordId' })
    wiredContacts({ data, error }) {
        if (data) {
            this.contacts = data;
        } else if (error) {
            console.error(error);
        }
    }

    openPopup() {
        this.showPopup = true;
    }

    closePopup() {
        this.showPopup = false;
    }
}