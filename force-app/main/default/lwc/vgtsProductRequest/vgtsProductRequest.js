
import { LightningElement, api } from 'lwc';

export default class VgtsProductRequest extends LightningElement {

    @api value;

    destination = '';
    customerEmail = '';

    handleDestination(event) {
        this.destination = event.target.value;
    }

    handleEmail(event) {
        this.customerEmail = event.target.value;
    }

    get isInvalid() {
        return !this.destination.trim() ||
               !this.customerEmail.trim() ||
               !this.customerEmail.includes('@');
    }

    handleSubmit() {

        if (this.isInvalid) {
            return;
        }

        const request = {
            destination: this.destination.trim(),
            customerEmail: this.customerEmail.trim()
        };

        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: {
                    value: request
                },
                bubbles: true,
                composed: true
            })
        );
    }
}

