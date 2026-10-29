import { LightningElement } from 'lwc';
import FLIGHT_BANNER from '@salesforce/resourceUrl/flightHeaderBanner';

export default class FlightHeader extends LightningElement {

    flightImageUrl = FLIGHT_BANNER;
}
