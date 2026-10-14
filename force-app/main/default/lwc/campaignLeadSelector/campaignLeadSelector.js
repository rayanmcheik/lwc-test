import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCampaigns from '@salesforce/apex/CampaignSelectorController.getCampaigns';
import getEnrolledCampaignIds from '@salesforce/apex/CampaignSelectorController.getEnrolledCampaignIds';

export default class CampaignLeadSelector extends LightningElement {
    @api leadId;
    @api selectedIds = '';

    campaigns = [];
    enrolledCampaignIds = [];

    selectedIdSet = new Set();

    searchName = '';
    selectedType = 'All Types';

    fromDate = null;
    toDate = null;

    @wire(getCampaigns)
    wiredCampaigns({ data, error }) {

        if (data) {
            this.campaigns = data;
        } else if (error) {
            console.error('Error loading campaigns:', error);
        }
    }

    @wire(
        getEnrolledCampaignIds,
        { leadId: '$leadId' }
    )
    wiredEnrolledCampaigns({ data, error }) {

        if (data) {
            this.enrolledCampaignIds = data || [];
        } else if (error) {

            console.error(
                'Error loading enrolled campaigns:',
                error
            );
        }
    }

    get typeOptions() {
        const types = [
            ...new Set(this.campaigns.map(campaign => campaign.Type).filter(type => type)
            )
        ];

        return [
            {
                label: 'All Types',
                value: 'All Types'
            },

            ...types.map(type => ({
                label: type,
                value: type
            }))
        ];
    }

    get filteredCampaigns() {
        return this.campaigns
            .filter(campaign => {
                const matchesName = !this.searchName || campaign.Name.toLowerCase().includes(this.searchName.toLowerCase());

                const matchesType = this.selectedType === 'All Types' || campaign.Type === this.selectedType;

                let matchesDate = true;

                if (
                    this.fromDate &&
                    campaign.EndDate &&
                    campaign.EndDate < this.fromDate
                ) {
                    matchesDate = false;
                }

                if (
                    this.toDate &&
                    campaign.StartDate &&
                    campaign.StartDate > this.toDate
                ) {
                    matchesDate = false;
                }


                return (
                    matchesName &&
                    matchesType &&
                    matchesDate
                );
            })

            .map(campaign => {

                return {
                    ...campaign,

                    isEnrolled: this.enrolledCampaignIds.includes(campaign.Id),

                    isSelected: this.selectedIdSet.has(campaign.Id)
                };
            });
    }

    handleSearchNameChange(event) {
        this.searchName = event.target.value;
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
    }

    handleFromDateChange(event) {
        this.fromDate = event.target.value;
    }

    handleToDateChange(event) {
        this.toDate = event.target.value;
    }

    handleCheckboxChange(event) {
        const campaignId = event.target.dataset.id;

        const checked = event.target.checked;

        if (
            this.enrolledCampaignIds.includes(campaignId)
        ) {
            return;
        }

        if (checked) {
            this.selectedIdSet.add(campaignId);

        } else {
            this.selectedIdSet.delete(campaignId);
        }

        this.selectedIdSet = new Set(this.selectedIdSet);

        this.selectedIds = Array.from(this.selectedIdSet).join(',');

        this.dispatchEvent(new FlowAttributeChangeEvent('selectedIds',this.selectedIds));
    }

    get selectedCount() {
        return this.selectedIdSet.size;
    }

    @api
    validate() {

        if (
            this.selectedIdSet.size === 0
        ) {

            return {
                isValid: false,
                errorMessage: 'Please select at least one new Campaign.'
            };
        }

        return {
            isValid: true
        };
    }
}