import { LightningElement,track } from "lwc";

export default class parentComponent extends LightningElement {
   @track child1Status = 'Select';
    @track child2Status = 'Select';

    handleChildStatusUpdate(event) {
        const childName = event.detail.name;
        const currentStatus = event.detail.currentStatus;

        if (childName === 'Child A') {
            this.child1Status = currentStatus;
        } else if (childName === 'Child B') {
            this.child2Status = currentStatus;
        }
    }

    resetAllChildren() {
        // FIXED: Querying c-child-one to target your active component
        const children = this.template.querySelectorAll('c-child-component');
        
        children.forEach(child => {
            child.forceStatusReset('Select');
        });

        this.child1Status = 'Select';
        this.child2Status = 'Select';
    }
    }