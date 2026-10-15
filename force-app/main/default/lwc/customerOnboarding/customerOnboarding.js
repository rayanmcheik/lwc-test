import { LightningElement, api, wire } from 'lwc';
import getOnboardingData from '@salesforce/apex/CustomerOnboardingController.getOnboardingData';
import saveOnboarding from '@salesforce/apex/CustomerOnboardingController.saveOnboarding';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CustomerOnboarding extends LightningElement {

    @api recordId;

    currentStep = '1';
    isLoading = true;
    hasLoaded = false;
    nextAddressKey = 0;

    accountData = {
        Rating: '',
        Type: '',
        Website: '',
        AnnualRevenue: null,
        Description: ''
    };

    contactData = {};
    addresses = [];
    uploadedFiles = [];

    @wire(getOnboardingData, { accountId: '$recordId' })
    wiredOnboarding({ data, error }) {
        if (data && !this.hasLoaded) {
            this.accountData = {
                Rating: data.account.Rating || '',
                Type: data.account.Type || '',
                Website: data.account.Website || '',
                AnnualRevenue: data.account.AnnualRevenue,
                Description: data.account.Description || ''
            };

            this.contactData = data.primaryContact || {};

            this.addresses = (data.addresses || []).map(address => ({
                ...address,
                key: ++this.nextAddressKey
            }));

            this.hasLoaded = true;
            this.isLoading = false;

        } else if (error) {
            this.isLoading = false;
            this.showToast(
                'Error',
                error.body?.message || 'Failed to load onboarding data.',
                'error'
            );
        }
    }

    get isStep1() {
        return this.currentStep === '1';
    }

    get isStep2() {
        return this.currentStep === '2';
    }

    get isStep3() {
        return this.currentStep === '3';
    }

    get isStep4() {
        return this.currentStep === '4';
    }

    get ratingOptions() {
        return [
            { label: 'Hot', value: 'Hot' },
            { label: 'Warm', value: 'Warm' },
            { label: 'Cold', value: 'Cold' }
        ];
    }

    get typeOptions() {
        return [
            { label: 'Luxury', value: 'Luxury' },
            { label: 'Fashion', value: 'Fashion' },
            { label: 'Brand', value: 'Brand' },
            { label: 'Kiosk', value: 'Kiosk' },
            { label: 'Art', value: 'Art' },
            { label: 'Design', value: 'Design' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get roleOptions() {
        return [
            { label: 'General Manager', value: 'General Manager' },
            { label: 'CEO', value: 'CEO' },
            { label: 'CTO', value: 'CTO' },
            { label: 'HR', value: 'HR' }
        ];
    }

    get addressTypeOptions() {
        return [
            { label: 'Billing', value: 'Billing' },
            { label: 'Shipping', value: 'Shipping' }
        ];
    }

    handleAccountChange(event) {
        const field = event.target.name;

        this.accountData = {
            ...this.accountData,
            [field]: event.target.value
        };
    }

    handleContactChange(event) {
        const field = event.target.name;

        this.contactData = {
            ...this.contactData,
            [field]: event.target.value
        };
    }

    handleNext() {
        const inputs = [
            ...this.template.querySelectorAll(
                'lightning-input, lightning-combobox, lightning-textarea'
            )
        ];

        const isValid = inputs.reduce((valid, input) => {
            input.reportValidity();
            return input.checkValidity() && valid;
        }, true);

        if (isValid) {
            if (this.currentStep === '1') {
                this.currentStep = '2';
            } else if (this.currentStep === '2') {
                this.currentStep = '3';
            }
        }
    }

    handlePrevious() {
        if (this.currentStep === '2') {
            this.currentStep = '1';
        } else if (this.currentStep === '3') {
            this.currentStep = '2';
        }
    }

    handleAddAddress() {
        this.addresses = [
            ...this.addresses,
            {
                key: ++this.nextAddressKey,
                Address_Type__c: 'Shipping',
                Street__c: '',
                City__c: '',
                State__c: '',
                Postal_Code__c: '',
                Country__c: '',
                Is_Default__c: false
            }
        ];
    }

    handleRemoveAddress(event) {
        const key = Number(event.target.dataset.key);

        this.addresses = this.addresses.filter(
            address => address.key !== key
        );
    }

    handleAddressChange(event) {
        const key = Number(event.target.dataset.key);

        this.addresses = this.addresses.map(address => {
            if (address.key !== key) {
                return address;
            }

            if (event.target.name === 'Address_Type__c') {
                return {
                    ...address,
                    Address_Type__c: event.detail.value
                };
            }

            return {
                ...address,
                Street__c: event.detail.street,
                City__c: event.detail.city,
                State__c: event.detail.province,
                Postal_Code__c: event.detail.postalCode,
                Country__c: event.detail.country
            };
        });
    }

    async handleSave() {
        if (this.isLoading) {
            return;
        }

        const inputs = [
            ...this.template.querySelectorAll(
                'lightning-input-address, lightning-combobox'
            )
        ];

        const isValid = inputs.reduce((valid, input) => {
            input.reportValidity();
            return input.checkValidity() && valid;
        }, true);

        if (!isValid) {
            return;
        }

        this.isLoading = true;

        try {
            const cleanAddresses = this.addresses.map(
                ({ key, ...address }) => address
            );

            await saveOnboarding({
                accountId: this.recordId,
                accountData: this.accountData,
                contactData: this.contactData,
                addresses: cleanAddresses
            });

            this.showToast(
                'Success',
                'Customer onboarding information saved successfully.',
                'success'
            );

            this.currentStep = '4';

        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || 'Failed to save onboarding.',
                'error'
            );

        } finally {
            this.isLoading = false;
        }
    }

    handleUploadFinished(event) {
        const files = event.detail.files;

        this.uploadedFiles = [
            ...this.uploadedFiles,
            ...files
        ];

        this.showToast(
            'Success',
            files.length + 'document(s) uploaded successfully.',
            'success'
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}