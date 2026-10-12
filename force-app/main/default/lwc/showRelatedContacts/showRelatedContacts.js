import { LightningElement, api, wire } from 'lwc';
import getRelatedContacts from
    '@salesforce/apex/AccountContactController.getRelatedContacts';
import { deleteRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ShowRelatedContacts extends LightningElement {
    @api recordId;
    contacts = [];
    wiredResult;

    @wire(getRelatedContacts, { accountId: '$recordId' })
    wiredContacts(result) {
        this.wiredResult = result;

        if (result.data) {
            this.contacts = result.data;
        } else if (result.error) {
            console.error(result.error);
        }
    }

    async deleteContact(event) {
        const contactId = event.currentTarget.dataset.id;

        try {
            await deleteRecord(contactId);
            await refreshApex(this.wiredResult);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Contact deleted successfully.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Unable to delete contact.',
                    variant: 'error'
                })
            );
        }
    }
}