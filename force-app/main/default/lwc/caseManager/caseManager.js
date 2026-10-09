import { LightningElement, wire } from 'lwc';
import getCases from '@salesforce/apex/CaseController.getCases';
import createCase from '@salesforce/apex/CaseController.createCase';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CaseManager extends LightningElement {

    searchInput = '';
    searchKey = '';
    subject = '';
    description = '';
    cases = [];
    wiredCasesResult;

    isLoading = false;
    isCreating = false;

    columns = [
        {
            label: 'Case Number',
            fieldName: 'CaseNumber',
            type: 'text'
        },
        {
            label: 'Subject',
            fieldName: 'Subject',
            type: 'text'
        },
        {
            label: 'Description',
            fieldName: 'Description',
            type: 'text',
            wrapText: true
        },
        {
            label: 'Status',
            fieldName: 'Status',
            type: 'text'
        }
    ];

    @wire(getCases, { caseNumber: '$searchKey' })
    wiredCases(result) {
        this.wiredCasesResult = result;

        if (result.data) {
            this.cases = result.data;
        } else if (result.error) {
            this.showToast(
                'Error',
                this.getErrorMessage(result.error),
                'error'
            );
        }
    }

    handleSearchInput(event) {
        this.searchInput = event.target.value;
    }

    async handleSearch() {
        this.isLoading = true;
        this.searchKey = this.searchInput.trim();

        try {
            await refreshApex(this.wiredCasesResult);
        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    async handleShowAll() {
        this.searchInput = '';
        this.searchKey = '';
        this.isLoading = true;

        try {
            await refreshApex(this.wiredCasesResult);
        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }
    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    async handleCreateCase() {
        const subjectInput =
            this.template.querySelector('lightning-input');

        if (!subjectInput.reportValidity()) {
            return;
        }

        this.isCreating = true;

        try {
            await createCase({
                subject: this.subject,
                description: this.description
            });

            this.showToast(
                'Success',
                'Case created successfully!',
                'success'
            );

            this.subject = '';
            this.description = '';
            this.searchInput = '';
            this.searchKey = '';

            await refreshApex(this.wiredCasesResult);

        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isCreating = false;
        }
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

    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.';
    }
}