
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getTravelPackages from '@salesforce/apex/VGTSBookingPackageController.getTravelPackages';
import getBookingServices from '@salesforce/apex/VGTSBookingPackageController.getBookingServices';
import saveBookingServices from '@salesforce/apex/VGTSBookingPackageController.saveBookingServices';
import savePayment from '@salesforce/apex/VGTSBookingPackageController.savePayment';
import createBookingQuote from '@salesforce/apex/VGTSBookingPackageController.createBookingQuote';

import getVisaSummary from '@salesforce/apex/VisaChecklistController.getVisaSummary';
import getActiveVisaChecklists from '@salesforce/apex/VisaChecklistController.getActiveVisaChecklists';
import checkVisaRequirements from '@salesforce/apex/VisaChecklistController.checkVisaRequirements';
import saveVisaInformation from '@salesforce/apex/VisaChecklistController.saveVisaInformation';

const HOTEL_ROOM_FEE = 50;
const HOTEL_NIGHT_FEE = 30;

export default class VgtsBookingServiceSelector extends LightningElement {

    @api recordId;

    travelPackages = [];
    selectedServices = [];
    savedServices = [];
    selectedService = null;

    hotelQuantities = {};
    visaDrafts = {};

    isLoading = true;
    isSaving = false;
    isCheckingVisa = false;

    loadError = '';
    activeTab = 'Air_Tickets';

    filterOrigin = '';
    filterDestination = '';
    filterFlightType = '';
    filterCabinClass = '';
    maxPrice = '';
    searchKeyword = '';

    hotelDestinationFilter = '';
    hotelSearchKeyword = '';

    paymentMethod = '';

    visaSummary;
    visaCheckResult;
    visaChecklists = [];

    hasLocalPackageChanges = false;

    wiredPackagesResult;
    wiredSavedServicesResult;
    wiredVisaSummaryResult;
    wiredVisaChecklistsResult;

    flightTypeOptions = [
        { label: 'All Flight Types', value: '' },
        { label: 'Roundtrip', value: 'Roundtrip' },
        { label: 'One-way', value: 'One-way' }
    ];

    cabinClassOptions = [
        { label: 'All Cabin Classes', value: '' },
        { label: 'Economy', value: 'Economy' },
        { label: 'Premium Economy', value: 'Premium Economy' },
        { label: 'Business', value: 'Business' },
        { label: 'First Class', value: 'First Class' }
    ];

    paymentMethodOptions = [
        { label: 'Cash', value: 'Cash' },
        { label: 'Credit Card', value: 'Credit Card' },
        { label: 'Bank Transfer', value: 'Bank Transfer' },
        { label: 'Online Payment', value: 'Online Payment' }
    ];

    visaApplicationStatusOptions = [
        { label: 'Not Started', value: 'Not Started' },
        { label: 'Documents Pending', value: 'Documents Pending' },
        { label: 'Documents Complete', value: 'Documents Complete' },
        { label: 'Appointment Scheduled', value: 'Appointment Scheduled' },
        { label: 'Submitted', value: 'Submitted' },
        { label: 'Rejected', value: 'Rejected' }
    ];

    // =====================================================
    // LOAD PRODUCT CATALOGUE
    // =====================================================

    @wire(getTravelPackages, { bookingId: '$recordId' })
    wiredPackages(result) {

        this.wiredPackagesResult = result;
        this.isLoading = false;

        if (result.data) {

            this.loadError = '';

            this.travelPackages = result.data
                .filter(item =>
                    item &&
                    item.id &&
                    item.name &&
                    Number(item.price) >= 0
                )
                .map(item => {

                    const category =
                        this.normalizePackageType(item.packageType);

                    return {
                        ...item,
                        id: item.id,
                        category,
                        basePrice: Number(item.basePrice || item.price || 0),
                        price: Number(item.price || 0),
                        currencyCode: item.currencyCode || 'USD'
                    };
                });

            const quantities = { ...this.hotelQuantities };

            this.travelPackages
                .filter(item => item.category === 'Hotels')
                .forEach(item => {

                    if (!quantities[item.id]) {
                        quantities[item.id] = {
                            rooms: 1,
                            nights: 1
                        };
                    }
                });

            this.hotelQuantities = quantities;

        } else if (result.error) {

            this.travelPackages = [];
            this.loadError = this.reduceError(result.error);
        }
    }

