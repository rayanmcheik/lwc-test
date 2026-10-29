import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTravelPackages from '@salesforce/apex/VGTSBookingPackageController.getTravelPackages';
import saveBookingServices from '@salesforce/apex/VGTSBookingPackageController.saveBookingServices';
import savePayment from '@salesforce/apex/VGTSBookingPackageController.savePayment';

import createBookingQuote from
    '@salesforce/apex/VGTSBookingPackageController.createBookingQuote';



const HOTEL_ROOM_FEE = 50;
const HOTEL_NIGHT_FEE = 30;


export default class VgtsBookingServiceSelector extends LightningElement {
    @api recordId;


    travelPackages = [];
    selectedServices = [];
    selectedService = null;
    isLoading = true;
    isSaving = false;
    loadError = '';
    activeTab = 'Air_Tickets';


    filterOrigin = '';
    filterDestination = '';
    filterFlightType = '';
    filterCabinClass = '';
    maxPrice = '';
    searchKeyword = '';


    hotelQuantities = {};
    paymentMethod = '';


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


    @wire(getTravelPackages)
    wiredPackages({ data, error }) {
        this.isLoading = false;


        if (data) {
            this.loadError = '';
            this.travelPackages = data.map((record) => {
                const category = this.normalizePackageType(
                    record.packageType ||
                    record.packageTypeName ||
                    record.category ||
                    ''
                );


                const price = this.getPrice(record);
                const origin = record.origin || record.departureAirport || '';
                const destination = record.destination || '';


                return {
                    id: record.id || record.Id,
                    name: record.name || record.Name || 'Unnamed Product',
                    category,
                    type: this.getDisplayType(category),
                    packageType: record.packageType || '',
                    origin,
                    destination,
                    departureAirport: record.departureAirport || origin,
                    arrivalAirport: record.arrivalAirport || destination,
                    flightType: record.flightType || '',
                    cabinClass: record.cabinClass || '',
                    departureDate: record.departureDate || '',
                    arrivalDate: record.arrivalDate || '',
                    supplier: record.supplier || '',
                    description: record.description || '',
                    imageUrl: record.imageUrl || '',
                    basePrice: price,
                    price
                };
            }).filter((item) => Boolean(item.id));


            const quantities = { ...this.hotelQuantities };
            this.travelPackages
                .filter((item) => item.category === 'Hotels')
                .forEach((item) => {
                    if (!quantities[item.id]) {
                        quantities[item.id] = { rooms: 1, nights: 1 };
                    }
                });


            this.hotelQuantities = quantities;
        } else if (error) {
            this.travelPackages = [];
            this.loadError = this.reduceError(error);
        }
    }


    normalizePackageType(value) {
        const type = String(value || '').trim().toLowerCase().replace(/[_-]+/g, ' ');


        if (type.includes('air') || type.includes('flight') || type.includes('ticket')) {
            return 'Air_Tickets';
        }


        if (type.includes('hotel') || type.includes('accommodation')) {
            return 'Hotels';
        }


        if (type.includes('ground') || type.includes('transfer') || type.includes('transport')) {
            return 'Ground';
        }


        return 'Ancillary';
    }


    getDisplayType(category) {
        const labels = {
            Air_Tickets: 'Air Tickets',
            Hotels: 'Hotel',
            Ground: 'Ground Transfer',
            Ancillary: 'Ancillary Service'
        };


        return labels[category] || category;
    }


