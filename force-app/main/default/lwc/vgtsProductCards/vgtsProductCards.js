import { LightningElement, api } from 'lwc';

export default class VgtsProductCards extends LightningElement {
    @api value;

    get products() {
        return Array.isArray(this.value)
            ? this.value
            : [];
    }

    get hasProducts() {
        return this.products.length > 0;
    }
}