    // =====================================================
    // LOAD SAVED TRAVEL PACKAGE
    // =====================================================

    @wire(getBookingServices, { bookingId: '$recordId' })
    wiredBookingServices(result) {

        this.wiredSavedServicesResult = result;

        if (result.data) {

            const validServices = result.data.filter(item =>
                item &&
                item.lineId &&
                item.productId &&
                item.name &&
                Number(item.quantity) > 0 &&
                Number(item.price) >= 0
            );

            this.savedServices = validServices;

            // Do not overwrite unsaved local selections.
            if (!this.hasLocalPackageChanges) {

                this.selectedServices = validServices.map(item => ({

                    packageId: item.productId,
                    lineId: item.lineId,

                    name: item.name,
                    category: item.category,

                    destination: item.destination || '',
                    supplier: item.supplier || '',
                    description: item.description || '',

                    imageUrl: item.imageUrl || '',

                    basePrice: Number(item.basePrice || 0),
                    price: Number(item.price || 0),

                    currencyCode: item.currencyCode || 'USD',

                    quantity: Number(item.quantity || 1),
                    rooms: Number(item.rooms || 1),
                    nights: Number(item.nights || 1)
                }));

                const quantities = { ...this.hotelQuantities };

                validServices
                    .filter(item => item.category === 'Hotels')
                    .forEach(item => {

                        quantities[item.productId] = {
                            rooms: item.rooms || 1,
                            nights: item.nights || 1
                        };
                    });

                this.hotelQuantities = quantities;
            }

        } else if (result.error) {

            this.showToast(
                'Saved package loading failed',
                this.reduceError(result.error),
                'error'
            );
        }
    }

    // =====================================================
    // VISA SUMMARY
    // =====================================================

    @wire(getVisaSummary, { bookingId: '$recordId' })
    wiredVisaSummary(result) {

        this.wiredVisaSummaryResult = result;

        if (result.data) {
            this.visaSummary = result.data;
        } else if (result.error) {
            this.visaSummary = null;
        }
    }

    @wire(getActiveVisaChecklists, { bookingId: '$recordId' })
    wiredVisaChecklists(result) {

        this.wiredVisaChecklistsResult = result;

        if (result.data) {
            this.visaChecklists = result.data;
        } else if (result.error) {
            this.visaChecklists = [];
        }
    }

    // =====================================================
    // GETTERS
    // =====================================================

    get isSelectionEmpty() {
        return this.selectedServices.length === 0;
    }

    get hasSelectedAirTicket() {
        return this.selectedServices.some(
            item => item.category === 'Air_Tickets'
        );
    }

    get hasSavedAirTicket() {
        return this.savedServices.some(
            item => item.category === 'Air_Tickets'
        );
    }

    get hasUnsavedChanges() {
        if (this.selectedServices.length !== this.savedServices.length) {
            return true;
        }

        const savedMap = new Map(
            this.savedServices.map(item => [item.productId, item])
        );

        return this.selectedServices.some(item => {

            const saved = savedMap.get(item.packageId);

            if (!saved) return true;

            return Number(saved.quantity || 1) !==
                    Number(item.quantity || 1) ||

                Number(saved.rooms || 1) !==
                    Number(item.rooms || 1) ||

                Number(saved.nights || 1) !==
                    Number(item.nights || 1) ||

                Number(saved.price || 0).toFixed(2) !==
                    Number(item.price || 0).toFixed(2);
        });
    }

    get savePackageDisabled() {
        return this.isSaving ||
            this.isCheckingVisa ||
            this.isSelectionEmpty ||
            !this.hasSelectedAirTicket;
    }

