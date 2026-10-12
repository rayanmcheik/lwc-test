import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAccountsWithOpportunities
    from '@salesforce/apex/AccountOpportunityController.getAccountsWithOpportunities';

import updateOpportunityStatus
    from '@salesforce/apex/AccountOpportunityController.updateOpportunityStatus';

export default class AccountOpportunityOverview extends LightningElement {
    accounts = [];
    error;
    wiredAccountsResult;

    showModal = false;
    selectedOpportunityId;
    selectedStage = 'Closed Won';

    isUpdating = false;
    isLoading = true;

    stageOptions = [
        { label: 'Closed Won', value: 'Closed Won' },
        { label: 'Closed Lost', value: 'Closed Lost' }
    ];

    @wire(getAccountsWithOpportunities)
    wiredAccounts(result) {
        this.wiredAccountsResult = result;

        const { data, error } = result;

        if (data) {
            this.accounts = data.map(account => ({
                ...account,
                hasOpportunities: account.opportunityCount > 0,
                opportunities: account.opportunities.map(opp => ({
                    ...opp,
                    canClose:
                        opp.stageName !== 'Closed Won' &&
                        opp.stageName !== 'Closed Lost'
                }))
            }));

            this.error = undefined;
        } else if (error) {
            this.accounts = [];
            this.error = error;
        }

        if (data || error) {
            this.isLoading = false;
        }
    }

    get hasAccounts() {
        return this.accounts.length > 0;
    }

    get showNoAccounts() {
        return !this.isLoading &&
            !this.error &&
            this.accounts.length === 0;
    }

    handleOpenModal(event) {
        this.selectedOpportunityId = event.currentTarget.dataset.id;
        this.selectedStage = 'Closed Won';
        this.showModal = true;
    }

    handleStageChange(event) {
        this.selectedStage = event.detail.value;
    }

    handleCancel() {
        if (!this.isUpdating) {
            this.showModal = false;
            this.selectedOpportunityId = undefined;
        }
    }

    async handleUpdate() {
        if (!this.selectedOpportunityId || !this.selectedStage) {
            this.showToast(
                'Error',
                'Please select a valid Opportunity and stage.',
                'error'
            );
            return;
        }

        this.isUpdating = true;

        try {
            await updateOpportunityStatus({
                opportunityId: this.selectedOpportunityId,
                newStage: this.selectedStage
            });

            this.showModal = false;

            this.showToast(
                'Success',
                'Opportunity stage updated successfully.',
                'success'
            );

            await refreshApex(this.wiredAccountsResult);
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || 'Unable to update Opportunity.',
                'error'
            );
        } finally {
            this.isUpdating = false;
            this.selectedOpportunityId = undefined;
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
}