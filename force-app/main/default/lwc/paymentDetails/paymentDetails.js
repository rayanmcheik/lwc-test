
import { LightningElement, api } from 'lwc';

export default class PaymentDetails extends LightningElement {

    _paymentMethod;

    paymentData = {};

    cardNumber = '';
    cardholderName = '';
    expiryDate = '';
    cvv = '';

    @api
    get paymentMethod() {
        return this._paymentMethod;
    }

    set paymentMethod(value) {
        this._paymentMethod = value;
        this.paymentData = {};

        this.cardNumber = '';
        this.cardholderName = '';
        this.expiryDate = '';
        this.cvv = '';
    }

    get isVisa() {
        return this.paymentMethod === 'Credit Card';
    }

    get isBankTransfer() {
        return this.paymentMethod === 'Bank Transfer';
    }

    get isOnlinePayment() {
        return this.paymentMethod === 'Online Payment';
    }

    // Format card number
    handleCardNumber(event) {

        const digits = event.target.value
            .replace(/\D/g, '')
            .slice(0, 16);

        this.cardNumber = digits
            .replace(/(.{4})/g, '$1 ')
            .trim();

        event.target.value = this.cardNumber;
    }

    // Cardholder name
    handleCardholder(event) {

        this.cardholderName = event.target.value
            .replace(/[^a-zA-Z ]/g, '')
            .toUpperCase();

        event.target.value = this.cardholderName;
    }

    // Expiration date MM/YY
    handleExpiry(event) {

        let digits = event.target.value
            .replace(/\D/g, '')
            .slice(0, 4);

        if (digits.length > 2) {
            digits = digits.slice(0, 2) + '/' +
                digits.slice(2);
        }

        this.expiryDate = digits;
        event.target.value = digits;
    }

    // CVV - demonstration only
    handleCvv(event) {

        this.cvv = event.target.value
            .replace(/\D/g, '')
            .slice(0, 4);

        event.target.value = this.cvv;
    }

    handleChange(event) {

        const field = event.target.dataset.field;

        this.paymentData = {
            ...this.paymentData,
            [field]: event.target.value
        };
    }

    @api
    validateAndGetDetails() {

        if (this.isVisa) {

            const number = this.cardNumber.replace(/\s/g, '');

            const validNumber = /^\d{16}$/.test(number);
            const validName = this.cardholderName.trim().length > 0;
            const validExpiry = /^\d{2}\/\d{2}$/.test(this.expiryDate);
            const validCvv = /^\d{3,4}$/.test(this.cvv);

            if (!validNumber || !validName ||
                !validExpiry || !validCvv) {
                return null;
            }

            // Never return or send card credentials to Apex.
            return {
                demonstrationOnly: true,
                cardholderName: this.cardholderName
            };
        }

        const inputs = [
            ...this.template.querySelectorAll('lightning-input')
        ];

        let valid = true;

        inputs.forEach(input => {
            input.reportValidity();

            if (!input.checkValidity()) {
                valid = false;
            }
        });

        if (!valid) return null;

        return { ...this.paymentData };
    }
}