    get visaButtonDisabled() {
        return !this.hasSavedAirTicket ||
            this.hasUnsavedChanges ||
            this.isSaving ||
            this.isCheckingVisa;
    }

    get quoteButtonDisabled() {
        return !this.visaSummary ||
            !this.visaSummary.quoteEligible ||
            this.isSaving ||
            this.isCheckingVisa;
    }

    get quoteBlockReason() {
        return this.visaSummary?.quoteBlockReason ||
            'Check visa requirements and complete all required approvals first.';
    }

    get showVisaFreeInformation() {
        return this.visaSummary?.visaStatus === 'Visa Free';
    }

    get showVisaRequiredInformation() {
        return this.visaChecklists.some(
            item => item.Visa_Required__c === true
        );
    }

    get showVisaPendingInformation() {
        return !this.visaSummary ||
            this.visaSummary.visaStatus === 'Pending Review';
    }

    get totalCurrencyCode() {
        return this.selectedServices[0]?.currencyCode || 'USD';
    }

    get totalPrice() {
        return this.selectedServices.reduce(
            (total, item) =>
                total +
                Number(item.price || 0) *
                Number(item.quantity || 1),
            0
        );
    }

    get services() {
        return this.selectedServices.map(item => ({
            ...item,
            id: item.packageId,
            lineTotal:
                Number(item.price || 0) *
                Number(item.quantity || 1),
            hotelDescription:
                item.category === 'Hotels'
                    ? `${item.rooms} room(s), ${item.nights} night(s)`
                    : ''
        }));
    }

    get originOptions() {

        const values = [...new Set(
            this.travelPackages
                .filter(item => item.category === 'Air_Tickets')
                .map(item => item.origin)
                .filter(Boolean)
        )];

        return [
            { label: 'All origins', value: '' },
            ...values.map(value => ({
                label: value,
                value
            }))
        ];
    }

    get destinationOptions() {

        const values = [...new Set(
            this.travelPackages
                .map(item => item.destination)
                .filter(Boolean)
        )];

        return [
            { label: 'All destinations', value: '' },
            ...values.map(value => ({
                label: value,
                value
            }))
        ];
    }

    get displayAirTickets() {

        return this.travelPackages
            .filter(item => item.category === 'Air_Tickets')
            .filter(item => {

                if (this.filterOrigin &&
                    item.origin !== this.filterOrigin) return false;

                if (this.filterDestination &&
                    item.destination !== this.filterDestination) return false;

                if (this.filterFlightType &&
                    String(item.flightType).toLowerCase() !==
                    this.filterFlightType.toLowerCase()) return false;

                if (this.filterCabinClass &&
                    String(item.cabinClass).toLowerCase() !==
                    this.filterCabinClass.toLowerCase()) return false;

                if (this.maxPrice !== '' &&
                    Number(item.price) > Number(this.maxPrice)) return false;

                if (this.searchKeyword) {

                    const term = this.searchKeyword.toLowerCase();

                    const searchable = [
                        item.name,
                        item.origin,
                        item.destination,
                        item.supplier,
                        item.description
                    ].join(' ').toLowerCase();

                    if (!searchable.includes(term)) return false;
                }

                return true;
            });
    }

    get displayHotels() {

        return this.travelPackages
            .filter(item => item.category === 'Hotels')
            .filter(item => {

                if (this.hotelDestinationFilter &&
                    !this.sameText(
                        item.destination,
                        this.hotelDestinationFilter
                    )) return false;

                if (this.hotelSearchKeyword) {

                    const term = this.hotelSearchKeyword.toLowerCase();

                    const searchable = [
                        item.name,
                        item.destination,
                        item.supplier,
                        item.description
                    ].join(' ').toLowerCase();

                    if (!searchable.includes(term)) return false;
                }

                return true;
            })
            .map(item => {

                const quantity =
                    this.hotelQuantities[item.id] ||
                    { rooms: 1, nights: 1 };

                return {
                    ...item,
                    rooms: quantity.rooms,
                    nights: quantity.nights,
                    calculatedPrice: this.calculateHotelPrice(
                        item.basePrice,
                        quantity.rooms,
                        quantity.nights
                    )
                };
            });
    }

