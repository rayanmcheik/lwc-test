import { LightningElement, api, wire } from 'lwc';
import getLeaseType from '@salesforce/apex/QuoteController.getLeaseType';
import createQuote from '@salesforce/apex/QuoteController.createQuote';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class CreateQuote extends LightningElement {
    @api recordId;

    leaseType;
    quoteRecord = {};

    @wire(getLeaseType, { opportunityId: '$recordId' })
    getLease({ data, error }) {
        if (data) {
            this.leaseType = data;
        }
        if (error) {
            console.error(error);
        }
    }

    get isOffice() {
        return this.leaseType === 'Office';
    }

    get isRetail() {
        return this.leaseType === 'Retail';
    }

    get isLand() {
        return this.leaseType === 'Land';
    }

    get retailOptions() {
        return [
            {
                label: 'Apparel and Accessories',
                value: 'Apparel and Accessories'
            },
            {
                label: 'Food and Beverages',
                value: 'Food and Beverages'
            },
            {
                label: 'Books & Stationary',
                value: 'Books & Stationary'
            },
            {
                label: 'Family Entertainment Center',
                value: 'Family Entertainment Center'
            }
        ];
    }

    handleChange(event) {

        const field = event.target.name;
        let value = event.detail?.value ?? event.target.value;

        // Convert number fields to numbers
        if (
            field === 'Payment_Terms__c' ||
            field === 'Grace_Period__c' ||
            field === 'Proposed_Lease_Duration__c' ||
            field === 'Rent_Review_Frequency__c'
        ) {
            value = value ? Number(value) : null;
        }

        this.quoteRecord = {
            ...this.quoteRecord,
            [field]: value
        };

        if (
            this.isLand &&
            (
                field === 'Proposed_Start_Date__c' ||
                field === 'Proposed_Lease_Duration__c'
            )
        ) {
            this.calculateEndDate();
        }
    }

    calculateEndDate() {
        const startDate =
            this.quoteRecord.Proposed_Start_Date__c;

        const duration =
            this.quoteRecord.Proposed_Lease_Duration__c;

        if (startDate && duration) {
            const endDate = new Date(startDate + 'T00:00:00');
            endDate.setFullYear(endDate.getFullYear() + Number(duration));
            this.quoteRecord = {
                ...this.quoteRecord,
                Proposed_End_Date__c:
                    endDate.toISOString().split('T')[0]
            };
        }
    }

    handleSave() {
        createQuote({
            opportunityId: this.recordId,
            quoteRecord: this.quoteRecord
        })
        .then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Quote created successfully.',
                    variant: 'success'
                })
            );

            this.dispatchEvent(
                new CloseActionScreenEvent()
            );
        })
        .catch(error => {
            let message = 'Error creating Quote';
            console.log('error=>',JSON.stringify(error));
            if (error.body && error.body.message) {
                message = error.body.message;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: message,
                    variant: 'error'
                })
            );
        });
    }

    handleCancel() {
        this.dispatchEvent(
            new CloseActionScreenEvent()
        );
    }
}