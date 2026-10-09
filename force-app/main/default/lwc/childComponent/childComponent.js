import { LightningElement,api,track } from 'lwc';

export default class childComponent extends LightningElement {
   @api childName = '';
   @track status = 'Select';

   get buttonLabel() {
        if (this.status === 'Deselect') return 'Deselect';
        return 'Select';
   }

   get buttonVariant() {
        if (this.status === 'Deselect') return 'destructive'; // Red      
        if (this.status === 'Select') return 'success'; // Green  
        return 'neutral';    
    } 

   notifyParent() {
        this.status = this.status === 'Select' ? 'Deselect' : 'Select';

        // Dispatches the event carrying the status update payload
        const statusEvent = new CustomEvent('statuschange', {
            detail: {
                name: this.childName,
                currentStatus: this.status
            }
        });
        this.dispatchEvent(statusEvent); // FIXED: Removed quotes to pass the event object variable
   }

    @api
    forceStatusReset(newStatus) {
        this.status = newStatus;
    }
}