    get displayTransfers() {
        return this.travelPackages.filter(
            item => item.category === 'Ground'
        );
    }

    get displayAncillaries() {
        return this.travelPackages.filter(
            item => item.category === 'Ancillary'
        );
    }

    get visaChecklistView() {

        return this.visaChecklists.map(item => {

            const draft = this.visaDrafts[item.Id] || {};

            return {
                ...item,

                isApproved: item.Status__c === 'Approved',

                applicationReference:
                    draft.applicationReference ??
                    item.Application_Reference__c,

                applicationStatus:
                    draft.status ??
                    item.Status__c,

                appointmentDate:
                    draft.appointmentDate ??
                    item.Appointment_Date__c,

                submissionDate:
                    draft.submissionDate ??
                    item.Submission_Date__c,

                decisionDate:
                    draft.decisionDate ??
                    item.Decision_Date__c,

                comments:
                    draft.comments ??
                    item.Comments__c,

                passportCopyReceived:
                    draft.passportCopyReceived ??
                    item.Passport_Copy_Received__c,

                passportPhotoReceived:
                    draft.passportPhotoReceived ??
                    item.Passport_Photo_Received__c,

                applicationFormCompleted:
                    draft.applicationFormCompleted ??
                    item.Application_Form_Completed__c,

                flightItineraryReceived:
                    draft.flightItineraryReceived ??
                    item.Flight_Itinerary_Received__c,

                hotelConfirmationReceived:
                    draft.hotelConfirmationReceived ??
                    item.Hotel_Confirmation_Received__c,

                travelInsuranceReceived:
                    draft.travelInsuranceReceived ??
                    item.Travel_Insurance_Received__c,

                financialProofReceived:
                    draft.financialProofReceived ??
                    item.Financial_Proof_Received__c,

                appointmentCompleted:
                    draft.appointmentCompleted ??
                    item.Appointment_Completed__c
            };
        });
    }

    get visaFreeChecklistView() {
        return this.visaChecklistView.filter(
            item => item.Visa_Required__c !== true &&
                item.Status__c === 'Not Required'
        );
    }

    get displayVisaRequired() {
        return this.visaChecklistView.filter(
            item => item.Visa_Required__c === true
        );
    }

    // =====================================================
    // CATEGORY AND PRICE HELPERS
    // =====================================================

    normalizePackageType(value) {

        const v = String(value || '')
            .trim()
            .toLowerCase()
            .replace(/[_-]+/g, ' ');

        if (v.includes('air') ||
            v.includes('flight') ||
            v.includes('ticket')) return 'Air_Tickets';

        if (v.includes('hotel') ||
            v.includes('accommodation')) return 'Hotels';

        if (v.includes('ground') ||
            v.includes('transfer') ||
            v.includes('transport')) return 'Ground';

        return 'Ancillary';
    }

    sameText(first, second) {

        return String(first || '').trim().toLowerCase() ===
            String(second || '').trim().toLowerCase();
    }

    calculateHotelPrice(basePrice, rooms, nights) {

        return Number(basePrice || 0) +
            ((Math.max(1, Number(rooms) || 1) - 1) * HOTEL_ROOM_FEE) +
            ((Math.max(1, Number(nights) || 1) - 1) * HOTEL_NIGHT_FEE);
    }

    // =====================================================
    // FILTERS
    // =====================================================

    handleTabChange(event) {
        this.activeTab = event.detail.value;
    }

    handleFilterChange(event) {

        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;

        if (field) this[field] = value;
    }

    handleClearFilters() {

        this.filterOrigin = '';
        this.filterDestination = '';
        this.filterFlightType = '';
        this.filterCabinClass = '';
        this.maxPrice = '';
        this.searchKeyword = '';
    }

