
import { LightningElement, api } from 'lwc';
import launchApproval from
    '@salesforce/apex/QuoteApprovalLauncher.launchApproval';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QuoteApprovalButton extends LightningElement {

    @api recordId;
    isLoading = false;

    async handleApproval() {

        this.isLoading = true;

        try {
            const result = await launchApproval({
                recordId: this.recordId
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: result,
                    variant: 'success'
                })
            );

        } catch (error) {

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message ||
                        'Something went wrong.',
                    variant: 'error'
                })
            );

        } finally {
            this.isLoading = false;
        }
    }
}

