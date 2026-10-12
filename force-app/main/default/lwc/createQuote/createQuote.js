import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

import getLeaseType from '@salesforce/apex/QuoteController.getLeaseType';
import createQuote from '@salesforce/apex/QuoteController.createQuote';

export default class CreateQuote extends NavigationMixin(LightningElement) {

    @api recordId;

    leaseType;
    loading = true;
    saving = false;
    loadError;

    startDate = '';
    endDate = '';
    paymentTerms = null;
    gracePeriod = null;
    retailCategory = '';
    duration = null;
    rentReviewFrequency = null;

    retailOptions = [
        { label: 'Apparel and Accessories', value: 'Apparel and Accessories' },
        { label: 'Food and Beverages', value: 'Food and Beverages' },
        { label: 'Books & Stationary', value: 'Books & Stationary' },
        { label: 'Family Entertainment Center', value: 'Family Entertainment Center' }
    ];

    connectedCallback() {
        this.loadLeaseType();
    }

    async loadLeaseType() {
        try {
            this.leaseType = await getLeaseType({
                opportunityId: this.recordId
            });

            if (!['Office', 'Retail', 'Land'].includes(this.leaseType)) {
                this.loadError = 'The Opportunity must have a valid Lease Type.';
            }
        } catch (error) {
            this.loadError = this.getErrorMessage(error);
        } finally {
            this.loading = false;
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

    get isOfficeOrRetail() {
        return this.isOffice || this.isRetail;
    }
    handleChange(event) {
        const { name, value, type } = event.target;

        this[name] = type === 'number'
            ? (value === '' ? null : Number(value))
            : value;

        if (this.isLand &&
            (name === 'startDate' || name === 'duration')) {
            this.calculateEndDate();
        }
    }
    calculateEndDate() {
        this.endDate = '';
        if (!this.startDate ||
            this.duration === null ||
            !Number.isInteger(this.duration) ||
            this.duration < 30) {
            return;
        }
        const [year, month, day] = this.startDate
            .split('-')
            .map(Number);

        const end = new Date(
            Date.UTC(year, month - 1, day)
        );
        end.setUTCFullYear(year + this.duration);
        if (end.getUTCMonth() !== month - 1) {
            end.setUTCDate(0);
        }
        this.endDate = [
            end.getUTCFullYear(),
            String(end.getUTCMonth() + 1).padStart(2, '0'),
            String(end.getUTCDate()).padStart(2, '0')
        ].join('-');
    }
    async handleSubmit(event) {
        event.preventDefault();
        const inputs = [
            ...this.template.querySelectorAll('lightning-input'),
            ...this.template.querySelectorAll('lightning-combobox')
        ];
        const isValid = inputs.reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
        if (!isValid) {
            return;
        }
        this.saving = true;
        try {
            const quoteId = await createQuote({
                opportunityId: this.recordId,
                startDate: this.startDate || null,
                endDate: this.endDate || null,
                paymentTerms: this.paymentTerms,
                gracePeriod: this.gracePeriod,
                retailCategory: this.retailCategory || null,
                duration: this.duration,
                rentReviewFrequency: this.rentReviewFrequency
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Quote created successfully.',
                    variant: 'success'
                })
            );
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: quoteId,
                    objectApiName: 'Quote',
                    actionName: 'view'
                }
            });

        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error creating Quote',
                    message: this.getErrorMessage(error),
                    variant: 'error'
                })
            );
        } finally {
            this.saving = false;
        }
    }
    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'An unexpected error occurred..';
    }
}