    handleClearHotelFilters() {

        this.hotelDestinationFilter = '';
        this.hotelSearchKeyword = '';
    }

    // =====================================================
    // HOTEL QUANTITIES
    // =====================================================

    handleHotelQuantityChange(event) {

        const productId = event.target.dataset.id;
        const field = event.target.dataset.field;

        if (!productId ||
            !['rooms', 'nights'].includes(field)) return;

        const raw = Number(event.target.value);

        const value = Number.isFinite(raw) && raw >= 1
            ? Math.floor(raw)
            : 1;

        this.hotelQuantities = {
            ...this.hotelQuantities,
            [productId]: {
                ...(this.hotelQuantities[productId] ||
                    { rooms: 1, nights: 1 }),
                [field]: value
            }
        };

        this.selectedServices = this.selectedServices.map(item => {

            if (item.packageId !== productId ||
                item.category !== 'Hotels') return item;

            const q = this.hotelQuantities[productId];

            return {
                ...item,
                rooms: q.rooms,
                nights: q.nights,
                price: this.calculateHotelPrice(
                    item.basePrice,
                    q.rooms,
                    q.nights
                )
            };
        });

        this.markPackageChanged();
    }

    // =====================================================
    // ADD PRODUCT
    // =====================================================

    handleAddPackage(event) {

        const productId = event.currentTarget.dataset.id;

        const product = this.travelPackages.find(
            item => item.id === productId
        );

        if (!product ||
            !product.name ||
            !product.id ||
            Number(product.price) < 0) {

            this.showToast(
                'Invalid product',
                'This product cannot be added.',
                'error'
            );
            return;
        }

        const hotel = product.category === 'Hotels';

        const q = this.hotelQuantities[productId] ||
            { rooms: 1, nights: 1 };

        const service = {

            packageId: product.id,
            name: product.name,
            category: product.category,

            destination: product.destination || '',
            supplier: product.supplier || '',
            description: product.description || '',
            imageUrl: product.imageUrl || '',

            basePrice: Number(product.basePrice || 0),

            price: hotel
                ? this.calculateHotelPrice(
                    product.basePrice,
                    q.rooms,
                    q.nights
                )
                : Number(product.price || 0),

            currencyCode: product.currencyCode || 'USD',

            quantity: 1,
            rooms: hotel ? q.rooms : 1,
            nights: hotel ? q.nights : 1
        };

        const index = this.selectedServices.findIndex(
            item => item.packageId === product.id
        );

        if (index >= 0) {

            this.selectedServices = this.selectedServices.map(
                (item, i) => i === index ? service : item
            );

        } else {

            this.selectedServices = [
                ...this.selectedServices,
                service
            ];
        }

        this.markPackageChanged();

        this.showToast(
            index >= 0 ? 'Product updated' : 'Product added',
            product.name,
            'success'
        );
    }

    handleSelectService(event) {

        const productId = event.currentTarget.dataset.id;

        const product = this.travelPackages.find(
            item => item.id === productId
        );

        if (!product) return;

        const q = this.hotelQuantities[productId] ||
            { rooms: 1, nights: 1 };

        const hotel = product.category === 'Hotels';

        this.selectedService = {
            ...product,
            rooms: q.rooms,
            nights: q.nights,
            price: hotel
                ? this.calculateHotelPrice(
                    product.basePrice,
                    q.rooms,
                    q.nights
                )
                : product.price
        };
    }

    handleCloseDetails() {
        this.selectedService = null;
    }

    // =====================================================
    // REMOVE PRODUCT
    // =====================================================

    handleRemoveService(event) {

        const productId = event.currentTarget.dataset.id;

        this.selectedServices = this.selectedServices.filter(
            item => item.packageId !== productId
        );

        this.markPackageChanged();
    }

    handleClearPackage() {

        this.selectedServices = [];
        this.selectedService = null;

        this.markPackageChanged();
    }

