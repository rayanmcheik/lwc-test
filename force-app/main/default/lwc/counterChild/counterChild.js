import { LightningElement,api} from 'lwc';

export default class CounterChild extends LightningElement {
    counter = 0;
@api incrementCounter() {
        this.counter++;
    }   
}