    getPrice(record) {
        const fields = [
            record.price,
            record.sellingPrice,
            record.retailPrice,
            record.basePrice
        ];


        for (const value of fields) {
            if (value !== undefined && value !== null && value !== '') {
                const amount = Number(value);
                if (Number.isFinite(amount)) {
                    return amount;
                }
            }
        }


        return 0;
    }


    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }


        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }


    get hasPackages() {
        return this.travelPackages.length > 0;
    }


    get showEmptyPackages() {
        return !this.isLoading && !this.loadError && this.travelPackages.length === 0;
    }


    get originOptions() {
        const values = [
            ...new Set(
                this.travelPackages
                    .filter((item) => item.category === 'Air_Tickets')
                    .map((item) => item.origin)
                    .filter(Boolean)
            )
        ];


        return [
            { label: 'All origins', value: '' },
            ...values.map((value) => ({ label: value, value }))
        ];
    }


    get destinationOptions() {
        const values = [
            ...new Set(
                this.travelPackages
                    .map((item) => item.destination)
                    .filter(Boolean)
            )
        ];


        return [
            { label: 'All destinations', value: '' },
            ...values.map((value) => ({ label: value, value }))
        ];
    }


    get displayAirTickets() {
        return this.travelPackages
            .filter((item) => item.category === 'Air_Tickets')
            .filter((item) => {
                if (this.filterOrigin && item.origin !== this.filterOrigin) {
                    return false;
                }


                if (this.filterDestination && item.destination !== this.filterDestination) {
                    return false;
                }


                if (
                    this.filterFlightType &&
                    String(item.flightType).toLowerCase() !== this.filterFlightType.toLowerCase()
                ) {
                    return false;
                }


                if (
                    this.filterCabinClass &&
                    String(item.cabinClass).toLowerCase() !== this.filterCabinClass.toLowerCase()
                ) {
                    return false;
                }


                if (
                    this.maxPrice !== '' &&
                    Number(item.price) > Number(this.maxPrice)
                ) {
                    return false;
                }


                if (this.searchKeyword) {
                    const keyword = this.searchKeyword.toLowerCase();
                    const searchable = [
                        item.name,
                        item.origin,
                        item.destination,
                        item.supplier,
                        item.description
                    ].join(' ').toLowerCase();


                    if (!searchable.includes(keyword)) {
                        return false;
                    }
                }


                return true;
            });
    }


    // Hotels share only the destination filter with Air Tickets.
    // An empty destination means every hotel is displayed.
    get displayHotels() {
        return this.travelPackages
            .filter((item) => item.category === 'Hotels')
            .filter((item) => {
                if (!this.filterDestination) {
                    return true;
                }


                return this.sameText(item.destination, this.filterDestination);
            })
            .map((item) => {
                const quantity = this.hotelQuantities[item.id] || {
                    rooms: 1,
                    nights: 1
                };


                const rooms = Math.max(1, Number(quantity.rooms) || 1);
                const nights = Math.max(1, Number(quantity.nights) || 1);


                return {
                    ...item,
                    rooms,
                    nights,
                    calculatedPrice: this.calculateHotelPrice(item.basePrice, rooms, nights)
                };
            });
    }


    // These categories do not use the flight filters or destination filter.
    get displayTransfers() {
        return this.travelPackages.filter((item) => item.category === 'Ground');
    }


    get displayAncillaries() {
        return this.travelPackages.filter((item) => item.category === 'Ancillary');
    }


    get noAirPackages() {
        return !this.isLoading &&
            this.travelPackages.some((item) => item.category === 'Air_Tickets') &&
            this.displayAirTickets.length === 0;
    }


    get noHotelPackages() {
        return !this.isLoading && this.displayHotels.length === 0;
    }


    get noGroundPackages() {
        return !this.isLoading && this.displayTransfers.length === 0;
    }


    get noAncillaryPackages() {
        return !this.isLoading && this.displayAncillaries.length === 0;
    }


    get hasServices() {
        return this.selectedServices.length > 0;
    }


    get totalPrice() {
        return this.selectedServices.reduce(
            (total, service) => total + Number(service.price || 0),
            0
        );
    }


    get services() {
        return this.selectedServices.map((service) => ({
            ...service,
            id: service.packageId,
            lineTotal: service.price,
            hotelDescription: service.category === 'Hotels'
                ? `${service.rooms} room(s), ${service.nights} night(s)`
                : ''
        }));
    }


    sameText(first, second) {
        return String(first || '').trim().toLowerCase() ===
            String(second || '').trim().toLowerCase();
    }


    calculateHotelPrice(basePrice, rooms, nights) {
        const roomCount = Math.max(1, Number(rooms) || 1);
        const nightCount = Math.max(1, Number(nights) || 1);


        return Number(basePrice || 0) +
            ((roomCount - 1) * HOTEL_ROOM_FEE) +
            ((nightCount - 1) * HOTEL_NIGHT_FEE);
    }


    handleTabChange(event) {
        this.activeTab = event.detail.value;
    }


    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;


        if (field) {
            this[field] = value;
        }
    }


    handleClearFilters() {
        this.filterOrigin = '';
        this.filterDestination = '';
        this.filterFlightType = '';
        this.filterCabinClass = '';
        this.maxPrice = '';
        this.searchKeyword = '';
    }


    handleHotelQuantityChange(event) {
        const productId = event.target.dataset.id;
        const field = event.target.dataset.field;


        if (!productId || !['rooms', 'nights'].includes(field)) {
            return;
        }


        const rawValue = Number(event.target.value);
        const value = Number.isFinite(rawValue) && rawValue >= 1
            ? Math.floor(rawValue)
            : 1;


        this.hotelQuantities = {
            ...this.hotelQuantities,
            [productId]: {
                ...(this.hotelQuantities[productId] || { rooms: 1, nights: 1 }),
                [field]: value
            }
        };


        this.selectedServices = this.selectedServices.map((service) => {
            if (service.packageId !== productId || service.category !== 'Hotels') {
                return service;
            }


            const quantity = this.hotelQuantities[productId];


            return {
                ...service,
                rooms: quantity.rooms,
                nights: quantity.nights,
                price: this.calculateHotelPrice(
                    service.basePrice,
                    quantity.rooms,
                    quantity.nights
                )
            };
        });


        if (this.selectedService?.id === productId && this.selectedService.isHotel) {
            const quantity = this.hotelQuantities[productId];
            this.selectedService = {
                ...this.selectedService,
                rooms: quantity.rooms,
                nights: quantity.nights,
                price: this.calculateHotelPrice(
                    this.selectedService.basePrice,
                    quantity.rooms,
                    quantity.nights
                )
            };
        }
    }


    handleSelectService(event) {
        const productId = event.currentTarget.dataset.id;
        const product = this.travelPackages.find((item) => item.id === productId);


        if (!product) {
            this.showToast('Product not found', 'The selected product could not be found.', 'error');
            return;
        }


        const quantity = this.hotelQuantities[productId] || { rooms: 1, nights: 1 };
        const isHotel = product.category === 'Hotels';
        const price = isHotel
            ? this.calculateHotelPrice(product.basePrice, quantity.rooms, quantity.nights)
            : product.price;


        this.selectedService = {
            ...product,
            isHotel,
            rooms: quantity.rooms,
            nights: quantity.nights,
            price
        };
    }


    handleCloseDetails() {
        this.selectedService = null;
    }


    handleAddPackage(event) {
        const productId = event.currentTarget.dataset.id;
        const product = this.travelPackages.find((item) => item.id === productId);


        if (!product) {
            this.showToast('Product not found', 'The selected product could not be found.', 'error');
            return;
        }


        const isHotel = product.category === 'Hotels';
        const quantity = this.hotelQuantities[productId] || { rooms: 1, nights: 1 };
        const rooms = isHotel ? quantity.rooms : 1;
        const nights = isHotel ? quantity.nights : 1;
        const price = isHotel
            ? this.calculateHotelPrice(product.basePrice, rooms, nights)
            : Number(product.price || 0);


        const service = {
            packageId: product.id,
            name: product.name,
            type: product.type,
            category: product.category,
            serviceType: this.getApexServiceType(product.category),
            supplier: product.supplier || '',
            description: product.description || '',
            destination: product.destination || '',
            imageUrl: product.imageUrl || '',
            basePrice: Number(product.basePrice || 0),
            price,
            rooms,
            nights,
            quantity: 1,
            roomCategory: '',
            mealPlan: ''
        };


        const existingIndex = this.selectedServices.findIndex(
            (item) => item.packageId === product.id
        );


        if (existingIndex >= 0) {
            this.selectedServices = this.selectedServices.map((item, index) =>
                index === existingIndex ? service : item
            );
            this.showToast('Package updated', `${product.name} was updated in My Travel Package.`, 'success');
        } else {
            this.selectedServices = [...this.selectedServices, service];
            this.showToast('Package added', `${product.name} was added to My Travel Package.`, 'success');
        }


        this.selectedService = null;
    }


    getApexServiceType(category) {
        const types = {
            Air_Tickets: 'Air',
            Hotels: 'Hotel',
            Ground: 'Transfer',
            Ancillary: 'Other'
        };


        return types[category] || 'Other';
    }


    handleRemoveService(event) {
        const productId = event.currentTarget.dataset.id;
        this.selectedServices = this.selectedServices.filter(
            (service) => service.packageId !== productId
        );
    }


    handleClearPackage() {
        this.selectedServices = [];
        this.selectedService = null;
    }


    async handleSavePackage() {
        if (!this.recordId) {
            this.showToast(
                'Booking record required',
                'Open this component on a Booking record page before saving services.',
                'error'
            );
            return;
        }


        if (!this.hasServices) {
            this.showToast('No services selected', 'Add a service before saving.', 'warning');
            return;
        }


        this.isSaving = true;


        try {
            const selectedServices = this.selectedServices.map((service) => ({
                packageId: service.packageId,
                productId: service.packageId,
                name: service.name,
                type: service.type,
                category: service.category,
                serviceType: service.serviceType,
                supplier: service.supplier,
                description: service.description,
                destination: service.destination,
                basePrice: service.basePrice,
                price: service.price,
                sellingPrice: service.price,
                rooms: service.rooms,
                nights: service.nights,
                quantity: service.quantity,
                roomCategory: service.roomCategory,
                mealPlan: service.mealPlan
            }));


            await saveBookingServices({
                bookingId: this.recordId,
                selectedServices
            });


            this.showToast('Success', 'Services were saved to the booking.', 'success');
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
                if (!this.recordId) {
            this.showToast(
                'Booking record required',
                'Open this component on a Booking record page before creating a payment.',
                'error'
            );
            return;
        }


        if (this.totalPrice <= 0) {
            this.showToast('No payment amount', 'Add at least one service to calculate the payment amount.', 'warning');
            return;
        }


        if (!this.paymentMethod) {
            this.showToast('Payment method required', 'Select a payment method.', 'warning');
            return;
        }


        this.isSaving = true;


        try {
            await savePayment({
                bookingId: this.recordId,
                amount: this.totalPrice,
                method: this.paymentMethod,
                paymentDate: new Date().toISOString().slice(0, 10),
                status: 'Completed'
            });


            this.showToast('Payment created', 'The payment record was created. No card was charged.', 'success');
            this.paymentMethod = '';
        } catch (error) {
            this.showToast('Payment failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }


    handlePaymentMethodChange(event) {
        this.paymentMethod = event.detail.value;
    }



async handleSave() {
    if (!this.recordId) {
        this.showToast(
            'Booking record required',
            'Open this component on an Opportunity record page.',
            'error'
        );
        return;
    }


    if (!this.services || this.services.length === 0) {
        this.showToast(
            'No services selected',
            'Add at least one service before saving.',
            'warning'
        );
        return;
    }


    this.isSaving = true;


    try {
        const selectedServices = this.services.map((service) => ({
            // This must be the Salesforce Product2 record ID.
            productId: service.productId || service.id,
            name: service.name,
            type: service.type,
            category: service.category,
            serviceType: service.serviceType,
            supplier: service.supplier,
            description: service.description || service.Description,
            destination: service.destination,
            basePrice: service.basePrice,
            price: Number(service.price) || 0,
            sellingPrice: Number(service.price) || 0,
            quantity: Number(service.quantity) > 0
                ? Number(service.quantity)
                : 1,
            rooms: service.rooms,
            nights: service.nights,
            roomCategory: service.roomCategory,
            mealPlan: service.mealPlan,
            taxes: service.taxes
        }));


        const savedCount = await saveBookingServices({
            bookingId: this.recordId,
            selectedServices
        });


        this.showToast(
            'Booking services saved',
            `${savedCount} opportunity product(s) saved successfully.`,
            'success'
        );


        // Refresh your UI here if you have a wired Apex method.
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


async handleRecordPayment() {
    if (!this.recordId) {
        this.showToast(
            'Booking record required',
            'Open this component on an Opportunity record page.',
            'error'
        );
        return;
    }


    if (!this.services || this.services.length === 0) {
        this.showToast(
            'No payment amount',
            'Add at least one service before creating a payment.',
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


    const amount = Number(this.totalPrice);


    if (!Number.isFinite(amount) || amount <= 0) {
        this.showToast(
            'Invalid payment amount',
            'The payment total must be greater than zero.',
            'error'
        );
        return;
    }


    this.isSaving = true;


    try {
        const paymentId = await savePayment({
            bookingId: this.recordId,
            amount,
            method: this.paymentMethod,
            paymentDate: new Date().toISOString().slice(0, 10),
            status: 'Pending'
        });


        this.showToast(
            'Payment record created',
            'Payment record ID: ' + paymentId +
                '. No card was charged.',
            'success'
        );


        this.paymentMethod = '';
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


async handleCreateQuote() {
    if (!this.recordId) {
        this.showToast(
            'Booking record required',
            'Open this component on an Opportunity record page.',
            'error'
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
            'Your quote was created successfully. Quote ID: ' + quoteId,
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
        return error.body.map((item) => item.message).join(', ');
    }


    return error?.body?.message ||
        error?.message ||
        'An unexpected error occurred.';
}



    async handleRecordPayment() {
        if (!this.recordId) {
            this.showToast(
                'Booking record required',
                'Open this component on a Booking record page before creating a payment.',
                'error'
            );
            return;
        }


        if (this.totalPrice <= 0) {
            this.showToast('No payment amount', 'Add at least one service to calculate the payment amount.', 'warning');
            return;
        }


        if (!this.paymentMethod) {
            this.showToast('Payment method required', 'Select a payment method.', 'warning');
            return;
        }


        this.isSaving = true;


        try {
            await savePayment({
                bookingId: this.recordId,
                amount: this.totalPrice,
                method: this.paymentMethod,
                paymentDate: new Date().toISOString().slice(0, 10),
                status: 'Completed'
            });


            this.showToast('Payment created', 'The payment record was created. No card was charged.', 'success');
            this.paymentMethod = '';
        } catch (error) {
            this.showToast('Payment failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }


    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}