    markPackageChanged() {

        this.hasLocalPackageChanges = true;

        // Previous visa result cannot be trusted after itinerary changes.
        this.visaCheckResult = null;
    }

    // =====================================================
    // SAVE PACKAGE
    // =====================================================

    async handleSavePackage() {

        if (this.isSaving) return;

        if (!this.recordId) {
            this.showToast(
                'Booking required',
                'Open a Booking record first.',
                'error'
            );
            return;
        }

        const validProducts = this.selectedServices.filter(item =>
            item &&
            item.packageId &&
            item.name &&
            Number(item.quantity || 1) > 0
        );

        if (!validProducts.some(
            item => item.category === 'Air_Tickets'
        )) {

            this.showToast(
                'Air Ticket required',
                'Add at least one Air Ticket.',
                'warning'
            );
            return;
        }

        this.isSaving = true;

        try {

            const selected = validProducts.map(item => ({

                productId: item.packageId,
                quantity: Number(item.quantity || 1),
                rooms: Number(item.rooms || 1),
                nights: Number(item.nights || 1),
                price: Number(item.price || 0),
                description: item.description || ''
            }));

            const count = await saveBookingServices({

                bookingId: this.recordId,
                selectedServices: selected
            });

            // Refresh saved products from Salesforce.
            this.hasLocalPackageChanges = false;

            await refreshApex(this.wiredSavedServicesResult);

            // Reload current visa information because itinerary may change.
            await Promise.all([
                refreshApex(this.wiredVisaSummaryResult),
                refreshApex(this.wiredVisaChecklistsResult)
            ]);

            this.showToast(
                'Travel Package saved',
                `${count} product lines saved successfully.`,
                'success'
            );

        } catch (error) {

            this.showToast(
                'Save failed',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isSaving = false;
        }
    }

    // =====================================================
    // MANUAL VISA CHECK
    // =====================================================

    async handleCheckVisa() {

        if (this.isCheckingVisa || this.isSaving) return;

        if (!this.hasSavedAirTicket) {

            this.showToast(
                'Save Travel Package first',
                'Save an Air Ticket before checking visa requirements.',
                'warning'
            );
            return;
        }

        if (this.hasUnsavedChanges) {

            this.showToast(
                'Unsaved package changes',
                'Save the Travel Package before checking visa requirements.',
                'warning'
            );
            return;
        }

        this.isCheckingVisa = true;

        try {

            this.visaCheckResult = await checkVisaRequirements({
                bookingId: this.recordId
            });

            await Promise.all([
                refreshApex(this.wiredVisaSummaryResult),
                refreshApex(this.wiredVisaChecklistsResult)
            ]);

            if (this.visaCheckResult.visaStatus === 'Pending Review') {

                this.showToast(
                    'Visa review required',
                    this.visaCheckResult.requirements ||
                        'Visa information is incomplete.',
                    'warning'
                );

            } else if (this.visaCheckResult.visaRequired) {

                this.showToast(
                    'Visa required',
                    'Complete the Visa Application Information.',
                    'warning'
                );

            } else {

                this.showToast(
                    'Visa Free',
                    'Visa requirements have been retrieved successfully.',
                    'success'
                );
            }

        } catch (error) {

            this.showToast(
                'Visa check failed',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isCheckingVisa = false;
        }
    }

    // =====================================================
    // VISA FORM
    // =====================================================

    handleVisaFieldChange(event) {

        const checklistId = event.target.dataset.id;
        const field = event.target.dataset.field;

        if (!checklistId || !field) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value ?? event.target.value);

        this.visaDrafts = {
            ...this.visaDrafts,
            [checklistId]: {
                ...(this.visaDrafts[checklistId] || {}),
                [field]: value
            }
        };
    }

    async handleSaveVisaInformation(event) {

        const checklistId = event.currentTarget.dataset.id;

        const row = this.visaChecklists.find(
            item => item.Id === checklistId
        );

        if (!row) return;

        const draft = this.visaDrafts[checklistId] || {};

        const payload = {

            applicationReference:
                draft.applicationReference ?? row.Application_Reference__c,

            status:
                draft.status ?? row.Status__c,

            appointmentDate:
                draft.appointmentDate ?? row.Appointment_Date__c,

            submissionDate:
                draft.submissionDate ?? row.Submission_Date__c,

            decisionDate:
                draft.decisionDate ?? row.Decision_Date__c,

            comments:
                draft.comments ?? row.Comments__c,

            passportCopyReceived:
                draft.passportCopyReceived ?? row.Passport_Copy_Received__c,

            passportPhotoReceived:
                draft.passportPhotoReceived ?? row.Passport_Photo_Received__c,

            applicationFormCompleted:
                draft.applicationFormCompleted ?? row.Application_Form_Completed__c,

            flightItineraryReceived:
                draft.flightItineraryReceived ?? row.Flight_Itinerary_Received__c,

            hotelConfirmationReceived:
                draft.hotelConfirmationReceived ?? row.Hotel_Confirmation_Received__c,

            travelInsuranceReceived:
                draft.travelInsuranceReceived ?? row.Travel_Insurance_Received__c,

            financialProofReceived:
                draft.financialProofReceived ?? row.Financial_Proof_Received__c,

            appointmentCompleted:
                draft.appointmentCompleted ?? row.Appointment_Completed__c
        };

        this.isSaving = true;

        try {

            const message = await saveVisaInformation({

                bookingId: this.recordId,
                checklistId,
                payloadJson: JSON.stringify(payload)
            });

            const updatedDrafts = { ...this.visaDrafts };

            delete updatedDrafts[checklistId];

            this.visaDrafts = updatedDrafts;

            await Promise.all([
                refreshApex(this.wiredVisaChecklistsResult),
                refreshApex(this.wiredVisaSummaryResult)
            ]);

            this.showToast(
                'Visa information saved',
                message,
                'success'
            );

        } catch (error) {

            this.showToast(
                'Visa information failed',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isSaving = false;
        }
    }

    // =====================================================
    // PAYMENT
    // =====================================================

    handlePaymentMethodChange(event) {
        this.paymentMethod = event.detail.value;
    }

    async handleRecordPayment() {

        if (this.isSaving) return;

        if (!this.hasSavedAirTicket) {
            this.showToast(
                'Save Travel Package first',
                'Save the Travel Package before payment.',
                'warning'
            );
            return;
        }

        if (!this.paymentMethod) {
            this.showToast(
                'Payment method required',
                'Select a payment method.',
                'warning'
            );
            return;
        }

        this.isSaving = true;

        try {

            const paymentId = await savePayment({

                bookingId: this.recordId,
                method: this.paymentMethod,
                paymentDate: new Date().toISOString().slice(0, 10)
            });

            this.paymentMethod = '';

            this.showToast(
                'Pending payment created',
                `Payment ID: ${paymentId}. No card was charged.`,
                'success'
            );

        } catch (error) {

            this.showToast(
                'Payment failed',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isSaving = false;
        }
    }

    // =====================================================
    // QUOTE
    // =====================================================

    async handleCreateQuote() {

        if (this.quoteButtonDisabled) {

            this.showToast(
                'Quote blocked',
                this.quoteBlockReason,
                'warning'
            );
            return;
        }

        this.isSaving = true;

        try {

            const quoteId = await createBookingQuote({

                bookingId: this.recordId
            });

            this.showToast(
                'Quote created',
                `Quote ID: ${quoteId}`,
                'success'
            );

        } catch (error) {

            this.showToast(
                'Quote creation failed',
                this.reduceError(error),
                'error'
            );

        } finally {

            this.isSaving = false;
        }
    }

    // =====================================================
    // TOAST AND ERROR
    // =====================================================

    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {

        if (Array.isArray(error?.body)) {
            return error.body.map(item => item.message).join(', ');
        }

        return error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.';
    }
}

