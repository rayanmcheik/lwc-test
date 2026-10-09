import { LightningElement, api } from 'lwc';

export default class card extends LightningElement {
    @api employeeName;
    @api employeeDepartment;
    @api employeePosition;
}
