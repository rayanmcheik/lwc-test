
import { LightningElement, api } from 'lwc';

export default class VgtsProductCards extends LightningElement {

    @api value;

    // Configure the official VGTS WhatsApp number.
    whatsappNumber = '';

    get products() {
        const data = this.value;

        if (Array.isArray(data)) {
            return data;
        }

        if (Array.isArray(data?.products)) {
            return data.products;
        }

        return [];
    }

    get hasProducts() {
        return this.products.length > 0;
    }

    handleWhatsApp(event) {

        const productId = event.currentTarget.dataset.id;

        const product = this.products.find(
            item => item.productId === productId
        );

        if (!product || !this.whatsappNumber) {
            return;
        }

        const message =
            `Hello VGTS Sales Team!\n\n` +
            `I am interested in ${product.name}.\n` +
            `Destination: ${product.destination}.\n` +
            `Product Code: ${product.productCode}.\n\n` +
            `Please provide more information.`;

        const url =
            `https://wa.me/${this.whatsappNumber}` +
            `?text=${encodeURIComponent(message)}`;

        window.open(url, '_blank', 'noopener,noreferrer');
    }
}

