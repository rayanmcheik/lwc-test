import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import createNewAccount from '@salesforce/apex/AccountController.createNewAccount';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

export default class createAccount extends NavigationMixin(LightningElement) {
    accountName = '';
    maxRecords = 10;
    isLoading = false;
    errorMessage = '';
    wiredAccountsResult;

    columns = [
        { label: 'Account Name', fieldName: 'Name', type: 'text' },
        { label: 'Account ID', fieldName: 'Id', type: 'text' }
    ];

    @wire(getAccounts, { maxRecords: '$maxRecords' })
    accounts(result) {
        this.wiredAccountsResult = result;
    }

    handleChange(event) {
        this.accountName = event.target.value;
        this.errorMessage = '';
    }

    async handleClick() {
        createNewAccount({ accountName: this.newAccountName })
            .then(() => {
                console.log('result: ', result)
            })
            
            .catch((error) => {
                this.errors = error;
            });
        // const name = this.accountName.trim();

        // if (!name) {
        //     this.errorMessage = 'Please enter an account name.';
        //     return;
        // }

        // this.isLoading = true;
        // this.errorMessage = '';

        // try {
        //     const recordId = await createNewAccount({
        //         accountName: name
        //     });

        //     await refreshApex(this.wiredAccountsResult);

        //     this.dispatchEvent(
        //         new ShowToastEvent({
        //             title: 'Success',
        //             message: 'Account created successfully!',
        //             variant: 'success'
        //         })
        //     );

        //     this.accountName = '';

        //     this[NavigationMixin.Navigate]({
        //         type: 'standard__recordPage',
        //         attributes: {
        //             recordId: recordId,
        //             objectApiName: 'Account',
        //             actionName: 'view'
        //         }
        //     });
        // } catch (error) {
        //     this.errorMessage =
        //         error.body?.message || 'An error occurred while creating the account.';

        //     this.dispatchEvent(
        //         new ShowToastEvent({
        //             title: 'Error',
        //             message: this.errorMessage,
        //             variant: 'error'
        //         })
        //     );
        // } finally {
        //     this.isLoading = false;
        // }
    }
}