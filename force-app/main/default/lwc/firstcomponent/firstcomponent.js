import { LightningElement, api } from 'lwc';

export default class Firstcomponent extends LightningElement {
    // Correct way to expose a public property with a default value
//     @api name = 'rayannnnnnnnnnn'; 
// students=["Rayan","Rayan2","Rayan3","Rayan4","Rayan5","Rayan6","Rayan7","Rayan8","Rayan9","Rayan10"];
//     // The missing event handler to update the property reactively
//     handleInput(event) {
//         this.name = event.target.value;
//     }

//        employees = [
//         {
//             id: 1,
//             name: 'John Smith',
//             department: 'IT',
//             position: 'Developer'
//         },
//         {
//             id: 2,
//             name: 'Sarah Johnson',
//             department: 'HR',
//             position: 'Recruiter'
//         },
//         {
//             id: 3,
//             name: 'Mike Brown',
//             department: 'IT',
//             position: 'QA Engineer'
//         },
//         {
//             id: 4,
//             name: 'Emma Davis',
//             department: 'Finance',
//             position: 'Accountant'
//         },
//         {
//             id: 5,
//             name: 'Chris Wilson',
//             department: 'HR',
//             position: 'HR Manager'
//         }
//     ];

//     selectedDepartment = '';
//     filteredEmployees = [];
//     selectedEmployee = null;
//     showEmployees = false;

//     get departmentOptions() {
//         return [
//             { label: 'IT', value: 'IT' },
//             { label: 'HR', value: 'HR' },
//             { label: 'Finance', value: 'Finance' }
//         ];
//     }

//     handleDepartmentChange(event) {
//         this.selectedDepartment = event.detail.value;
//         this.showEmployees = false;
//         this.selectedEmployee = null;
//     }

//     handleShowEmployees() {

//         this.filteredEmployees = this.employees.filter(employee =>
//             employee.department === this.selectedDepartment
//         );

//         this.showEmployees = true;
//         this.selectedEmployee = null;
//     }

//     handleEmployeeClick(event) {

//         const employeeId = Number(event.currentTarget.dataset.id);

//         this.selectedEmployee = this.employees.find(
//             employee => employee.id === employeeId
//         );}
}
