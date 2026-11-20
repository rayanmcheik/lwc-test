import { LightningElement, api } from 'lwc';

export default class PaymentDetails extends LightningElement {

    _paymentMethod;
    paymentData = {};

    @api
    get paymentMethod() {
        return this._paymentMethod;
    }

    set paymentMethod(value) {
        this._paymentMethod = value;
        this.paymentData = {};
    }

    get isVisa() {
        return this.paymentMethod === 'Visa';
    }

    get isBankTransfer() {
        return this.paymentMethod === 'Bank Transfer';
    }

    get isOnlinePayment() {
        return this.paymentMethod === 'Online Payment';
    }

    handleChange(event) {
        this.paymentData[event.target.dataset.field] =
            event.target.value;
    }

    @api
    validateAndGetDetails() {

        const inputs = [
            ...this.template.querySelectorAll('lightning-input')
        ];

        const valid = inputs.reduce((result, input) => {
            input.reportValidity();
            return input.checkValidity() && result;
        }, true);

        if (!valid) {
            return null;
        }

        return { ...this.paymentData };
    }
}