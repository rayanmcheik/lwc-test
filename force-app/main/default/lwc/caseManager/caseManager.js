import { LightningElement, wire, track } from 'lwc';
import getCases from '@salesforce/apex/CaseController.getCases';
import createCase from '@salesforce/apex/CaseController.createCase';
import getAllCasesByStatus from '@salesforce/apex/CaseController.getAllCasesByStatus';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CaseManager extends LightningElement {

    searchKey = '';
    searchKeyStatus = '';
    subject = '';
    description = '';

    @track cases = [];
    @track allStatusCases = [];
    @track displayedCases = [];
    
    wiredCasesResult;
    wiredStatusResult;

    isLoading = false;
    isCreating = false;

    columns = [
        { label: 'Case Number', fieldName: 'CaseNumber', type: 'text' },
        { label: 'Subject', fieldName: 'Subject', type: 'text' },
        { label: 'Description', fieldName: 'Description', type: 'text', wrapText: true },
        { label: 'Status', fieldName: 'Status', type: 'text' }
    ];

    @wire(getCases, { caseNumber: '$searchKey' })
    wiredCases(result) {
        this.wiredCasesResult = result;
        if (result.data) {
            this.cases = result.data;
            this.isLoading = false;
        } else if (result.error) {
            this.cases = [];
            this.isLoading = false;
            this.showToast('Error', this.getErrorMessage(result.error), 'error');
        }
    }

    @wire(getAllCasesByStatus)
    wiredAllCases(result) {
        this.wiredStatusResult = result;
        if (result.data) {
            this.allStatusCases = result.data;
            this.filterCases();
        } else if (result.error) {
            this.allStatusCases = [];
            this.displayedCases = [];
            this.showToast('Error', this.getErrorMessage(result.error), 'error');
        }
    }

   
    handleSearch(event) {
        this.searchKey = event.target.value.trim();
        this.isLoading = true;
    }


    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleCreateCase() {
        const subjectInput = this.template.querySelector('[data-id="subject"]');
        if (!subjectInput.reportValidity()) {
            return;
        }

        this.isCreating = true;

        createCase({
            subject: this.subject,
            description: this.description
        })
            .then(() => {
                this.showToast('Success', 'Case created successfully!', 'success');
                this.subject = '';
                this.description = '';
                this.searchKey = '';
                this.searchKeyStatus = '';
                return Promise.all([
                    refreshApex(this.wiredCasesResult),
                    refreshApex(this.wiredStatusResult)
                ]);
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isCreating = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
     get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'New', value: 'New' },
            { label: 'Working', value: 'Working' },
            { label: 'Escalated', value: 'Escalated' }
        ];
    }

        handleSearchbyStatus(event) {
        this.searchKeyStatus = event.detail.value;
        this.filterCases();
    }

    filterCases() {
        if (!this.searchKeyStatus) {
            this.displayedCases = this.allStatusCases;
        } else {
            this.displayedCases = this.allStatusCases.filter(
                c => c.Status === this.searchKeyStatus
            );
        }
    }

}
